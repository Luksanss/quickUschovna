# quickUschovna

Drop files on the menu bar, get an [Úschovna](https://www.uschovna.cz) link.

Úschovna is a Czech service for sending files that are too big for email or chat, up to 30 GB
for free. Sending through the website means opening a browser, loading the page, typing your
email, adding the files and waiting for the link. quickUschovna is a macOS menu-bar app that
does it in one move: drag files onto its icon, and when the upload finishes the link is on your
clipboard. You type your email once, in its settings.

**Status: not built yet.** It's being designed. There's nothing to download.

## How it uses Úschovna

quickUschovna is **unofficial**. It isn't made, endorsed or supported by Úschovna or its
operator, TISCALI MEDIA, a.s.

Úschovna has no public API. quickUschovna sends your files the way the website does, to the
same servers, as one package like one you'd send by hand. That has consequences you should know
about:
- **It can stop working at any time.** Úschovna's terms let them change the service without
  notice, and a change to their website can break the app until it's updated.
- **It's for personal use,** a person's sends at a person's pace. Don't use it to send in bulk
  or automatically.
- **Úschovna's terms describe uploading through their website** and don't mention other clients.
  Read [their terms](https://www.uschovna.cz/vseobecne_podminky_uschovna) and decide for
  yourself.
- **The free service is paid for by the ads on Úschovna's website.** If you send often,
  [Úschovna+](https://www.uschovna.cz/cenik) supports them, removes the ads, and lifts the
  limits below.

Úschovna's limits apply, as their [price list](https://www.uschovna.cz/cenik) stated them on
2026-10-04:

| | Free | Premium package | Úschovna+ |
|---|---|---|---|
| Package size | 30 GB | 50 GB | 50 GB |
| Kept for | 14 days | 90 days | 90 days, plus 50 GB kept for good |
| Downloads per link | 30 | unlimited | unlimited |
| Price | free | 40 Kč per package | 79 Kč / 3 months, 259 Kč / year |

## Privacy

Your files go from your Mac straight to Úschovna, and nowhere else. Your email address is kept
in the app's settings on your Mac and sent only to Úschovna, as the sender of each package, just
as the website would send it. Úschovna emails the sender a control message for each package, and
[its privacy policy](https://www.uschovna.cz/Zasady%20zpracovani%20osobnich%20udaju%20Uschovna.pdf)
says how it uses sender addresses, marketing included. quickUschovna itself has no analytics,
crash reporting or telemetry.

## More

Where the work stands, and what was found out about Úschovna, is in
[`docs/handoff.md`](docs/handoff.md).
