# Screenshot checklist

Every image referenced by `README.md`, what has to be on screen, and how to
frame it. Retake any of these and the README picks them up with no edits.

## General notes

- **Retina, then no downscaling.** Capture at 2x (`⌘⇧4` on a Retina display).
  The README sets display widths with `<img width>`, so oversized sources are
  fine and stay crisp.
- **Dark mode** for everything. The app's popovers and panels use vibrancy
  materials that look flat over a light desktop.
- **Clean the menu bar first.** Hide unrelated status items (⌘-drag them out or
  use a bar hider) so the pill is the obvious subject.
- **Neutral desktop wallpaper.** Nothing busy behind translucent panels.
- **No personal data.** Use plausible-but-generic Space labels — the README
  frames SpacePill around parallel coding agents, so things like `AGENT 1`,
  `REVIEW`, `DOCS`, `SCRATCH`, `INBOX` fit the story.
- Crop tight. Every shot should be mostly subject, minimal empty desktop.
- Aim for at least 4–5 configured Spaces before shooting; a single-Space setup
  makes the switching features look pointless.

---

## `pill-menubar.png`

**Shows:** the pill in a real menu bar.

- State: on a Space that has both a label and a colour set.
- Frame: the right-hand end of the menu bar — pill plus the clock and one or two
  neighbouring system items, so the scale is obvious. A thin strip, roughly
  400–600pt wide by the menu bar's height plus a little padding.
- Make sure the number badge on the left of the capsule is legible.

## `pill-variants.png`

**Shows:** that colour carries the meaning.

- State: four to six differently coloured and labelled pills.
- Since only one pill exists at a time, capture the same menu bar crop on
  several Spaces and stack the crops vertically into one image (equal widths,
  small consistent gap, same background).
- Vary label length — include at least one short label and one long enough to
  show truncation behaviour.

## `quick-edit.png`

**Shows:** the Quick Edit popover.

- Trigger: `⌘⇧S`, or left-click the pill.
- State: label field populated with a real-looking name (not empty, not
  placeholder text), and a preset colour swatch visibly selected with its ring.
- Frame: the popover plus its arrow and the pill it's anchored to. A little
  desktop bleed around it is fine — the shadow reads better with room.

## `quick-switch.png`

**Shows:** switching by keyword.

- Prerequisite: Quick Switch enabled in Preferences.
- Trigger: `⌘⇧J`.
- State: search field with a partial query typed (e.g. `age`), the filtered list
  below it, and one row highlighted with the `⏎` marker. Footer should show the
  normal `↑↓ to navigate • ⏎ to switch • ESC to close` hint.
- All visible rows should be reachable here — the greyed-out case has its own
  shot.
- Frame: the whole 400pt-wide popover including the footer hint.

## `quick-switch-unreachable.png`

**Shows:** SpacePill refusing rather than silently failing.

- Setup: create more than ten Spaces, **or** turn off a couple of the "Switch to
  Desktop N" shortcuts in System Settings.
- Trigger: `⌘⇧J` with the search field empty so the full list shows.
- State: at least two rows dimmed with the `nosign` icon, ideally adjacent to
  normal rows for contrast. Select an unreachable row with `↓` so the orange
  footer explains why — either "Can't jump here — macOS has no shortcut past
  Desktop 10" or "Enable 'Switch to Desktop N' in Keyboard Shortcuts to jump
  here". That footer line is the point of the shot; make sure it's readable.

## `notes.png`

**Shows:** the Space Notes panel.

- Prerequisite: Space Notes enabled in Preferences, and "Match Space Color for
  Notes Border" left on so the coloured border is visible.
- Trigger: `⌘⇧N`.
- State: a few lines of Markdown that exercise the highlighter — a `#` heading,
  a bullet list, some `**bold**`, and an inline `` `code` `` span. Keep it
  work-shaped (agent status, a TODO list) rather than lorem ipsum.
- Frame: the panel plus the pill above it, so the connection between the two
  reads. Enough content that the panel is comfortably tall, but not so much that
  it hits the max-height scroll.

## `preferences.png`

**Shows:** the toggles a new user has to find.

- Trigger: right-click the pill → Preferences…
- State: **Quick Switch Bar and Space Notes both enabled**, so all three hotkey
  recorders and the Notes sub-options (border colour, max height slider) are
  visible. The orange "Quick Switch can't change Spaces yet" warning should be
  *absent* — Desktop shortcuts enabled — since this shot illustrates the
  finished state.
- Frame: the full 550x600 window with its title bar.

## `setup-shortcuts.png`

**Shows:** the single most important setup step.

- Where: System Settings → Keyboard → Keyboard Shortcuts… → Mission Control →
  expand the nested **Mission Control** group.
- State: **Switch to Desktop 1…N ticked**, with their key bindings visible in the
  right-hand column. Scroll so the "Switch to Desktop" rows dominate the frame,
  not the "Mission Control" / "Application windows" rows above them.
- Frame: the shortcuts sheet only. Crop out the rest of the System Settings
  window if it adds nothing.
- Annotation is worth it here if you're willing to maintain it: a highlight box
  around the checkbox column. Optional.

## `demo-switch.gif`

**Shows:** the whole value proposition in a few seconds. This is the hero image.

- Length: 4–8 seconds, looping, no title cards.
- Suggested beat sheet:
  1. Start on a labelled Space, pill visible.
  2. `⌘⇧J`, type two or three characters, press Return.
  3. The native transition plays and the pill changes colour and label.
  4. Repeat once to a different Space so it's clearly not a one-off.
- Frame: crop to the menu bar region plus enough of the screen below it that the
  Space transition is legible — a full-screen recording makes the pill too small
  to see at 640px wide.
- Keep the file under ~5 MB; GitHub serves it inline on every README view.
  Reduce frame rate before reducing dimensions.
- Make sure the Quick Switch popover is visible while typing — the point is that
  the keyword drives the jump.

---

## Stale files

`img.png`, `img_1.png`, `img_2.png` are the old README screenshots. Nothing
references them any more; they're kept only so historical README revisions still
render.
