# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

i-con is a personal menu bar tidier for **macOS 27 only**, built for a MacBook with a notch. It's distributed directly (never the App Store) and needs no permissions.

There are two branches with different approaches:
- **`native-overflow` (this one):** i-con adds a mark plus a blank divider. Icons left of the mark get tucked behind macOS's own « overflow button. It uses no private API and has no popup.
- **`main`:** the earlier version. It hid icons with macOS's private exam-lockdown restriction (`MenuBarClientCore`) and showed them in its own popup. That broke native behavior (Notification Center, gestures, Now Playing, account switching, «), which is why this branch exists. See "Learned on main" below before reviving any of it.

## Commands

```sh
swift build                                          # compile check (debug)
swift test                                           # unit tests (Swift Testing)
swift test --filter "DividerWidthTests/neverReachesHalfTheScreen"   # one test
./scripts/build-app.sh                               # release build → /Applications/i-con.app → launch
./scripts/make-dmg.sh                                # shareable dist/i-con-<version>.dmg (app + Applications link + Resources/dmg-readme.txt)
swift scripts/make-icon.swift                        # redraw Resources/AppIcon.icns
open -g -n /Applications/i-con.app --args --snapshot /tmp/bar.png                       # main display's menu bar as drawn
open -g -n /Applications/i-con.app --args --snapshot-region -1470,0,1470,32 /tmp/mb.png # any region, global top-left coordinates
/usr/bin/log stream --info --predicate 'subsystem == "com.karembadawy.icon"'            # app logs
```

- **Install only through `build-app.sh`.** It kills the running copy, rebuilds the bundle with `scripts/bundle.sh`, re-signs and relaunches. The app refuses to run outside `/Applications/` and says so in an alert.
- **Signing:** builds are signed with the self-signed "i-con Local" keychain identity, which keeps the designated requirement stable. That matters for the Screen Recording grant the `--snapshot` debug tool uses.
- Use `/usr/bin/log`, not `log`. In zsh, `log` is a builtin.
- **Commits** never carry Co-Authored-By or "Generated with Claude Code" lines.

## Architecture

- **`IConKit`** holds pure logic: `DividerWidth.width(markOffsetFromRight:screenWidth:notchRight:)`, unit tested.
- **`ICon`** is the executable, built with `.defaultIsolation(MainActor.self)`. Mark anything that runs off the main thread `nonisolated`.
  - **`StatusBar/DividerController`** owns two status items:
    - the **mark** (`i-con.mark`, SF Symbol `chevron.left.to.line`, with a menu: explanation, Launch at Login via `SMAppService.mainApp`, Quit)
    - the blank **divider** (`i-con.divider`)
  - Every 2s and on screen changes, it sizes the divider from the mark's position.
  - **`Debug/Snapshot`** handles `--snapshot` and `--snapshot-region`: a second, inert i-con saves what macOS draws, using i-con's own Screen Recording grant, then quits.

### How tucking works (verified on this machine)

- **Overflow order:** macOS 27 tucks menu bar icons that don't fit behind « **from the left**. A divider too wide to fit next to the visible icons acts as a wall: macOS tucks it away, and with it everything to its left.
- **Too wide breaks «:** a divider of 120–200pt kept « working on the 1470pt MacBook screen. One 700pt divider, or two of them, made « disappear, so tucked icons became unreachable. `DividerWidth` therefore uses the free space between the notch and the mark plus a 12pt margin, capped below half the screen (macOS discards wider items).
- **Clicking « doesn't open a dropdown.** It turns into » and the tucked icons appear inline on the left side of the menu bar, replacing some of the front app's menus.
- **Saved positions:** `NSStatusItem Preferred Position <autosaveName>` in the app's own defaults is honored, and larger values sit further left. The divider is saved at mark + 0.5 so it sits just left of the mark. It's re-created whenever the mark's saved position changes (after a ⌘-drag).
- **Several displays:** status items are mirrored on every display, but an item's length is global. The mark's `button.window` frame shows which menu bar is active.
  - On a screen without a notch, the divider is set to 0, because a wide screen has room and the divider would only show as a blank gap.
  - The first launch puts the mark at saved position 400.
- **A crowded bar tucks the mark too.** When the front app's menus (Chrome, Xcode) fill the space up to the notch, the mark goes behind « as well.

### Debugging without seeing the screen

The terminal Claude runs in has Accessibility but not Screen Recording.

- **Ground truth is a `--snapshot`.** Crop the MacBook bar with `sips -c 64 1300 --cropOffset 0 1640` (it's 2x) and look at it.
- **Snapshots perturb crowded layouts:** while capturing, macOS shows a ~50pt purple screen-recording pill in the menu bar, which can push one more item into «.
- **Hidden menu bars:** the external display's menu bar may be auto-hidden (for example behind a full-screen app); the snapshot then comes out blank.
- **Accessibility positions** (`AXExtrasMenuBar` per app) are only trustworthy on a roomy bar. Tucked items report off-screen or stacked positions. AX reports items for the active menu bar only, which may be either display, so check the sign of x before clicking anything.
- **Probe apps:** a throwaway `LSUIElement` app with fixed-length `NSStatusItem`s and saved positions is how the divider was prototyped. Clean up its `defaults` domain and run `lsregister -u` afterwards.
- **Never synthesize ⌘-drags.** Dropping an icon below the menu bar deletes it. That was confirmed for Apple's icons (input menu, Weather).
  - **Restore the input menu:** `defaults write com.apple.TextInputMenu visible -bool true`, then `defaults delete com.apple.TextInputMenuAgent "NSStatusItem VisibleCC Item-0"`, then `killall TextInputMenuAgent`.
  - **Restore others:** System Settings → Menu Bar (`open "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"`).

## Learned on main (lockdown approach), for reference

- **API:** `MBAssessmentModeConfiguration -initWithAllowedSystemItems:allowedBundleIdentifiers:` with `MBAssessmentModeAssertion`. It's process-bound: macOS restores every icon when i-con quits.
- **Side effects while it's active:**
  - Notification Center is blocked (clock click and swipe).
  - Now Playing, Fast User Switching and « are always hidden.
  - Apps outside `/Applications` are always hidden, whatever the allow-list says.
- **Launch detection:** `didLaunchApplicationNotification` isn't sent for `LSUIElement` apps; watch `NSWorkspace.runningApplications` with KVO instead.
- **`AXPress`** on a status item returns `-25204` while its menu opens; that still counts as success.
- **Hover:** status items get no hover events, and NSEvent mouse-moved monitors only start after the app has shown a window.

## Product decisions (made by the user; don't reintroduce)

- No ⌘-drag-into-popup and no hover-to-open. Both were built on main and removed.
- This branch is "Apple's « only": no popup, and nothing tucked away on screens without a notch.
- Reordering icons stays with macOS (⌘-drag inside the menu bar).
