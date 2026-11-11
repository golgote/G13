# Changelog

## 2.0.0 — G13 Studio redesign

This is one major update to the original macOS G13 driver: a visual profile editor for application shortcuts, with Pro Tools as a starter workflow. It retains the upstream USB HID foundation, bundle identifier, MIT license, and attribution.

### Profile and command workflow

- Universal Default profile and application profiles with automatic switching, duplication, backup, restore, and three M-key layers per profile. Each layer has separate assignments, joystick settings, and backlight color.
- Named Keystroke, Multi Key, and Mouse commands; a Pro Tools starter library; application-scoped folders; All Apps commands; collapsible sections; alphabetical and date sorting; search; and drag-and-drop assignment and folder moves.
- Searchable assignment picker, shortcut capture, timed key or modifier holds, and left, right, middle, and double mouse clicks. Mouse actions can carry configured modifiers such as Shift-click or Cmd-click, and separate G13 controls can hold modifiers through a click.

### Keypad, display, and output

- Visual G13 layout with thumb and joystick controls, larger key tiles, contextual assignment menus, hover descriptions, and Selected Control editing. Selection starts clear and can be dismissed.
- Command and key icons, imported images, adaptive or custom icon colors, configurable labels and shortcut text, light and dark appearance, and portrait or landscape PDF key maps.
- LCD Overview, profile list, and CPU/RAM pages, with optional BD/L display controls. Joystick key and scrolling modes support one or both axes and separate axis speeds.
- Safe Test previews assignments without output. It starts off for normal use. Accessibility access is requested from Settings.

### Stability and packaging

- Balanced key and modifier release on device disconnect, profile changes, output pause, and timed-hold expiry. The command editor keeps Save and Cancel available and closes after saving.
- Portable Xcode signing settings and focused tests for key state, mouse modifiers, macro cancellation, profiles, backup and restore, shortcut capture, LCD pages, drag payloads, icons, and PDF layout.

The public source contains no personal profiles or Ned-specific commands. Locally shared app bundles are ad hoc signed and not notarized; distributors should sign and notarize their own builds.
