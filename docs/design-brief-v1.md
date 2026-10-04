# Design brief: quickUschovna v1

Written on 2026-10-04 for Claude Design. New project, no base file. The maintainer chose the
completion bubble, the link history and the three ways to drop files; the panel on click was the
agent's pick, because the drop zone and the bubble already hang from the icon (§ What to design).
Once a direction is chosen, the spec should describe what was built and this brief stays as the
record of what was asked for.

---

Make **quickUschovna v1**: an interactive prototype of a macOS menu-bar app that sends files
through [Úschovna](https://www.uschovna.cz), the Czech file-transfer service, and puts the link on
the clipboard. Show it on a mock macOS desktop with a menu bar, a Finder window with a few files
in it, and the app's icon in the menu bar. The app has no window and no Dock icon; everything it
shows hangs from that icon.

The UI copy is **English**. The strings quoted below are a starting point; improve them if a
shorter one says the same.

## Why

Sending a file that's too big for Discord or email through Úschovna's website means: open the
browser, load the page, type your email, add the files, click send, wait, copy the link. The app
cuts that to one move: drag the files onto the menu bar, and the link is on the clipboard. Every
screen, field and click it adds has to earn its place against that.

## The flow

These are requirements, not suggestions.

1. **Drop files on the app** (§ Three ways in). The upload starts at once. Nothing opens and
   nothing asks to confirm.
2. **One drop is one package with one link,** however many files it holds. A dropped folder is
   zipped first, under the folder's name, so its structure survives. Mixed drops (files and a
   folder) are still one package.
3. **While it uploads,** the menu-bar icon shows the progress. Clicking the icon shows the
   details (§ The panel).
4. **When it's done,** the link is copied to the clipboard and **a bubble** slides out under the
   icon for about 3 seconds: "Link copied", what was sent ("report.mov · 2.4 GB" or
   "3 files · 2.4 GB"), and until when it's valid ("Expires Oct 18"; free packages are kept 14
   days). Hovering keeps it open; clicking it opens the link in the browser.
5. **A second drop during an upload** is a second package. It queues behind the first and gets
   its own link and its own bubble.
6. **The first drop ever,** with no sender email set, opens the bubble with one field: "Your email
   (the sender)". Return saves it and the upload starts. That's the whole onboarding. The
   address can be changed later in the panel.
7. **Too big:** over 30 GB in one drop, the bubble says so straight away ("Free packages are
   limited to 30 GB") and nothing uploads.
8. **The connection drops:** the upload pauses, the icon and panel say it's reconnecting, and it
   resumes where it stopped when the network is back. No restart from zero.
9. **Úschovna fails** (their site is down or has changed): the bubble says Úschovna isn't
   answering, with "Try Again". The files stay queued until then or until cancelled.
10. **Cancel** an upload from the panel. Quitting during an upload asks first.

## What to design

### The menu-bar icon

A monochrome template image, like every menu-bar icon, about 16–18 pt, readable in light and
dark menu bars. Suggest a motif (a parcel, a box with an up arrow, a paper plane…) but **don't use
Úschovna's logo, its colours or anything that looks like it**: the app is unofficial. Design its
states:
- idle;
- a file is being dragged over it (clearly a drop target);
- uploading, showing progress at that size, e.g. a ring or a pie filling up; say whether a
  percentage next to the icon helps or clutters;
- reconnecting or paused;
- done, for the 2–3 seconds the bubble is out (e.g. a ✓);
- error, until the user looks at it.

### Three ways in

**Design all three,** each complete, behind a prototype toggle, and say which you'd keep as the
default experience if only one could be:

1. **The icon as the drop target.** Drag files onto the menu-bar icon. Always there, but a small
   target, about 22 pt.
2. **A drop zone under the icon.** As soon as a file drag starts anywhere on the screen, a larger
   zone slides out under the icon ("Drop here"), so you don't have to hit 22 pt. It highlights
   when the drag is over it and disappears when the drag ends anywhere else. It must not get in
   the way of drags that have nothing to do with sending: decide how big it is, how far it reaches
   down, and how quietly it appears.
3. **Finder's right-click menu.** A Quick Action, "Send with Úschovna", under Quick Actions
   for the selected files and folders. Design its label and icon there. Choosing it
   gives the same flow as a drop: icon progress, then the bubble.

### The bubble

It's the main feedback surface, so it sets the visual language: a small panel hanging from the
icon, in system materials. Design its versions: link copied, the first-run email field, too big,
Úschovna not answering. At most one bubble at a time; a new one replaces the old.

### The panel

Clicking the icon opens **a panel hanging from the icon, in the same family as the bubble and the
drop zone,** so the whole app reads as one surface under the icon that changes state. Keep it as
compact as a menu; it's not a window. It holds:
- **uploads in progress:** name (or "3 files"), size, a progress bar, the time left, cancel.
  Queued packages below the running one;
- **recent links,** for as long as Úschovna keeps them (14 days): name, size, and the days left
  ("12 days left", "expires tomorrow"). Clicking one copies its link again, with visible feedback.
  Opening it in the browser is a secondary action. Expired links disappear on their own. Empty
  state: one quiet line, not an illustration;
- **settings, at the bottom:** the sender email (editable in place), "Launch at Login",
  and "Quit". Nothing else.

If you find a native `NSMenu` would fit the rest of the design better than a panel, show both
and say why. The maintainer asked for whichever fits the app's main design.

### For everything

- light and dark mode, the system accent colour, system materials and system fonts;
- animations of at most 150 ms, or none;
- placement: everything hangs from the icon, on the display whose menu bar was used;
- numbers, sizes and dates in the system's locale (`ByteCountFormatter`, `DateFormatter`); the
  mock uses English ones ("2.4 GB", "Oct 18").

## Scenarios

A scenario picker, as in a prototype: each one sets up the desktop mock and plays the flow. Real
drags from Finder can't happen in a prototype, so the mock Finder window's files are draggable
chips, and the upload speed is a prototype control.

1. **First run:** no email set; drop one file → the email field → upload → bubble.
2. **One video:** `report.mov`, 2.4 GB (the default).
3. **Three photos and a folder** in one drop → zipping, one package, one link.
4. **A 45 GB file** → too big, nothing uploads.
5. **The network drops at 60 %** → reconnecting → resumes → done.
6. **A second drop while the first uploads** → queued, two bubbles in turn.
7. **The panel with history:** five links, one expiring tomorrow, plus an upload running.
8. **A very long file name**, in the bubble and in the panel.
9. **Finder's Quick Action** on two selected files.
10. **Úschovna not answering** → error bubble → "Try Again" works.

## Don't add

- a keyboard shortcut (considered, dropped);
- recipients, a message or a subject: the output is one link to share;
- paying for Premium, or signing in to Úschovna+;
- the download count or cap: the app can't see downloads;
- Úschovna's logo, colours, or anything suggesting the app is theirs;
- a main window, a Dock icon, onboarding screens or a tour;
- settings beyond the sender email and launch at login;
- analytics, accounts, or anything about the user sent anywhere but Úschovna.
