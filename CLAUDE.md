# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

i-con is a personal menu bar organizer for **macOS 27 only**. It puts a ▾ chevron in the menu bar. Clicking it opens a popup of hidden icons, and clicking a hidden icon opens that app's menu. **Edit** mode lets the user drag icons between a "Hidden" row and a "Menu bar" row.

It is distributed directly, never through the App Store. It is not sandboxed and relies on a private Apple framework.

## Commands

```sh
swift build                                         # compile check (debug)
swift test                                          # all unit tests (Swift Testing)
swift test --filter AllowListTests                  # one suite
swift test --filter "ArrangementTests/showRemoves"  # one test
./scripts/build-app.sh                              # release build → /Applications/i-con.app → launch
./scripts/make-dmg.sh                               # shareable dist/i-con-<version>.dmg (app + Applications link + Resources/dmg-readme.txt)
swift scripts/make-icon.swift                       # redraw Resources/AppIcon.icns (pass a path to also write a 1024px preview PNG)
open -g -n /Applications/i-con.app --args --snapshot /tmp/bar.png   # save the menu bar exactly as macOS draws it (ground truth, see below)
/usr/bin/log stream --info --predicate 'subsystem == "com.karembadawy.icon"'   # app logs
```

- **Run the installed app only through `build-app.sh`.** It must run from `/Applications`: macOS matches the allow-list against the copy LaunchServices resolves for the bundle ID. The script kills the running copy, re-signs and relaunches. Both scripts put the bundle together with `scripts/bundle.sh <path.app>`.
- **Location guard:** `AppDelegate` refuses to start (it shows a "Move i-con to Applications" alert) when the bundle path isn't under `/Applications/`. So `swift run` and copies opened from the disk image quit right away.
- **Sharing:** the disk image is self-signed, not notarized. Gatekeeper rejects it until the recipient clicks Open Anyway in Privacy & Security (checked with `spctl` on a quarantined copy). Use `diskutil image create from` rather than the deprecated `hdiutil create`.
- Use `/usr/bin/log`, not `log`. In zsh, `log` is a builtin and fails with "too many arguments".
- **Signing:** `build-app.sh` signs with a self-signed "i-con Local" identity from the login keychain. That keeps the designated requirement stable, so the Accessibility and Screen Recording grants survive rebuilds. If the identity is missing it falls back to ad hoc signing, and the grants then reset on every build.
- **Stale grants:** if permissions look granted but `AXIsProcessTrusted()` stays false, the grant is tied to an older signature. Reset it with `tccutil reset Accessibility com.karembadawy.icon` (and `ScreenCapture`), then relaunch.

## Architecture

Three SwiftPM targets:

- **`MenuBarPrivate`** (Objective-C) is the only code that touches private API. `IMBVisibilityShim` dlopens `MenuBarClientCore` and checks every selector, wraps calls in `@try/@catch`, and reports `unavailableReason` when anything is missing.
- **`IConKit`** holds the pure logic that the unit tests cover:
  - `Arrangement`: the ordered list of hidden bundle IDs.
  - `AllowList`: builds the allow-list.
- **`ICon`** is the executable. It is built with `.defaultIsolation(MainActor.self)`, so anything that runs off the main thread (AX scans, ScreenCaptureKit, data structs) must be marked `nonisolated` explicitly.

### Hiding (the core mechanism)

macOS 27 draws the whole menu bar in one window. The old trick of pushing icons off-screen with a very wide spacer item no longer works, because macOS 27 discards any status item wider than half the screen.

i-con uses the private exam lockdown ("assessment mode") restriction instead:

