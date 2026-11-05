# Reverse engineering: GAOMON Linux driver 16.0.0.50

Findings log with REA Evidence IDs. Each item says whether it was **observed** (in the binary or on the hardware), **inferred**, or is **unknown**.

## Artifacts

| File | SHA-256 | Source |
|---|---|---|
| `GaomonTablet_LinuxDriver_v16.0.0.50.x86_64.deb` | `c0f95d9f…161afb` | GAOMON website |
| `GaomonTablet_LinuxDriver_v16.0.0.50.x86_64.tar.xz` | `4ab94b7f…14efdd` | GAOMON website |
| `huionCore` (ELF x86-64, not stripped, with debug info) | `5174e0ab…9cd9bb` | identical in both packages |
| `gaomontablet` (Qt/QML settings UI) | `d38ad19a…19f7b` | both packages |

- **Observed**: both packages carry the same `/usr/lib/gaomontablet` tree. The only difference is `gaomontablet.sh`: the tarball starts `huionCore -d` twice, the `.deb` once. The tarball also ships `uninstallHuionDriver.sh`.
- **Observed**: the driver is Huion's. The daemon is called `huionCore`, the udev rule names `HUION 256C PEN STYLUS`, and `log.conf`/`.huion.log` come from Huion.
- **Observed**: the installer copies `20-gaomon.rules`, which makes `/dev/uinput`, `/dev/uhid` and every `256c` USB device mode `0666` for all users, and `postinst` copies a bundled `xdotool` and `libxdo.so.3` into `/bin` and `/usr/lib`. This plugin does neither.

## huionCore: device protocol

- **Observed**: `parse_cmd_resp_200` fills the tablet parameters from the reply to string descriptor 200 (`ev_dc9ff7c9…`): max X (`parse_maxx`, bytes 0-2 little-endian, `ev_7cbea43c…`), max Y, max pressure, LPI, report rate, pen/express/strip button counts (`parse_hbtn_num` is byte 11, `ev_0899a7c7…`), and whether it is a pen display. `parse_cmd_resp_201` reads descriptor 201 (firmware name).
- **Observed**: in a report, byte 1 is the report type (`report_type`, `ev_7facd438…`) and the express key bitmap is bytes 4-7 (`report_hbtn_id`, `ev_edb5789b…`). With no per-model key code table, the key index is the highest set bit (`parse_index_hek_default`, `ev_19726a52…`; `parse_index_hek`, `ev_bd7adaae…`).
- **Inferred**: this is the same Huion "v2" protocol the kernel's `hid-uclogic` driver speaks: it reads string descriptor 200 to switch the tablet out of its mouse-emulation mode and builds a report descriptor from the parameters.
- **Observed**: the daemon reads `hidraw` and writes its own events to `/dev/uinput` (strings `hidraw/`, `/dev/uinput`, `/dev/input/event%d`; `ev_1931d275…`). Shortcuts go through a uinput keyboard (`huion_send_key_input`, `HnMouseKeyboard::keyboardDown/Up`) and the wheel through `xdotool click 4/5`. Per-application profiles find the focused window with `xdotool getwindowpid $(xdotool getwindowfocus)`, which only works on X11 (`ev_572be4d6…`, `ev_1931d275…`).
- **Observed**: the pressure curve is applied in user space before the daemon emits the pen (`calibrate_press_low/mid/high`, `HnDoerPen::get_pressure_power_grade`, `ev_572be4d6…`).

## Vendor model table

- **Observed**: `res/tablet.cfg` is a table of UTF-16LE records separated by `ff ff`. The record for firmware `OEM02_T18e` has the product name `S620` and the board name `GM_PW205`. The record's other fields were not decoded.

## Hardware on this machine (observed on 2026-10-24)

