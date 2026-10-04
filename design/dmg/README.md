# Disk image background

The release disk image opens to one window: quickUschovna on the left, a link to Applications on
the right, and this background behind them. It reads "Drag. Drop." followed by a parcel, and a
dotted hop leads from the app to Applications. More parcels drift at the edges at different
depths, and a dot grid fades in towards the corners. The parcels are the app icon's, from
`design/icon/make-icon.swift`, in its teal.

`background.png` and `background@2x.png` are generated; don't edit them by hand. Change the numbers
at the top of `make-background.swift` and run `xcrun swift design/dmg/make-background.swift` from
the repo root. The icon positions there and in `scripts/dmg-settings.py` must match, and the
parcel's shapes and colour are copied from `make-icon.swift`, so change them together.

The canvas is 640 × 400 pt, but only the top 368 pt show: Finder puts the picture under its 32 pt
title bar (`docs/releasing.md` § The disk image). Finder draws the icons' names itself, dark on a
light background, so this one stays light too.