- **API:** `MBAssessmentModeConfiguration -initWithAllowedSystemItems:allowedBundleIdentifiers:` (both arguments must be `NSArray`) and `MBAssessmentModeAssertion -activateWithConfiguration:completionHandler:` / `-invalidate`.
- **Allow-list semantics:** apps not in the allow-list lose their status items.
- **Process-bound:** if i-con quits or crashes, macOS restores everything.
- **Allow-list contents:** `AllowList.bundleIDs` returns i-con's own ID plus every running app's bundle ID, minus hidden apps, plus a temporarily revealed app. It returns `nil`, meaning "no restriction at all", when no hidden app is running.
- **System items:** IDs `0..<64` are always allowed. macOS 27.2 keeps only 0–8 and silently drops the rest (read back via `allowedSystemItems`); the wider range is headroom for new items.
- **`-initWithUnrestrictedMenuBarItems`** is new in 27.2 (absent in 27.0.1). It behaves exactly like no restriction, so it's no use for hiding.
- **No flash:** the shim activates the new assertion before invalidating the old one.
- **Only apps in `/Applications` (or Apple's `/System/…`) are recognized.** While any restriction is active, macOS hides every icon from an app installed elsewhere (`~/Applications`, Xcode build folders, temp folders), whatever the allow-list says. Verified with snapshots using a probe app copied to each location. `AppLocation.isRecognized` encodes the rule, and the popup warns about visible apps outside it (`AppState.appsMacOSWillHide`).
- **Launch detection:** watch `NSWorkspace.shared.runningApplications` with KVO. `didLaunchApplicationNotification` isn't sent for `LSUIElement` (menu-bar-only) apps, which are exactly the apps with status items. A launch triggers an immediate apply, which adds the new app to the allow-list before its status item appears, then rescans at +2s and +8s. Verified: an `/Applications` app launched while hiding is drawn within a second, with no restart needed.
- **Don't "restart" the restriction to reveal icons.** An earlier attempt to fix missing icons by switching the restriction off and on was based on a misleading probe self-report, and was removed. Every case it targeted was really the location rule above.
- **The restriction also blocks Notification Center.** Clicking the clock does nothing while it's active (verified on 27.0.1 and 27.2: the panel opens with i-con quit and not while hiding; Notification Center connects to MenuBarAgent's restriction server as a monitor). `ClockClickHandler` watches for a mouse-up on the clock, which `AppState.isClock` defines as the rightmost `MenuBarAgent` item in its bar. It then suspends hiding (`setHidingSuspended`, an allow-list of `nil`), replays the click, and resumes once the Notification Center panel closes. The panel is a `com.apple.notificationcenterui` window with layer > 0; its desktop widgets have negative layers. Hidden icons show while the panel is open. Two-finger-swipe opening isn't covered.
- **macOS's « overflow button works while a restriction is active, since 27.2.** On 27.0.1 it was hidden, so tucked icons were unreachable. The bar right of the notch is often full (app menus like Xcode's spill past the notch), and macOS tucks from the left, so i-con's own ▾ is usually the first icon tucked.
  - **Tucked apps report no AX items at all** until « is expanded. Pressing it turns it into » and shows them inline left of the notch, with real frames.
  - « is a `MenuBarAgent` item with `AXIdentifier` `menu-bar-overflow-indicator`, which becomes `menu-bar-overflow-indicator-expanded`. AXPress toggles it. Esc doesn't collapse it.
- **Completion handler:** its first argument is `nil` on success. The shim takes it as `void *` and only bridges it when it looks like an object pointer.

### Data flow

`AppState` (`@Observable`) owns everything:

- the scanned `items`
- the `arrangement`, persisted as JSON under the UserDefaults key `arrangement` by `ArrangementStore`
- the engine state
- the icon cache

`ChevronController` owns the status item and the `PopupPanel`, a non-activating borderless `NSPanel` hosting SwiftUI `PopupView`:

- It resizes via `NSHostingController.sizingOptions = .preferredContentSize` and re-anchors under the chevron on resize.
- It closes on any global mouse-down or Esc.
- A 0.3s `lastClose` debounce stops the closing click from reopening it.

### Inventory: `AXInventory`

- Scans every running `.app` in parallel, reading the app's `AXExtrasMenuBar` children, with a 0.1s messaging timeout per element.
- `com.apple.MenuBarAgent` owns the system items and macOS's « button. It is scanned only to get obstacle frames (`AppState.systemFrames`) and is never shown in the UI.
- **Accessibility frames don't tell you whether an icon is drawn.** Hidden apps keep stale frames if they were drawn when hidden, and icons hidden for other reasons can report real-looking positions too. Never infer visibility from AX; use a `--snapshot`. Exclude hidden apps when checking overlaps.
- **No AX items at all:** an app whose icon macOS removed, an app tucked behind «, a hidden app that was tucked (or never drawn) when it got hidden, and (on 27.2) an app outside `/Applications` launched while hiding. So `AppState.update` adds every running hidden app the scan missed, without frames, or the popup would silently lose it.

