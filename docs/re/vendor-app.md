# The vendor settings app (`gaomontablet`)

Inventory of every feature in GAOMON's Qt settings app, and where each one stands in this plugin. Sources:

- **Observed**: the QML page and control names in the app's Qt resources (`strings -eb gaomontablet | grep -E '\.(qml|js)$'`), the identifiers in the compiled QML units (`strings -el gaomontablet`), and the English UI strings in `res/Lang.json`. The QML ships compiled, so behaviour comes from names and strings, not from source.
- **Not covered**: the app is shared by every GAOMON model. Pages for hardware the S620 lacks (dial, touch strip, touch, wheel, wireless pen) are listed once at the end.

Status: ✅ in the plugin · 🟡 feasible on Hyprland, not built yet · 🔴 needs a pen proxy over uinput (rotate/rewrite the pen before libinput) · ⚪ does not apply on Linux/Omarchy.

## Tablet page

| Vendor feature | Evidence | Status |
|---|---|---|
| Map to one screen or all screens | `workArea_allscreen_btn`, "All screens", "Switch Screen" | ✅ all, focused, or one monitor |
| Full area / screen ratio | "Full Area", "Screen Ratio", `initWorkAreaBorderRaitoEqueToScreenRaito` | ✅ "Full area" / "Match screen" |
| Custom work area (drag the edges) | "Define the Workspace", `HnAdjustRect`, `setCurrentScreenBorderRatioU/D/L/R` | ✅ "Custom" area drawn in the panel, kept at the screen's ratio |
| Rotation 0°/90°/180°/270° | "Rotate Left", "Rotate Right", `setDevRotate` | ✅ 0° and 180°; 🔴 90° and 270° |
| Express keys on/off | "Enable Express Keys" | ✅ panel switch and `keys on|off` IPC |
| Show the key functions on screen | "Show/Hide Functions of Express Keys", `HnKey_ShowEKeyValue` | ✅ "Show key functions" sends a notification listing the four keys |
| Per-application settings | `HnAppList`, "All Programs", "Add Application" (X11-only in `huionCore`: `xdotool getwindowfocus`) | 🟡 Hyprland's active window class |

## Express key and pen button actions

The same action list serves the four express keys and the two pen buttons (`Key_fun_tab` … `QuickMenu_fun_tab`, `HnKey_*`).

| Vendor action | Evidence | Express keys | Pen buttons |
|---|---|---|---|
| None | `HnKey_None` | ✅ | 🔴 |
| Keystroke (any combination, named) | `HnKey_Btn`, "Enter the Keystroke", "Enter a name for the keystroke" | ✅ presets + custom | 🔴 |
| Hold a key down (pan, Shift, Ctrl, Alt) | `HnMouseKeyboard::keyboardDown/Up` | 🟡 needs a virtual keyboard | 🔴 |
| Run a program | `HnKey_Exec`, "Launch the Program" | ✅ command | 🔴 |
| Mouse left/right/middle/double click | `HnKey_MouseLeft/Right/Mid/DbClick` | 🟡 needs a virtual pointer | 🔴 |
| Wheel forward/backward | `HnKey_MouseWheelForward/BackWark` | 🟡 | 🔴 |
| Hold and drag to scroll | `HnKey_Move_Roll`, "Scroll Up/Down" | 🔴 | 🔴 |
| Media: play/pause, previous/next, volume, mute | `Media_fun_tab`, "Pause/Play", "Volume Up" | ✅ play/pause, next/previous, volume up/down, mute presets | 🔴 |
| System: lock, sleep, power off | `HnKey_RRivateCmd`, "Lock the Screen", "Sleep", "Power Off" | ✅ lock screen and suspend presets | 🔴 |
| Switch screen | `HnKey_SwitchDisPlay` | ✅ "Next monitor" cycles the mapped monitor | 🔴 |
| Switch pen/mouse mode | `HnKey_SwitchAbsolutemode` | ✅ "Toggle pen/mouse" flips `relative_input` | 🔴 |
| Switch brush/eraser | `HnKey_SwitchBrush` | ✅ app shortcut (E) | 🔴 |
| Fine (precision) mode | `HnKey_FineModel`, `onShowFineModel` | 🟡 temporary smaller area | 🔴 |
| Fixed pressure | `HnKey_FixedPressure` | 🔴 | 🔴 |
| Radial/quick menu | `HnKey_RadialMenu`, `QuickMenu_fun_tab` | 🟡 open the Omarchy menu | 🔴 |
| Game mode | `HnKey_SwitchGame`, `pen_gamemode_check` | ⚪ Windows Ink | ⚪ |

Pen buttons reach applications as stylus buttons 1 and 2 (`findings.md`); Hyprland can only turn one into an eraser (`input.tablettool.eraser_button_*`). Any other action needs the proxy.

## Pen page

| Vendor feature | Evidence | Status |
|---|---|---|
| Pressure curve: 5 presets (very soft … very hard) and draggable points | `pressure_ssoft/soft/def/hard/hhard_btn`, "Drag the points to adjust the pen sensitivity", `bezierCurveTo` | 🔴 libinput only has a range |
| Force to reach maximum pressure | "The force to reach maxmium pressure", `HnPressurePowerSlider`, `setMaxPressurePower` | ✅ "Full pressure at" (applies after replugging) |
| Pressure test | "Pressure Test", `HnPressureTest`, `HnPressureBar` | ✅ live value and stroke peak |
| Reset pressure | `pressure_reset_btn` | ✅ "Restore defaults" |
| Pen buttons only while the nib touches ("Contact click") | `pen_nib_touch_switch`, `penKeyEnableWhenNibTouch` | 🔴 |
| Mouse mode and its speed | `pen_mousemode_check`, `mouse_speed_list` | ✅ mode; 🟡 speed, untested on Hyprland |
| Disable the nib | "Disable Nib", `pen_nib_combox` | 🔴 |

## Settings

| Vendor feature | Evidence | Status |
|---|---|---|
| Back up / import settings | `Backup.qml`, `exportCfg`, `string_importConfig` | 🟡 the profile is one JSON file |
| Factory reset | "Factory Reset", "Restore Defaults" | ✅ |
| Firmware version, device info | `ThisDevice.qml`, "Firmware Version" | ✅ firmware version under the connection status, read from sysfs (`uniq`) |
| Autostart, language, updates, account, experience program | `General.qml`, `About.qml`, "Sign in" | ⚪ Omarchy shell handles startup |

## Not for the S620

Dial and wheel (`mux_*_fun_tab`, `HnKeyDialCombox`), touch gestures ("Tap with two fingers" …), touch strip and soft keys, Windows Ink and Windows Radial, wireless pen calibration (`HnWirelessPenCalibrationQtWindow`), pen displays (screen calibration).
