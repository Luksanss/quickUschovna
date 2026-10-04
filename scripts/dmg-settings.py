# dmgbuild settings for the release disk image: quickUschovna.app, a link to Applications, and the
# background from design/dmg/. scripts/build-release.sh passes both paths: `-D app=<path>` and
# `-D background=<path>`.
#
# Finder's window bounds include its 32 pt title bar, and the background is pinned under it, so
# the window is the background's full 640 x 400 and the last 32 pt of the picture are bleed.
# The icon positions are centres, in points from the window content's top left; they match
# design/dmg/make-background.swift.
import os.path

application = defines["app"]  # noqa: F821, dmgbuild provides `defines`
appname = os.path.basename(application)

format = "ULMO"  # lzma, the smallest; macOS 10.15 and later
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

# dmgbuild finds background@2x.png beside it and makes one HiDPI TIFF of the pair.
background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (640, 400))
icon_size = 128
text_size = 13
icon_locations = {appname: (180, 196), "Applications": (460, 196)}
