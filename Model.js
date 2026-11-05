// Rules for the GAOMON S620 widget. s620-pad prints one JSON object per line;
// what the bar shows, the Hyprland settings and what each express key sends
// are decided here so tests/tst_model.qml covers them.

var GLYPH_TABLET = "󰽉"
var TITLE = "GAOMON S620"

// Pen node as Hyprland names it (`hyprctl devices`): libinput's
// "GAOMON Gaomon Tablet Pen", lowercased with spaces turned into dashes.
var PEN_DEVICE = "gaomon-gaomon-tablet-pen"

// Read from the tablet by hid-uclogic (docs/re/findings.md): 33020 x 20320
// units at 5080 LPI, 8192 pressure levels, four express keys.
var TABLET_WIDTH_MM = 165.1
var TABLET_HEIGHT_MM = 101.6
var KEY_COUNT = 4
// The pad reports its buttons as BTN_0 upwards.
var BTN_0 = 0x100

var NOTICES = {
  starting: "looking for the tablet",
  missing: "tablet disconnected",
  "no-driver": "no driver owns the tablet",
  "access-denied": "no permission on the express keys (install the udev rule)",
  error: "invalid response from the helper"
}

// Who owns the tablet (GLOSSARY.md), from the helper's connected or
// access-denied line; a message without the field reads as the kernel default.
var BACKENDS = { kernel: "Kernel driver", otd: "OpenTabletDriver" }

function backendOf(state) {
  return (state || {}).backend === "otd" ? "otd" : "kernel"
}

// ---------- Helper lines ----------

// Folds one helper line into the connection state. Key events leave it as is.
function applyLine(previous, line) {
  var prev = previous || { connection: "starting" }
  var message = parseLine(line)
  if (message === null) return { connection: "error" }
  if (message.ok !== true) {
    var denied = withFirmware({ connection: NOTICES[message.error] ? String(message.error) : "error" }, message)
    if (typeof message.backend === "string") denied.backend = message.backend
    return denied
  }
  if (message.event === "connected") {
    var next = withFirmware({ connection: "ready" }, message)
    if (typeof message.backend === "string") next.backend = message.backend
    return next
  }
  return prev
}

// The helper sends the firmware version (the node's uniq) when it finds the
// tablet; a user can quote it when reporting a problem.
function withFirmware(state, message) {
  if (typeof message.firmware === "string" && message.firmware !== "") state.firmware = message.firmware
  return state
}

function firmwareText(state) {
  return tabletPresent(state) && backendOf(state) === "kernel" && state.firmware ? "Firmware " + state.firmware : ""
}

// Whether the tablet is plugged in. Without the udev rule the pad cannot be
// read, but the helper still finds it, so the tablet is there.
function tabletPresent(state) {
  var connection = (state || {}).connection
  return connection === "ready" || connection === "access-denied"
}

// {index, pressed} for an express key line, null for anything else. The keys
// sit in a row in the top-left corner; index 0 is the leftmost.
function keyEvent(line) {
  var message = parseLine(line)
  if (message === null || message.ok !== true || message.event !== "key") return null
  var index = Number(message.code) - BTN_0
  if (!(index >= 0 && index < KEY_COUNT)) return null
  return { index: index, pressed: message.pressed === true }
}

function parseLine(line) {
  var message = parseJson(line)
  return message && typeof message === "object" ? message : null
}

function parseJson(text) {
  try { return JSON.parse(String(text || "")) } catch (error) { return null }
}

function barView(state) {
  var s = state || { connection: "starting" }
  return { text: GLYPH_TABLET, active: false, dimmed: s.connection !== "ready" }
}

function statusText(state) {
  var s = state || { connection: "starting" }
  if (s.connection !== "ready") return NOTICES[s.connection]
  return "connected" + (BACKENDS[s.backend] ? " · " + BACKENDS[s.backend] : "")
}

function tooltip(state) {
  return TITLE + " · " + statusText(state)
}

