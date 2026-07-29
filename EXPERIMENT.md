# Experiment: switching to Spaces beyond Desktop 10

Branch `experimental/switch-beyond-10`. Goal: reach Desktops 11+ (and ideally
drop the "Switch to Desktop N" shortcut requirement) from a normal, SIP-enabled
app. **Conclusion: not achievable cleanly. The Desktop-1-10 shortcut method
remains the only reliable one.** This documents what was tried so nobody has to
rediscover it.

## What macOS gives us

There is no public API to activate a Space. The only *clean* switch a normal
process can cause is by driving the OS's own space-switch handler, which happens
when it receives a real "Switch to Desktop N" (Ctrl+1..0) or "Move left/right a
space" (Ctrl+←/→) shortcut. "Switch to Desktop N" only exists for desktops 1-10.

## Approach 1 — direct private API: `SLSManagedDisplaySetCurrentSpace`

This is the call yabai uses internally (with the target's display UUID + id64).
It *looked* perfect: switching to any Space (incl. 11/12) reported success, the
pill updated, and 30/30 scripted switches "passed".

**It does not actually switch the display.** It only updates the window server's
*record* of the current Space. With real windows open the failure is obvious:
the pill says "Space 2" but Space 12's windows are still on screen and the menu
bar double-renders. The scripted tests were fooled because (a) the test Spaces
were empty, and (b) they only checked `spacepill current`, which reads that same
(now-desynced) record.

Adding `SLSShowSpaces` / `SLSHideSpaces` did not complete the transition either.

This is exactly why yabai needs **SIP disabled + a scripting addition injected
into Dock**: the real transition only happens when the request comes from a
trusted process (Dock/WindowServer). From an external app the call desyncs the
window server (recovered with `killall Dock` or an open/close of Mission
Control).

## Approach 2 — Ctrl+←/→ stepping, one Space at a time, confirmed

"Move left/right a space" *is* enabled by default (unlike Switch to Desktop N),
reaches any Space, and produces a genuine transition (windows move, menu bar
stays clean -- verified). Stepping toward the target and confirming each hop via
SkyLight before the next avoids the old blind-fire overshoot.

**Blocker: posting the arrow keys via `CGEvent` does not trigger the shortcut.**
The same Ctrl+Right sent through `System Events` (AppleScript) switches Spaces;
the identical key sent via `CGEvent` (any tap: hid / session / annotated; with
or without the `.maskSecondaryFn` bit the binding uses -- modifier `0x840000` =
control+fn) does nothing. Curiously, Ctrl+<number> via `CGEvent` *does* work, so
it is specific to the arrow keys. Repeated CGEvent arrow attempts also left the
modifier state stuck, blocking subsequent System Events arrows until a Mission
Control toggle cleared it.

Driving `System Events` from the app (ScriptingBridge / osascript shell-out) is
the remaining untried variant, but it is heavy, needs Automation permission, and
is fragile -- not worth shipping on this evidence.

## Approach 3 — not tried here, but the real options

- **Mission Control click.** Open Mission Control and accessibility-click the
  target Space's thumbnail in the Dock's spaces bar. This is a *real* switch, works
  for any N, needs only Accessibility -- but flashes Mission Control (~0.5s). This
  is the most promising path if 11+ is a must-have. (SpacePill already uses this
  Dock spaces-bar tree elsewhere.)
- **SIP off + Dock injection** (the yabai way). Reliable and instant, but asks the
  user to disable System Integrity Protection. Not appropriate for a lightweight
  menu bar app.

## What shipped from this branch

The switching code is reverted to the reliable Desktop-1-10 shortcut method
(`canSwitchToSpace` and Quick Switch's greying reflect the honest limit again).
Kept, because they are good regardless of the 11+ question:

- `spacepill jump | j <number|label>` (aliases of `switch`).
- The CLI's target resolver now uses the same fuzzy matcher as the Quick Switch
  bar (`SpacePillCore.SpaceSearch`), so `jump dpl` finds "Deploy".

## If revisiting

Try Approach 3's Mission Control click first -- it is the only no-SIP method that
produces a genuine switch beyond Desktop 10.
