# quickUschovna: releasing

Every push to `main` publishes a GitHub Release. If several pushes queue up while one is building,
only the newest of them runs. The workflow is `.github/workflows/release.yml`; it builds with
`scripts/build-release.sh` and writes the notes with `scripts/make-release-notes.sh`. It's
betterTab's pipeline without the updater. Written 2026-10-04.

## How a release happens

1. You merge `dev` into `main` and push.
2. GitHub Actions builds the Release configuration on the `xcode-27` runner, signs the app and its
   Quick Action with your Apple Development certificate (§ Signing), packs `quickUschovna.app`
   into a disk image (§ The disk image), and publishes it as `v<version>`. The release notes are
   the `feat`, `fix` and `perf` commits since the last release.
3. If that version's tag already exists, the run does nothing. To run it again by hand, use
   Actions → Release → Run workflow, on `main`. It refuses any other branch.

Releases aren't notarized, so on first launch users click Open Anyway in System Settings →
Privacy & Security. The app has no updater: there's no Check for Updates…, so there's no Sparkle,
no appcast and no Sparkle key. To update, users download the latest release and replace the app
(`README.md` § Install).

## Versions

A version is `MARKETING_VERSION` plus the number of commits on `main`: `1.0.87` means
`MARKETING_VERSION = 1.0` at the 87th commit. The build number (`CFBundleVersion`) is the commit
count alone. For a new minor, bump `MARKETING_VERSION` in the quickUschovna target's Build
Settings; the workflow reads it from there. The build sets both numbers in both targets, so the
Quick Action always carries the app's version. The last part is automatic and never resets.

To build a release disk image locally: `scripts/build-release.sh 1.0.87 87`. It lands in
`build/release/`. That's ad hoc; pass an identity (`security find-identity -v -p codesigning`
lists them) as a third argument to sign it. `scripts/make-release-notes.sh` then writes the notes
the release would get to `build/release/notes.md`.

## The disk image

`quickUschovna-<version>.dmg` opens to one window: the app, a link to Applications, and a
background that says what to do. The background is drawn by `design/dmg/make-background.swift`
(`design/dmg/README.md`); the layout is `scripts/dmg-settings.py`.

- **[dmgbuild](https://github.com/dmgbuild/dmgbuild)** (MIT) writes the window's `.DS_Store`
  directly, without Finder, so it runs on CI. The script installs it into `build/dmgbuild` from
  `scripts/dmgbuild-requirements.txt`, pinned by hash, and needs Python 3.10 or later; macOS's
  own `/usr/bin/python3` is 3.9, so the workflow sets up Python first.
- **Finder's window bounds include its 32 pt title bar,** and the background is pinned below it.
  So the window is the picture's full 640 × 400 pt and its last 32 pt never show (measured for
  betterTab's disk image).
- **Don't hide the `.app` extension in the image** (dmgbuild's `hide_extensions`). It sets a
  Finder flag on the bundle, and `codesign --verify --strict` then rejects the app. Finder hides
  it anyway.
- **macOS 27 says `hdiutil`'s `create`, `attach` and `convert` are deprecated** in favour of
  `diskutil image`. Those warnings come from dmgbuild and don't fail the build.
- **The image isn't signed or notarized,** like the app, so the first launch still needs Open
  Anyway. The image only changes how installing looks.

## Signing

The app embeds the Finder Quick Action, `Contents/PlugIns/QuickAction.appex`, and the two are
signed differently: the extension is sandboxed (App Sandbox, read-only access to the files the
user picks), the app isn't. Both come from the targets' build settings (`ENABLE_APP_SANDBOX`,
`ENABLE_USER_SELECTED_FILES`); there are no entitlements files. `scripts/build-release.sh`:
1. builds with Xcode, signed ad hoc, which gives each part the entitlements Xcode derives from
   its target;
2. reads each part's entitlements back and drops `get-task-allow`, which Xcode adds to every
   build and which would let any debugger attach to the release;
3. signs inside out: the extension with its own entitlements, then the app with its own, both
   with the hardened runtime. Never `--deep`: it would sign the extension with the app's
   entitlements and take its sandbox away, and Finder doesn't load an extension without one;
4. checks the result with `codesign --verify --strict --deep` and prints each part's identifier,
   team, flags and entitlements. It doesn't print the certificate's name, which holds an email
   address, because the workflow's logs are public.

It stops if the extension isn't sandboxed, or if anything other than the extension is nested in
the app (a framework, a helper), since that would keep Xcode's ad-hoc signature.

Without an identity, the build is ad hoc. That's fine for checking the disk image, but macOS may
not load the Quick Action of an ad-hoc app, so try the Quick Action with a signed build. The
workflow refuses to release without the certificate: an ad-hoc build's designated requirement is
its cdhash, so every release would look like a different app to macOS, and its Quick Action might
not show up at all.

## Signing with your certificate

The certificate is betterTab's: your Apple Development identity (Personal Team `5KDU5HYH35`), not
a per-app key, so it's reused rather than made anew. Environment secrets don't cross
repositories, though, so this repository needs its own `release` environment with its own copy.

The exported certificate carries its private key, and whoever holds that key can sign an app that
Macs accept as yours, betterTab included. So it's kept where only the release job can read it:
- **The secrets live in the `release` environment,** which only `main` can use. Repository
  secrets would be readable by a workflow pushed to any branch. The job names the environment.
- **Actions are pinned by commit,** not by tag, because the key sits unlocked in the job's
  keychain while later steps run. dmgbuild is pinned by hash for the same reason. The pins are
  betterTab's.
- **The GitHub account has two-factor sign-in,** since anyone who can push can change the workflow.

To sign releases with your Apple Development certificate:
1. Once: on GitHub, in quickUschovna's Settings → Environments → New environment, named
   `release`. Under Deployment branches and tags choose Selected branches and tags, and add
   `main`.
2. In Keychain Access → My Certificates, right-click **Apple Development: …** → Export. Save it as
   `cert.p12` (Personal Information Exchange) with a long random password.
3. `base64 -i cert.p12 | gh secret set SIGNING_CERT_P12 --env release --repo Luksanss/quickUschovna`.
   It goes in through the pipe, without the clipboard. `--repo` makes sure it lands here and not
   in betterTab, whichever folder the shell is in.
4. `gh secret set SIGNING_CERT_PASSWORD --env release --repo Luksanss/quickUschovna`, and type the
   password when asked.
5. `rm cert.p12`.

The next release is signed. Each run's summary says it was. When the certificate expires (the
current one on 2027-09-29) and you renew it, repeat steps 2–5 here and in betterTab.