// No express key held: one slot per key, each the key's settings while held.
function emptyKeys() {
  var keys = []
  for (var i = 0; i < KEY_COUNT; i++) keys.push(null)
  return keys
}

// ---------- Profile ----------

// Only 0° and 180°. Hyprland rotates a tablet through libinput's calibration
// matrix, which libinput only accepts on screen tablets, so `transform` does
// nothing on the S620 (seen on 2026-10-24). 180° goes through libinput's
// left-handed mode instead; libwacom marks the S620 as reversible.
var ROTATIONS = [
  { value: "0", label: "Right-handed" },
  { value: "2", label: "Left-handed (180°)" }
]

var AREAS = [
  { value: "full", label: "Full area" },
  { value: "ratio", label: "Match screen" },
  { value: "custom", label: "Custom" }
]

// Express key actions. Shortcuts go down on press and up on release;
// Hyprland cannot keep a key held (docs/re/findings.md), so there is no pan
// or hold-a-modifier action.
var ACTIONS = [
  { value: "none", label: "Nothing" },
  { value: "undo", label: "Undo", mods: "CTRL", key: "Z" },
  { value: "redo", label: "Redo", mods: "CTRL SHIFT", key: "Z" },
  { value: "save", label: "Save", mods: "CTRL", key: "S" },
  { value: "brush", label: "Brush (B)", mods: "", key: "B" },
  { value: "eraser", label: "Eraser (E)", mods: "", key: "E" },
  { value: "smaller", label: "Smaller brush ([)", mods: "", key: "bracketleft" },
  { value: "bigger", label: "Bigger brush (])", mods: "", key: "bracketright" },
  { value: "zoomIn", label: "Zoom in", mods: "CTRL", key: "equal" },
  { value: "zoomOut", label: "Zoom out", mods: "CTRL", key: "minus" },
  // Media and system presets run once per press, detached.
  { value: "playPause", label: "Play/pause", argv: ["omarchy-shell", "media", "playPause"] },
  { value: "nextTrack", label: "Next track", argv: ["omarchy-shell", "media", "next"] },
  { value: "previousTrack", label: "Previous track", argv: ["omarchy-shell", "media", "previous"] },
  { value: "volumeUp", label: "Volume up", argv: ["omarchy-audio-output-volume", "raise"] },
  { value: "volumeDown", label: "Volume down", argv: ["omarchy-audio-output-volume", "lower"] },
  { value: "mute", label: "Mute", argv: ["omarchy-audio-output-volume", "mute-toggle"] },
  { value: "lock", label: "Lock screen", argv: ["omarchy-system-lock"] },
  { value: "suspend", label: "Suspend", argv: ["systemctl", "suspend"] },
  { value: "showKeys", label: "Show key functions" },
  { value: "switchMonitor", label: "Next monitor" },
  // The pen/mouse toggle only exists through Hyprland's relative_input,
  // which the OTD document never gets, so it is kernel-only.
  { value: "togglePenMouse", label: "Toggle pen/mouse", otd: false },
  { value: "shortcut", label: "Custom shortcut" },
  { value: "command", label: "Run command" }
]

// The vendor app's "force to reach maximum pressure" goes down to a very light
// touch; 10% is as light as stays usable.
var PRESSURE_MAX_FLOOR = 10

var DEFAULTS = {
  output: "",
  rotation: 0,
  area: "full",
  relative: false,
  keysEnabled: true,
  pressureMin: 0,
  pressureMax: 100,
  keys: [
    { action: "undo", text: "" },
    { action: "redo", text: "" },
    { action: "eraser", text: "" },
    { action: "showKeys", text: "" }
  ]
}

function actionFor(value) {
  for (var i = 0; i < ACTIONS.length; i++) if (ACTIONS[i].value === value) return ACTIONS[i]
  return null
}

// The actions a backend can do: entries marked `otd: false` disappear from
// the choices while the OTD backend owns the tablet.
function actionsFor(backend) {
  return ACTIONS.filter(function(a) { return backend !== "otd" || a.otd !== false })
}