- USB `256c:006d`, manufacturer `GAOMON`, product `Gaomon Tablet`, `bcdDevice 0100`, two HID interfaces, both bound to `hid-uclogic` (kernel 7.2.8).
- `hid-uclogic` created `GAOMON Gaomon Tablet Pen`, `Pad`, `Touch Strip` and `Dial` input nodes, all with `Uniq=OEM02_T18e_200919`. Commands: `grep -A8 -i gaomon /proc/bus/input/devices`, `readlink /sys/bus/hid/devices/0003:256C:006D.*/driver`.
- The pen report descriptor that `hid-uclogic` built (`od -An -tx1 -v /sys/bus/hid/devices/0003:256C:006D.001A/report_descriptor`): X 0-33020 over 6.500 in, Y 0-20320 over 4.000 in (5080 LPI), pressure 0-8191, tilt X/Y. Hyprland reports the pen as `gaomon-gaomon-tablet-pen`, 165.1 × 101.6 mm (`hyprctl devices`).
- The pad node advertises `BTN_0`-`BTN_8`, `BTN_STYLUS` and `BTN_RIGHT` (`/sys/class/input/event23/device/capabilities/key` = `800 201ff 0 0 0 0`), the generic set `hid-uclogic` gives every v2 frame.
- **Observed**: the four express keys sit side by side in a horizontal row in the tablet's top-left corner.
- **Observed**: from left to right the keys send `BTN_0`-`BTN_3` (codes 256-259), one press and one release each, no autorepeat. Command: `./s620-pad watch`.

## Conclusion for the plugin

The kernel already does what `huionCore` does at the device level. What is missing on Hyprland is the user-space part: mapping the pen to a screen, rotation, the pressure range and actions for the express keys. Hyprland 0.56 covers the first three with `hl.device` and `input.tablettool.pressure_range_*`; the plugin reads the pad node for the keys and sends shortcuts with `hl.dsp.send_key_state`, with no uinput, no xdotool and no world-writable device.

