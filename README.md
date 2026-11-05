# GAOMON S620 for Omarchy

An Omarchy bar widget for the GAOMON S620 pen tablet (`256c:006d`). It
sets the screen mapping, orientation, pressure range and the four
express keys, and it works on the kernel's `hid-uclogic` driver — no
vendor driver to install.

## Requirements

- Omarchy with Hyprland 0.56 or newer.
- The tablet plugged in over USB.

There is nothing else to install.

## Installation

1. Add the plugin and enable it:

   ```sh
   omarchy plugin add https://github.com/AeonArcHQ/omarchy-gaomon-s620 --enable
   ```

   `--enable` asks where in the bar the widget goes and turns it on.
   Without it, enable later with `omarchy plugin enable
   com.aeonarc.gaomon-s620`.

2. Install the udev rule so your session can read the express keys:

   ```sh
   sudo install -m 644 "$HOME/.config/omarchy/plugins/com.aeonarc.gaomon-s620/udev/71-gaomon-s620-pad.rules" /etc/udev/rules.d/
   sudo udevadm control --reload
   sudo udevadm trigger --subsystem-match=input
   ```

   The rule gives the local session (`uaccess`) read access to the
   tablet's pad node only, and to OpenTabletDriver's virtual pad when
   that backend owns the tablet. The pen keeps going to Hyprland
   through libinput and works without the rule; only the express keys
   need it.

3. Check that it worked. The bar shows 󰽉, dimmed while the tablet is
   missing or the express keys cannot be read. Click it: the status
   line should say "connected · Kernel driver", and with the tablet
   plugged in the panel shows its firmware version. If it says "no
   permission on the express keys (install the udev rule)", see
   Troubleshooting.

## Using the panel

Click the bar icon. Settings are saved in
`~/.local/state/gaomon-s620/profile.json` and sent to Hyprland again on
every config reload and monitor change. Until the first change from
the panel there is no file, and the plugin leaves the tablet settings
in your Hyprland config alone.

- **Status**: "connected · Kernel driver", "tablet disconnected",
  "no driver owns the tablet" or "no permission on the express keys
  (install the udev rule)", or "connected · OpenTabletDriver" when the
  OpenTabletDriver daemon owns the tablet. On the kernel driver, with
  the tablet plugged in, its firmware version
  (`OEM02_T18e_200919` on the tablet tested), worth quoting when
  reporting a problem.
- **Screen mapping**: all monitors, the focused one or a specific
  monitor; full area, an area cropped to the screen's proportions so
  circles stay round ("Match screen"), or a custom area drawn on the
  tablet (dragged and resized in the panel, always at the screen's
  ratio); mouse (relative) mode.
- **Orientation**: right-handed or left-handed (turned 180°).
  Hyprland cannot turn this tablet 90° or 270°; see
  docs/re/findings.md.
- **Pressure**: the threshold and the pressure that already counts as
  full (10% to 100%), plus a pressure test: press the pen in the box
  to see the live pressure and the stroke's peak. Hyprland reads the
  range only when the tablet connects, so a change takes effect after
  unplugging and plugging the tablet back in; the panel says so.
- **Express keys**: each of the four keys gets an action: shortcut
  presets (undo, redo, save, brush, eraser, smaller and bigger brush,
  zoom in and out), a custom shortcut, media and system presets
  (play/pause, next and previous track, volume up/down, mute, lock
  screen, suspend), "Show key functions" (a notification listing the
  four keys), "Next monitor" and "Toggle pen/mouse" (both change the
  profile, as the panel does), "Run command", or "Nothing" to turn
  that one key off. Each runs once per press. A dot lights up while
  each key is pressed, even with the keys switched off; the **Express
  keys** switch turns them all off so they send nothing. Turned
  left-handed, key 1 is the rightmost of the row. Defaults: undo,
  redo, eraser, show key functions.
- **Defaults**: restoring the defaults takes two clicks.

## IPC

`omarchy-shell com.aeonarc.gaomon-s620
toggle|open|close|show|hide|status|resetDefaults|lastError`, `keys
on|off` and `set <field> <json>`, for example `set rotation 2`,
`set output '"eDP-2"'` or `set keys.0.action '"undo"'`.

## OpenTabletDriver (experimental)

The kernel driver is the default and needs nothing else. If you have
installed OpenTabletDriver and its daemon owns the tablet, the panel
notices it on its own and shows "connected · OpenTabletDriver". On that
backend the plugin applies the screen mapping, the working area and the
express keys; 90°/270° rotation and the pressure curve are not wired
yet. The plugin never installs, removes or blocks drivers: removing
OpenTabletDriver gives the tablet back to the kernel driver, with the
same profile.

## Not supported

- 90° and 270° rotation and the vendor's pressure curve: the kernel
  driver cannot do either; planned for v1.1 on the OpenTabletDriver
  backend ([docs/adr/0001](docs/adr/0001-kernel-driver-default-opentabletdriver-optional.md)).
- Remapping the two pen buttons: they reach applications as stylus
  buttons, and what they do is up to each application.
- Holding a key down (Space to pan, Shift, Ctrl or Alt): Hyprland
  releases it right away, so it needs a virtual keyboard; see
  docs/re/findings.md.
- Per-application profiles.

## Removing

```sh
omarchy plugin remove com.aeonarc.gaomon-s620
sudo rm /etc/udev/rules.d/71-gaomon-s620-pad.rules
sudo udevadm control --reload
```

Optionally delete the saved settings:
`rm ~/.local/state/gaomon-s620/profile.json`.

## Troubleshooting

- **"no permission on the express keys"**: install the udev rule
  (Installation, step 2). The pen does not need it. A rule installed
  by an earlier version only covers the kernel pad — on
  OpenTabletDriver the express keys need the rule reinstalled.
- **A pressure change did not take effect**: unplug the tablet and
  plug it back in. Hyprland reads the pressure range only when the
  tablet connects.
- **Do not install the vendor driver alongside.** It grabs the tablet
  through `hidraw`, re-emits it through `uinput` and, on install,
  makes `/dev/uinput` and every `256c` USB device writable by all
  users.

## How it works

- `s620-pad`: Python helper. It finds the pad's evdev node through
  sysfs and prints each key press and release. It does not grab the
  node.
- `Model.js`: the profile, the `hl.device` Lua sent with `hyprctl
  eval`, the active area for "Match screen", and the
  `send_key_state` shortcut for each key.
- `Service.qml`: processes, profile and Hyprland events.
  `TabletPanel.qml`: bar and panel, following the official Omarchy
  panels.
- What the vendor driver does and what the kernel already covers,
  from the reverse engineering of `huionCore`, is in
  [docs/re/findings.md](docs/re/findings.md).

## Development

```sh
git config core.hooksPath .githooks   # once per clone: enables the pre-commit hook
tests/check.sh                        # unittest, qmltestrunner, plugin validate
```

- Edit the plugin in `~/.config/omarchy/plugins/com.aeonarc.gaomon-s620`
  as a real folder: through a symlink, Quickshell rejects the QML with
  "File name case mismatch".
- Hot reload does not replace the panel already loaded or the
  `IpcHandler`. After changing QML, run `omarchy restart shell`. QML
  errors only show up in `journalctl --user | grep TabletPanel.qml`.
- `./s620-pad watch` prints the express key events, handy to check
  the udev rule. Run `omarchy-shell
  com.aeonarc.gaomon-s620 keys off` first: with the keys
  on, each press also sends its shortcut to the focused window, the
  terminal included. `keys on` afterwards.