function clamp(value, low, high, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(low, Math.min(high, Math.round(n)))
}

function normalizeKey(raw, fallback) {
  var k = raw && typeof raw === "object" ? raw : {}
  var action = actionFor(String(k.action)) ? String(k.action) : fallback.action
  return { action: action, text: typeof k.text === "string" ? k.text : "" }
}

function normalizeProfile(raw, monitors) {
  var r = raw && typeof raw === "object" ? raw : {}
  var keys = []
  for (var i = 0; i < KEY_COUNT; i++) {
    keys.push(normalizeKey(r.keys && r.keys[i], DEFAULTS.keys[i]))
  }
  var high = clamp(r.pressureMax, PRESSURE_MAX_FLOOR, 100, DEFAULTS.pressureMax)
  // libinput refuses a range whose minimum is not below its maximum.
  var low = Math.min(clamp(r.pressureMin, 0, 50, DEFAULTS.pressureMin), high - 5)
  var output = validOutput(r.output) ? String(r.output) : DEFAULTS.output
  return {
    output: output,
    rotation: Number(r.rotation) === 2 ? 2 : 0,
    area: r.area === "ratio" || r.area === "custom" ? r.area : "full",
    relative: r.relative === true,
    keysEnabled: r.keysEnabled !== false,
    pressureMin: low,
    pressureMax: high,
    keys: keys,
    customArea: normalizeCustomArea(r.customArea)
  }
}

// The area the user draws, in millimetres on the tablet as held (Hyprland
// applies the active area after left_handed). Numbers keep one decimal;
// anything missing or not a number stays unset, and the default applies
// where the area is used, so monitors that arrive after the load still
// shape it. Fitting to the tablet happens in customRect, so a stored area
// survives a reload unchanged.
function normalizeCustomArea(raw) {
  var c = raw && typeof raw === "object" ? raw : null
  if (!c) return null
  var fields = ["width", "height", "centerX", "centerY"]
  var out = {}
  for (var i = 0; i < fields.length; i++) {
    var v = c[fields[i]]
    if (typeof v !== "number" || !isFinite(v)) return null
    out[fields[i]] = roundToTenth(v)
  }
  return out
}

// The default custom area: three quarters of the "Match screen" rectangle,
// centred on the tablet.
function defaultCustomArea(output, monitors) {
  var ratio = targetRatio(output, monitors)
  var w = TABLET_WIDTH_MM, h = TABLET_HEIGHT_MM
  if (ratio > 0) {
    if (w / h > ratio) w = h * ratio
    else h = w / ratio
  }
  return {
    width: roundToTenth(w * 0.75),
    height: roundToTenth(h * 0.75),
    centerX: roundToTenth(TABLET_WIDTH_MM / 2),
    centerY: roundToTenth(TABLET_HEIGHT_MM / 2)
  }
}

// `path` is a profile field ("rotation") or a key field ("keys.2.action").
function withValue(profile, path, value, monitors) {
  var next = JSON.parse(JSON.stringify(normalizeProfile(profile, monitors)))
  var parts = String(path).split(".")
  if (parts[0] === "keys" && parts.length === 3) {
    var key = next.keys[Number(parts[1])]
    if (key && (parts[2] === "action" || parts[2] === "text")) key[parts[2]] = value
  } else if (parts.length === 1 && next.hasOwnProperty(parts[0]) && parts[0] !== "keys") {
    next[parts[0]] = value
  }
  return normalizeProfile(next, monitors)
}

// "" maps the tablet across every monitor, "current" follows the focused one.
// Connector names are plain (eDP-2, DP-1, HDMI-A-1); anything else is refused
// before it reaches the Lua passed to Hyprland.
function validOutput(name) {
  return typeof name === "string" && (name === "" || /^[A-Za-z0-9_.-]{1,32}$/.test(name))
}

function pressureChanged(before, after) {
  var a = normalizeProfile(before)
  var b = normalizeProfile(after)
  return a.pressureMin !== b.pressureMin || a.pressureMax !== b.pressureMax
}

