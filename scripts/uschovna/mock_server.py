#!/usr/bin/env python3
"""A local stand-in for Úschovna's upload protocol, so the client can be tested without sending
anything to the real service.

It mirrors docs/uschovna-protocol.md: the send page, /ajax/package_target/, /ajax/test_xss,
/ajax/zalozeni_zasilky (create and finish), /ajax/ajax_upload/{ms}, /ajax/still_alive and the
package page /zasilka/{code}. Two ports play the two origins: "www" (the site) and "upload" (the
upload host package_target names), so cross-origin behaviour can be checked too.

Uploaded bytes are stored in a temporary directory and every chunk is checked against the
protocol: package, name, order of files, offsets, sizes, X_TMP, and the headers a browser would
send (cookies only to the site, X-Requested-With where jQuery adds it). Anything off is recorded
in `errors`, which the test harness reads from GET /__state.

Faults are injected by rules, either from the command line (for trying the app by hand) or with
POST /__control (the harness). A rule applies to the n-th request to one endpoint, counted from
when the rules were set: drop the connection mid-chunk, lose the answer after storing the chunk,
stall, answer 500, answer something that isn't JSON, answer a fatal res.

Python 3 standard library only. Run with --help for the switches.
"""

import argparse
import json
import os
import secrets
import socket
import sys
import tempfile
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCRIPT_VERSION = "1.1.85"
DEFAULT_ANSWERS = {
    "package_target_status": True,
    "test_xss": {"status": 1},
    "create_status": 1,
    "finish_status": 1,
    "res1": 1,
    "res2": 2,
}
ANSWER_STYLES = {
    # As the real server answered package_target on 2026-10-04; the rest as numbers.
    "real": {},
    "bool": {"package_target_status": True, "create_status": True, "finish_status": True, "res1": True},
    "number": {"package_target_status": 1},
    "string": {"package_target_status": "1", "create_status": " 1", "finish_status": "1.0",
               "res1": "1", "res2": "2"},
}
MAIL_SUBJECT = "zásilka služby Úschovna.cz"


class State:
    """Everything both servers share, behind one lock."""

    def __init__(self, store):
        self.lock = threading.Lock()
        self.store = store
        self.settings = {
            "slow_kbps": 0,
            "test_xss_fails": False,
            "no_upload_host": False,
            "link_style": "public",
            # "secret" answers finish with "{public}/{secret}" as the real server does; "plain"
            # with a code that has no slash, to check the client won't share a link it can't vouch for.
            "finish_code_style": "secret",
            # The values the mock answers with where the page compares loosely (`1 == e.status`).
            # The real package_target answers `"status": true`; the others haven't been seen.
            "answers": dict(DEFAULT_ANSWERS),
        }
        self.www_origin = ""
        self.upload_host = ""
        # Bumped by every reset. A request remembers the generation it started in, so one that
        # outlives a reset (a cancelled client's chunk still draining from the kernel's buffers)
        # can't land in the next scenario's state.
        self.generation = 0
        self.reset()

    def reset(self):
        self.generation += 1
        self.sessions = set()
        self.targets = []
        self.packages = {}
        self.tmps = {}
        self.requests = []
        self.chunks = []
        self.still_alive = []
        self.aborted = []
        self.errors = []
        self.links = []
        self.rules = []
        self.counters = {}

    def set_rules(self, rules):
        self.rules = [dict(rule) for rule in rules]
        self.counters = {}

    def fault_for(self, endpoint):
        """Counts this request to `endpoint` and returns the rule that applies to it, if any."""
        count = self.counters.get(endpoint, 0) + 1
        self.counters[endpoint] = count
        for rule in self.rules:
            if rule.get("endpoint", "ajax_upload") != endpoint:
                continue
            first = int(rule.get("at", 1))
            if first <= count < first + int(rule.get("times", 1)):
                return rule
        return None

    def error(self, message):
        self.errors.append(message)
        print(f"  ! {message}", file=sys.stderr, flush=True)


STATE: State = None  # set in main()


def answer(name):
    return STATE.settings["answers"].get(name, DEFAULT_ANSWERS[name])


def check_agent(endpoint, entry):
    agent = entry["user_agent"] or ""
    if not agent.startswith("quickUschovna/"):
        STATE.error(f"{endpoint}: unexpected User-Agent {agent!r}")


