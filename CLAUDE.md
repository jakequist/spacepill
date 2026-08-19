# SpacePill

A native macOS menu bar app that shows which Space (virtual desktop) you are on
as a colour-coded pill, and adds hotkeys to relabel, jump between, and take
notes on Spaces.

Single SwiftPM executable, no third-party dependencies, SwiftUI + AppKit.
macOS 13+, built and shipped as a `.app` bundle.

---

## Commands

```bash
./bin/start.sh              # build + bundle + run in foreground
./bin/start.sh -d           # same, detached
./bin/start.sh --debug      # debug config (much faster compiles)
./bin/logs.sh               # stream the unified log
./bin/logs.sh --last 5m hotkeys   # dump one category
./bin/dev-cert.sh           # one-time: stable dev signing identity (see below)
./bin/package.sh            # signed/notarised .app + .dmg into staging/
./bin/release.sh            # tag, package, publish GitHub release

# The CLI, from a dev build (it is not on PATH until installed):
./staging/SpacePill.app/Contents/Helpers/spacepill doctor
```

`swift build` alone produces a bare executable. **Do not run that binary
directly** — see "Always run from a bundle" below.

---

## Architecture

```
SpacePill/SpacePill/
  SpacePillApp.swift        @main + AppDelegate: owns the managers, wires hotkeys
  Managers/
    SpaceManager.swift      detects the current Space (polling + notification + event tap)
    SettingsManager.swift   ~/.spacepill/settings.json, @Published mirrors of every setting
    NotesManager.swift      ~/.spacepill/space_<N>/notes.md
    GlobalHotKeyManager.swift   Carbon RegisterEventHotKey wrapper
    StatusBarController.swift   NSStatusItem, popovers, the floating notes panel
    CLIServer.swift         Unix socket control channel for the `spacepill` CLI
  Views/                    SwiftUI: QuickEdit, QuickSwitch, Notes, Preferences, HotKeyRecorder
  Utils/
    SkyLight.swift          private SkyLight/CGS API bindings + space switching
    SpaceShortcuts.swift    reads the user's "Switch to Desktop N" key bindings
    Log.swift               os.Logger channels

SpacePill/SpacePillCLI/     the `spacepill` CLI -- a separate executable target
  main.swift                argument parsing, human output, doctor, install-cli
  Client.swift              the socket client and exit codes
  Update.swift              `spacepill update`
  Support.swift             version resolution, subprocesses, semver
```

Data flow: `SpaceManager` publishes the current space → `StatusBarController`
renders the pill and `NotesManager` swaps the notes file. `SettingsManager` is
the single store for everything persisted.

### Two identifiers for a Space, and they are not interchangeable

- **UUID** — stable for the life of a Space. `SettingsManager.spaceConfigs` is
  keyed by UUID, so labels and colours survive reordering.
- **Index** — 1-based position across all displays, recomputed on every call to
  `SkyLight.getAllSpacesMetadata()`. It shifts whenever a Space is added,
  removed, or reordered.

`NotesManager` currently keys notes by **index** (`~/.spacepill/space_3/notes.md`)
while everything else keys by UUID. Adding or deleting a Space therefore
re-points existing notes at the wrong Space. Prefer UUID for anything new.

### `visualSpaceIndex` vs `currentSpaceIndex`

`SpaceManager` tracks two values. `current*` is what SkyLight reports.
`visual*` is an optimistic guess applied the instant a Ctrl+Arrow keypress is
seen, so the pill updates at the start of the native animation rather than
~700ms later. UI should read `visual*` and fall back to `current*`.

---

## The `spacepill` CLI and its IPC protocol

`spacepill` is a second executable that ships inside the bundle. It holds **no**
state and calls **no** private API — it opens a Unix domain socket to the running
app and asks it to do the work.

That split is not stylistic. Switching a Space means posting keystrokes, which
requires Accessibility, and TCC keys grants to the binary that posts them. A CLI
that switched Spaces itself would need its own Accessibility grant and would
throw a second, scarier-looking permission prompt at the user. Routing through
the app reuses the one grant SpacePill already has, and keeps a single source of
truth for labels, colours and notes.

### Transport

`~/.spacepill/spacepill.sock`, chmod 0600. The app creates it in
`applicationDidFinishLaunching` (unlinking any stale one first — `bind` fails
with EADDRINUSE on a leftover inode) and removes it from `AppDelegate.shutdown()`,
which both `applicationWillTerminate` and the SIGINT/SIGTERM handlers call.

