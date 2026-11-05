import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "GaomonS620Model"

  function line(object) { return JSON.stringify(object) }

  // `hyprctl monitors -j` on 2026-10-24, trimmed to the fields used.
  readonly property string laptop: JSON.stringify([
    { name: "eDP-2", width: 1920, height: 1200, scale: 1.25, transform: 0, x: 0, y: 0, focused: true }
  ])

  function test_connection_follows_the_helper() {
    var s = Model.applyLine(null, line({ ok: true, event: "connected", device: "/dev/input/event23" }))
    compare(s, { connection: "ready" })
    compare(Model.statusText(s), "connected")
    compare(Model.tabletPresent(s), true)
    compare(Model.barView(s).dimmed, false)
    compare(Model.tooltip(s), "GAOMON S620 · connected")
    var key = Model.applyLine(s, line({ ok: true, event: "key", code: 256, pressed: true }))
    compare(key, s)
    var gone = Model.applyLine(s, line({ ok: false, error: "missing" }))
    compare(gone.connection, "missing")
    compare(Model.tabletPresent(gone), false)
    compare(Model.barView(gone).dimmed, true)
    // Without the udev rule the pad is found but unreadable: still plugged in.
    compare(Model.tabletPresent(Model.applyLine(s, line({ ok: false, error: "access-denied" }))), true)
  }

  // Firmware as hid-uclogic reported it on 2026-10-24 (docs/re/findings.md).
  function test_firmware_shows_while_the_tablet_is_present() {
    var s = Model.applyLine(null, line({ ok: true, event: "connected", device: "/dev/input/event23", firmware: "OEM02_T18e_200919" }))
    compare(Model.firmwareText(s), "Firmware OEM02_T18e_200919")
    var key = Model.applyLine(s, line({ ok: true, event: "key", code: 256, pressed: true }))
    compare(Model.firmwareText(key), "Firmware OEM02_T18e_200919")
    var denied = Model.applyLine(s, line({ ok: false, error: "access-denied", firmware: "OEM02_T18e_200919" }))
    compare(Model.firmwareText(denied), "Firmware OEM02_T18e_200919")
    compare(Model.firmwareText(Model.applyLine(s, line({ ok: false, error: "missing" }))), "")
    compare(Model.firmwareText(Model.applyLine(null, line({ ok: true, event: "connected", device: "/dev/input/event23" }))), "")
    compare(Model.firmwareText(Model.applyLine(null, line({ ok: true, event: "connected", firmware: 42 }))), "")
    compare(Model.firmwareText(null), "")
  }

  function test_every_error_has_a_notice() {
    var codes = ["missing", "access-denied", "nonsense"]
    for (var i = 0; i < codes.length; i++) {
      var s = Model.applyLine(null, line({ ok: false, error: codes[i] }))
      verify(Model.tooltip(s).indexOf("undefined") === -1, codes[i])
    }
    compare(Model.applyLine(null, "not json").connection, "error")
    compare(Model.tooltip(null), "GAOMON S620 · looking for the tablet")
  }

  function test_key_events_map_btn_codes_to_the_four_keys() {
    compare(Model.keyEvent(line({ ok: true, event: "key", code: 256, pressed: true })), { index: 0, pressed: true })
    compare(Model.keyEvent(line({ ok: true, event: "key", code: 259, pressed: false })), { index: 3, pressed: false })
    compare(Model.keyEvent(line({ ok: true, event: "key", code: 260, pressed: true })), null)
    compare(Model.keyEvent(line({ ok: true, event: "connected" })), null)
  }

  function test_profile_is_normalized() {
    var p = Model.normalizeProfile({ rotation: 9, pressureMin: -4, pressureMax: 20, output: "x\"); os.exit()", keys: [{ action: "bogus" }] })
    compare(p.rotation, 0)
    compare(Model.normalizeProfile({ rotation: 1 }).rotation, 0)
    compare(Model.normalizeProfile({ rotation: 2 }).rotation, 2)
    compare(p.pressureMin, 0)
    compare(p.pressureMax, 20)
    compare(p.output, "")
    compare(p.keys.length, 4)
    compare(p.keys[0].action, "undo")
    compare(Model.normalizeProfile(null), Model.normalizeProfile(Model.DEFAULTS))
  }

  function test_pressure_range_reaches_a_light_touch() {
    compare(Model.normalizeProfile({ pressureMax: 5 }).pressureMax, 10)
    compare(Model.normalizeProfile({ pressureMax: 10 }).pressureMax, 10)
    // The threshold always stays below full pressure.
    var p = Model.normalizeProfile({ pressureMin: 40, pressureMax: 20 })
    compare([p.pressureMin, p.pressureMax], [15, 20])
  }

  function test_express_keys_can_be_switched_off() {
    compare(Model.normalizeProfile(null).keysEnabled, true)
    compare(Model.withValue(null, "keysEnabled", false).keysEnabled, false)
  }

  function test_with_value_changes_one_field() {
    var p = Model.withValue(null, "keys.2.action", "shortcut")
    p = Model.withValue(p, "keys.2.text", "Ctrl+K")
    compare(p.keys[2], { action: "shortcut", text: "Ctrl+K" })
    compare(Model.withValue(p, "rotation", 2).rotation, 2)
    compare(Model.withValue(p, "keys", []).keys.length, 4)
  }

  function test_monitors_use_logical_sizes() {
    compare(Model.parseMonitors(laptop), [{ name: "eDP-2", x: 0, y: 0, width: 1536, height: 960, focused: true }])
    var turned = Model.parseMonitors(JSON.stringify([{ name: "DP-1", width: 1920, height: 1080, scale: 1, transform: 1, x: 0, y: 0 }]))
    compare([turned[0].width, turned[0].height], [1080, 1920])
    compare(Model.parseMonitors("nope"), [])
  }

  function test_full_area_is_the_default() {
    compare(Model.activeArea(null, Model.parseMonitors(laptop)), null)
    compare(Model.areaNote(null), "The whole 165 × 102 mm area is active.")
    compare(Model.areaNote({ width: 162.6, height: 101.6, x: 1.3, y: 0 }), "Active area 162.6 × 101.6 mm, centred.")
  }

  function test_empty_keys_has_one_slot_per_key() {
    compare(Model.emptyKeys(), [null, null, null, null])
    compare(Model.parseJson("{\"a\": 1}"), { a: 1 })
    compare(Model.parseJson("nope"), null)
  }

  function test_match_screen_crops_the_long_side() {
    // 16:10 screen on a 165.1 x 101.6 mm (1.625) tablet: the width shrinks.
    var area = Model.activeArea({ area: "ratio" }, Model.parseMonitors(laptop))
    compare(area, { width: 162.6, height: 101.6, x: 1.3, y: 0 })
    compare(Model.activeArea({ area: "ratio", rotation: 2 }, Model.parseMonitors(laptop)), area)
    compare(Model.activeArea({ area: "ratio", relative: true }, Model.parseMonitors(laptop)), null)
  }

  function test_device_lua() {
    compare(Model.deviceLua({ output: "eDP-2", rotation: 2, pressureMax: 80 }, []),
      "hl.device({ name = \"gaomon-gaomon-tablet-pen\", output = \"eDP-2\", left_handed = true, relative_input = false"
      + ", active_area_size = { 165.1, 101.6 }, active_area_position = { 0, 0 } })\n"
      + "hl.config({ input = { tablettool = { pressure_range_min = 0, pressure_range_max = 0.8 } } })")
  }

  function test_shortcuts_are_parsed_strictly() {
    compare(Model.parseShortcut("Ctrl+Shift+z"), { mods: "CTRL SHIFT", key: "Z" })
    compare(Model.parseShortcut("SUPER space"), { mods: "SUPER", key: "space" })
    compare(Model.parseShortcut("F5"), { mods: "", key: "F5" })
    compare(Model.parseShortcut("Hyper+Z"), null)
    compare(Model.parseShortcut("Ctrl+\"x"), null)
    compare(Model.parseShortcut(""), null)
  }

  function test_key_commands() {
    compare(Model.keyCommands({ action: "undo", text: "" }, true), [{ detached: false, argv: ["hyprctl", "eval",
      "hl.dispatch(hl.dsp.send_key_state({ mods = \"CTRL\", key = \"Z\", state = \"down\" }))"] }])
    compare(Model.keyCommands({ action: "brush", text: "" }, false), [{ detached: false, argv: ["hyprctl", "eval",
      "hl.dispatch(hl.dsp.send_key_state({ mods = \"\", key = \"B\", state = \"up\" }))"] }])
    compare(Model.keyCommands({ action: "command", text: "omarchy launch browser" }, true),
      [{ detached: true, argv: ["bash", "-lc", "omarchy launch browser"] }])
    compare(Model.keyCommands({ action: "command", text: "omarchy launch browser" }, false), [])
    compare(Model.keyCommands({ action: "shortcut", text: "not a shortcut!" }, true), [])
    compare(Model.keyCommands({ action: "none", text: "" }, true), [])
  }

  function test_hold_actions_are_gone() {
    var values = Model.ACTIONS.map(function(a) { return a.value })
    var removed = ["pan", "shift", "ctrl", "alt"]
    for (var i = 0; i < removed.length; i++) verify(values.indexOf(removed[i]) === -1, removed[i])
    // A profile that still uses one falls back to the key's default.
    var p = Model.normalizeProfile({ keys: [{ action: "pan" }, { action: "shift" }, { action: "ctrl" }, { action: "alt" }] })
    compare(p.keys[0].action, "undo")
    compare(p.keys[1].action, "redo")
    compare(p.keys[2].action, "eraser")
    compare(p.keys[3].action, "showKeys")
    compare(Model.normalizeProfile(null).keys[3].action, "showKeys")
  }

  function test_media_and_system_presets_run_once_per_press() {
    var presets = {
      playPause: ["omarchy-shell", "media", "playPause"],
      nextTrack: ["omarchy-shell", "media", "next"],
      previousTrack: ["omarchy-shell", "media", "previous"],
      volumeUp: ["omarchy-audio-output-volume", "raise"],
      volumeDown: ["omarchy-audio-output-volume", "lower"],
      mute: ["omarchy-audio-output-volume", "mute-toggle"],
      lock: ["omarchy-system-lock"],
      suspend: ["systemctl", "suspend"]
    }
    for (var value in presets) {
      compare(Model.keyCommands({ action: value, text: "" }, true),
        [{ detached: true, argv: presets[value] }], value)
      compare(Model.keyCommands({ action: value, text: "" }, false), [], value)
      var key = Model.normalizeProfile({ keys: [{ action: value }] }).keys[0]
      compare(key.action, value, value)
      verify(Model.actionFor(value).label !== "", value)
    }
  }

  // Omarchy's notification card shows at most three body lines
  // (NotificationCard.qml, maximumLineCount: 3), so the keys go two per line.
  function test_show_key_functions_sends_one_notification() {
    var p = Model.withValue(null, "keys.3.action", "showKeys")
    compare(Model.keyCommands(p.keys[3], true, p.keys), [{ detached: true, argv:
      ["omarchy-notification-send", "-g", "󰽉", "GAOMON S620 express keys",
       "1 Undo · 2 Redo\n3 Eraser (E) · 4 Show key functions"] }])
    compare(Model.keyCommands(p.keys[3], false, p.keys), [])
  }

  function test_show_key_functions_lists_custom_labels() {
    var p = Model.withValue(null, "keys.3.action", "showKeys")
    p = Model.withValue(p, "keys.0.action", "shortcut")
    p = Model.withValue(p, "keys.0.text", "Ctrl+K")
    p = Model.withValue(p, "keys.1.action", "command")
    p = Model.withValue(p, "keys.1.text", "omarchy launch browser --new-window")
    p = Model.withValue(p, "keys.2.action", "none")
    compare(Model.keyCommands(p.keys[3], true, p.keys), [{ detached: true, argv:
      ["omarchy-notification-send", "-g", "󰽉", "GAOMON S620 express keys",
       "1 Ctrl+K · 2 omarchy launch browse…\n3 Nothing · 4 Show key functions"] }])
  }

  function test_show_key_functions_survives_normalize() {
    compare(Model.normalizeProfile({ keys: [{ action: "showKeys" }] }).keys[0].action, "showKeys")
    var p = Model.withValue(null, "keys.2.action", "showKeys")
    compare(p.keys[2].action, "showKeys")
    compare(Model.keyLabel(p.keys[2]), "Show key functions")
  }

  function test_pressure_changes_are_spotted() {
    compare(Model.pressureChanged(null, { pressureMax: 80 }), true)
    compare(Model.pressureChanged(null, { rotation: 2 }), false)
  }

  function test_lua_strings_are_escaped() {
    compare(Model.luaString("a\"b\\c\nd"), "\"a\\\"b\\\\c\\nd\"")
  }

  // Monitors shaped like parseMonitors output.
  readonly property var twoMonitors: [
    { name: "eDP-2", x: 0, y: 0, width: 1920, height: 1200, focused: true },
    { name: "DP-1", x: 1920, y: 0, width: 2560, height: 1440, focused: false }
  ]
  readonly property var threeMonitors: [
    { name: "eDP-2", x: 0, y: 0, width: 1920, height: 1200, focused: false },
    { name: "DP-1", x: 1920, y: 0, width: 2560, height: 1440, focused: true },
    { name: "HDMI-A-1", x: 4480, y: 0, width: 1920, height: 1080, focused: false }
  ]

  function test_next_monitor_cycles_through_each_connected_monitor() {
    var switchKey = { action: "switchMonitor", text: "" }
    var p = Model.keyProfile(switchKey, { output: "eDP-2" }, twoMonitors)
    compare(p.output, "DP-1")
    compare(Model.keyProfile(switchKey, p, twoMonitors).output, "eDP-2")
    p = Model.keyProfile(switchKey, { output: "eDP-2" }, threeMonitors)
    compare(p.output, "DP-1")
    p = Model.keyProfile(switchKey, p, threeMonitors)
    compare(p.output, "HDMI-A-1")
    compare(Model.keyProfile(switchKey, p, threeMonitors).output, "eDP-2")
  }

  function test_next_monitor_starts_at_the_first_from_all_or_unknown() {
    var switchKey = { action: "switchMonitor", text: "" }
    compare(Model.keyProfile(switchKey, { output: "" }, threeMonitors).output, "eDP-2")
    compare(Model.keyProfile(switchKey, { output: "DP-9" }, threeMonitors).output, "eDP-2")
  }

  function test_next_monitor_after_the_focused_one_moves_off_that_screen() {
    var switchKey = { action: "switchMonitor", text: "" }
    compare(Model.keyProfile(switchKey, { output: "current" }, threeMonitors).output, "HDMI-A-1")
    compare(Model.keyProfile(switchKey, { output: "current" }, twoMonitors).output, "DP-1")
  }

  function test_next_monitor_edge_cases() {
    var switchKey = { action: "switchMonitor", text: "" }
    var one = [{ name: "eDP-2", x: 0, y: 0, width: 1920, height: 1200, focused: true }]
    compare(Model.keyProfile(switchKey, { output: "" }, one).output, "eDP-2")
    compare(Model.keyProfile(switchKey, { output: "eDP-2" }, one).output, "eDP-2")
    compare(Model.keyProfile(switchKey, { output: "eDP-2" }, []), null)
  }

  function test_toggle_pen_mouse_flips_relative_both_ways() {
    var toggleKey = { action: "togglePenMouse", text: "" }
    var p = Model.keyProfile(toggleKey, { relative: false }, twoMonitors)
    compare(p.relative, true)
    compare(Model.keyProfile(toggleKey, p, twoMonitors).relative, false)
  }

  function test_profile_keys_send_no_commands() {
    compare(Model.keyCommands({ action: "switchMonitor", text: "" }, true), [])
    compare(Model.keyCommands({ action: "switchMonitor", text: "" }, false), [])
    compare(Model.keyCommands({ action: "togglePenMouse", text: "" }, true), [])
    compare(Model.keyProfile({ action: "undo", text: "" }, {}, twoMonitors), null)
    compare(Model.keyProfile({ action: "none", text: "" }, {}, twoMonitors), null)
    compare(Model.keyProfile({ action: "command", text: "x" }, {}, twoMonitors), null)
  }

  // An action the backend cannot do leaves the choices on that backend, and
  // a key still bound to it (a profile saved on the kernel backend) does
  // nothing instead of toggling a field OTD never applies.
  function test_actions_the_backend_cannot_do_are_filtered() {
    var kernel = Model.actionsFor("kernel").map(function(a) { return a.value })
    var otd = Model.actionsFor("otd").map(function(a) { return a.value })
    verify(kernel.indexOf("togglePenMouse") >= 0)
    verify(otd.indexOf("togglePenMouse") === -1)
    compare(otd.length, kernel.length - 1)
    compare(Model.keyProfile({ action: "togglePenMouse", text: "" }, { relative: false }, twoMonitors, "otd"), null)
    compare(Model.keyProfile({ action: "togglePenMouse", text: "" }, { relative: false }, twoMonitors).relative, true)
    // Actions that do work keep working on OTD.
    compare(Model.keyProfile({ action: "switchMonitor", text: "" }, { output: "eDP-2" }, twoMonitors, "otd").output, "DP-1")
  }

  function test_profile_keys_survive_normalize() {
    compare(Model.normalizeProfile({ keys: [{ action: "switchMonitor" }] }).keys[0].action, "switchMonitor")
    compare(Model.normalizeProfile({ keys: [{ action: "togglePenMouse" }] }).keys[0].action, "togglePenMouse")
    var p = Model.withValue(null, "keys.1.action", "togglePenMouse")
    compare(p.keys[1].action, "togglePenMouse")
    compare(Model.keyLabel({ action: "switchMonitor", text: "" }), "Next monitor")
    compare(Model.keyLabel({ action: "togglePenMouse", text: "" }), "Toggle pen/mouse")
  }

  // ---------- Custom working area ----------

  readonly property var monitor169: [{ name: "DP-9", x: 0, y: 0, width: 1920, height: 1080, focused: true }]

  function test_custom_area_is_a_third_choice() {
    compare(Model.AREAS.map(function(a) { return a.value }), ["full", "ratio", "custom"])
    compare(Model.normalizeProfile({ area: "custom" }).area, "custom")
    compare(Model.normalizeProfile({ area: "bogus" }).area, "full")
  }

  // The default is three quarters of the "Match screen" rectangle, centred:
  // on a 16:10 screen the match rect is 162.56 x 101.6 mm, so 121.9 x 76.2 mm.
  // customArea stays unset until the user draws, so the default is computed
  // with whatever monitors are known where the area is used.
  function test_custom_area_defaults_to_three_quarters_of_the_screen() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ area: "custom" }, mons)
    compare(p.customArea, null)
    compare(Model.customRect(p, mons), { width: 121.9, height: 76.2, x: 21.6, y: 12.7 })
    // On 16:9 the match rect is the whole width, so the default is wider.
    compare(Model.customRect(Model.normalizeProfile({ area: "custom" }, monitor169), monitor169),
      { width: 123.8, height: 69.6, x: 20.7, y: 16 })
    // No monitors: the tablet ratio stands in.
    compare(Model.customRect(Model.normalizeProfile({ area: "custom" }), []),
      { width: 123.8, height: 76.2, x: 20.7, y: 12.7 })
  }

  // A stored area keeps its width and centre when the mapped output
  // changes; the height follows the new ratio (121.9 / 1.7778 = 68.6 mm).
  function test_custom_area_keeps_the_mapped_ratio() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ area: "custom",
      customArea: { width: 121.9, height: 76.2, centerX: 82.6, centerY: 50.8 } }, mons)
    compare(Model.customRect(p, monitor169), { width: 121.9, height: 68.6, x: 21.6, y: 16.5 })
  }

  // Switching the output through withValue (the ChoiceRow path) re-fits the
  // stored area to the new screen's ratio.
  function test_custom_area_follows_an_output_change() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ area: "custom", output: "eDP-2",
      customArea: { width: 80, height: 50, centerX: 82.6, centerY: 50.8 } }, mons)
    compare(Model.customRect(p, mons), { width: 80, height: 50, x: 42.6, y: 25.8 })
    var switched = Model.withValue(p, "output", "DP-9", monitor169)
    compare(switched.output, "DP-9")
    compare(Model.customRect(switched, monitor169), { width: 80, height: 45, x: 42.6, y: 28.3 })
  }

  function test_custom_area_stays_inside_the_tablet() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ area: "custom",
      customArea: { width: 80, height: 50, centerX: 5, centerY: 200 } }, mons)
    // Centre pushed left and down: x clamps to 0, y to 101.6 - 50.
    compare(Model.customRect(p, mons), { width: 80, height: 50, x: 0, y: 51.6 })
    // A width that only fits when shrunk: height would pass the tablet.
    var wide = Model.normalizeProfile({ area: "custom",
      customArea: { width: 300, height: 50, centerX: 82.6, centerY: 50.8 } }, mons)
    compare(Model.customRect(wide, mons), { width: 162.6, height: 101.6, x: 1.3, y: 0 })
  }

  function test_move_custom_area_clamps_at_the_edges() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ area: "custom",
      customArea: { width: 80, height: 50, centerX: 82.6, centerY: 50.8 } }, mons)
    var moved = Model.moveCustomArea(p, 200, -200, mons)
    compare(Model.customRect(moved, mons), { width: 80, height: 50, x: 85.1, y: 0 })
    // The stored centre is the rect's centre: 85.1 + 40, 0 + 25.
    compare(moved.customArea, { width: 80, height: 50, centerX: 125.1, centerY: 25 })
    compare(Model.moveCustomArea(p, 0, 0, mons).customArea, p.customArea)
  }

  // A corner drag is anchored at the opposite corner, which does not move.
  function test_resize_custom_area_keeps_the_ratio_and_the_anchor() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ area: "custom",
      customArea: { width: 80, height: 50, centerX: 82.6, centerY: 50.8 } }, mons)
    var min = Model.resizeCustomArea(p, 10, "se", mons)
    compare(Model.customRect(min, mons), { width: 30, height: 18.8, x: 42.6, y: 25.8 })
    // Growing past the edge facing the drag stops there; the anchor does
    // not move (165.1 - 42.6 and (101.6 - 25.8) * 1.6 cap the width).
    var max = Model.resizeCustomArea(p, 200, "se", mons)
    compare(Model.customRect(max, mons), { width: 121.3, height: 75.8, x: 42.7, y: 25.8 })
    // Top-left drag keeps the bottom-right corner (42.6 + 80, 25.8 + 50).
    var nw = Model.resizeCustomArea(p, 60, "nw", mons)
    compare(Model.customRect(nw, mons), { width: 60, height: 37.5, x: 62.6, y: 38.4 })
    // The same gesture takes the pointer in millimetres: (30, 30) against
    // the bottom-right anchor (122.6, 75.8) gives width 92.6.
    var at = Model.resizeCustomAreaAt(p, 30, 30, "nw", mons)
    compare(Model.customRect(at, mons), { width: 92.6, height: 57.9, x: 30, y: 17.9 })
  }

  function test_old_profiles_and_bad_values_load() {
    // No customArea field: normalized like before, the default applies
    // where the area is used.
    var old = Model.normalizeProfile({ area: "ratio", pressureMax: 80 })
    compare([old.area, old.pressureMax], ["ratio", 80])
    compare(old.customArea, null)
    // Bad customArea values fall back to the default, null included:
    // Number(null) is 0, so a plain isFinite would accept it.
    var bad = Model.normalizeProfile({ area: "custom", customArea: { width: "x", centerX: 40 } })
    compare(bad.customArea, null)
    compare(Model.normalizeProfile({ area: "custom",
      customArea: { width: null, height: null, centerX: null, centerY: null } }).customArea, null)
    compare(Model.customRect(bad, []), { width: 123.8, height: 76.2, x: 20.7, y: 12.7 })
    // Numbers round to 0.1 mm and survive a second normalization (load path).
    var p = Model.normalizeProfile({ area: "custom",
      customArea: { width: 80.04, height: 50, centerX: 82.55, centerY: 50.8 } })
    compare(p.customArea.width, 80)
    compare(Model.normalizeProfile(p).customArea, p.customArea)
    // Setting "custom" through withValue keeps the saved area.
    compare(Model.withValue(p, "rotation", 2).customArea, p.customArea)
  }

  function test_custom_area_reaches_hyprland() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ area: "custom" }, mons)
    compare(Model.activeArea(p, mons), { width: 121.9, height: 76.2, x: 21.6, y: 12.7 })
    compare(Model.activeArea({ area: "custom", relative: true }, mons), null)
    var lua = Model.deviceLua(p, mons)
    verify(lua.indexOf("active_area_size = { 121.9, 76.2 }") >= 0, lua)
    verify(lua.indexOf("active_area_position = { 21.6, 12.7 }") >= 0, lua)
    // Custom areas are not described as centred.
    compare(Model.areaNote(Model.activeArea(p, mons), false), "Active area 121.9 × 76.2 mm.")
  }

  // ---------- Backend ----------

  function test_backend_comes_from_the_helper_line() {
    var k = Model.applyLine(null, line({ ok: true, event: "connected", device: "/dev/input/event23", backend: "kernel" }))
    compare(k.backend, "kernel")
    compare(Model.statusText(k), "connected · Kernel driver")
    compare(Model.backendOf(k), "kernel")
    var o = Model.applyLine(null, line({ ok: true, event: "connected", backend: "otd" }))
    compare(o.backend, "otd")
    compare(Model.statusText(o), "connected · OpenTabletDriver")
    compare(Model.backendOf(o), "otd")
    // No backend field (older helper, errors) reads as the kernel default.
    compare(Model.backendOf(null), "kernel")
    compare(Model.backendOf(Model.applyLine(null, line({ ok: false, error: "missing" }))), "kernel")
    compare(Model.statusText(Model.applyLine(null, line({ ok: true, event: "connected", device: "/dev/input/event23" }))), "connected")
  }

  function test_no_driver_has_a_notice() {
    var s = Model.applyLine(null, line({ ok: false, error: "no-driver" }))
    compare(s.connection, "no-driver")
    compare(Model.statusText(s), "no driver owns the tablet")
    compare(Model.tabletPresent(s), false)
    compare(Model.tooltip(s), "GAOMON S620 · no driver owns the tablet")
  }

  function test_firmware_stays_hidden_on_the_otd_backend() {
    var o = Model.applyLine(null, line({ ok: true, event: "connected", backend: "otd", firmware: "x" }))
    compare(Model.firmwareText(o), "")
  }

  // ---------- The OTD settings document ----------

  // Shaped like ~/.config/OpenTabletDriver/settings.json (OTD 0.6.7): X/Y
  // are the rectangle's centre.
  readonly property var otdBase: ({
    Profiles: [
      { Tablet: "Gaomon S620",
        OutputMode: { Path: "OpenTabletDriver.Desktop.Output.LinuxArtistMode" },
        AbsoluteModeSettings: {
          Display: { Width: 1536, Height: 960, X: 768, Y: 480, Rotation: 0 },
          Tablet: { Width: 165.1, Height: 101.6, X: 82.55, Y: 50.8, Rotation: 0 }
        },
        Bindings: { keep: "untouched" } },
      { Tablet: "Huion Other",
        OutputMode: { Path: "Other.Mode" },
        AbsoluteModeSettings: { Display: { Width: 1 } } }
    ],
    Other: { keep: true }
  })

  function otdProfile(plan) {
    for (var i = 0; i < plan.document.Profiles.length; i++)
      if (plan.document.Profiles[i].Tablet === "Gaomon S620") return plan.document.Profiles[i]
    return null
  }

  function test_the_kernel_plan_is_the_lua_as_today() {
    var mons = Model.parseMonitors(laptop)
    var p = Model.normalizeProfile({ output: "eDP-2", rotation: 2 }, mons)
    compare(Model.applyPlan(p, mons, "kernel", null), { backend: "kernel", lua: Model.deviceLua(p, mons) })
    compare(Model.applyPlan(p, mons, "anything", null).backend, "kernel")
  }

  function test_the_otd_plan_patches_only_the_s620_profile() {
    var mons = Model.parseMonitors(laptop)
    var plan = Model.applyPlan(null, mons, "otd", otdBase)
    compare(plan.backend, "otd")
    compare(plan.changed, true)
    compare(plan.note, "")
    var prof = otdProfile(plan)
    compare(prof.OutputMode.Path, "OpenTabletDriver.Desktop.Output.LinuxArtistMode")
    compare(prof.AbsoluteModeSettings.Display, { Width: 1536, Height: 960, X: 768, Y: 480, Rotation: 0 })
    compare(prof.AbsoluteModeSettings.Tablet, { Width: 165.1, Height: 101.6, X: 82.55, Y: 50.8, Rotation: 0 })
    compare(prof.Bindings.keep, "untouched")
    compare(prof.Bindings.AuxButtons.length, 4)
    compare(plan.document.Profiles[1], otdBase.Profiles[1])
    compare(plan.document.Other, { keep: true })
    // The document passed in is not mutated.
    compare(otdBase.Profiles[0].AbsoluteModeSettings.Tablet.X, 82.55)
  }

  function test_the_otd_plan_reads_a_json_string_too() {
    var mons = Model.parseMonitors(laptop)
    var plan = Model.applyPlan(null, mons, "otd", JSON.stringify(otdBase))
    compare(plan.changed, true)
  }

  function test_the_otd_plan_maps_the_output_rectangle() {
    // twoMonitors: eDP-2 1920x1200 focused at 0,0; DP-1 2560x1440 at 1920,0.
    var all = Model.applyPlan(null, twoMonitors, "otd", otdBase)
    compare(otdProfile(all).AbsoluteModeSettings.Display, { Width: 4480, Height: 1440, X: 2240, Y: 720, Rotation: 0 })
    var named = Model.applyPlan({ output: "DP-1" }, twoMonitors, "otd", otdBase)
    compare(otdProfile(named).AbsoluteModeSettings.Display, { Width: 2560, Height: 1440, X: 3200, Y: 720, Rotation: 0 })
    var focused = Model.applyPlan({ output: "current" }, twoMonitors, "otd", otdBase)
    compare(otdProfile(focused).AbsoluteModeSettings.Display, { Width: 1920, Height: 1200, X: 960, Y: 600, Rotation: 0 })
    // An output nothing matches leaves the document's display alone.
    var gone = Model.applyPlan({ output: "DP-9" }, twoMonitors, "otd", otdBase)
    compare(otdProfile(gone).AbsoluteModeSettings.Display, otdBase.Profiles[0].AbsoluteModeSettings.Display)
  }

  function test_the_otd_plan_uses_the_active_area() {
    var mons = Model.parseMonitors(laptop)
    var ratio = Model.applyPlan({ area: "ratio" }, mons, "otd", otdBase)
    compare(otdProfile(ratio).AbsoluteModeSettings.Tablet, { Width: 162.6, Height: 101.6, X: 82.6, Y: 50.8, Rotation: 0 })
  }

  function test_the_otd_plan_turns_180_and_mirrors_the_custom_centre() {
    var mons = Model.parseMonitors(laptop)
    var p = { rotation: 2, area: "custom",
      customArea: { width: 80, height: 50, centerX: 40, centerY: 30 } }
    var plan = Model.applyPlan(p, mons, "otd", otdBase)
    // As held the rect sits at x 0..80, y 5..55 (centre 40,30); in the raw
    // frame that is centre 125.1, 71.6.
    compare(otdProfile(plan).AbsoluteModeSettings.Tablet, { Width: 80, Height: 50, X: 125.1, Y: 71.6, Rotation: 180 })
    compare(otdProfile(plan).AbsoluteModeSettings.Display.Rotation, 0)
    // A centred area is its own mirror.
    var full = Model.applyPlan({ rotation: 2 }, mons, "otd", otdBase)
    compare(otdProfile(full).AbsoluteModeSettings.Tablet, { Width: 165.1, Height: 101.6, X: 82.55, Y: 50.8, Rotation: 180 })
  }

  function test_the_otd_plan_stays_in_artist_mode_in_relative() {
    var mons = Model.parseMonitors(laptop)
    var plan = Model.applyPlan({ relative: true }, mons, "otd", otdBase)
    compare(otdProfile(plan).OutputMode.Path, "OpenTabletDriver.Desktop.Output.LinuxArtistMode")
    compare(otdProfile(plan).AbsoluteModeSettings.Tablet.Width, 165.1)
    // `relative` is out of scope on OTD: an inherited mouse-mode profile
    // still applies its crop.
    var cropped = Model.applyPlan({ relative: true, area: "ratio" }, mons, "otd", otdBase)
    compare(otdProfile(cropped).AbsoluteModeSettings.Tablet, { Width: 162.6, Height: 101.6, X: 82.6, Y: 50.8, Rotation: 0 })
    var custom = Model.applyPlan({ relative: true, area: "custom",
      customArea: { width: 80, height: 50, centerX: 40, centerY: 30 } }, mons, "otd", otdBase)
    compare(otdProfile(custom).AbsoluteModeSettings.Tablet, { Width: 80, Height: 50, X: 40, Y: 30, Rotation: 0 })
  }

  function test_the_otd_plan_leaves_a_document_without_the_s620_profile() {
    var doc = { Profiles: [{ Tablet: "Huion Other", OutputMode: { Path: "Other" } }] }
    var plan = Model.applyPlan(null, twoMonitors, "otd", doc)
    compare(plan.changed, false)
    compare(plan.document, doc)
    verify(plan.note.indexOf("Gaomon S620") >= 0, plan.note)
    var bad = Model.applyPlan(null, twoMonitors, "otd", "not json")
    compare(bad.changed, false)
    verify(bad.note !== "")
    compare(Model.applyPlan(null, twoMonitors, "otd", {}).changed, false)
  }

  // Whether Hyprland's pressure range reaches the OTD virtual tablet is
  // still unknown (docs/re/opentabletdriver.md); until it is observed the
  // plan sends no Lua and sends nothing for the GAOMON pen.
  function test_no_hyprland_lua_goes_to_the_otd_backend() {
    compare(Model.OTD_PRESSURE_RANGE_APPLIES, false)
    var mons = Model.parseMonitors(laptop)
    var plan = Model.applyPlan({ pressureMax: 80 }, mons, "otd", otdBase)
    compare(plan.lua, null)
    verify(Model.applyPlan(null, mons, "kernel", null).lua.indexOf("pressure_range_max = 0.8") === -1)
  }

  // An access-denied on the OTD pad keeps the OTD backend: without the field
  // the state would read as the kernel default and apply Hyprland settings.
  function test_access_denied_on_otd_keeps_the_backend() {
    var s = Model.applyLine(null, line({ ok: false, error: "access-denied", backend: "otd" }))
    compare(s.connection, "access-denied")
    compare(s.backend, "otd")
    compare(Model.backendOf(s), "otd")
    compare(Model.tabletPresent(s), true)
  }

  function padButton(n) {
    return { Path: "OpenTabletDriver.Desktop.Binding.LinuxArtistMode.LinuxArtistModePadBinding",
      Settings: [{ Property: "Button", Value: "Pad Button " + n }], Enable: true }
  }

  // The plugin decides every action, so OTD binds the four express keys to
  // pad buttons 1-4 in key order and sends no keys of its own.
  function test_the_otd_plan_binds_the_four_pad_buttons() {
    var plan = Model.applyPlan(null, Model.parseMonitors(laptop), "otd", otdBase)
    var prof = otdProfile(plan)
    compare(prof.Bindings.AuxButtons, [padButton(1), padButton(2), padButton(3), padButton(4)])
    compare(prof.Bindings.keep, "untouched")
    compare(otdBase.Profiles[0].Bindings, { keep: "untouched" })
  }

  function test_the_otd_plan_replaces_aux_buttons_and_keeps_the_rest() {
    var doc = { Profiles: [{ Tablet: "Gaomon S620",
      Bindings: { AuxButtons: [{ Path: "OpenTabletDriver.Desktop.Binding.MultiKeyBinding" }],
                  PenSettings: { keep: 1 } } }] }
    var plan = Model.applyPlan(null, [], "otd", doc)
    var prof = otdProfile(plan)
    compare(prof.Bindings.AuxButtons.length, 4)
    compare(prof.Bindings.AuxButtons[2], padButton(3))
    compare(prof.Bindings.PenSettings, { keep: 1 })
  }

  function test_the_otd_plan_creates_missing_bindings() {
    var doc = { Profiles: [{ Tablet: "Gaomon S620" }] }
    var plan = Model.applyPlan(null, [], "otd", doc)
    compare(otdProfile(plan).Bindings.AuxButtons.length, 4)
  }

  // Before the first profile exists only the bindings go out: the pad shows
  // up so the keys work, and the pen settings stay as the user left them.
  function test_the_otd_plan_without_a_profile_binds_only_the_keys() {
    var doc = { Profiles: [{ Tablet: "Gaomon S620",
      OutputMode: { Path: "User.Mode" },
      AbsoluteModeSettings: { Tablet: { Width: 1, Height: 1, X: 0, Y: 0, Rotation: 0 } },
      Bindings: { keep: "untouched" } }] }
    var plan = Model.applyPlan(null, twoMonitors, "otd", doc, true)
    var prof = otdProfile(plan)
    compare(plan.changed, true)
    compare(prof.OutputMode, { Path: "User.Mode" })
    compare(prof.AbsoluteModeSettings, { Tablet: { Width: 1, Height: 1, X: 0, Y: 0, Rotation: 0 } })
    compare(prof.Bindings.AuxButtons, [padButton(1), padButton(2), padButton(3), padButton(4)])
    compare(prof.Bindings.keep, "untouched")
  }
}
