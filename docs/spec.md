# quickUschovna: spec

What v1 does. The design is Claude Design's "quickUschovna v1" (`design/prototype/quickUschovna v1.dc.html`,
the maintainer's final pick on 2026-10-04), built one to one; where the app differs, this file says
so and why. The brief it answered is `docs/design-brief-v1.md`.

## Ways in

- **The drop zone.** Dragging files anywhere opens a 300 × 88 pt zone under the menu-bar icon. It
  fades in over 120 ms, only for file drags (not text, not windows), and closes when the drag ends.
  Over it, it reads "Release to send" in the accent colour; otherwise "Drop here to send", with
  what's being dragged and its size, or "…, over the 30 GB limit" in orange.
  - *Differs from the prototype:* a drag that includes a folder shows its label without a size.
    Measuring a folder means listing it, and before the drop that would raise macOS's permission
    prompt for Desktop, Documents or Downloads in the middle of the drag. The drop grants access;
    the size is checked then.
- **The icon** takes drops too. A file drag over it (or over the zone) shows the open box on an
  accent highlight.
- **Finder:** Quick Actions › Send with Úschovna on the selected files and folders does the same as a
  drop (`docs/quick-action.md`).

Either way the upload starts at once; nothing asks to confirm.

## One drop, one link

- However many items a drop holds, it's one package on Úschovna with one link.
- A folder is zipped first, as `<folder name>.zip` with the folder at its top, without compression
  (`quickUschovna/App/Zipper.swift`: UTF-8 names, ZIP64, `.DS_Store` left out).
- A package's label is the file's name, the folder's name plus ".zip", or "N files".
- A second drop while one is uploading queues behind it, and gets its own link and bubble.
- Over 30 GB (Úschovna's free limit, `Limits.freePackageBytes`) is refused before anything uploads.
- The link goes to the clipboard as soon as Úschovna hands it back.

## The bubble

Hangs from the icon, 300 pt wide. Only one at a time; a new one replaces the old.
- **Link copied:** what was sent, its size, "Expires Oct 18". Stays 3 s, stays while hovered and
  1.5 s after; a click opens the link in the browser; ↗ shows on hover.
- **First run:** no sender email yet, so the first drop asks for it ("Your email (the sender)").
  Return saves it and sends; an invalid address shows "That doesn’t look like an email address."
- **Too big:** "<size> is too big · Free packages are limited to 30 GB." Stays 5 s.
- **Úschovna isn’t answering:** "<name> is waiting to be sent." with Try Again. Stays until dealt with.

A click in another app closes every bubble except "Link copied", which goes by itself. Esc closes the
bubble that has the keyboard (the first-run one).

## The panel

A click on the icon opens it (the icon shades, like an open menu); another click, a click elsewhere,
or Esc closes it. It replaces any bubble.
- **Sending:** the running package with a bar and its status ("Zipping “Raw footage”…",
  "Connecting to Úschovna…", "Resuming at 1.4 GB…", "1.4 GB of 2.4 GB · 3 min left",
  "Reconnecting… 1.4 GB of 2.4 GB sent", "Úschovna isn’t answering" with Try Again), the queued
  ones as "Waiting · 1.2 GB", and a cancel button on each.
- **Recent:** links sent in the last 14 days, newest first: name, size, days left ("expires
  tomorrow" in orange). A click copies the link again ("✓ Link copied"); ↗ opens it. Empty: "Links
  you send stay here for 14 days."
- **Sender:** the address; a click edits it in place. Return or leaving the field saves a valid one.
- **Launch at Login** (through `SMAppService`; the system owns the state).
- **Quit quickUschovna.** During an upload it asks first: "Quit while sending?".

While the panel is open, a finished upload is confirmed in Recent ("✓ Link copied") instead of a
bubble, and a failure shows on its row instead of a bubble.

## The icon

A parcel with an up arrow, a template image at 18 pt. States: idle; target (a file drag over it or
the zone); zipping (dashed ring); uploading (the ring fills clockwise); reconnecting (the ring dims
with pause bars); done (a filled check, 2.5 s); needs a look (a badge, until the error bubble is seen
or the panel opens).

## Failures

- **The network drops:** the upload pauses, the icon and the panel show it's reconnecting, and it
  resumes where it stopped when the network is back.
- **Úschovna fails:** the package stays queued with Try Again, which resumes the same package when
  Úschovna still has it, until the user retries or cancels.

## For everything

- Light and dark mode, the system accent colour, system materials and fonts. Animations 150 ms or
  less.
- Every surface hangs from the icon, 8 pt left of it and 6 pt under the menu bar, kept 8 pt inside
  the screen, on the display whose menu bar holds the icon.
- Sizes from `ByteCountFormatter`, dates from `DateFormatter`, so they follow the system's locale.
- The Mac doesn't idle-sleep while something is sending.

## Privacy

The files go to Úschovna and nowhere else. The sender address is kept in the app's preferences on
this Mac and sent only to Úschovna with each package. The history of links is kept in
`~/Library/Application Support/quickUschovna/history.json` and only holds links that are still valid.
No analytics, crash reporting or telemetry.

## Out of scope

A keyboard shortcut; recipients, a message or a subject; paying for Premium or signing in to
Úschovna+; the download count; a main window, a Dock icon or onboarding; settings beyond the sender
and Launch at Login; an in-app updater.
