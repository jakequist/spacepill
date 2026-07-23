---
name: spacepill-run
description: Build, launch, and visually verify SpacePill on this Mac. Use when changing SpacePill's UI, hotkeys, or space detection and you need to confirm the behaviour on screen — covers building a signed bundle, driving the menu bar and hotkeys programmatically, taking screenshots, and reading the unified log.
---

# Running and verifying SpacePill

SpacePill is a menu bar app driven by global hotkeys and private Space APIs.
Nothing about it can be verified by reading code alone — you have to run it,
drive it, and look at the screen.

## 1. Build and launch

```bash
./bin/start.sh -d          # build, bundle, sign, launch detached
./bin/start.sh --debug -d  # much faster compiles while iterating
```

Never run `.build/release/SpacePill` directly: without a bundle it has no
bundle identifier, which disables Launch at Login and gives it a different TCC
identity than the real app.

Confirm it came up, and check for permission failures at the same time:

```bash
pgrep -lf "MacOS/SpacePill"
./bin/logs.sh --last 1m
```

## 2. Permissions

SpacePill needs **Accessibility** (to post space-switching keystrokes) and
**Input Monitoring** (for the event tap that makes the pill update instantly).

These grants are tied to the code signature, so an ad-hoc signed build loses
them on every rebuild. If `./bin/dev-cert.sh` has been run on this machine the
identity is stable and grants persist; otherwise expect this after each build:

```
[com.jake.SpacePill:spaces] Failed to create space switch event tap
[com.jake.SpacePill:app] Accessibility permission not granted
```

Re-granting needs a real user to authenticate in System Settings. Ask — do not
try to work around it.

## 3. Screenshots

The logical display is smaller than the captured pixels on a Retina Mac. Get
the logical size once and convert:

```bash
osascript -e 'tell application "Finder" to get bounds of window of desktop'
```

`screencapture` takes **logical** coordinates but writes **physical** pixels
(2x), so an image coordinate maps back as `logical = origin + image_coord / 2`.

```bash
S=/private/tmp/.../scratchpad   # use the session scratchpad, not the repo
screencapture -x -R0,0,1470,30 "$S/menubar.png"    # menu bar strip
screencapture -x -R700,0,500,400 "$S/popover.png"  # pill + popover below it
screencapture -x "$S/full.png" && sips -Z 1200 "$S/full.png"   # downscale before reading
```

Read the PNG back with the Read tool. Downscale full-screen captures first or
they are needlessly large.

The status item sits around x≈975, y≈12 on a 1470-wide logical display, but it
moves as other menu bar items come and go — take a menu bar strip and locate the
pill before clicking it.

## 4. Driving the UI

Hotkeys (these are the app's real entry points, so prefer them):

```bash
osascript -e 'tell application "System Events" to keystroke "s" using {command down, shift down}'  # Quick Edit
osascript -e 'tell application "System Events" to keystroke "j" using {command down, shift down}'  # Quick Switch
osascript -e 'tell application "System Events" to keystroke "n" using {command down, shift down}'  # Notes
```

Mouse — `brew install cliclick`. The status item is a custom `NSHostingView`
with no accessibility role, so AppleScript cannot see it; you must click by
coordinate:

```bash
cliclick c:975,12     # left click  -> Quick Edit popover
cliclick rc:975,12    # right click -> context menu (Preferences / Quit)
```

The app's *windows* are visible to AppleScript, so drive Preferences by element
rather than coordinate:

```bash
osascript -e 'tell application "System Events" to tell process "SpacePill" to get entire contents of window 1'
osascript -e 'tell application "System Events" to tell process "SpacePill" to click item 2 of (checkboxes of group 2 of scroll area 1 of group 1 of window 1)'
```

Allow ~1.5–2s after any hotkey or click before capturing; popovers animate and
space transitions take most of a second.

## 5. Managing Spaces

Space switching:

```bash
osascript -e 'tell application "System Events" to key code 124 using control down'  # right
osascript -e 'tell application "System Events" to key code 123 using control down'  # left
```

Creating Spaces for a multi-Space test setup — the `+` button is `button 1` of
the Spaces Bar, and clicking by coordinate hits the wrong element:

```bash
open -a "Mission Control"; sleep 2
osascript -e 'tell application "System Events" to tell process "Dock" to click button 1 of group "Spaces Bar" of group 1 of group "Mission Control"'
osascript -e 'tell application "System Events" to key code 53'   # Esc to leave
```

Verify how many exist:

```bash
osascript -e 'tell application "System Events" to tell process "Dock" to get name of every button of list 1 of group "Spaces Bar" of group 1 of group "Mission Control"'
```

Space switching by number also depends on the user's Mission Control shortcuts
being enabled — a switch that silently does nothing is usually that, not a bug
in the app.

## 6. Inspecting state

```bash
cat ~/.spacepill/settings.json | python3 -m json.tool   # labels, colours, hotkeys
ls ~/.spacepill/                                        # per-space notes dirs
./bin/logs.sh --last 5m hotkeys                         # one category
```

macOS drops `debug`-level messages for a subsystem unless it has been enabled,
so a missing `Log.*.debug` line proves nothing. Enable it once before relying on
debug output:

```bash
./bin/logs.sh --enable-debug     # needs sudo, persists across reboots
```

To test a first-run experience, quit the app, move `~/.spacepill` aside, and
relaunch.

## 7. Cleaning up

Leave the machine as you found it: quit the app (`pkill -x SpacePill`), close
any popover or notes panel you opened, and put back any Spaces you created.
Notes panels in particular stay on screen — Escape does not dismiss them.