### Icon images: `IconCapture` and `IconCache`

- Hidden icons are not drawn, so images are captured with ScreenCaptureKit while an icon is visible and cached as PNGs in `~/Library/Application Support/i-con/icons/`. Without a capture, the app icon is the fallback.
- **The menu bar window belongs to WindowServer, not MenuBarAgent.** It is found by `windowLayer == CGWindowLevelForKey(.mainMenuWindow)`. Capturing that window alone gives transparent icons. `SCScreenshotManager.captureImage(in:)` is the fallback and includes the wallpaper.
- Always call `waitForSettledLayout()` before capturing. After a launch or a restriction change, icons slide into place, and an early capture grabs a neighbor's pixels.
- **Skip an item when** it is behind the notch, when it overlaps another item's frame, or when it overlaps a system frame. macOS stacks overflowed items on its own chevron.
- **Template detection:** single-color, single-brightness icons on transparency render as templates, so they adapt to light and dark mode.
- **Blank captures** (`IconCapture.isBlank`) mean the icon isn't drawn. They aren't stored, so the popup falls back to the app icon instead of an empty tile, and they aren't retried until apps launch or quit.

### Click-through: `ItemActivator`

The sequence when the user clicks a hidden icon:
1. Dismiss the popup.
2. Add the app to the allow-list (`setRevealed`).
3. Wait 250ms.
4. If the app reports no items, it didn't fit and is tucked behind «: expand « and poll up to 1s for its items (`reachTuckedItem`).
5. Call `AXPress` on the app's only status item.
6. If AXPress fails, post a CGEvent click at the item's frame center and warp the cursor back.
7. Re-hide the app when its menu or popover window closes, on a click outside that app's windows, or after 60s. Collapse « first if this reveal expanded it; once the app is hidden, « can vanish while still expanded.

Menu windows are app-owned windows with layer > 0 that reach below the menu bar (`hasOpenMenu`). Apps own no windows in the bar itself on 27, and some menus start above the screen top: the input menu's window is at y = −41. A click outside the menu while it's open is swallowed by the menu, so the window check is what ends most reveals.

Two rules:
- **`AXPress` on a status item returns `-25204` (`kAXErrorCannotComplete`) while the menu opens.** Treat that as success. Clicking again on top of it double-activates the item.
- An app's menu always opens from its real menu bar icon. No app can draw another app's menu inside its own popup, so the icon visibly appears in the menu bar while its menu is open. That's inherent; Bartender and Ice do the same.

## macOS 27 facts (verified on this machine unless noted)

First verified on 27.0.1 (26A434). On 27.2 (26B123) the «, system ID, Notification Center, Fast User Switching and location findings were rechecked with snapshots.

- **Now Playing and Fast User Switching are always hidden while any restriction is active.** That held with system IDs up to 65,535, with all 232 running process bundle IDs, and with string IDs. On 27.2 the configuration keeps only system IDs 0–8, so neither has an ID to allow. The user accepted using Control Center for both. Don't try to "fix" this again without new information.
- **Seen once on 27.2, cause unknown:** the copy of i-con launched at the first login after updating hid *everything* except MenuBarAgent's items, its own ▾ included, until it was relaunched. Its assertions were balanced (one live), and a fresh process with the same allow-list behaved. If it recurs, capture MenuBarAgent's `visibilityRestriction` log and a `--snapshot` before relaunching.
- **Hiding is per app:** all of an app's icons move together.
- **⌘-dragging an icon out of the menu bar can delete it.** Confirmed for Apple's icons (input menu, Weather): macOS sets the owner's `NSStatusItem Visible…` key to 0. Third-party behavior on 27 is unconfirmed, so treat every icon as at risk and never synthesize ⌘-drags.
  - **Restore the input menu:** `defaults write com.apple.TextInputMenu visible -bool true`, then `defaults delete com.apple.TextInputMenuAgent "NSStatusItem VisibleCC Item-0"`, then `killall TextInputMenuAgent`.
  - **Restore sandboxed items like Weather:** System Settings → Menu Bar (`open "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"`).
