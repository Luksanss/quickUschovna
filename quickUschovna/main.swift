import AppKit

#if DEBUG
// `--render-gallery <dir>` draws every surface and icon state to PNGs and quits.
if DesignGallery.renderIfRequested() { exit(0) }
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
