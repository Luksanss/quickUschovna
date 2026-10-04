import AppKit
import os

extension AppDelegate {
    /// Files and folders opened with the app through Launch Services, all in one call, so they go
    /// out as one package like a drop. Finder's Quick Action (`QuickAction/`) hands its selection
    /// over this way, launching the app first if it isn't running; `open -a quickUschovna …` does
    /// the same. Opened like this, the app may read them even in Desktop, Documents or Downloads
    /// without a privacy prompt, for as long as it runs. See `docs/quick-action.md`.
    ///
    /// On a launch it arrives before `applicationDidFinishLaunching(_:)`, so the send waits one turn
    /// of the main queue: by then the status item and everything else set up at launch exist.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        Logger(subsystem: "com.luksanss.quickUschovna", category: "quickAction")
            .info("Received \(files.count) of \(urls.count) item(s) to send")
        guard !files.isEmpty else { return }
        DispatchQueue.main.async {
            self.model.send(files)
        }
    }
}