- **Hover detection was unreliable:** a tracking area on the status item button and `NSEvent` mouse-moved monitors both only fired after the app had shown a window. A listen-only `CGEventTap` worked. The feature itself was later removed (see below).
- **Chevron frame after launch:** the status item button's window frame is bogus right after launch. `ChevronController.chevronFrame()` only trusts a frame that sits inside a menu bar, and onboarding opens the popup after 0.5s.
- **Sandbox (from Hidden Bar's macOS 27 work, not tested here):** the App Sandbox blocks the AX server lookup, so the app must stay unsandboxed.
- **Icon drawing:** Core Graphics shadows ignore the CTM. `make-icon.swift` scales the shadow blur and offset by hand and uses a negative y offset.

## Product decisions (made by the user; don't reintroduce)

- **The lockdown popup (this branch) is the chosen approach.** The `native-overflow` branch tried the alternative: a blank divider that makes macOS tuck the icons to its left behind its own « button. It works, but it adds almost nothing over macOS 27's built-in overflow. Nothing gets tucked away on a roomy external display, and on the notched screen macOS already tucks icons away. The user went back to this branch. That branch's CLAUDE.md records what was learned about «.

- Drag and drop happens only inside the popup, in Edit mode. A ⌘-drag-into-popup feature was built and then removed because it deleted icons. A "drop on ▾" alternative was declined.
- The popup opens on **click only**. Hover-to-open was built and then removed at the user's request.
- Launch at login uses `SMAppService.mainApp`, from the gear menu in the popup.
- Reordering icons inside the real menu bar is left to macOS.

## Debugging without seeing the screen

The terminal Claude runs in has Accessibility permission but not Screen Recording. Useful techniques, written as throwaway scripts in the scratchpad:

- **Read the real menu bar:** scan each app's `AXExtrasMenuBar` from a Swift script.
- **Find windows:** list a pid's windows with `CGWindowListCopyWindowInfo`. The popup is the layer-101 window owned by i-con.
- **Exercise the private API in isolation:** a small ObjC program with `dlopen` and `objc_msgSend`. `pkill -x i-con` first so two restrictions don't interact, then relaunch with `open /Applications/i-con.app`.
- **Drive the UI:** `AXPress` on i-con's own status item toggles the popup. Posted `CGEvent` `mouseMoved` events simulate the pointer; `CGWarpMouseCursorPosition` doesn't generate events.
- **Check captures:** view the cached PNGs in `~/Library/Application Support/i-con/icons/` directly.
- **Ground truth for visibility: `--snapshot`.** Running `open -g -n /Applications/i-con.app --args --snapshot <png>` starts a second, inert i-con that saves the WindowServer menu bar window (on white) and quits. Launched through `open`, it uses i-con's own Screen Recording grant. Crop the right of the notch with `sips -c 66 1300 --cropOffset 0 1640` (Retina) and look at it. To test a scenario, quit i-con, drive the restriction from a small ObjC program, and snapshot each stage.
- **MenuBarAgent's side of the restriction:** `/usr/bin/log show --last 5m --info --predicate 'process == "MenuBarAgent" AND category == "visibilityRestriction"'` lists every activate and invalidate. The `statusItems` category logs `Creating status item …, isAllowed:`. i-con's own info logs live in memory only and are gone within the hour. Subscribing as a monitor (`VisibilityRestrictionMonitorSession`) from a test program got no callbacks; it likely needs an entitlement.
- **Synthetic clicks on popup tiles:** a CGEvent click within about a second of opening the popup by AXPress was ignored, while later clicks worked. A tile's AX frame is the tile itself, except that a tile alone in its row reported the whole row's width.
- **Don't trust a status item's own self-report either.** A probe app's `button.window.frame` and `occlusionState` claimed "visible" for icons the snapshot showed weren't drawn.
- **Probe apps:** a throwaway `LSUIElement` app with one `NSStatusItem` (a text title like ◆ is easy to spot) is useful for testing launches. Remember the location rule when placing it, and clean up its `defaults` domain and LaunchServices registration (`lsregister -u`) afterwards.

Anything that changes the user's menu bar is visible to them, so keep experiments brief and say what will flash.
