# quickUschovna: architecture

How v1 is built. What it does is `docs/spec.md`; this file is the map of the code and the reasons
behind its shape. Written 2026-10-04.

## One model, many views

`AppModel` (`quickUschovna/Model/AppModel.swift`) is an `@Observable` port of the prototype's state
machine (`class Component` in `design/prototype/quickUschovna v1.dc.html`): the queue, the history,
the bubble and its timings, the panel's state, the drag. Everything else either reads it or calls
its methods:
- **The SwiftUI views** (`quickUschovna/UI/`) read it and call its actions.
- **The AppKit side** (`quickUschovna/Surfaces/`) follows it with `observe` (`Observe.swift`, a
  re-arming `withObservationTracking`) to swap the icon's image and show or hide windows.
- **The upload** goes through the `UploadService` / `UploadSession` contract
  (`Model/UploadService.swift`), so the model never sees HTTP, and Debug builds can swap in
  `SimulatedUploadService`.

The app target runs with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything is on the main
actor unless it says otherwise. What must not block it is marked `nonisolated` / `@concurrent`:
measuring and zipping files, and the client's reads and requests.

## The menu bar and the surfaces

- **`StatusItemController`**: a fixed 32 pt `NSStatusItem` (the prototype's item, so the wider
  drag-over image doesn't push neighbours). A click toggles the panel; drags and drops on it go
  through `FileDrop`, which takes the dragging-destination calls the status bar window forwards to
  its delegate. A file drag reaching it calls `AppModel.dragOverIcon`, which opens the drop zone
  (`AppModel.isDropZoneOpen`) for the rest of the drag. It also says where the surfaces hang
  (`surfaceAnchor`) and the area near it where a drag opens the zone (`dropZoneApproach`).
- **`SurfacePresenter`**: three `Surface`s, the drop zone, the bubble and the panel, each a
  `SurfaceWindow` (a borderless, non-activating, transparent `NSPanel` at `.statusBar` level on all
  Spaces) with a fresh `SurfaceHostingView` each time it's shown, so the view's entrance plays.
  The hosting view reports size changes and the window grows downwards, its top pinned 6 pt under
  the menu bar and its left 8 pt left of the item, clamped 8 pt inside the screen
  (`StatusItemController.surfaceAnchor`, `SurfaceMetrics`).
  - **The views draw their own shadow**, so a window is bigger than its surface by
    `SurfaceMetrics.shadowInsets`. A window takes the mouse only over the surface itself
    (`SurfaceWindow.updateMouseHandling`, driven by mouse-moved and dragged monitors); otherwise
    the shadow's faint pixels would catch clicks, even over the menu bar.
  - **Keyboard:** only the panel and the first-run bubble become key (non-activating, so the front
    app stays active). Esc goes through a local key monitor to `AppModel.escape()`.
  - **Clicks elsewhere:** a global mouse-down monitor calls `AppModel.clickedOutside()`.
- **`DragMonitor`**: follows file drags anywhere (`AppModel.drag`), opens the zone when one comes
  near the icon (`StatusItemController.dropZoneApproach`; a drag that starts there has to leave it
  first), and closes it when the drag ends. Global mouse monitors need no permission, and during a
  drag they get its dragged events; a changed drag-pasteboard count since mouse-down means a drag
  started, and only file URLs count. A folder isn't measured until it's dropped (`docs/spec.md` § Ways in, and Findings in
  `docs/archive/handoffs/2026-10-04.md`). The zone stays 300 ms after the mouse goes up, because
  the drop is delivered just after.

## The views

`quickUschovna/UI/` matches the prototype one to one, checked side by side against renders of the
prototype (`docs/handoff.md`):
- `SurfaceStyle.swift`: the prototype's light and dark colour tokens and Chrome's line heights.
- `SurfaceChrome.swift`: `.surfaceChrome(padding:entrance:)`, the 300 pt surface with radius 14,
  hairlines, a CSS-like shadow outside the surface only, the shadow's room, and the 120 ms
  entrances. The material is `.hudWindow` with the prototype's background colour over it, the
  closest of the system materials.
- `SurfaceControls.swift`: head/tail names (the end with the extension never truncates), the email
  field, the switch, buttons, separators.
- `MenuBarGlyphGeometry.swift`: the icon's SVG paths from `design/prototype/MenuBarIcon.dc.html`,
  one source for `MenuBarIconRenderer` (the status item's 18 pt images, template except the
  drag-over one) and `MenuBarGlyph` (SwiftUI).
- `DropZoneView`, `BubbleView`, `PanelView`.

`quickUschovna/Debug/DesignGallery.swift`: `--render-gallery <dir>` (Debug only) renders every
surface and icon state to PNGs and quits; add `-AppleLocale en_US` for the prototype's formats.

## Sending

- **`AppModel.send`** measures the items (`FileMeasure`, off the main actor), refuses over 30 GB,
  asks for the sender first if there's none, and queues one `UploadPackage`. The first package in
  the queue is worked on by one task at a time.
- **`Zipper`** writes folders into stored (uncompressed) ZIP archives itself, with UTF-8-flagged
  NFC names, ZIP64 and zlib's CRC32, because neither Apple's `zip` nor `ditto` produces archives
  that arrive intact everywhere (`docs/handoff.md` § Findings). Archives live in the temporary
  directory under the package's ID until it's sent or cancelled.
- **The Úschovna client** (`quickUschovna/Uschovna/`, protocol in `docs/uschovna-protocol.md`):
  - `UschovnaService` makes one `UschovnaSession` per package, which keeps the package code and
    offsets so Try Again resumes it.
  - `UschovnaClient` builds the page's requests: its own ephemeral `URLSession` and cookie, the
    page's headers, an honest User-Agent.
  - `UschovnaWire` holds the exact encodings, the chunk-size rule, and JavaScript's loose equality
    for the server's answers (it answers `true` where the page compares with `1`).
  - `NetworkWatch` (`NWPathMonitor`) lets a session wait out a lost network and resume from the
    last acknowledged byte; `FileChunks` reads chunks off the main actor.
  - Progress includes the chunk in flight, so the ring moves smoothly.
  - The link is always the public one, `https://www.uschovna.cz/zasilka/<public code>/`. The part
    of the finish code after its slash is the sender's secret (it can delete the package); it's
    never returned or logged.
- **`SettingsStore`** keeps the sender address in `UserDefaults` and the links in
  `~/Library/Application Support/quickUschovna/history.json`. `LaunchAtLogin` is `SMAppService`.
- **While anything is queued,** a `ProcessInfo` activity keeps the Mac from idle-sleeping.

## The Quick Action

`QuickAction/` is a headless Action extension (`com.apple.services`) that Finder lists under Quick
Actions. It resolves the selection to file URLs and opens them with the containing app through
Launch Services, which launches it if needed, delivers them in one `application(_:open:)`
(`quickUschovna/App/QuickActionReceiver.swift`), and lets the non-sandboxed app read Desktop,
Documents and Downloads without a prompt. Details and the manual test: `docs/quick-action.md`.

## Updates (added 2026-10-04)

`docs/spec.md` § Updates says what it does. It's betterTab's updater:
[Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.0 (MIT) as a Swift package pinned to
that exact version. `quickUschovna/App/Updater.swift` is the whole of our side;
`quickUschovna/Info.plist` holds Sparkle's settings and is merged into the generated Info.plist.
- **Only on request.** `SUEnableAutomaticChecks` is NO, so Sparkle never checks or asks to, and
  `SUAllowsAutomaticUpdates` NO removes its "install automatically" checkbox. The panel's row calls
  `AppModel.checkForUpdates`, which closes the panel and calls `onCheckForUpdates`; `AppDelegate`
  points that at `Updater` in Release builds only, so a Debug build beeps instead of replacing
  itself. Sparkle's controller isn't created until the first check, so nothing runs in the
  background.
- **Not during a send.** Install and Relaunch quits the app. `Updater` is Sparkle's delegate and
  postpones the relaunch (`updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`) while
  `AppModel.queue` isn't empty, then goes ahead once `observe` sees it empty.
- **What has to match.** The release workflow signs the disk image with an EdDSA key, and the app
  carries the public half (`SUPublicEDKey`). `SUVerifyUpdateBeforeExtraction` makes Sparkle check
  that signature before it unpacks anything; without it, a code signature matching the running app
  would be enough. After unpacking, the new app's code signature must be valid.
- **Replacing the app.** quickUschovna isn't sandboxed, and a copy dragged into `/Applications`
  belongs to the user, so Sparkle's `Autoupdate` helper can replace it, Quick Action included.
  Sparkle releases the new bundle from quarantine, so Gatekeeper shouldn't ask for Open Anyway
  again; not yet tried.
- **The feed.** `SUFeedURL` is `releases/latest/download/appcast.xml` on GitHub: each release
  carries an appcast with one item, itself (`scripts/make-appcast.sh`). Its notes are Markdown,
  which Sparkle draws in a text view, so no web page is loaded. The feed isn't signed: it's served
  over HTTPS by GitHub, and anyone who could replace it could replace the release too.
- **What it sends and saves.** Requests carry only `User-Agent: quickUschovna/<version>
  Sparkle/<version>`; `SUEnableSystemProfiling` is NO. Sparkle writes `SUHasLaunchedBefore`,
  `SULastCheckTime` and any skipped version to the app's defaults.
- **Sparkle's helpers** (`Autoupdate`, `Updater.app`) keep Sparkle's ad hoc signatures inside the
  framework; the release script signs the framework itself with our identity, so the app's
  hardened runtime loads it (`docs/releasing.md` § Signing). The XPC services are only for
  sandboxed apps and go unused.

## Testing without a mouse or Úschovna

- `scripts/uschovna/run-tests.sh`: the client's real sources compiled with the app's settings,
  against `scripts/uschovna/mock_server.py`, a stdlib Python mock of the protocol with switches for
  drops, stalls, errors and slow links.
- `--simulate [MB/s]` (Debug): a stand-in for Úschovna (`SimulatedUploadService`, with
  `--simulate-failure` and `--simulate-offline`) and separate settings.
- `scripts/debug-control.swift` (Debug): posts commands to the running app (`DebugControl`):
  `send`, `drag`, `over`, `panel`, `email`, `dump <file>` and more, so the prototype's scenarios can
  be played and the windows captured.
