# i-con

A menu bar organizer for macOS 27. Click the ▾ arrow to see hidden icons; click one to open it. Use **Edit** to drag icons between "Hidden" and "Menu bar".

## Build and run

```sh
./scripts/build-app.sh          # builds, installs to /Applications/i-con.app, launches
swift test                      # unit tests
swift scripts/make-icon.swift   # redraws Resources/AppIcon.icns after design changes
./scripts/make-dmg.sh           # builds dist/i-con-<version>.dmg to share
```

## Sharing

`make-dmg.sh` builds a disk image containing the app, an Applications shortcut, and `Read Me First.txt` with install steps (from `Resources/dmg-readme.txt`). The app is self-signed, not notarized, so on another Mac Gatekeeper blocks the first launch: the user has to click **Open Anyway** in System Settings → Privacy & Security. Removing that step needs a paid Apple Developer ID and notarization. The recipient needs macOS 27.

If i-con is opened from anywhere other than `/Applications` (for example straight from the disk image), it shows a "Move i-con to Applications" alert and quits.

i-con must run from `/Applications`. It needs **Accessibility** (required) and **Screen Recording** (optional, for real icon images instead of app icons).

The build is signed with a local self-signed certificate named "i-con Local" from the login keychain, so macOS keeps those permissions across rebuilds. Without it the script signs ad hoc, and you have to grant the permissions again after every build.

Logs: `log stream --info --predicate 'subsystem == "com.karembadawy.icon"'`

## How it works on macOS 27

macOS 27 draws the whole menu bar in one window, so the old "wide spacer" trick no longer works. i-con instead uses a private restriction from `MenuBarClientCore`, the one behind exam lockdown mode (see `Sources/MenuBarPrivate`). It takes an allow-list of apps, and every other app's icons leave the menu bar. If i-con quits or crashes, macOS restores every icon.

## Limitations

- **Per app:** an app's icons hide and show together.
- **Apple's system items** (clock, Wi-Fi, battery, Control Center) always stay visible.
- **Apps must be installed in /Applications.** While anything is hidden, macOS also hides icons of apps installed elsewhere (for example `~/Applications` or an Xcode build folder). The popup warns when that happens.
- **macOS's « overflow button is hidden while anything is hidden,** so icons macOS tucks away for lack of space can't be reached. Hiding more icons in i-con doesn't bring them back.
- **Notification Center is blocked while anything is hidden.** Clicking the clock still works, because i-con pauses hiding until Notification Center closes, so hidden icons show meanwhile. Opening it with a trackpad swipe doesn't work while icons are hidden.
- **Now Playing and Fast User Switching disappear while anything is hidden.** The exam restriction always hides them, whatever the allow-list says. Use them from Control Center instead.
- **Opening a hidden icon** shows it in the menu bar while its menu is open, because macOS attaches the menu to the real icon.
- **Never ⌘-drag an icon out of the menu bar.** macOS 27 deletes it. Turn it back on in System Settings → Menu Bar or in the app's settings.
- **Icon images** are captured while an icon is visible. Icons macOS has pushed into its overflow can't be captured, so they show the app icon until opened once.