def new_code(length=16):
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(length))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    role = "www"  # set on the subclass per server
    server_version = "MockUschovna/1.0"

    def log_message(self, format, *args):
        if ARGS.verbose:
            sys.stderr.write(f"[{self.role}] {format % args}\n")

    # MARK: Plumbing

    def header(self, name):
        return self.headers.get(name)

    def cookie_session(self):
        cookie = self.header("Cookie") or ""
        for part in cookie.split(";"):
            key, _, value = part.strip().partition("=")
            if key == "PHPSESSID":
                return value
        return None

    def read_body(self, slow=False):
        """Reads the request body, throttled when the link is set to be slow. Returns None when
        the client went away mid-body."""
        length = int(self.header("Content-Length") or 0)
        if length == 0:
            return b""
        kbps = STATE.settings.get("slow_kbps", 0) if slow else 0
        if not kbps:
            data = self.rfile.read(length)
            return data if len(data) == length else None
        parts = []
        received = 0
        rate = kbps * 1024
        piece = 8192
        started = time.monotonic()
        while received < length:
            try:
                data = self.rfile.read(min(piece, length - received))
            except (ConnectionError, socket.timeout, OSError):
                return None
            if not data:
                return None
            parts.append(data)
            received += len(data)
            ahead = received / rate - (time.monotonic() - started)
            if ahead > 0:
                time.sleep(ahead)
        return b"".join(parts)

    def send(self, status, body, content_type="application/json", extra=None):
        payload = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def send_json(self, value, status=200, extra=None):
        self.send(status, json.dumps(value), "application/json", extra)

    def drop(self):
        """Closes the connection without an answer."""
        self.close_connection = True
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def record(self, endpoint):
        entry = {
            "role": self.role,
            "method": self.command,
            "endpoint": endpoint,
            "path": self.path,
            "cookie": self.cookie_session(),
            "x_requested_with": self.header("X-Requested-With"),
            "origin": self.header("Origin"),
            "referer": self.header("Referer"),
            "user_agent": self.header("User-Agent"),
            "content_type": self.header("Content-Type"),
            "headers": [[key, value] for key, value in self.headers.items()],
            "time": time.time(),
        }
        STATE.requests.append(entry)
        return entry

    def check_browser_headers(self, endpoint, entry, jquery):
        """What the page's browser would send. `jquery` requests carry X-Requested-With only on
        the site; the upload XHR always does."""
        check_agent(endpoint, entry)
        if any(key.lower().startswith("upload-") for key, _ in entry["headers"]):
            STATE.error(f"{endpoint}: resumable-upload headers, which a browser doesn't send")
        if self.command == "POST" and entry["origin"] != STATE.www_origin:
            STATE.error(f"{endpoint}: Origin {entry['origin']!r}, expected {STATE.www_origin!r}")
        if self.role == "upload":
            if entry["cookie"] is not None:
                STATE.error(f"{endpoint}: a cookie went to the upload host, which a browser wouldn't send")
            if entry["referer"] != STATE.www_origin + "/":
                STATE.error(f"{endpoint}: cross-origin Referer {entry['referer']!r}")
        else:
            if entry["referer"] != STATE.www_origin + "/poslat-zasilku":
                STATE.error(f"{endpoint}: Referer {entry['referer']!r}")
        wants_xrw = (not jquery) or self.role == "www"
        if wants_xrw and entry["x_requested_with"] != "XMLHttpRequest":
            STATE.error(f"{endpoint}: X-Requested-With missing on the {self.role} host")
        if not wants_xrw and entry["x_requested_with"] is not None:
            STATE.error(f"{endpoint}: X-Requested-With sent cross-origin, which jQuery wouldn't")
        if jquery:
            query = urllib.parse.urlsplit(self.path).query
            if not query.isdigit():
                STATE.error(f"{endpoint}: no millisecond timestamp query ({self.path})")

    def form(self, body):
        return urllib.parse.parse_qs(body.decode("utf-8"), keep_blank_values=True)

    # MARK: Routing

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == "/__state":
            with STATE.lock:
                return self.send_json(snapshot())
        if self.role == "www" and path == "/poslat-zasilku":
            return self.send_page()
        if self.role == "www" and path.startswith("/zasilka/"):
            return self.package_page(path[len("/zasilka/"):])
        self.send(404, "not here", "text/plain")

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == "/__control":
            return self.control()
        if path.startswith("/ajax/ajax_upload/"):
            return self.ajax_upload(path)
        body = self.read_body()
        if body is None:
            return self.drop()
        with STATE.lock:
            if path == "/ajax/package_target/" and self.role == "www":
                return self.package_target(body)
            if path == "/ajax/test_xss":
                return self.test_xss()
            if path == "/ajax/zalozeni_zasilky":
                return self.zalozeni_zasilky(body)
            if path == "/ajax/still_alive" and self.role == "www":
                return self.still_alive(body)
            STATE.error(f"POST to an unknown endpoint {self.role}:{path}")
        self.send(404, "not here", "text/plain")

    # MARK: Control

    def control(self):
        body = self.read_body() or b"{}"
        command = json.loads(body)
        with STATE.lock:
            if command.get("reset"):
                STATE.reset()
            STATE.settings.update(command.get("settings", {}))
            if "rules" in command:
                STATE.set_rules(command["rules"])
        self.send_json({"ok": True})

    # MARK: The site

    def send_page(self):
        with STATE.lock:
            entry = self.record("page")
            check_agent("page", entry)
            fault = STATE.fault_for("page")
            session = entry["cookie"]
            extra = {}
            if session not in STATE.sessions:
                session = new_code(26).lower()
                STATE.sessions.add(session)
                extra["Set-Cookie"] = f"PHPSESSID={session}; path=/"
        if fault and fault["kind"] == "http500":
            return self.send(500, "<html>oops</html>", "text/html")
        page = (
            "<!DOCTYPE html><html><head><title>Úschovna (mock)</title></head><body>"
            '<form id="upload_form" action="/uploaded/1/" method="post"></form>'
            f'<script type="text/javascript" src="/www/js/uschovna.js?v{SCRIPT_VERSION}"></script>'
            "</body></html>"
        )
        self.send(200, page, "text/html; charset=UTF-8", extra)

    def package_target(self, body):
        entry = self.record("package_target")
        self.check_browser_headers("package_target", entry, jquery=True)
        if entry["cookie"] not in STATE.sessions:
            STATE.error("package_target: no PHPSESSID from the send page")
        fault = STATE.fault_for("package_target")
        if fault and fault["kind"] == "http500":
            return self.send(500, "<html>oops</html>", "text/html")
        fields = self.form(body)
        names = fields.get("filenames[]", [])
        size = int(fields.get("size", ["0"])[0])
        if not names:
            STATE.error("package_target: no filenames[]")
        STATE.targets.append({"session": entry["cookie"], "filenames": names, "size": size})
        reply = {"status": answer("package_target_status")}
        if not STATE.settings["no_upload_host"]:
            reply["name"] = STATE.upload_host
        self.send_json(reply)

    def test_xss(self):
        entry = self.record("test_xss")
        self.check_browser_headers("test_xss", entry, jquery=True)
        if STATE.settings["test_xss_fails"]:
            return self.send(200, "<html>no</html>", "text/html")
        self.send_json(answer("test_xss"))

    def zalozeni_zasilky(self, body):
        fields = self.form(body)
        if "dokoncit" in fields:
            return self.finish(fields)
        entry = self.record("create")
        self.check_browser_headers("create", entry, jquery=True)
        fault = STATE.fault_for("create")
        if fault and fault["kind"] == "http500":
            return self.send(500, "<html>oops</html>", "text/html")
        if fault and fault["kind"] == "refuse":
            return self.send_json({"status": 0})
        expected = {
            "message": "",
            "premium_checkbox": "0",
            "vice_moznosti": "1",
            "mail_subject": MAIL_SUBJECT,
            "language_to": "cs",
        }
        for key, value in expected.items():
            if fields.get(key) != [value]:
                STATE.error(f"create: {key}={fields.get(key)!r}, the page sends {value!r}")
        if "package_recipients[]" in fields:
            STATE.error("create: package_recipients[] sent with no recipients")
        sender = fields.get("sender_mail", [""])[0]
        if "@" not in sender:
            STATE.error(f"create: sender_mail {sender!r}")
        if not STATE.targets:
            STATE.error("create: no package_target before it")
            return self.send_json({"status": 0})
        target = STATE.targets[-1]
        code = new_code()
        STATE.packages[code] = {
            "code": code,
            # The real shape, e.g. ABCDEFGH23456789-XYZ/QRSTUVWXYZ: the recipients' code, then the
            # sender's secret, which opens the page that can delete the package.
            "public_code": f"{code}-{new_code(3)}",
            "secret": new_code(10),
            "role": self.role,
            "sender": sender,
            "filenames": target["filenames"],
            "size": target["size"],
            "files": {},
            "finished": False,
        }
        self.send_json({"status": answer("create_status"), "code": code})

    def finish(self, fields):
        entry = self.record("finish")
        if self.role != "www":
            STATE.error("finish: sent to the upload host, but the page finishes on the site")
        self.check_browser_headers("finish", entry, jquery=True)
        if entry["cookie"] not in STATE.sessions:
            STATE.error("finish: no PHPSESSID from the send page")
        fault = STATE.fault_for("finish")
        if fault and fault["kind"] == "http500":
            return self.send(500, "<html>oops</html>", "text/html")
        if fault and fault["kind"] == "refuse":
            return self.send_json({"status": 0})
        if fields.get("dokoncit") != ["true"]:
            STATE.error(f"finish: dokoncit={fields.get('dokoncit')!r}")
        code = fields.get("package_code", [""])[0]
        package = STATE.packages.get(code)
        if not package:
            STATE.error("finish: unknown package_code")
            return self.send_json({"status": 0})
        missing = [n for n in package["filenames"] if not package["files"].get(n, {}).get("complete")]
        if missing:
            STATE.error(f"finish: {len(missing)} file(s) not complete")
            return self.send_json({"status": 0})
        plain = STATE.settings["finish_code_style"] == "plain"
        finish_code = package["public_code"] if plain else f"{package['public_code']}/{package['secret']}"
        if not package["finished"]:
            package["finished"] = True
            package["finish_code"] = finish_code
            link = f"{STATE.www_origin}/zasilka/{package['public_code']}/"
            STATE.links.append(link)
            print(f"share link: {link}   (sender's page: {STATE.www_origin}/zasilka/{finish_code})", flush=True)
        self.send_json({"status": answer("finish_status"), "code": package["finish_code"]})

    def still_alive(self, body):
        entry = self.record("still_alive")
        self.check_browser_headers("still_alive", entry, jquery=True)
        code = self.form(body).get("package_code", [""])[0]
        if code not in STATE.packages:
            STATE.error("still_alive: unknown package_code")
        STATE.still_alive.append({"code": code, "time": time.time()})
        self.send_json({"status": 1})

    def package_page(self, rest):
        """/zasilka/{public}/{secret} is the sender's page, /zasilka/{public}/ the recipients'. A
        code that has no secret (finish_code_style "plain") opens the sender's page either way."""
        with STATE.lock:
            entry = self.record("package_page")
            check_agent("package_page", entry)
            if entry["cookie"] not in STATE.sessions:
                STATE.error("package_page: opened without the send page's PHPSESSID")
            if "%2f" in rest.lower():
                # Apache refuses an encoded slash in a path (AllowEncodedSlashes Off).
                STATE.error("package_page: the slash in the code was sent encoded, which gets a 404")
                return self.send(404, "<html><h1>Not Found</h1></html>", "text/html; charset=iso-8859-1")
            parts = urllib.parse.unquote(rest).split("/")
            plain = STATE.settings["finish_code_style"] == "plain"
            package = next((p for p in STATE.packages.values() if p["public_code"] == parts[0]), None)
            view = None
            if package and len(parts) == 2 and parts[1] == package["secret"] and not plain:
                view = "sender"
            elif package and (parts[1:] in ([], [""])):
                view = "sender" if plain else "recipient"
            entry["view"] = view
            style = STATE.settings["link_style"]
        if view is None:
            return self.send(404, "<html>Zásilka nenalezena</html>", "text/html; charset=UTF-8")
        public = f"{STATE.www_origin}/zasilka/{package['public_code']}/"
        if view == "recipient":
            page = (
                "<!DOCTYPE html><html><body><div id=\"zasilka_wrapper\">"
                f"<h1>{package['sender']} vám posílá zásilku</h1>"
                f'<div class="soubor"><a class="iframe_download button_down" href="/download/x/1">stáhnout</a>'
                '<span>staženo 0 x</span> <span>zbývá <span class="download-count-left">30</span> stažení</span></div>'
                "</div></body></html>"
            )
            return self.send(200, page, "text/html; charset=UTF-8")
        link = {
            "public": public,
            "public-suffix": public + "sdilet",
            "anchor": public,
            "secret": f"{STATE.www_origin}/zasilka/{package['public_code']}/{package['secret']}",
            "elsewhere": f"{STATE.www_origin}/zasilka/{new_code()}-ABC/",
            "foreign": f"https://example.com/zasilka/{package['public_code']}/",
            "unrelated": f"{STATE.www_origin}/uschovna_plus",
        }.get(style)
        if style == "anchor":
            element = f'<div class="l data package-link"><a href="{link}">{link}</a></div>'
        elif link:
            # The real page follows the link with tabs.
            element = f'<div class="l data package-link">{link}\t\t\t\t</div>'
        else:
            element = ""
        page = (
            "<!DOCTYPE html><html><body><div id=\"zasilka_wrapper\">"
            "<h1>vaše zásilka byla úspěšně odeslána</h1>"
            f"<div class=\"c\"><div class=\"l label\">odkaz</div>{element}</div>"
            '<a id="button_smazat_zasilku" href="#">SMAZAT ZÁSILKU</a> <a href="#">prodloužit</a>'
            f'<a href="{STATE.www_origin}/cenik">ceník</a>'
            "</div></body></html>"
        )
        self.send(200, page, "text/html; charset=UTF-8")

    # MARK: Chunks

    def ajax_upload(self, path):
        with STATE.lock:
            entry = self.record("ajax_upload")
            generation = STATE.generation
            number = len(STATE.chunks) + 1
            fault = STATE.fault_for("ajax_upload")
        if not path[len("/ajax/ajax_upload/"):].isdigit():
            with STATE.lock:
                STATE.error(f"ajax_upload: no millisecond timestamp in {path}")
        kind = fault["kind"] if fault else None

        if kind == "drop":
            # Read part of the body, then hang up: the chunk never arrives.
            length = int(self.header("Content-Length") or 0)
            try:
                self.rfile.read(max(1, length // 2))
            except OSError:
                pass
            print(f"  fault: dropped chunk {number} mid-body", file=sys.stderr, flush=True)
            return self.drop()

        body = self.read_body(slow=True)
        with STATE.lock:
            stale = STATE.generation != generation
            if body is None and not stale:
                STATE.aborted.append({"chunk": number, "time": time.time()})
        if stale:
            print(f"  ignoring chunk {number}: it began before the last reset", file=sys.stderr, flush=True)
            return self.drop()
        if body is None:
            print(f"  client went away during chunk {number}", file=sys.stderr, flush=True)
            return self.drop()

        if kind == "stall":
            seconds = float(fault.get("seconds", 5))
            print(f"  fault: stalling chunk {number} for {seconds}s", file=sys.stderr, flush=True)
            time.sleep(seconds)
            return self.drop()
        if kind == "http500":
            return self.send(500, "<html>Internal Server Error</html>", "text/html")
        if kind == "bad_json":
            return self.send(200, "<html><b>Warning</b>: something</html>", "text/html")
        if kind == "fatal":
            return self.send_json({"res": 0})

        with STATE.lock:
            if STATE.generation != generation:
                print(f"  ignoring chunk {number}: it began before the last reset", file=sys.stderr, flush=True)
                return self.drop()
            self.check_browser_headers("ajax_upload", entry, jquery=False)
            answer = self.store_chunk(number, body)
        if kind == "lose_response":
            print(f"  fault: stored chunk {number}, then lost the answer", file=sys.stderr, flush=True)
            return self.drop()
        self.send_json(answer)

    def store_chunk(self, number, body):
        """Checks a chunk against the protocol and writes it where X_USIZE says. Returns the
        answer the client gets."""
        headers = {name: self.header(name) for name in ("X_PACKAGE", "X_NAME", "X_SIZE", "X_USIZE", "X_CSIZE", "X_TMP")}
        for name, value in headers.items():
            if value is None:
                STATE.error(f"chunk {number}: header {name} missing")
                return {"res": 0}
        name = urllib.parse.unquote(headers["X_NAME"])
        # encodeURIComponent leaves letters, digits and -_.!~*'() alone and escapes all else.
        if headers["X_NAME"] != urllib.parse.quote(name, safe="!*'()"):
            STATE.error(f"chunk {number}: X_NAME {headers['X_NAME']!r} isn't encodeURIComponent of {name!r}")
        size, offset, csize = int(headers["X_SIZE"]), int(headers["X_USIZE"]), int(headers["X_CSIZE"])
        tmp = headers["X_TMP"]
        STATE.chunks.append({
            "n": number, "role": self.role, "name": name, "size": size, "usize": offset,
            "csize": csize, "tmp": tmp, "length": len(body),
            "content_type": self.header("Content-Type"), "time": time.time(),
        })
        package = STATE.packages.get(headers["X_PACKAGE"])
        if package is None:
            STATE.error(f"chunk {number}: unknown X_PACKAGE")
            return {"res": 0}
        if package["role"] != self.role:
            STATE.error(f"chunk {number}: went to {self.role}, the package was created on {package['role']}")
        if csize != len(body):
            STATE.error(f"chunk {number}: X_CSIZE {csize} but {len(body)} bytes came")
            return {"res": 0}
        if name not in package["filenames"]:
            STATE.error(f"chunk {number}: X_NAME {name!r} isn't one of package_target's names")
            return {"res": 0}
        expected = next((n for n in package["filenames"] if not package["files"].get(n, {}).get("complete")), None)
        if name != expected:
            STATE.error(f"chunk {number}: {name!r} sent while {expected!r} isn't complete")
        if offset + csize > size:
            STATE.error(f"chunk {number}: X_USIZE {offset} + X_CSIZE {csize} is past X_SIZE {size}")
            return {"res": 0}

        if tmp == "":
            if offset != 0:
                STATE.error(f"chunk {number}: a new file (no X_TMP) starting at {offset}")
                return {"res": 0}
            tmp = new_code(12).lower()
            path = os.path.join(STATE.store, "partial", tmp)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").close()
            STATE.tmps[tmp] = {"package": package["code"], "name": name, "size": size, "received": 0, "path": path}
        record = STATE.tmps.get(tmp)
        if record is None or record["package"] != package["code"] or record["name"] != name:
            STATE.error(f"chunk {number}: X_TMP doesn't belong to this file")
            return {"res": 0}
        if record["size"] != size:
            STATE.error(f"chunk {number}: X_SIZE changed from {record['size']} to {size}")
            return {"res": 0}
        if offset > record["received"]:
            STATE.error(f"chunk {number}: X_USIZE {offset} leaves a gap after {record['received']}")
            return {"res": 0}
        if offset < record["received"]:
            print(f"  chunk {number}: rewound from {record['received']} to {offset}", file=sys.stderr, flush=True)
            STATE.chunks[-1]["rewound"] = True

        with open(record["path"], "r+b") as handle:
            handle.truncate(offset)
            if body == bytes(len(body)):
                # Zeros: extend the file instead of writing them, so a sparse test file stays sparse.
                handle.truncate(offset + len(body))
            else:
                handle.seek(offset)
                handle.write(body)
        record["received"] = offset + len(body)

        if record["received"] < size:
            return {"res": answer("res1"), "usize": record["received"], "tmp": tmp}
        folder = os.path.join(STATE.store, package["code"])
        os.makedirs(folder, exist_ok=True)
        final = os.path.join(folder, name.replace("/", "_"))
        os.replace(record["path"], final)
        package["files"][name] = {"size": size, "path": final, "complete": True}
        del STATE.tmps[tmp]
        return {"res": answer("res2")}


def snapshot():
    return {
        "settings": STATE.settings,
        "sessions": sorted(STATE.sessions),
        "targets": STATE.targets,
        "packages": list(STATE.packages.values()),
        "requests": STATE.requests,
        "chunks": STATE.chunks,
        "still_alive": STATE.still_alive,
        "aborted": STATE.aborted,
        "errors": STATE.errors,
        "links": STATE.links,
        "store": STATE.store,
    }


def handler_for(role):
    return type(f"{role.capitalize()}Handler", (Handler,), {"role": role})


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # A fixed, modest receive buffer, inherited by every accepted connection. Over loopback the
        # kernel would otherwise grow it to megabytes and swallow a whole chunk at once, which no
        # slow uplink does; with it, the client's sending is paced by --slow-kbps as on a real link.
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 128 * 1024)
        super().server_bind()

    def handle_error(self, request, client_address):
        # A client hanging up on a kept-alive connection, or mid-body after a fault, is normal here.
        error = sys.exc_info()[1]
        if isinstance(error, (ConnectionError, socket.timeout, TimeoutError)):
            return
        super().handle_error(request, client_address)


ARGS = None


def main():
    global STATE, ARGS
    parser = argparse.ArgumentParser(description="Mock Úschovna upload protocol (docs/uschovna-protocol.md).")
    parser.add_argument("--www-port", type=int, default=8780, help="the site's port (0: any free one)")
    parser.add_argument("--upload-port", type=int, default=8781, help="the upload host's port (0: any free one)")
    parser.add_argument("--store", help="where uploaded files go (default: a new temporary directory)")
    parser.add_argument("--ready-file", help="write the chosen ports and store here as JSON once listening")
    parser.add_argument("--slow-kbps", type=int, default=0, help="read chunk bodies at this many KiB/s")
    parser.add_argument("--drop-chunk", type=int, help="hang up halfway through this chunk")
    parser.add_argument("--lose-response-chunk", type=int, help="store this chunk, then hang up without answering")
    parser.add_argument("--stall-chunk", type=int, help="stall on this chunk, then hang up")
    parser.add_argument("--stall-seconds", type=float, default=90, help="how long --stall-chunk stalls")
    parser.add_argument("--http500-chunk", type=int, help="answer HTTP 500 from this chunk on")
    parser.add_argument("--http500-times", type=int, default=3, help="how many chunks get the 500")
    parser.add_argument("--fatal-chunk", type=int, help="answer res=0 to this chunk")
    parser.add_argument("--test-xss-fails", action="store_true", help="make test_xss fail, so the site is used")
    parser.add_argument("--no-upload-host", action="store_true", help="name no upload host in package_target")
    parser.add_argument("--link-style", default="public",
                        choices=["public", "public-suffix", "anchor", "secret", "elsewhere", "foreign", "unrelated", "none"],
                        help="what the sender's package page shows as its package link (the real one: public)")
    parser.add_argument("--plain-finish-code", action="store_true",
                        help="answer finish with a code that has no '/secret' part")
    parser.add_argument("--answers", default="real", choices=sorted(ANSWER_STYLES),
                        help="how status and res values are written: as the real server was seen to "
                             "(package_target status true, the rest numbers), all booleans, all numbers, "
                             "or numeric strings")
    parser.add_argument("--verbose", action="store_true", help="log every request")
    ARGS = parser.parse_args()

    store = ARGS.store or tempfile.mkdtemp(prefix="mock-uschovna-")
    os.makedirs(store, exist_ok=True)
    STATE = State(store)
    STATE.settings.update({
        "slow_kbps": ARGS.slow_kbps,
        "test_xss_fails": ARGS.test_xss_fails,
        "no_upload_host": ARGS.no_upload_host,
        "link_style": ARGS.link_style,
        "finish_code_style": "plain" if ARGS.plain_finish_code else "secret",
        "answers": dict(DEFAULT_ANSWERS, **ANSWER_STYLES[ARGS.answers]),
    })
    rules = []
    if ARGS.drop_chunk:
        rules.append({"kind": "drop", "at": ARGS.drop_chunk})
    if ARGS.lose_response_chunk:
        rules.append({"kind": "lose_response", "at": ARGS.lose_response_chunk})
    if ARGS.stall_chunk:
        rules.append({"kind": "stall", "at": ARGS.stall_chunk, "seconds": ARGS.stall_seconds})
    if ARGS.http500_chunk:
        rules.append({"kind": "http500", "at": ARGS.http500_chunk, "times": ARGS.http500_times})
    if ARGS.fatal_chunk:
        rules.append({"kind": "fatal", "at": ARGS.fatal_chunk})
    STATE.set_rules(rules)

    www = Server(("127.0.0.1", ARGS.www_port), handler_for("www"))
    upload = Server(("127.0.0.1", ARGS.upload_port), handler_for("upload"))
    STATE.www_origin = f"http://127.0.0.1:{www.server_address[1]}"
    STATE.upload_host = f"127.0.0.1:{upload.server_address[1]}"
    threading.Thread(target=upload.serve_forever, daemon=True).start()

    print(f"mock Úschovna: site {STATE.www_origin}, upload host {STATE.upload_host}, files in {store}", flush=True)
    if ARGS.ready_file:
        with open(ARGS.ready_file + ".tmp", "w") as handle:
            json.dump({"www": www.server_address[1], "upload": upload.server_address[1], "store": store}, handle)
        os.replace(ARGS.ready_file + ".tmp", ARGS.ready_file)
    try:
        www.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