One line of UTF-8 JSON per request, `\n` terminated; one line back; server closes.

```
-> {"protocol":1,"command":"list","args":{}}
<- {"ok":true,"data":{"spaces":[…]}}
<- {"ok":false,"code":"not_found","error":"No space matching \"9\"."}
```

Unknown `protocol` values are rejected with `unsupported_protocol`. Commands:
`status`, `list`, `switch`, `set-label`, `clear-label`, `notes-get`, `notes-set`,
`notes-path`. Omitting `index`/`uuid` always means the current Space.

Error slugs map to CLI exit codes: `0` ok, `1` error, `2` usage,
`3` app not running, `4` `unreachable`/`no_shortcut`, `5` `not_found`.

### Threading

`accept` and all socket I/O run on background queues; every command handler runs
inside a single `DispatchQueue.main.sync` hop, because SkyLight, AppKit and the
`@Published` manager state are all main-queue-only. Getting this wrong produces
intermittent crashes rather than reliable ones.

Two POSIX traps this code already pays for:

- **BSD kernels give the accepted socket the listener's file status flags.** The
  listening fd is `O_NONBLOCK` so the dispatch source can drain the backlog, and
  the accepted fd inherits it — so the first `read()` returns EAGAIN whenever the
  request has not landed yet. It presents as a random "empty request" error.
  `serve()` clears `O_NONBLOCK` explicitly and relies on `SO_RCVTIMEO`.
- `SO_NOSIGPIPE` on every accepted socket, or a client that hangs up mid-reply
  kills the app.

Reachability must go through `SkyLight.canSwitchToSpace(index:)` /
`SpaceShortcuts`. `SpaceShortcuts` caches, so `status` and `list` call
`refresh()` first — otherwise a shortcut enabled while SpacePill was running
never shows up.

### Where the binary lives, and why the names are odd

**macOS filesystems are case-insensitive by default.** Two consequences, both of
which silently corrupt the build if you "fix" the names back:

- The SwiftPM target is `SpacePillCLI`, not `spacepill`. A target named
  `spacepill` shares `.build/<arch>/<config>/spacepill.build` and its output
  binary with `SpacePill`, and SwiftPM cheerfully compiles the *app's* sources
  into it.
- It is installed to `SpacePill.app/Contents/**Helpers**/spacepill`, not
  `Contents/MacOS/`. `MacOS/spacepill` and `MacOS/SpacePill` are the same file:
  copying it there overwrites the app binary with the CLI, and the app then
  "launches" by printing CLI help and exiting.

`bin/start.sh` and `bin/package.sh` copy and rename it; both sign the nested
binary *before* the enclosing bundle. Users run `spacepill install-cli` to
symlink it into `/usr/local/bin`.

The CLI has no compiled-in version number: it reads
`CFBundleShortVersionString` from the bundle two directories above itself
(resolving symlinks first, since `install-cli` puts one on `PATH`), and falls
back to asking the running app. `./VERSION` stays the only source of truth.

Distribution is the GitHub release DMG and the `curl | sh` installer only.
Homebrew was dropped deliberately (v1.3.2) — do not reintroduce a cask, tap, or
`brew` code path.

### `spacepill update`

Updates compare against the GitHub latest-release API, and for an actual
install require **both** `codesign --verify --deep --strict` to pass **and** an
`Authority=Developer ID Application:` line before anything is copied. An update
path that installs whatever a URL returns is a remote code execution primitive;
refusing an unverifiable build is the feature. Note a self-signed certificate
passes `--verify` happily — the authority check is the one doing the work.

---

## macOS specifics that will bite you

### Always run from a bundle

`Bundle.main.bundleIdentifier` is `nil` for a bare SwiftPM executable. That
silently disables Launch at Login (`SMAppService` traps without a bundle ID),
and gives the process a different TCC identity than the shipped app — so
permissions you grant while testing do not apply to the real thing.
`bin/start.sh` assembles and signs a real bundle for exactly this reason.

### Permissions

| Permission | Needed for | Triggered by |
| :-- | :-- | :-- |
| **Accessibility** | posting Ctrl+N / Ctrl+Arrow to switch Spaces | `AXIsProcessTrustedWithOptions` in `AppDelegate` |
| **Input Monitoring** | the keyDown event tap that drives optimistic pill updates | `CGEvent.tapCreate` in `SpaceManager` |

