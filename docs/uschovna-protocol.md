# Úschovna's upload protocol

How the website at <https://www.uschovna.cz> uploads a package, and how quickUschovna's client
(`quickUschovna/Uschovna/`) mirrors it.

**Source.** Read on **2026-10-04** from the send page `https://www.uschovna.cz/poslat-zasilku` and
the script it loads, `https://www.uschovna.cz/www/js/uschovna.js?v1.1.85` (312,484 bytes,
`Last-Modified: Tue, 17 Mar 2026`). The bundle is minified; it was formatted with Prettier and the
send flow traced by hand. Only public pages and the script were fetched with GET. Nothing was
posted, no package was created, and no address was entered anywhere. Everything below about the
server's answers comes from how the page's code reads them, except what's marked **seen**: the
first real upload (2026-10-04, one small file, made by the integrator with the maintainer's
permission) settled some of it. The **Open questions** section lists what's still open.

Úschovna has no API, and none of this is documented or promised by its operator. The page's
minified names (`nm`, `tm`, `Rm`…) change with every build; the endpoint paths, fields and headers
are what matter.

## The flow at a glance

| # | Request | Where | Purpose |
|---|---|---|---|
| 0 | `GET /poslat-zasilku` | site | The send page. Sets `PHPSESSID`. |
| 1 | `POST /ajax/package_target/?{ms}` | site | File names and total size in; the upload host's name out. |
| 2 | `POST {host}/ajax/test_xss?{ms}` | upload host | Can the page talk to that host? If not, it uses the site. |
| 3 | `POST {host}/ajax/zalozeni_zasilky?{ms}` | upload host | Creates the package; returns its code. |
| 4 | `POST {host}/ajax/ajax_upload/{ms}` | upload host | One chunk of one file, raw. Repeated until every file is in. |
| 5 | `POST /ajax/still_alive?{ms}` | site | Once every 12 hours of uploading. |
| 6 | `POST /ajax/zalozeni_zasilky?{ms}` with `dokoncit` | **site** | Finishes the package; returns `{public}/{secret}`. |
| 7 | `GET /zasilka/{public}/{secret}` | site | The page goes here: the sender's page, which shows the link to share, `/zasilka/{public}/`. |

"Site" is the page's own origin, `https://www.uschovna.cz`. "Upload host" is whatever step 1
names (or the site, when step 1 names nothing or step 2 fails). `{ms}` is `Date.now()`, a
millisecond timestamp. Note that step 6, and step 5, go to the **site** even when the files went
to an upload host: the page builds those two URLs without the upload host's prefix.

## The page and its session

- The home page `/` has no upload form; it links to `/poslat-zasilku` (`/en/poslat-zasilku` and
  `/sk/poslat-zasilku` are the same page in other languages).
- Any page load sets `PHPSESSID=…; path=/`: host-only, no `Secure`, `HttpOnly` or `SameSite`
  attributes. It's the only cookie the upload flow involves.
- The AJAX flow uses **no hidden field, token or CSRF value** from the page. The form
  `#upload_form` (action `/uploaded/{number}/`, fields `f[]`, `akce=upload`,
  `APC_UPLOAD_PROGRESS`) is the old multipart upload, used only by browsers without the File
  API; the client ignores it.
- The server is Apache 2.4 (Debian) and speaks HTTP/1.1 only (no HTTP/2 offered).
- A GET of `/poslat-zasilku` with the client's own User-Agent gets the same page as a browser.

## How the page sends its requests

Steps 1, 2, 3, 5 and 6 go through one helper (`ajax_dotaz`), a jQuery 1.11.0 `$.ajax` call:

- `POST` to the path plus `?` plus `Date.now()`.
- The body is `$.param(data)`: `application/x-www-form-urlencoded; charset=UTF-8`, every key and
  value through `encodeURIComponent`, pairs joined with `&`, and `%20` turned into `+`. An array
  field `a: [x, y]` is written `a%5B%5D=x&a%5B%5D=y`; **an empty array writes nothing at all**;
  `true` is written `true`.