// ---------- Monitors ----------

// `hyprctl monitors -j` to the logical rectangles the tablet can map onto.
function parseMonitors(text) {
  var list = parseJson(text)
  if (!Array.isArray(list)) return []
  var monitors = []
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m || !validOutput(m.name) || m.name === "" || !(m.width > 0 && m.height > 0)) continue
    var scale = m.scale > 0 ? m.scale : 1
    var w = m.width / scale
    var h = m.height / scale
    if (m.transform % 2 === 1) { var t = w; w = h; h = t }
    monitors.push({ name: m.name, x: m.x || 0, y: m.y || 0, width: w, height: h, focused: m.focused === true })
  }
  return monitors
}

function outputOptions(monitors) {
  var options = [{ value: "", label: "All monitors" }, { value: "current", label: "Focused monitor" }]
  for (var i = 0; i < (monitors || []).length; i++) options.push({ value: monitors[i].name, label: monitors[i].name })
  return options
}

// Width / height of what the tablet maps onto.
function targetRatio(output, monitors) {
  var list = monitors || []
  if (list.length === 0) return 0
  var pick = []
  for (var i = 0; i < list.length; i++) {
    if (output === "current" ? list[i].focused : (output === "" || list[i].name === output)) pick.push(list[i])
  }
  if (pick.length === 0) return 0
  var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
  for (var j = 0; j < pick.length; j++) {
    left = Math.min(left, pick[j].x)
    top = Math.min(top, pick[j].y)
    right = Math.max(right, pick[j].x + pick[j].width)
    bottom = Math.max(bottom, pick[j].y + pick[j].height)
  }
  return (right - left) / (bottom - top)
}

// Centred part of the tablet with the screen's proportions, in tablet
// millimetres, or null for the whole tablet. Centred, it is the same area
// whether the tablet is turned or not. A custom area comes from customRect.
function activeArea(profile, monitors) {
  var p = normalizeProfile(profile, monitors)
  if (p.relative) return null
  if (p.area === "custom") return customRect(p, monitors)
  if (p.area !== "ratio") return null
  var ratio = targetRatio(p.output, monitors)
  if (!(ratio > 0)) return null
  var w = TABLET_WIDTH_MM
  var h = TABLET_HEIGHT_MM
  if (w / h > ratio) w = h * ratio
  else h = w / ratio
  return {
    width: roundToTenth(w),
    height: roundToTenth(h),
    x: roundToTenth((TABLET_WIDTH_MM - w) / 2),
    y: roundToTenth((TABLET_HEIGHT_MM - h) / 2)
  }
}

// ---------- Custom area ----------

var CUSTOM_AREA_MIN_WIDTH = 30

// The ratio the custom rectangle keeps: the mapped screen's, or the
// tablet's own while there is no monitor to match.
function customAreaRatio(profile, monitors) {
  var ratio = targetRatio(profile.output, monitors)
  return ratio > 0 ? ratio : TABLET_WIDTH_MM / TABLET_HEIGHT_MM
}

// Width and centre to a rect that fits the tablet at the screen's ratio:
// the height always follows the width, an oversized width shrinks, and the
// centre shifts until the rectangle lies inside the tablet.
function fitCustomArea(width, centerX, centerY, ratio) {
  var max = Math.min(TABLET_WIDTH_MM, TABLET_HEIGHT_MM * ratio)
  var w = Math.max(Math.min(CUSTOM_AREA_MIN_WIDTH, max), Math.min(max, Number(width)))
  var h = w / ratio
  var cx = Math.max(w / 2, Math.min(TABLET_WIDTH_MM - w / 2, Number(centerX)))
  var cy = Math.max(h / 2, Math.min(TABLET_HEIGHT_MM - h / 2, Number(centerY)))
  return { width: roundToTenth(w), height: roundToTenth(h), x: roundToTenth(cx - w / 2), y: roundToTenth(cy - h / 2) }
}