Input Monitoring is a separate, scarier-sounding grant than Accessibility, and
the app asks for it just to make the pill feel snappier. Worth remembering when
weighing changes to `setupSpaceSwitchEventTap`.

If the tap fails you will see this in the log, and the pill will lag behind
Ctrl+Arrow switches rather than break outright:

```
[com.jake.SpacePill:spaces] Failed to create space switch event tap
```

### Signing resets permissions on every build

TCC keys grants to the code signature. An ad-hoc signature (`codesign -s -`) has
a new cdhash after every build, so **each rebuild looks like a brand new app and
loses both grants**. Symptom: hotkeys and pill tracking work, you rebuild, and
they silently stop.

Run `./bin/dev-cert.sh` once per machine to create a stable self-signed
identity; `bin/start.sh` picks it up automatically. The designated requirement
then pins to the certificate rather than a cdhash, so grants survive rebuilds:

```
designated => identifier "com.jake.SpacePill" and certificate leaf = H"3ae0f5..."
```

Two things that make this trickier than it looks:

- The identity lives in a **dedicated keychain**, not the login keychain.
  Releasing a login-keychain private key needs user authorisation, which a
  background or SSH session can never obtain (`launchctl managername` →
  `Background`) — so builds outside a GUI session fail with
  `errSecInternalComponent` no matter how the keychain is set up.
- `codesign` does **not** require the certificate to be trusted. Trust only
  affects Gatekeeper and `find-identity -v`. Because a self-signed cert is never
  "valid", any lookup must use `find-identity` *without* `-v` or it will silently
  find nothing and fall back to ad-hoc.

Changing the signature invalidates existing TCC entries, and toggling them in
System Settings does not rebind them. Clear them instead:

```bash
tccutil reset Accessibility com.jake.SpacePill
tccutil reset ListenEvent com.jake.SpacePill
```

### Space switching is simulated keystrokes, not an API

There is no public or private API to activate a Space directly.
`SkyLight.switchToSpace` replays the user's own "Switch to Desktop N" shortcut.
That makes their System Settings configuration part of the app's contract:

- **These shortcuts are disabled by default.** A stock macOS install has nothing
  bound, so Quick Switch cannot move at all until the user enables them under
  System Settings → Keyboard → Keyboard Shortcuts → Mission Control.
- **macOS only defines ten of them** (symbolic hotkey IDs 118…127 = Desktop
  1…10). Desktop 11+ is unreachable, full stop. Stepping there with
  Ctrl+Left/Right was tried and removed: transitions take ~0.5s and swallow
  arrow keys posted mid-flight, so multi-step hops land somewhere arbitrary.
- **Users can rebind them**, so never hardcode Ctrl+N.

`Utils/SpaceShortcuts.swift` reads all of this from the
`com.apple.symbolichotkeys` domain. Always gate a jump on
`SkyLight.canSwitchToSpace(index:)` rather than on the index alone, and surface
the refusal — a switch that silently does nothing is indistinguishable from a
bug. Inspect the live state with:

```bash
# 118..127 = "Switch to Desktop 1..10"; 79-82 = move left/right a space
/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:118" \
    ~/Library/Preferences/com.apple.symbolichotkeys.plist
```

An absent entry means the factory default, which for these IDs is *off*.

Two gotchas when testing this by hand: `defaults write` to that domain does
**not** take effect until the WindowServer re-reads it at login, so enable
shortcuts through the System Settings UI (which registers them live); and
`cfprefsd` caches the domain, so editing the plist behind its back is invisible
to a running app until `killall cfprefsd`.

### Private SkyLight API

`Utils/SkyLight.swift` binds `SLSMainConnectionID`, `SLSGetActiveSpace`, and
`SLSCopyManagedDisplaySpaces` via `@_silgen_name`, and links
`/System/Library/PrivateFrameworks` through `unsafeFlags` in `Package.swift`.

Consequences: these symbols can vanish in any macOS release, `unsafeFlags`
means this package can never be consumed as a SwiftPM dependency, and the
dictionary keys (`"Display Identifier"`, `"Spaces"`, `"id64"`, `"uuid"`,
`"Current Space"`) are undocumented and version-sensitive. Guard every lookup;
never force-unwrap a SkyLight result.

---

## Logging