- `Accept: application/json, text/javascript, */*; q=0.01` (it asks for JSON). A 2xx answer that
  doesn't parse as JSON counts as an error.
- jQuery adds `X-Requested-With: XMLHttpRequest` only to **same-origin** requests.
- No `withCredentials`: cross-origin requests to an upload host carry **no cookies**, and cookies
  they set are ignored.
- The browser adds `Origin: https://www.uschovna.cz` to every POST, and a `Referer`: the full
  page URL on the site, only `https://www.uschovna.cz/` cross-origin (the default
  `strict-origin-when-cross-origin` policy; the page sets none).

The chunk upload (step 4) is a plain `XMLHttpRequest` and sets `X-Requested-With` itself, on any
origin.

### The answers are compared loosely

Every check the page makes on a value in Úschovna's answers uses JavaScript's loose `==` or `!=`,
never `===`. The only strict checks are on whether a field is there at all (`void 0 === s.status`):

| Step | The page's check |
|---|---|
| 1 `package_target` | `void 0 === s.status \|\| 1 != s.status` fails it |
| 2 `test_xss` | `"error" == answer` falls back to the site |
| 3 create | `1 == e.status`, then `0 != code` |
| 4 chunk | `1 == a.res`, else `2 == a.res`, else fatal (`200 == xhr.status` compares the HTTP status) |
| 6 finish | `void 0 !== e.status && 1 == e.status && 0 != e.code` |

So `1 == x` holds for `1`, `true`, `"1"`, `" 1 "`, `"1.0"`, `"0x1"` and `[1]`. And `0 != code`
fails for `0`, `false`, `""` and `"0"`: all of those mean "no package". **The real server answers
`package_target` with `"status": true`** (seen on 2026-10-04), so this isn't academic. The client
mirrors JavaScript's `ToNumber` for every one of these checks (`UschovnaWire.looselyEquals`).

## 1. `POST /ajax/package_target/` (site)

Sent synchronously when Send is clicked, before anything else.

| Field | Value |
|---|---|
| `filenames[]` | Each file's name, in the order they were added. |
| `size` | The files' total size in bytes. |

Answer: JSON, e.g. `{"status": true, "name": "www307.uschovna.cz"}` (the real answer's shape, with
the host it named). `status` must be loosely 1, or the page alerts "Vyskytla se chyba na straně serveru"
("a server error occurred") and stops. `name`, if present, is the upload host: the page uses
`location.protocol + "//" + name` as the base for steps 2–4. Without `name`, everything goes to
the site. No retry.

## 2. `POST {host}/ajax/test_xss` (upload host)