// The rectangle to apply: {width, height, x, y} in millimetres, x/y the
// top-left corner on the tablet as held.
function customRect(profile, monitors) {
  var p = normalizeProfile(profile, monitors)
  var c = p.customArea || defaultCustomArea(p.output, monitors)
  return fitCustomArea(c.width, c.centerX, c.centerY, customAreaRatio(p, monitors))
}

// The fitted rect back into the profile: the stored centre is the rect's
// centre, so the drawing and the next gesture start from what is applied.
function storeCustomArea(profile, rect) {
  return withValue(profile, "customArea", {
    width: rect.width, height: rect.height,
    centerX: roundToTenth(rect.x + rect.width / 2),
    centerY: roundToTenth(rect.y + rect.height / 2)
  })
}

// The drawing's move gesture: the centre shifts by (dxMm, dyMm), clamped
// by the same rules as customRect.
function moveCustomArea(profile, dxMm, dyMm, monitors) {
  var p = normalizeProfile(profile, monitors)
  var c = p.customArea || defaultCustomArea(p.output, monitors)
  var rect = fitCustomArea(c.width,
    c.centerX + (Number(dxMm) || 0), c.centerY + (Number(dyMm) || 0),
    customAreaRatio(p, monitors))
  return storeCustomArea(p, rect)
}

// The drawing's resize gesture, anchored at the corner opposite the
// dragged one ("nw", "ne", "sw", "se"), which does not move: the width is
// capped by the space between the anchor and the tablet edge facing the
// drag. The minimum width is CUSTOM_AREA_MIN_WIDTH and the height follows
// the ratio.
function resizeCustomArea(profile, widthMm, corner, monitors) {
  var p = normalizeProfile(profile, monitors)
  var ratio = customAreaRatio(p, monitors)
  var c = p.customArea || defaultCustomArea(p.output, monitors)
  var old = fitCustomArea(c.width, c.centerX, c.centerY, ratio)
  var w = Number(widthMm)
  if (!(w > 0)) w = old.width
  var ax = corner === "nw" || corner === "sw" ? old.x + old.width : old.x
  var ay = corner === "nw" || corner === "ne" ? old.y + old.height : old.y
  var spaceX = corner === "nw" || corner === "sw" ? ax : TABLET_WIDTH_MM - ax
  var spaceY = corner === "nw" || corner === "ne" ? ay : TABLET_HEIGHT_MM - ay
  var maxW = Math.min(spaceX, spaceY * ratio)
  w = Math.max(Math.min(CUSTOM_AREA_MIN_WIDTH, maxW), Math.min(maxW, w))
  var h = w / ratio
  var x = corner === "nw" || corner === "sw" ? ax - w : ax
  var y = corner === "nw" || corner === "ne" ? ay - h : ay
  return storeCustomArea(p, {
    width: roundToTenth(w), height: roundToTenth(h),
    x: roundToTenth(Math.max(0, Math.min(TABLET_WIDTH_MM - w, x))),
    y: roundToTenth(Math.max(0, Math.min(TABLET_HEIGHT_MM - h, y)))
  })
}

// The same gesture with the pointer in millimetres instead of a width: the
// anchor corner is found here, so the QML only turns pixels into
// millimetres. The wider of the two dragged axes drives the width.
function resizeCustomAreaAt(profile, pointXMm, pointYMm, corner, monitors) {
  var p = normalizeProfile(profile, monitors)
  var ratio = customAreaRatio(p, monitors)
  var c = p.customArea || defaultCustomArea(p.output, monitors)
  var old = fitCustomArea(c.width, c.centerX, c.centerY, ratio)
  var ax = corner === "nw" || corner === "sw" ? old.x + old.width : old.x
  var ay = corner === "nw" || corner === "ne" ? old.y + old.height : old.y
  var w = Math.max(Math.abs((Number(pointXMm) || 0) - ax),
    Math.abs((Number(pointYMm) || 0) - ay) * ratio)
  return resizeCustomArea(p, w, corner, monitors)
}