Use `Log.<category>` from `Utils/Log.swift`. **Do not use `print`** — a menu bar
app has no attached terminal, and stdout is block-buffered when it is not a TTY,
so `print` output is simply lost.

```swift
Log.hotkeys.info("Registered hotkey id=\(id, privacy: .public)")
```

`os.Logger` redacts interpolated values as `<private>` by default. Mark
non-sensitive values `.public` explicitly; leave user content (space labels,
note text) redacted.

Categories: `app`, `spaces`, `hotkeys`, `ui`, `settings`, `notes`.

**`debug` messages are dropped unless you opt in.** macOS discards debug-level
logging for a subsystem by default, so `Log.hotkeys.debug(...)` is invisible to
both `log show` *and* `log stream` until you run:

```bash
./bin/logs.sh --enable-debug     # sudo log config --mode "level:debug" ...
```

This is a real trap when debugging: an absent debug line means "debug logging is
off", not "this code path did not run". Put anything you need to see
unconditionally at `.info` or above.

---

## Settings and persistence

Everything lives in `~/.spacepill/`:

```
~/.spacepill/settings.json      SettingsData (hotkeys, toggles, per-space label/colour)
~/.spacepill/space_<N>/notes.md per-space notes, keyed by index (see caveat above)
~/.spacepill/spacepill.sock     CLI control socket, 0600, only while the app runs
```

`SettingsManager` mirrors each field as a `@Published` property with
`didSet { save() }`. Two things follow from that:

- Any write to `spaceConfigs` rewrites the whole JSON file. Scroll-position
  updates go through `spaceConfigs`, so scrolling the notes panel writes to
  disk repeatedly.
- `AppDelegate` re-runs `setupHotKeys()` on every `objectWillChange`, which
  means every settings write tears down and re-registers all three global
  hotkeys. Suspect this first when hotkeys stop responding.

Use `isUpdating` to suppress saves while loading, and prefer `save()` on a
debounce over adding more `didSet` writers.

---

## Conventions

- 4-space indent, standard Swift naming; types and non-obvious behaviour get a
  `/** */` block comment. Match the density of the surrounding file.
- Managers are `ObservableObject` classes; views take them as `@ObservedObject`
  injected from `AppDelegate`. There is no global singleton — keep it that way.
- UI work must be on the main queue: SkyLight calls and the event tap callback
  run off-main, so hop with `DispatchQueue.main.async` before touching
  `@Published` state.
- Never force-unwrap the result of a SkyLight or CGS call.
- Version lives in `./VERSION` only. `Info.plist` carries a placeholder that
  `bin/package.sh` stamps at build time — do not hand-edit the plist version.
- The bundle identifier `com.jake.SpacePill` is load-bearing: it is the TCC key
  for both permissions and the `SMAppService` login-item key. Changing it forces
  every existing user to re-grant permissions. `bin/package.sh` and
  `bin/logs.sh` both derive from or match `Info.plist`; keep them in sync.

---

## Testing

There is no automated test suite. The app is driven by private APIs and global
hotkeys, so verification is manual and visual — see the `spacepill-run` skill
in `.claude/skills/`, which covers building, launching, driving the UI with
`cliclick`/AppleScript, and screenshotting the result.

Pure logic worth covering if a suite is ever added: `Color(hex:)`/`toHex()`
round-tripping, `HotKeyConfig.displayString`, `SettingsData` decoding of older
files, and `QuickSwitchView`'s label matching.

When changing anything in the table below, re-verify by hand:

| Change | Verify |
| :-- | :-- |
| hotkey registration | all three hotkeys, **and** again after opening Preferences |
| pill rendering | labelled and unlabelled Spaces, light and dark menu bar |
| space detection | Ctrl+Arrow, Mission Control click, and a >10 Space setup |
| space switching | with the Desktop shortcuts enabled *and* disabled |
| notes | switching Spaces mid-edit, and that content follows the right Space |
| settings | delete `~/.spacepill/settings.json` and relaunch |
| the CLI or `CLIServer` | `spacepill doctor`, and every command with the app **down** (all must exit 3, not hang) |
| bundle layout / build scripts | that `Contents/MacOS/SpacePill` is still the app and not the CLI |

The CLI is the one part of this project that *is* testable without the GUI —
drive it over the socket, and poke the raw protocol with
`nc -U ~/.spacepill/spacepill.sock`.
