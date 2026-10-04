<img src="design/icon/AppIcon.png" width="128" alt="quickUschovna's icon: a parcel with an up arrow">

# quickUschovna

Drop files on the menu bar, get an [Úschovna](https://www.uschovna.cz) link on your clipboard.
A menu-bar app for macOS 27. Unofficial: not made or endorsed by Úschovna.

## Install

1. Download the `.dmg` from [the latest release](https://github.com/Luksanss/quickUschovna/releases/latest)
   and drag the app to Applications.
2. The first launch is blocked because the app isn't notarized: System Settings → Privacy &
   Security → Open Anyway.
3. Optional, for Finder's right-click menu: right-click a file → Quick Actions › Customize… → tick
   Send with Úschovna.

To update, click the icon → Check for Updates…. A version without that item is updated once by
hand, the same way as installing.

## Use

- Drag files towards the menu-bar icon and drop them on the zone that opens under it, or in Finder,
  right-click → Quick Actions › Send with Úschovna.
- The link lands on your clipboard. The first send asks for your email, the package's sender.
- Click the icon for what's sending, your links from the last 14 days, and settings.

## Good to know

- **It can break any day.** Úschovna has no API, so the app uploads the way their website does.
  It's for a person's own sends, not bulk or automated sending. Their
  [terms](https://www.uschovna.cz/vseobecne_podminky_uschovna) only describe the website; decide
  for yourself.
- **Recipients see your email address** on the download page. Your files go to Úschovna and
  nowhere else; the app has no analytics or telemetry.
- **Úschovna's free limits apply:** 30 GB per package, kept 14 days.
  [Úschovna+](https://www.uschovna.cz/cenik) lifts them and pays for the free service.

## Build

Open `quickUschovna.xcodeproj`, choose your team for both targets, and build the quickUschovna
scheme. `scripts/uschovna/run-tests.sh` tests the Úschovna client against a local mock. Where the
work stands: [`docs/handoff.md`](docs/handoff.md).