function roundToTenth(n) { return Math.round(n * 10) / 10 }

// `centred` is false for the custom area, which sits where the user left it.
function areaNote(area, centred) {
  if (area) return "Active area " + area.width + " × " + area.height + " mm" + (centred === false ? "." : ", centred.")
  return "The whole " + Math.round(TABLET_WIDTH_MM) + " × " + Math.round(TABLET_HEIGHT_MM) + " mm area is active."
}

// ---------- Hyprland ----------

function luaString(text) {
  return "\"" + String(text).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\""
}

// One chunk for `hyprctl eval`: pen mapping and pressure range. The whole
// tablet is sent as an explicit area: Hyprland skips a zero size and would
// keep the last crop (seen on 2026-10-24).
function deviceLua(profile, monitors) {
  var p = normalizeProfile(profile, monitors)
  var area = activeArea(p, monitors) || { width: TABLET_WIDTH_MM, height: TABLET_HEIGHT_MM, x: 0, y: 0 }
  return "hl.device({ name = " + luaString(PEN_DEVICE)
    + ", output = " + luaString(p.output)
    + ", left_handed = " + (p.rotation === 2 ? "true" : "false")
    + ", relative_input = " + (p.relative ? "true" : "false")
    + ", active_area_size = { " + area.width + ", " + area.height + " }"
    + ", active_area_position = { " + area.x + ", " + area.y + " } })\n"
    + pressureLua(p)
}

function pressureLua(profile) {
  var p = normalizeProfile(profile)
  return "hl.config({ input = { tablettool = { pressure_range_min = " + (p.pressureMin / 100)
    + ", pressure_range_max = " + (p.pressureMax / 100) + " } } })"
}

// ---------- OpenTabletDriver ----------

var OTD_TABLET = "Gaomon S620"
var OTD_ARTIST_MODE = "OpenTabletDriver.Desktop.Output.LinuxArtistMode"
var OTD_PAD_BINDING = "OpenTabletDriver.Desktop.Binding.LinuxArtistMode.LinuxArtistModePadBinding"

// Whether Hyprland's pressure range still reaches the OTD virtual tablet.
// It does not (docs/re/opentabletdriver.md, seen 2026-10-25), so the panel
// disables the control on OTD and no hl.device goes to the GAOMON pen.
var OTD_PRESSURE_RANGE_APPLIES = false

// The logical rectangle the profile's output covers ("" every monitor,
// "current" the focused one), or null when nothing matches.
function outputRect(output, monitors) {
  var list = monitors || []
  var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!(output === "" || (output === "current" ? m.focused === true : m.name === output))) continue
    left = Math.min(left, m.x)
    top = Math.min(top, m.y)
    right = Math.max(right, m.x + m.width)
    bottom = Math.max(bottom, m.y + m.height)
  }
  if (left === Infinity) return null
  return { x: left, y: top, width: right - left, height: bottom - top }
}

// One entry point: what Service.qml applies for the profile on the current
// backend. On the kernel backend it is the Hyprland Lua as today; on OTD it
// is the running settings document with only the S620 profile's output mode
// and area patched (everything else untouched), plus a note saying why when
// there is nothing to apply.
function applyPlan(profile, monitors, backend, otdDocument, keysOnly) {
  if (backend === "otd") return otdPlan(profile, monitors, otdDocument, keysOnly)
  return { backend: "kernel", lua: deviceLua(profile, monitors) }
}

// The tablet area OTD applies. Mouse (relative) mode is out of scope on
// OTD - the document stays in Artist Mode - so a profile carried over with
// `relative` keeps its crop instead of widening to the whole tablet.
function otdArea(profile, monitors) {
  var p = normalizeProfile(profile, monitors)
  p.relative = false
  return activeArea(p, monitors)
}

