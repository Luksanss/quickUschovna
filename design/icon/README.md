# App icon

The app icon is `quickUschovna/AppIcon.icon`, an Icon Composer document (`icon.json` plus one SVG
per layer). It's the menu-bar glyph drawn bold: a parcel, its lid set apart from its body, with an
up arrow on the body. A white parcel with a teal arrow on a teal gradient in light mode, a grey
parcel with a white arrow on the system's dark background in dark mode. The system derives the
tinted and clear looks. The app is unofficial, so the icon stays clear of Úschovna's mark (a yellow
open ring around a dark grey triangle) and its colours (yellow, orange and dark grey): no ring, no
triangle, no yellow. Teal also keeps it apart from betterTab's indigo in the Dock and in Finder.

Xcode compiles it into `Assets.car` and `AppIcon.icns` because the quickUschovna target sets
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; the `quickUschovna` folder is synchronized with the
target, so the document needs no other entry in the project. Don't edit the bundle by hand: change
the numbers at the top of `make-icon.swift` (the lid, the body, the arrow, the brand colour) and
regenerate it with `xcrun swift design/icon/make-icon.swift` from the repo root. To preview it
without opening any app, render it with Icon Composer's command-line tool (renditions `Default`,
`Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`):

```
"$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool" \
  quickUschovna/AppIcon.icon --export-image --output-file /tmp/AppIcon.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

`ictool` looks for `icrtool` beside the path it was started from, so call it by its real path, not
through a symlink. Render at `--width 16` and `--width 32` too when the shapes change: at 32 px
the lid, the body and the arrow must still read, and at 16 px the parcel at least.

`AppIcon.png` here is the `Default` rendition at 512 × 512, exported with the same command, for the
README and anywhere else outside the app. Export it again whenever the icon changes.

The motif is the idle state of the menu-bar icon in the design (`design/prototype/MenuBarIcon.dc.html`):
a lid, a body narrower than it, and an up arrow. The menu-bar icon is a template image drawn in
outline; the app icon fills the same shapes, with a bigger arrow so it reads at small sizes. Its
proportions are copied by eye, not computed, so when one of them changes, look at the other.