Body `test=test`. Synchronous. If the request fails in any way (network, non-2xx, an answer that
isn't JSON, or, in a browser, a missing CORS header), the page drops the upload host and sends
steps 3 and 4 to the site instead. The answer's content isn't otherwise read.

## 3. `POST {host}/ajax/zalozeni_zasilky` (create)

The page's form, in this order:

| Field | The page sends | quickUschovna sends |
|---|---|---|
| `sender_mail` | the "od" field | the address from the app's settings |
| `package_recipients[]` | one per recipient | nothing: with no recipients jQuery writes no field at all |
| `message` | the message field | empty |
| `premium_checkbox` | `"1"` if ticked, else `"0"` | `"0"` |
| `vice_moznosti` | always `1` | `1` |
| `mail_subject` | the subject field, prefilled `zásilka služby Úschovna.cz` | that default |
| `language_to` | the recipients' email language, `cs` by default | `cs` |

The page asks for a sender only when there are recipients. Its own check of the sender's address
(`/ajax/emailcheck`, an MX lookup when the field loses focus) is a form nicety, not part of the
upload, and the client doesn't call it.

Answer: JSON. If `status == 1`, `code` is the package code (the page treats `0` as "no package"
and alerts "chyba při vytvoření zásilky"). If `status` isn't 1, or the request fails, the page
does nothing at all: it just stays on the spinner. No retry. Nothing else in the answer is read.

## 4. `POST {host}/ajax/ajax_upload/{ms}` (chunks)

One request per chunk, one at a time, files one after another in the order they were added. The
body is the chunk's raw bytes: a `Blob` slice with no type, so the browser sends no
`Content-Type`.

| Header | Meaning |
|---|---|
| `X-Requested-With` | `XMLHttpRequest` |
| `X_PACKAGE` | The package code from step 3. |
| `X_NAME` | The file's name through `encodeURIComponent`: `Úschovna Ž.mov` is `%C3%9Aschovna%20%C5%BD.mov`. |
| `X_SIZE` | The whole file's size in bytes. |
| `X_USIZE` | The offset this chunk starts at: 0 for a file's first chunk, then the `usize` the last answer gave. |
| `X_CSIZE` | This chunk's size in bytes. |
| `X_TMP` | Empty for a file's first chunk, then the `tmp` the last answer gave. |

The header names really contain underscores; that's what the page sends.

**Answers** (JSON, read only on HTTP 200):
- `res: 1`: continue. `usize` is the next offset (**the server's count**, not the page's) and
  `tmp` the handle to quote with the next chunk.
- `res: 2`: this file is complete. The next file starts at offset 0 with an empty `X_TMP`.
- Any other `res`: fatal. The page alerts "nahrávání zásilky selhalo" ("the upload failed") and
  stops for good.

**Errors and retries.** The page never gives up on a chunk by itself:
- any HTTP status other than 200, including a network failure (status 0): send the **same chunk
  again, from the same offset with the same `X_TMP`, after 1 second**, forever;
- a 200 whose body isn't JSON: send the same chunk again at once, forever;
- the XHR has no timeout.

So "resuming" in this protocol is simply sending the chunk at the last offset the server
confirmed; the server's `usize` is the source of truth.

**Chunk size** (`UPL_CHUNK`), worked out before each request from the speed of the last
successful chunk (`rychlost`, the chunk's bytes over the whole milliseconds from sending to the
answer, at least 1 ms, rounded down; it starts at 0 and carries over between files):
- up to 104,857.6 B/s (or before anything was measured): 104,857.6 bytes, i.e. 0.1 MiB, which
  `Blob.slice` rounds to **104,858**;
- above that and up to 2 MiB/s (2,097,152 B/s): **5 × speed**, about five seconds' worth, so
  512 KiB to 10 MiB;
- above 2 MiB/s: **10 MiB** (10,485,760 bytes).

The last chunk of a file is whatever is left.

**Empty files** are never sent: the page won't add a 0-byte file, and skips one if it has one.

## 5. `POST /ajax/still_alive` (site)

Before each chunk, if more than `still_alive_seconds` (43,200 s, **12 hours**) have passed since
the package was created or the last keep-alive, the page sends `package_code={code}` here,
asynchronously, and ignores the answer.

## 6. Finishing: `POST /ajax/zalozeni_zasilky` with `dokoncit` (site)

When the last file's last chunk gets `res: 2`: `package_code={code}&dokoncit=true`, sent to the
**site** with its `PHPSESSID`.

Answer: JSON. If `status` is loosely 1 and `code` isn't loosely 0, the page waits 3.5 s and goes
to `/zasilka/{code}`, using the `code` **from this answer**. Any other answer gets the "upload
failed" alert; a failed request gets nothing (the page just waits). No retry.

**Seen:** that code isn't the package code from step 3. It's two codes joined by a slash,
`{public}/{secret}`, shaped like `ABCDEFGH23456789-XYZ/QRSTUVWXYZ` (made up here; the real one had
the same shape). The part before the slash names the package for recipients; the part after it
is the **sender's secret**, which opens the page that can delete the package (step 7).

If an ad video is playing (`nextbranding_is_video`), the page holds the redirect until the video
ends. The finishing request itself goes out regardless.

## 7. The link

The page's last step is `window.location.href = "/zasilka/" + code`, slash and all. No answer
holds a link as a URL. **Seen** on the first real upload, there are two pages:

| URL | Page | What's on it |
|---|---|---|
| `https://www.uschovna.cz/zasilka/{public}/{secret}` | **The sender's page**: where the website goes after sending. | "vaše zásilka byla úspěšně odeslána", "SMAZAT ZÁSILKU" (`#button_smazat_zasilku`), "prodloužit" (extend). Its `.l.data.package-link` element holds `https://www.uschovna.cz/zasilka/{public}/`, followed by tabs. |
| `https://www.uschovna.cz/zasilka/{public}/` | **The recipients' page**: the link to share. | "{sender} vám posílá zásilku" ("{sender} is sending you a package"), a download button, "staženo 0 x zbývá 30 stažení" (downloaded 0 times, 30 downloads left). No delete button. |

So **the link to share is `https://www.uschovna.cz/zasilka/{public}/`**, with the trailing slash.
The sender's URL must never be shared: anyone holding it can delete or extend the package. Sending
the slash encoded (`/zasilka/{public}%2F{secret}`) gets Apache's "Not Found".

The sender's page is the script's `IS_SENDER_VIEW`; its "downloads exhausted" handling sends the
sender to `…/premium`. The FAQ says each recipient gets a code of their own; with no recipients,
the public link is the only one to share. `robots.txt` keeps crawlers off `/zasilka/`. (The prior
art printed `/zasilka/{id}` from the old multipart form, whose ids may have looked different.)

## Limits in the script

| | Value | Bytes |
|---|---|---|
| Package cap (`horni_limit_zasilky`), refused above | `51200 * 1048576` = 50 GiB | 53,687,091,200 |
| Free package (`cenik_velikost_souboru`); above it the page ticks and locks Premium (paid) | `30720 * 1048576` = 30 GiB | 32,212,254,720 |
| Files per package (`maximalni_pocet_souboru_v_zasilce`) | 1000 | |
| Recipients (`maximalni_pocet_prijemcu`) | 200 (the FAQ says 30 free) | |

The "GB" on the price list are binary: the free limit is 30 GiB. The app's
`Limits.freePackageBytes` (30,000,000,000) is decimal, so it refuses drops between 30.0 and
32.2 GB that Úschovna would take for free. That's safe, just stricter than needed.

## What could break automation

Nothing in the upload flow was found that ties a request to a browser:
- no token, nonce or signature from the page; no CAPTCHA (no reCAPTCHA, hCaptcha or Turnstile) in
  the page or the script; no timing check; nothing derived from the page load except the
  `PHPSESSID` cookie;
- the ads are client-side: branding iframes, a countdown and an optional video before the
  redirect, and an anti-adblock module at the top of the script that sets an `adb` cookie. None
  of it is part of the upload requests, and nothing seen suggests the server checks that ads
  were shown. That's a guess, though, and they could start checking any day;
- the server could check `User-Agent`, `Origin`, `Referer` or `X-Requested-With`. The client sends
  the latter three exactly as the browser would, and an honest `User-Agent` (below).

## How quickUschovna implements it

`UschovnaService` (`quickUschovna/Uschovna/`) makes one `UschovnaSession` per package. The session
does steps 0–7 in order, one request at a time, over its own ephemeral `URLSession`, so the
`PHPSESSID` from step 0 goes with every request to the site and is never shared with another
upload.

Where it matches the page exactly:
- the endpoints, fields, field order, encodings, `X_*` headers, chunk sizes and speed measure;
- `Origin`, `Referer` and `X-Requested-With` per request as above, and cookies only on the site:
  requests to an upload host are sent with cookie handling off, as a credential-less XHR would be;
- `test_xss` decides between the upload host and the site;
- `still_alive` after 12 hours, before a chunk; finishing on the site; the link from the finish
  answer's `code`;
- the server's `usize` is trusted as the next offset; a failed chunk is sent again from the last
  confirmed offset with the last `X_TMP`; empty files are skipped.

Where it deliberately differs:
- **`User-Agent: quickUschovna/<version> (macOS; +https://github.com/Luksanss/quickUschovna)`.**
  Nothing in the script or the GETs needs a browser's. If the real upload is refused because of
  it, that's the first thing to change, and this document should say why.
- **Chunks carry `Content-Type: application/octet-stream`**, where the browser sends none. Without
  one, URLSession labels a POST body `application/x-www-form-urlencoded` (checked on macOS 27),
  and a PHP server would try to parse 10 MiB of binary as form fields.
- **Chunks go as a data task with a body, not an upload task.** Upload tasks add the
  resumable-upload draft's `Upload-Complete` and `Upload-Draft-Interop-Version` headers, which a
  browser never sends.
- **File names are sent in composed Unicode (NFC).** macOS can hand out decomposed names (NFD);
  `filenames[]` and `X_NAME` both use the composed form.
- **Retries end.** The page retries a chunk every second forever. The client retries with
  1, 2, 4, 8, 15, 15 and 15 s waits (8 attempts, about a minute), then throws
  `UploadFailure.notAnswering(detail:)`, keeping the package and offset so Try Again (another
  `run`) continues from there. HTTP 5xx, 408, 429 and answers that aren't JSON are retried; other
  4xx on the non-chunk calls aren't. The page doesn't retry steps 1, 3 and 6 at all; the client
  retries them the same way, since a lost answer there would otherwise lose the whole upload.
- **Requests have a timeout**: 60 s in which URLSession sees nothing move counts as a dropped
  connection. The kernel's socket buffers take a whole chunk at once, so for a chunk that's
  roughly the time from handing it over to the answer; chunks are sized to take about 5 s, which
  leaves a link twelve times slower than the last measure before a chunk times out.
- **Network loss is waited out.** A request that fails for network reasons (offline, dropped,
  timed out, host unreachable) reports `.waitingForNetwork(sent:)`. If `NWPathMonitor` says there's
  no path, or the error itself says there's no internet, the client waits for the network with no
  limit, then reports `.connecting(sent:)` and sends the same chunk again from the same offset.
  If the network is there and requests still fail, those failures count toward the 8 attempts.
- **After a network failure, the chunk is re-measured.** The retry starts from the smallest chunk
  (104,858 bytes) at the same offset, so a chunk sized for Wi-Fi isn't pushed through a much
  slower link and timed out again. (The page resends the same size; it has no timeout to hit.)
- **A fatal `res` (or `status` other than 1) ends the package.** Try Again then starts a new
  package from zero. If a package resumed from an earlier run is refused on its first chunk, the
  client starts a new one at once, in the same run (`.connecting(sent: 0)`).
- **It shares the recipients' link, never the sender's.** It splits the finish code at its first
  slash, then opens the sender's page as the redirect would: slash unencoded, with the session
  cookie. It reads that page's `package-link` and returns the link if three things hold: it's on
  Úschovna's domain, it starts with `https://www.uschovna.cz/zasilka/{public}/`, and nothing after
  that holds the secret. Otherwise it returns that built form. The secret is never logged, not
  even as private data; the log says in public words what the page showed. A finish code with no
  slash is refused unless the page shows a different link, because the client can't tell whether
  the page such a code opens is the sender's: "Úschovna isn't answering" is better than sharing a
  link that deletes the package.
- **It refuses up front** what the page wouldn't send as a free package: nothing but empty files,
  more than 1000 files, or more than 30 GiB. A file that's missing or changed size since the drop
  is refused too.
- **Progress** is the bytes Úschovna has confirmed (`usize`), across files, at most 10 events a
  second plus one at the end of each file. It moves once per chunk, and chunks are sized to take
  about 5 s, so a UI wanting a smooth ring has to interpolate (the model already has
  `bytesPerSecond`).
- The send page's `uschovna.js?v…` version is checked on every new package. A version other than
  1.1.85 is logged as a warning (the first sign the protocol may have moved) but doesn't stop the
  upload.

Logs go to `os.Logger` (subsystem `com.luksanss.quickUschovna`, category `uschovna`), with file
names, the sender, package codes and links private:

```sh
/usr/bin/log stream --info --predicate 'subsystem == "com.luksanss.quickUschovna" AND category == "uschovna"'
```

## Testing without Úschovna

`scripts/uschovna/run-tests.sh` compiles the app's real client sources with the app's Swift
settings (Swift 6, MainActor by default, approachable concurrency) into a test harness
(`scripts/uschovna/main.swift`) and runs it against `scripts/uschovna/mock_server.py`, a stdlib
Python mock of every endpoint above. The mock plays the site and an upload host on two ports,
stores the uploaded bytes, and records every deviation from the protocol: wrong offsets, sizes or
file order, an `X_NAME` that isn't `encodeURIComponent`, cookies sent to the upload host, missing
or extra `X-Requested-With`, a wrong `Origin` or `Referer`, upload-task headers, a missing
timestamp. The harness fails a scenario on any of them.

Faults can be set per scenario (`POST /__control`) or on the command line for trying the app by
hand: `--drop-chunk N`, `--lose-response-chunk N`, `--stall-chunk N`, `--http500-chunk N`,
`--fatal-chunk N`, `--slow-kbps K`, `--test-xss-fails`, `--no-upload-host`, `--link-style …`, and
`--plain-finish-code` (a finish code with no secret), and
`--answers real|bool|number|string` for how `status` and `res` are written (`real`, the default,
answers `package_target` with `true` as the real server does).
Run `scripts/uschovna/mock_server.py --help`, and point a debug build's `UschovnaService` at
`http://127.0.0.1:8780`.

## What the first real upload settled, and what's still open

**Settled** on 2026-10-04 (one small file, two chunks, finished):
- The server takes the client as it is: the honest `User-Agent`, `Content-Type:
  application/octet-stream` on chunks, composed file names.
- `package_target` answers `"status": true`, a JSON boolean, and named the upload host
  `www307.uschovna.cz`, where the package was created (so `test_xss` passed).
- The finish code is `{public}/{secret}`, not the package code, and the link to share is the
  recipients' page `https://www.uschovna.cz/zasilka/{public}/` (step 7). A free package's
  recipients' page allows 30 downloads.

**Still open.** The log doesn't show these, so they'd need a look at the raw answers or a deliberate
fault:

1. **The other answers' exact types.** Are create's and finish's `status`, and the chunks' `res`,
   numbers or booleans? Is `usize` a number and `tmp` a string? The loose comparisons cover
   booleans, numbers and numeric strings, so this is only curiosity, except for `usize`, which must
   be a number or a string of digits.
2. **The control email** reaches the sender in Czech (`language_to=cs`, the page's language), with
   the default subject. Does it carry the recipients' link, the sender's, or both?
3. **A resent chunk after a lost answer.** If the server got a chunk but its answer was lost, the
   client (like the page) sends it again from the old offset. Does the server overwrite from
   `X_USIZE`, or append (which would corrupt the file)? The page relies on the same behaviour, so
   it presumably overwrites. A lost answer to a file's **last** chunk is worse: the server has
   probably closed that `tmp` already and would refuse the resend, which ends the package and
   makes Try Again start over.
4. **What a package that waited too long answers.** After hours offline, the upload host may have
   dropped the partial file or the package. The client expects a `res` other than 1 or 2 then,
   which ends the package (or, right after a resume, starts a new one).
5. **Whether `still_alive` matters**: it's only sent after 12 hours of uploading.