// The OTD document patched for the profile. X/Y are the rectangle's centre:
// the display in logical pixels, the tablet in millimetres. Relative mode
// stays in Artist Mode (out of scope on OTD). With `keysOnly` only the
// express key bindings are written: before the first profile exists the pen
// settings stay as the user left them, but the virtual pad still has to
// appear for the keys to work.
function otdPlan(profile, monitors, otdDocument, keysOnly) {
  var lua = OTD_PRESSURE_RANGE_APPLIES && keysOnly !== true ? pressureLua(profile) : null
  var doc = typeof otdDocument === "string" ? parseJson(otdDocument) : otdDocument
  if (!doc || typeof doc !== "object" || !Array.isArray(doc.Profiles)) {
    return { backend: "otd", document: null, changed: false, lua: lua,
      note: "the OpenTabletDriver settings could not be read" }
  }
  var next = JSON.parse(JSON.stringify(doc))
  var target = null
  for (var i = 0; i < next.Profiles.length; i++) {
    if (next.Profiles[i] && next.Profiles[i].Tablet === OTD_TABLET) { target = next.Profiles[i]; break }
  }
  if (target === null) {
    return { backend: "otd", document: doc, changed: false, lua: lua,
      note: "the OpenTabletDriver settings have no Gaomon S620 profile" }
  }
  if (keysOnly !== true) {
    var p = normalizeProfile(profile, monitors)
    if (!target.OutputMode || typeof target.OutputMode !== "object") target.OutputMode = {}
    target.OutputMode.Path = OTD_ARTIST_MODE
    if (!target.AbsoluteModeSettings || typeof target.AbsoluteModeSettings !== "object") target.AbsoluteModeSettings = {}
    var display = outputRect(p.output, monitors)
    if (display !== null) {
      target.AbsoluteModeSettings.Display = {
        Width: display.width, Height: display.height,
        X: display.x + display.width / 2, Y: display.y + display.height / 2,
        Rotation: 0
      }
    }
    var area = otdArea(p, monitors) || { width: TABLET_WIDTH_MM, height: TABLET_HEIGHT_MM, x: 0, y: 0 }
    var cx = area.x + area.width / 2
    var cy = area.y + area.height / 2
    // OTD reads the tablet area in the raw frame, but a custom area is drawn
    // as held (docs/re/findings.md): under a 180° turn the centre mirrors so
    // the same drawing covers the same physical part on both backends.
    if (p.rotation === 2) { cx = TABLET_WIDTH_MM - cx; cy = TABLET_HEIGHT_MM - cy }
    target.AbsoluteModeSettings.Tablet = {
      Width: area.width, Height: area.height,
      X: cx, Y: cy,
      Rotation: p.rotation === 2 ? 180 : 0
    }
  }
  // The plugin decides every key action, so OTD binds the express keys to
  // pad buttons 1-4 for s620-pad to read and sends no keys of its own.
  if (!target.Bindings || typeof target.Bindings !== "object") target.Bindings = {}
  var aux = []
  for (var k = 0; k < KEY_COUNT; k++) {
    aux.push({ Path: OTD_PAD_BINDING,
      Settings: [{ Property: "Button", Value: "Pad Button " + (k + 1) }],
      Enable: true })
  }
  target.Bindings.AuxButtons = aux
  return { backend: "otd", document: next, changed: true, note: "", lua: lua }
}

var MODIFIERS = ["SUPER", "SHIFT", "CTRL", "ALT"]

// "Ctrl+Shift+Z", "CTRL SHIFT Z" or "z" to {mods: "CTRL SHIFT", key: "Z"}; null
// when it is not a shortcut. Keys are xkb key names (Z, F5, space, bracketleft).
function parseShortcut(text) {
  var parts = String(text || "").trim().split(/[\s+]+/).filter(function(s) { return s !== "" })
  if (parts.length === 0) return null
  var key = parts.pop()
  if (!/^[A-Za-z0-9_]{1,32}$/.test(key)) return null
  var mods = []
  for (var i = 0; i < parts.length; i++) {
    var mod = parts[i].toUpperCase()
    if (mod === "CONTROL") mod = "CTRL"
    if (mod === "META" || mod === "WIN") mod = "SUPER"
    if (MODIFIERS.indexOf(mod) < 0) return null
    if (mods.indexOf(mod) < 0) mods.push(mod)
  }
  return { mods: mods.join(" "), key: key.length === 1 ? key.toUpperCase() : key }
}

