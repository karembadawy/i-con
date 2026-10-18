# i-con

A menu bar tidier for macOS 27 on MacBooks with a notch. It tucks the icons you rarely use behind macOS's own « button, so the menu bar stays native: Notification Center, gestures, Now Playing and account switching all keep working.

> This is the `native-overflow` branch. The `main` branch has the earlier version, which hid icons with macOS's exam lockdown mode and showed them in its own popup.

## Using it

- i-con adds a small mark (⇤) to the menu bar. **Icons to the left of the mark are tucked behind «.**
- **Click «** to see them. macOS shows them on the left side of the menu bar; click » to put them away.
- **To choose what's tucked away,** hold ⌘ and drag an icon across the mark. Keep it inside the menu bar: macOS deletes icons that are dropped below it.
- Click the mark for Launch at Login and Quit.
- On a screen without a notch (an external display), there's usually room for everything, so nothing is tucked away there.

## Build and run

```sh
./scripts/build-app.sh          # builds, installs to /Applications/i-con.app, launches
swift test                      # unit tests
swift scripts/make-icon.swift   # redraws Resources/AppIcon.icns after design changes
./scripts/make-dmg.sh           # builds dist/i-con-<version>.dmg to share
```

i-con needs no permissions. It runs from `/Applications` (it asks to be moved there otherwise), so Launch at Login keeps working.

## How it works

macOS 27 tucks menu bar icons that don't fit behind its « button, starting from the left. i-con places a blank divider right against the left side of its mark and sizes it to be just too wide to fit between the notch and the mark. macOS then tucks the divider away, and with it every icon to its left. The divider stays as narrow as that allows, because a much wider one (700pt on a 1470pt screen) makes macOS drop « too.

## Limitations

- **A crowded menu bar can tuck the mark itself away** (for example when an app with many menus, like Chrome or Xcode, is in front). It's still behind «.
- **Icons keep their own order.** macOS decides where a newly launched app's icon goes; drag it across the mark if it lands on the wrong side.
- **Wide screens** don't get anything tucked away, because the divider shrinks to nothing when the mark is on a screen without a notch.