- **Observed (2026-10-24)**: `hl.device({ transform = 1 })` and `transform = 2` leave the pen unrotated; at 180° the cursor moves against the pen.
- **Observed (source)**: Hyprland 0.56.2 `CInputManager::setTabletConfigs` rotates tablets only with `libinput_device_config_calibration_set_matrix`. libinput 1.32 `tablet_init_calibration` (`src/evdev-tablet.c`) enables the calibration matrix only for display tablets or `INPUT_PROP_DIRECT`. The S620 pen node has only `INPUT_PROP_POINTER` (`/sys/class/input/event22/device/properties` = `1`), so the matrix is dropped. Turning it 90° needs a uinput proxy that rotates the coordinates, as `huionCore` does.
- **Observed**: libwacom ships `/usr/share/libwacom/gaomon-s620.tablet` with `Reversible=true` and `EvdevCodes=BTN_0;BTN_1;BTN_2;BTN_3`. With `left_handed = true` the pen works turned 180°, over the whole tablet (confirmed on the tablet on 2026-10-24).
- **Observed (2026-10-24)**: `hl.device` skips an `active_area_size` of `{ 0, 0 }` and keeps the previous crop. The plugin sends the whole tablet (165.1 × 101.6 mm) explicitly.
- **Observed (2026-10-25)**: the active area applies after `left_handed`, in the tablet as the user holds it. With `active_area_size = { 82.5, 101.6 }` and `active_area_position = { 0, 0 }`, the left half moves the cursor right-handed, and with `left_handed = true` and the tablet turned 180° it is still the left half as held (set with `hyprctl eval 'hl.device({ ... })'`, drawn on the tablet).
- **Observed (2026-10-24)**: `input.tablettool.pressure_range_max = 0.5` is stored right away (`hyprctl getoption`) but the pen only follows it after the tablet is unplugged and plugged back in. Toggling `hl.device({ enabled = false })` and back does not apply it, and neither does taking the pen out of range (checked with a `PointerEvent.pressure` meter in Chrome, with the range at 0.2).
- **Observed (source)**: a change to `input.tablettool.*` trips `REFRESH_INPUT_DEVICES`, so Hyprland calls `setTabletToolConfigs` on the existing tools. libinput 1.32 stores the range as `wanted_range` and copies it in `apply_pressure_range_configuration` only when the tool leaves proximity, or when the tool is set up. With this pen, only the set-up path took effect.
- **Unknown**: why leaving proximity does not apply the range on this pen; Hyprland's log shows libinput forcing proximity out from its `tablet-proximity-timer` plugin, which may bypass that path.
- **Observed (2026-10-24)**: the two pen buttons reach applications as stylus buttons 1 and 2 (Xournal++ input test lights both). What they do is up to each application; Xournal++ ships them set to nothing.
- **Observed (2026-10-24)**: express keys 1 and 2 undo and redo in Xournal++ through `hl.dsp.send_key_state` (Ctrl+Z, Ctrl+Shift+Z), with the tablet turned left-handed. The keys keep their `BTN_*` codes when turned, so key 1 is then the rightmost.
- **Observed (2026-10-25)**: `./s620-pad watch` reports `"firmware": "OEM02_T18e_200919"` on connecting, read from the pad node's `uniq` in sysfs, and the panel shows "Firmware OEM02_T18e_200919" under the connection status (screenshot after `omarchy restart shell`). Unplugged with the panel open, the line goes away.
- **Observed (2026-10-25)**: with `keys off` (or the panel switch) the express keys send nothing while the panel's dots still light; `keys on` brings undo back in Xournal++.
- **Observed (2026-10-25)**: the eight media and system presets work from the express keys, once per press and not again while held: play/pause, next and previous track (`omarchy-shell media playPause|next|previous`), volume up, down and mute (`omarchy-audio-output-volume raise|lower|mute-toggle`, with Omarchy's OSD), lock (`omarchy-system-lock`) and suspend (`systemctl suspend`, as Omarchy's system menu runs it). Set with `set keys.N.action` and pressed on the tablet.
- **Observed (2026-10-25)**: Omarchy's notification card shows at most three body lines and silently drops the rest (`maximumLineCount: 3` in `/usr/share/omarchy/shell/plugins/notifications/components/NotificationCard.qml`), and it collapses repeated spaces. One line per express key lost key 4.
- **Observed (2026-10-25)**: the "Show key functions" key sends one notification through `omarchy-notification-send` with the four keys two per line (`1 Undo · 2 omarchy launch browse…` / `3 Eraser (E) · 4 Show key functions`, a long command cut with "…"). Set with `set keys.3.action '"showKeys"'` and pressed on the tablet.
- **Observed (2026-10-25)**: the "Next monitor" key moves the pen to the next monitor and wraps (eDP-2 → a headless second output made with `hyprctl output create headless` → eDP-2), and "Toggle pen/mouse" flips mouse mode on and off; the panel's monitor dropdown and mouse-mode switch follow each press. Set with `set keys.2.action '"switchMonitor"'` and `set keys.3.action '"togglePenMouse"'`, pressed on the tablet.
- **Observed (2026-10-25)**: the custom area works from the panel: dragging and resizing the rectangle on the tablet drawing keeps the screen's ratio and stays inside the tablet (saved as `customArea` 128.7 × 80.4 mm on a 16:10 screen), the pen covers the whole screen only inside that part of the tablet, and turned left-handed the keys' marks move to the bottom right of the drawing and the area stays where it is drawn, as held. Drawn on the tablet with the panel open.
- **Observed (2026-10-25)**: from the express keys, zoom in and zoom out (Ctrl+= and Ctrl+-) zoom a page in the browser, save (Ctrl+S) opens the browser's save dialog, brush, eraser, smaller and bigger brush type `be[]` into a text field, a custom shortcut (`Ctrl+A`) selects all text, "Run command" runs `notify-send`, and "Nothing" does nothing while the panel's dot still lights. Set with `set keys.N.action` and pressed on the tablet.
- **Observed (2026-10-25)**: holding a key through `hl.dsp.send_key_state` does not work. "Hold Shift/Ctrl/Alt" do not change the keys typed on the keyboard, and "Pan" (hold Space) only scrolls a browser page once, as a single Space tap; in Pinta, Space plus a pen drag pans neither with the keyboard's Space nor with the express key. Cause, from the Hyprland 0.56.2 source: `Actions::pass` (`src/config/shared/actions/ConfigActions.cpp`) sends the modifiers, then the key, then resets the modifiers to none, so nothing stays held for other input. Shortcuts that carry their modifiers in one call (Ctrl+Z, Ctrl+S) work. Holding a key needs a virtual keyboard.
- **Not reproduced**: 90° and 270° rotation and the vendor's pressure curve (both need a uinput proxy for the pen), pen button remapping and per-application profiles.