// Omarchy's notification card shows at most three body lines and drops the
// rest, so long labels (commands) are cut to keep two keys on each line.
var SUMMARY_LABEL_MAX = 22

// The "Show key functions" notification: the express keys numbered 1-4 from
// the left with the label the panel shows, two per line.
function keysSummary(keys) {
  var items = []
  for (var i = 0; i < KEY_COUNT; i++) {
    var label = keyLabel((keys || [])[i])
    if (label.length > SUMMARY_LABEL_MAX) label = label.slice(0, SUMMARY_LABEL_MAX - 1) + "…"
    items.push((i + 1) + " " + label)
  }
  var lines = []
  for (var j = 0; j < items.length; j += 2) lines.push(items.slice(j, j + 2).join(" · "))
  return lines.join("\n")
}

// What one press or release of an express key runs: {detached, argv} jobs.
// Shortcuts go down on press and up on release, in order through Hyprland;
// commands run on press only, detached, so a slow one never delays a key.
function keyCommands(key, pressed, keys) {
  var k = key || { action: "none", text: "" }
  if (k.action === "showKeys") {
    return pressed ? [{ detached: true, argv: ["omarchy-notification-send", "-g", GLYPH_TABLET,
      "GAOMON S620 express keys", keysSummary(keys)] }] : []
  }
  var action = actionFor(k.action)
  if (action && action.argv) return pressed ? [{ detached: true, argv: action.argv }] : []
  if (k.action === "command") {
    var command = String(k.text || "").trim()
    return pressed && command !== "" ? [{ detached: true, argv: ["bash", "-lc", command] }] : []
  }
  var shortcut = k.action === "shortcut" ? parseShortcut(k.text) : actionFor(k.action)
  if (!shortcut || shortcut.key === undefined) return []
  return [{ detached: false, argv: ["hyprctl", "eval", "hl.dispatch(hl.dsp.send_key_state({ mods = " + luaString(shortcut.mods)
    + ", key = " + luaString(shortcut.key) + ", state = " + luaString(pressed ? "down" : "up") + " }))"] }]
}

// The profile a profile-key press leaves behind, null when the key changes
// nothing or there is nothing to change to (no monitor). Returned through
// withValue so it is normalized like a panel change.
function keyProfile(key, profile, monitors, backend) {
  var k = key || { action: "none", text: "" }
  var action = actionFor(k.action)
  // A key still bound to an action the backend cannot do (a profile saved on
  // the other backend) is a no-op instead of flipping a profile field the
  // backend never applies.
  if (action && backend === "otd" && action.otd === false) return null
  if (k.action === "togglePenMouse") return withValue(profile, "relative", !normalizeProfile(profile).relative)
  if (k.action === "switchMonitor") {
    var output = nextOutput(normalizeProfile(profile).output, monitors)
    return output === null ? null : withValue(profile, "output", output)
  }
  return null
}

// The monitor after `output` in Hyprland's order: "" and names of monitors
// that are gone start at the first, "current" follows the focused one, and
// a connected name steps to the next, wrapping. null with no monitors.
function nextOutput(output, monitors) {
  var list = monitors || []
  if (list.length === 0) return null
  var index = -1
  for (var i = 0; i < list.length; i++) {
    if (output === "current" ? list[i].focused : list[i].name === output) { index = i; break }
  }
  return list[(index + 1) % list.length].name
}

function keyLabel(key) {
  var k = key || { action: "none", text: "" }
  if (k.action === "shortcut") return parseShortcut(k.text) ? String(k.text).trim() : "invalid shortcut"
  if (k.action === "command") return String(k.text || "").trim() || "no command"
  var action = actionFor(k.action)
  return action ? action.label : ""
}
