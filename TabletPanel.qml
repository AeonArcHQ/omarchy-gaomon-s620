import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar entry and popup for the GAOMON S620. Same structure as the first-party
// panels: one Service child owns the processes, the popup is a KeyboardPanel,
// and the rules live in Model.js where tests/tst_model.qml covers them.
Panel {
  id: root
  moduleName: "com.aeonarc.gaomon-s620"
  ipcTarget: "com.aeonarc.gaomon-s620"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var view: Model.barView(s620.tablet)
  readonly property var p: s620.profile
  // On OTD the profile's `relative` is out of scope: the crop still applies.
  readonly property var area: root.otd ? Model.otdArea(p, s620.monitors) : Model.activeArea(p, s620.monitors)
  // The OTD backend owns the tablet through its daemon: the pressure range
  // is not available on it yet.
  readonly property bool otd: Model.backendOf(s620.tablet) === "otd"

  // Restoring defaults takes two clicks; the second must come within 5 s.
  property bool confirmingReset: false
  Timer {
    id: resetConfirmTimer
    interval: 5000
    onTriggered: root.confirmingReset = false
  }

  // Scroll the panel by a wheel step; sliders hand their wheel events here so
  // scrolling past them does not change the tablet.
  function scrollBy(wheel) {
    var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - dy))
  }

  onOpenedChanged: if (opened) {
    confirmingReset = false
    s620.refreshMonitors()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: s620
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return s620.tablet.connection }
    function resetDefaults(): string { s620.resetDefaults(); return "ok" }
    // e.g. set rotation 2, set output '"eDP-2"', set keys.0.action '"undo"'
    function set(path: string, value: string): string {
      var parsed
      try { parsed = JSON.parse(value) } catch (error) { return "invalid value" }
      s620.set(path, parsed)
      return "sent"
    }
    function lastError(): string { return s620.lastError }
    // Switch the express keys off before reading them with `s620-pad watch`.
    function keys(state: string): string {
      if (state !== "on" && state !== "off") return "use on or off"
      s620.set("keysEnabled", state === "on")
      return "sent"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.view.text
    active: root.view.active
    dimmed: root.view.dimmed
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: Model.tooltip(s620.tablet)
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      // fixing-accessibility §2: the first Tab focuses the custom-area
      // drawing instead of leaving the panel; the next one switches panels.
      onTabRequested: function(direction) {
        if (customMap.visible && !customMap.activeFocus) customMap.forceActiveFocus()
        else root.switchPanel(direction)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Status ----------
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: Model.TITLE
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              textFormat: Text.PlainText
            }
            Text {
              width: parent.width
              text: Model.statusText(s620.tablet)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
            Text {
              width: parent.width
              visible: text !== ""
              text: Model.firmwareText(s620.tablet)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
          }

          Text {
            width: parent.width
            visible: s620.lastError !== ""
            text: s620.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }

          // ---------- Mapping ----------
          Section {
            title: "SCREEN MAPPING"
            note: Model.areaNote(root.area, root.p.area !== "custom")

            Dropdown {
              width: parent.width
              showLabel: false
              options: Model.outputOptions(s620.monitors)
              value: root.p.output
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(v) { s620.set("output", v) }
            }
            ChoiceRow {
              options: Model.AREAS
              value: root.p.area
              enabled: !root.p.relative || root.otd
              // through withValue so the default custom area uses the monitors
              onPicked: function(v) { s620.commit(Model.withValue(root.p, "area", v, s620.monitors)) }
            }
            CustomAreaMap {
              id: customMap
              width: parent.width
              visible: root.p.area === "custom" && (!root.p.relative || root.otd)
            }
            SwitchRow {
              label: "Mouse mode (relative)"
              checked: root.p.relative
              enabled: !root.otd
              onFlipped: s620.set("relative", !root.p.relative)
            }
            Text {
              width: parent.width
              visible: root.otd
              text: "Mouse mode is not available on OpenTabletDriver."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
          }

          // ---------- Orientation ----------
          Section {
            title: "ORIENTATION"
            note: "Left-handed turns the tablet 180°, with the keys at the bottom right. Hyprland cannot turn this tablet 90°."

            ChoiceRow {
              options: Model.ROTATIONS
              value: String(root.p.rotation)
              onPicked: function(v) { s620.set("rotation", Number(v)) }
            }
          }

          // ---------- Pressure ----------
          Section {
            title: "PRESSURE"
            note: (root.otd && !Model.OTD_PRESSURE_RANGE_APPLIES) ? "The pressure range is not available on OpenTabletDriver yet."
              : s620.pressureNeedsReplug ? "Unplug the tablet and plug it back in to apply: Hyprland only reads the pressure range when the tablet connects."
              : "Lower full pressure for a lighter touch; raise the threshold to ignore a resting pen."

            ValueSlider {
              label: "Threshold"
              minimum: 0
              maximum: 50
              value: root.p.pressureMin
              enabled: !root.otd || Model.OTD_PRESSURE_RANGE_APPLIES
              format: function(v) { return v + "%" }
              onCommitted: function(v) { s620.set("pressureMin", v) }
            }
            ValueSlider {
              label: "Full pressure at"
              minimum: Model.PRESSURE_MAX_FLOOR
              maximum: 100
              value: root.p.pressureMax
              enabled: !root.otd || Model.OTD_PRESSURE_RANGE_APPLIES
              format: function(v) { return v + "%" }
              onCommitted: function(v) { s620.set("pressureMax", v) }
            }
            PressureTest { }
          }

          // ---------- Express keys ----------
          Section {
            title: "EXPRESS KEYS"
            note: root.p.rotation === 2 ? "Turned left-handed, key 1 is the rightmost of the row in the bottom-right corner."
              : "Key 1 is the leftmost of the row in the top-left corner."

            Column {
              width: parent.width
              spacing: Style.space(8)

            SwitchRow {
              label: "Express keys"
              checked: root.p.keysEnabled
              onFlipped: s620.set("keysEnabled", !root.p.keysEnabled)
            }

            Repeater {
              model: Model.KEY_COUNT
              delegate: Column {
                id: keyRow
                required property int index
                readonly property var key: root.p.keys[index]
                readonly property bool needsText: key.action === "shortcut" || key.action === "command"

                width: parent ? parent.width : 0
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  implicitHeight: keyMenu.implicitHeight

                  Rectangle {
                    id: keyDot
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(8)
                    height: width
                    radius: width / 2
                    color: s620.heldKeys[keyRow.index] ? root.urgent : "transparent"
                    border.width: 1
                    border.color: root.dim
                  }
                  Text {
                    anchors.left: keyDot.right
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.4 - keyDot.width - Style.space(6)
                    text: "Key " + (keyRow.index + 1)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                  }
                  Dropdown {
                    id: keyMenu
                    anchors.right: parent.right
                    width: parent.width * 0.6
                    showLabel: false
                    options: Model.actionsFor(root.otd ? "otd" : "kernel").map(function(a) { return { value: a.value, label: a.label } })
                    value: keyRow.key.action
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onChanged: function(v) { s620.set("keys." + keyRow.index + ".action", v) }
                  }
                }
                TextField {
                  width: parent.width
                  visible: keyRow.needsText
                  text: keyRow.key.text
                  placeholderText: keyRow.key.action === "shortcut" ? "Ctrl+Shift+Z" : "omarchy launch browser"
                  foreground: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  onEditingFinished: s620.set("keys." + keyRow.index + ".text", text)
                }
                Text {
                  width: parent.width
                  visible: keyRow.key.action === "shortcut" && keyRow.key.text !== "" && Model.parseShortcut(keyRow.key.text) === null
                  text: "Not a shortcut: use modifiers (Super, Ctrl, Shift, Alt) and one key, like Ctrl+Shift+Z."
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
              }
            }
            }
          }

          // ---------- Defaults ----------
          Section {
            title: "DEFAULTS"
            note: root.confirmingReset ? "Click again to confirm."
              : "Resets mapping, rotation, pressure and express keys."

            Button {
              width: parent.width
              text: root.confirmingReset ? "Confirm reset" : "Restore defaults"
              bordered: true
              selected: root.confirmingReset
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: {
                if (!root.confirmingReset) {
                  root.confirmingReset = true
                  resetConfirmTimer.restart()
                  return
                }
                root.confirmingReset = false
                resetConfirmTimer.stop()
                s620.resetDefaults()
              }
            }
          }

          Item { width: parent.width; height: Style.space(2) }
        }
      }
    }
  }

  // A titled block, laid out like the sections of omarchy.monitor.
  component Section: Column {
    property string title: ""
    property string note: ""
    default property alias rows: body.data

    width: parent ? parent.width : 0
    spacing: Style.space(6)

    PanelSeparator { width: parent.width; foreground: root.fg }
    PanelSectionHeader { text: parent.title; foreground: root.fg; fontFamily: root.fontFamily }
    Text {
      width: parent.width
      visible: parent.note !== ""
      text: parent.note
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }
    Column {
      id: body
      width: parent.width
      spacing: Style.space(8)
    }
  }

  // Press the pen here to see the pressure applications receive, after the
  // range above, like the vendor app's pressure test. The bar shows the live
  // value and the tick the highest one of the stroke, which fades 1.5 s after
  // the pen lifts so it never reads as a stale value.
  component PressureTest: Column {
    id: pressureTest
    property real live: 0
    property real peak: 0

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: testLabel.implicitHeight

      Text {
        id: testLabel
        anchors.left: parent.left
        text: "Pressure test"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        text: Math.round(pressureTest.live * 100) + "%" + (pressureTest.peak > 0 ? " · peak " + Math.round(pressureTest.peak * 100) + "%" : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        textFormat: Text.PlainText
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(56)
      radius: Style.space(4)
      color: "transparent"
      border.width: 1
      border.color: root.dim

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: Math.max(0, (parent.width - 2) * pressureTest.live)
        radius: Style.space(3)
        color: root.fg
        opacity: 0.35
      }
      Rectangle {
        visible: pressureTest.peak > 0
        x: Math.max(1, (parent.width - 2) * pressureTest.peak - width)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: Style.space(3)
        color: root.urgent
      }
      Text {
        anchors.centerIn: parent
        visible: pressureTest.peak === 0
        text: "Press the pen here"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Timer {
        id: peakFade
        interval: 1500
        onTriggered: pressureTest.peak = 0
      }

      PointHandler {
        id: penPoint
        acceptedDevices: PointerDevice.Stylus | PointerDevice.Airbrush
        onActiveChanged: {
          if (active) {
            peakFade.stop()
            pressureTest.peak = 0
          } else {
            pressureTest.live = 0
            peakFade.restart()
          }
        }
        onPointChanged: {
          var pressure = active ? Math.max(0, Math.min(1, penPoint.point.pressure)) : 0
          pressureTest.live = pressure
          if (pressure > pressureTest.peak) pressureTest.peak = pressure
        }
      }
    }
  }

  // The tablet drawn to scale with the custom area on top, as the user
  // holds the tablet: express keys top-left right-handed, bottom-right
  // left-handed. Dragging the body moves the area, dragging a corner
  // resizes it at the screen's ratio; the profile commits once on release.
  // emil-design-eng "Pointer capture for drag": preventStealing keeps the
  // gesture when the pointer leaves the drawing. "Multi-touch protection":
  // a second press while a gesture runs is ignored (draft already set).
  // fixing-accessibility §2/§7: the drawing tabs to focus, shows a focus
  // ring, and arrow keys move 1 mm (Shift: 10 mm), +/- resize 5 mm.
  component CustomAreaMap: Item {
    id: areaMap
    implicitHeight: Math.round(width * Model.TABLET_HEIGHT_MM / Model.TABLET_WIDTH_MM)
    activeFocusOnTab: true

    property var draft: null
    property var gesture: null

    readonly property real pxPerMm: width / Model.TABLET_WIDTH_MM
    readonly property var areaMm: Model.customRect(draft || root.p, s620.monitors)
    readonly property var corners: [
      { corner: "nw", fx: 0, fy: 0 },
      { corner: "ne", fx: 1, fy: 0 },
      { corner: "sw", fx: 0, fy: 1 },
      { corner: "se", fx: 1, fy: 1 }
    ]

    // `point` is the press position in the drawing's own coordinates;
    // callers map it so a moving rectangle never distorts the delta.
    function beginGesture(point, corner, mouse) {
      if (draft) { mouse.accepted = false; return }
      gesture = { corner: corner, x0: point.x, y0: point.y, base: root.p }
      draft = root.p
    }

    onVisibleChanged: if (!visible) areaMap.focus = false
    function endGesture() {
      if (draft) s620.commit(draft)
      draft = null
      gesture = null
    }

    Keys.onPressed: function(keyEvent) {
      var step = (keyEvent.modifiers & Qt.ShiftModifier) ? 10 : 1
      var dx = 0, dy = 0
      if (keyEvent.key === Qt.Key_Left) dx = -step
      else if (keyEvent.key === Qt.Key_Right) dx = step
      else if (keyEvent.key === Qt.Key_Up) dy = -step
      else if (keyEvent.key === Qt.Key_Down) dy = step
      else if (keyEvent.key === Qt.Key_Plus || keyEvent.key === Qt.Key_Equal) {
        s620.commit(Model.resizeCustomArea(root.p, areaMm.width + 5, "se", s620.monitors))
        keyEvent.accepted = true
        return
      } else if (keyEvent.key === Qt.Key_Minus) {
        s620.commit(Model.resizeCustomArea(root.p, areaMm.width - 5, "se", s620.monitors))
        keyEvent.accepted = true
        return
      } else return
      s620.commit(Model.moveCustomArea(root.p, dx, dy, s620.monitors))
      keyEvent.accepted = true
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: "transparent"
      border.width: areaMap.activeFocus ? 2 : 1
      border.color: areaMap.activeFocus ? Commons.Color.accent : root.dim

      Repeater {
        model: Model.KEY_COUNT
        delegate: Rectangle {
          required property int index
          width: Style.space(4)
          height: width
          radius: 1
          color: root.dim
          x: root.p.rotation === 2 ? areaMap.width - Style.space(10) - (4 - index) * Style.space(7)
            : Style.space(10) + index * Style.space(7)
          y: root.p.rotation === 2 ? areaMap.height - Style.space(14) : Style.space(10)
        }
      }
    }

    Rectangle {
      x: areaMap.areaMm.x * areaMap.pxPerMm
      y: areaMap.areaMm.y * areaMap.pxPerMm
      width: areaMap.areaMm.width * areaMap.pxPerMm
      height: areaMap.areaMm.height * areaMap.pxPerMm
      radius: Style.space(3)
      color: Commons.Color.accent
      opacity: 0.25
    }
    Rectangle {
      id: areaRect
      x: areaMap.areaMm.x * areaMap.pxPerMm
      y: areaMap.areaMm.y * areaMap.pxPerMm
      width: areaMap.areaMm.width * areaMap.pxPerMm
      height: areaMap.areaMm.height * areaMap.pxPerMm
      radius: Style.space(3)
      color: "transparent"
      border.width: 1
      border.color: Commons.Color.accent
    }

    MouseArea {
      anchors.fill: areaRect
      preventStealing: true
      // mouse.x follows the moving rectangle; the press and the move are
      // both read in areaMap coordinates so the delta stays true.
      onPressed: function(mouse) { areaMap.beginGesture(mapToItem(areaMap, mouse.x, mouse.y), "", mouse) }
      onPositionChanged: function(mouse) {
        if (!areaMap.draft || areaMap.gesture.corner !== "") return
        var point = mapToItem(areaMap, mouse.x, mouse.y)
        areaMap.draft = Model.moveCustomArea(areaMap.gesture.base,
          (point.x - areaMap.gesture.x0) / areaMap.pxPerMm,
          (point.y - areaMap.gesture.y0) / areaMap.pxPerMm, s620.monitors)
      }
      onReleased: areaMap.endGesture()
    }

    Repeater {
      model: areaMap.corners
      delegate: Item {
        id: handle
        required property var modelData
        // fixing-accessibility: hit area never below 24 px, even under a
        // small interface scale.
        width: Math.max(24, Style.space(28))
        height: width
        x: (areaMap.areaMm.x + areaMap.areaMm.width * modelData.fx) * areaMap.pxPerMm - width / 2
        y: (areaMap.areaMm.y + areaMap.areaMm.height * modelData.fy) * areaMap.pxPerMm - height / 2

        Rectangle {
          anchors.centerIn: parent
          // Visible square never below 8 px.
          width: Math.max(8, Style.space(9))
          height: width
          radius: 2
          color: Commons.Color.accent
        }
        MouseArea {
          anchors.fill: parent
          preventStealing: true
          onPressed: function(mouse) { areaMap.beginGesture(mapToItem(areaMap, mouse.x, mouse.y), handle.modelData.corner, mouse) }
          onPositionChanged: function(mouse) {
            if (!areaMap.draft || areaMap.gesture.corner !== handle.modelData.corner) return
            var point = mapToItem(areaMap, mouse.x, mouse.y)
            areaMap.draft = Model.resizeCustomAreaAt(areaMap.gesture.base,
              point.x / areaMap.pxPerMm, point.y / areaMap.pxPerMm,
              handle.modelData.corner, s620.monitors)
          }
          onReleased: areaMap.endGesture()
        }
      }
    }
  }

  component ChoiceRow: ButtonGroup {
    signal picked(string value)

    foreground: root.fg
    fontFamily: root.fontFamily
    opacity: enabled ? 1 : 0.45
    onChanged: function(v) { picked(v) }
  }

  // A plain row with the compact switch on the trailing edge, as in the
  // first-party audio and network panels; the whole row flips it.
  component SwitchRow: Item {
    id: switchRow
    property string label: ""
    property bool checked: false
    signal flipped()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(rowLabel.implicitHeight, rowSwitch.implicitHeight)
    opacity: enabled ? 1 : 0.45

    MouseArea {
      anchors.fill: parent
      enabled: switchRow.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: function() { switchRow.flipped() }
    }
    Text {
      id: rowLabel
      anchors.left: parent.left
      anchors.right: rowSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: switchRow.label
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }
    ToggleSwitch {
      id: rowSwitch
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      checked: switchRow.checked
      enabled: switchRow.enabled
      foreground: root.fg
      onToggled: switchRow.flipped()
    }
  }

  // Header with the live value on the right, then the slider. The tablet only
  // hears the value where the drag ends.
  component ValueSlider: Column {
    id: valueSlider
    property string label: ""
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property real value: 0
    property var format: function(v) { return String(Math.round(v)) }
    signal committed(int value)

    width: parent ? parent.width : 0
    spacing: Style.space(4)
    opacity: enabled ? 1 : 0.45

    Item {
      width: parent.width
      implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

      Text {
        id: labelText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: valueSlider.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
      Text {
        id: valueText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: valueSlider.format(Math.round(slider.dragging ? slider.liveValue : valueSlider.value))
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        textFormat: Text.PlainText
      }
    }

    PanelSlider {
      id: slider
      bar: root.bar
      width: parent.width
      enabled: valueSlider.enabled
      minimum: valueSlider.minimum
      maximum: valueSlider.maximum
      step: valueSlider.step
      integer: true
      value: valueSlider.value
      onReleased: function(v) {
        var snapped = Math.round(v / valueSlider.step) * valueSlider.step
        if (snapped !== valueSlider.value) valueSlider.committed(snapped)
      }

      // Above the slider's own MouseArea: takes only the wheel, so clicks and
      // drags still reach the slider and the wheel scrolls the panel.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) { root.scrollBy(wheel) }
      }
    }
  }
}
