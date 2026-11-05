import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// Tablet state for one bar entry. `s620-pad watch` stays running for the
// express keys; each key press becomes a shortcut sent through Hyprland. The
// pen settings live in Hyprland's config, which a reload wipes, so they are
// sent again on every reload and monitor change.
Item {
  id: root

  property var tablet: ({ connection: "starting" })
  property var profile: Model.normalizeProfile(null)
  property var monitors: []
  property string lastError: ""
  // The settings of each express key while it is held, null when it is up.
  // The release goes to the shortcut the press sent, even if the key's action
  // changed in between.
  property var heldKeys: Model.emptyKeys()
  // Hyprland hands the pressure range to the pen only when the tablet shows
  // up, so a change made while it is plugged in waits for the next plug-in.
  property bool pressureNeedsReplug: false

  readonly property string helperPath: String(Qt.resolvedUrl("s620-pad")).replace(/^file:\/\//, "")
  readonly property string profilePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/gaomon-s620/profile.json"

  // True once a profile file exists. Until then the plugin leaves Hyprland's
  // tablet settings alone, including any the user wrote in the config.
  property bool _hasProfile: false
  property bool _saveAgain: false
  property bool _monitorsAgain: false
  property bool _otdAgain: false
  property bool _otdJobRunning: false
  // Bumped on every backend change; OTD work from an older generation is dropped.
  property int _backendGeneration: 0
  property int _otdReadGeneration: 0
  property var _queue: []

  // `path` is a profile field ("rotation") or a key field ("keys.2.action").
  function set(path, value) {
    root.commit(Model.withValue(root.profile, path, value, root.monitors))
  }

  function resetDefaults() {
    root.commit(Model.normalizeProfile(null, root.monitors))
  }

  function commit(next) {
    if (JSON.stringify(next) === JSON.stringify(root.profile) && root._hasProfile) return
    if (Model.pressureChanged(root.profile, next) && Model.tabletPresent(root.tablet)) root.pressureNeedsReplug = true
    if (!next.keysEnabled) root.releaseKeys()
    // Focus is only tracked while the output is "current"; read it afresh
    // when it becomes so, for the crop and the "next monitor" key.
    var toCurrent = next.output === "current" && root.profile.output !== "current"
    root.profile = next
    root._hasProfile = true
    root.save()
    root.applyDevice()
    if (toCurrent) root.refreshMonitors()
  }

  // One save at a time; a change made during a save is written right after it,
  // so the file always ends with the newest profile.
  function save() {
    if (saveProcess.running) {
      root._saveAgain = true
      return
    }
    root._saveAgain = false
    saveProcess.command = [root.helperPath, "save", JSON.stringify(root.profile)]
    saveProcess.running = true
  }

  // The kernel backend takes the Hyprland Lua; on OTD the running settings
  // are read first, patched by the model and applied back through the
  // helper, so a stale file can never reset the daemon's other settings.
  function applyDevice() {
    var backend = Model.backendOf(root.tablet)
    // On OTD the express key bindings go out even before the first profile
    // exists; without them the virtual pad never appears.
    if (backend === "otd") {
      root.otdRead()
      return
    }
    if (!root._hasProfile) return
    root.run(["hyprctl", "eval", Model.applyPlan(root.profile, root.monitors, backend).lua])
  }

  // The OTD cycle is serialized like the command queue: a read never starts
  // while an apply is queued or in flight, and queued OTD work is dropped
  // once the backend is no longer OTD.
  function otdPending() {
    if (root._otdJobRunning) return true
    for (var i = 0; i < root._queue.length; i++) if (root._queue[i].otd) return true
    return false
  }

  function otdRead() {
    if (otdProcess.running || root.otdPending()) {
      root._otdAgain = true
      return
    }
    root._otdAgain = false
    root._otdReadGeneration = root._backendGeneration
    otdProcess.running = true
  }

  function refreshMonitors() {
    if (monitorsProcess.running) {
      root._monitorsAgain = true
      return
    }
    root._monitorsAgain = false
    monitorsProcess.running = true
  }

  // Commands run one at a time, in order, so a quick tap never sends the key
  // release before the press. `otd` marks OTD work: it goes stale when the
  // backend changes before it runs, even if it changes back.
  function run(argv, otd) {
    root._queue = root._queue.concat([{ argv: argv, otd: otd === true, generation: root._backendGeneration }])
    root.flush()
  }

  function flush() {
    if (runProcess.running || root._queue.length === 0) return
    var job = root._queue[0]
    root._queue = root._queue.slice(1)
    if (job.otd && (Model.backendOf(root.tablet) !== "otd" || job.generation !== root._backendGeneration)) {
      root.flush()
      return
    }
    root._otdJobRunning = job.otd
    runProcess.command = job.argv
    runProcess.running = true
  }

  function runJobs(jobs) {
    for (var i = 0; i < jobs.length; i++) {
      if (jobs[i].detached) Quickshell.execDetached(jobs[i].argv)
      else root.run(jobs[i].argv)
    }
  }

  function onWatchLine(line) {
    var wasPresent = Model.tabletPresent(root.tablet)
    var wasMissing = root.tablet.connection === "missing"
    var backend = Model.backendOf(root.tablet)
    root.tablet = Model.applyLine(root.tablet, line)
    // A backend switch keeps the profile and reapplies it the new way.
    if (Model.backendOf(root.tablet) !== backend) {
      root._backendGeneration++
      root.applyDevice()
    }
    // Only a real plug-in clears the notice, not the helper starting again.
    if (wasMissing && Model.tabletPresent(root.tablet)) root.pressureNeedsReplug = false
    if (wasPresent && root.tablet.connection !== "ready") root.releaseKeys()
    var key = Model.keyEvent(line)
    if (key === null) return
    // Keys switched off still light the panel's dots, so a test can see them.
    var held = root.heldKeys.slice()
    var settings = key.pressed ? (root.profile.keysEnabled ? root.profile.keys[key.index] : { action: "none", text: "" }) : held[key.index]
    held[key.index] = key.pressed ? settings : null
    root.heldKeys = held
    if (settings) root.runJobs(Model.keyCommands(settings, key.pressed, root.profile.keys))
    // Profile keys change the profile instead of sending input.
    if (key.pressed) {
      var next = Model.keyProfile(settings, root.profile, root.monitors, Model.backendOf(root.tablet))
      if (next !== null) root.commit(next)
    }
  }

  // A tablet unplugged or a helper gone with a key down never sends its
  // release; send the release matching each recorded press.
  function releaseKeys() {
    for (var i = 0; i < root.heldKeys.length; i++) {
      if (root.heldKeys[i]) root.runJobs(Model.keyCommands(root.heldKeys[i], false, root.profile.keys))
    }
    root.heldKeys = Model.emptyKeys()
  }

  function loadProfile(text) {
    root.profile = Model.normalizeProfile(Model.parseJson(text), root.monitors)
    root._hasProfile = true
    root.applyDevice()
  }

  Component.onCompleted: root.refreshMonitors()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "configreloaded") {
        root.applyDevice()
        // A reload can change a monitor's scale or resolution too.
        root.refreshMonitors()
      } else if (name.indexOf("monitoradded") === 0 || name.indexOf("monitorremoved") === 0) {
        root.refreshMonitors()
      } else if (name === "focusedmon" && root.profile.output === "current") {
        // "Focused monitor" follows focus: the crop and the "next monitor"
        // express key both read which monitor is focused.
        root.refreshMonitors()
      }
    }
  }

  FileView {
    id: profileFile
    path: root.profilePath
    watchChanges: true
    printErrors: false
    // A write of ours in flight would load an older profile over a newer one.
    onLoaded: if (!saveProcess.running && !root._saveAgain) root.loadProfile(text())
    // No file yet: nothing was set from the panel. The keys get their default
    // actions, and Hyprland keeps its own tablet settings.
    onLoadFailed: root.profile = Model.normalizeProfile(null, root.monitors)
    onFileChanged: reload()
  }

  Process {
    id: watchProcess
    command: [root.helperPath, "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.onWatchLine(line) }
    }
    // The helper retries on its own; it only exits on a crash. Let go of any
    // held key, then start it again after a pause instead of spinning.
    onExited: function(exitCode) {
      root.releaseKeys()
      root.tablet = Model.applyLine(root.tablet, "")
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 5000
    onTriggered: watchProcess.running = true
  }

  Process {
    id: monitorsProcess
    running: false
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector { id: monitorsStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var monitors = Model.parseMonitors(monitorsStdout.text)
      if (JSON.stringify(monitors) !== JSON.stringify(root.monitors)) {
        root.monitors = monitors
        root.applyDevice()
      }
      if (root._monitorsAgain) root.refreshMonitors()
    }
  }

  Process {
    id: otdProcess
    running: false
    command: [root.helperPath, "otd-read"]
    stdout: StdioCollector { id: otdStdout; waitForEnd: true }
    onExited: function(exitCode) {
      // The read is stale if the backend changed while it ran; the
      // backend-change path already queued a fresh apply.
      var current = Model.backendOf(root.tablet) === "otd" && root._otdReadGeneration === root._backendGeneration
      if (current && exitCode === 0) {
        var plan = Model.applyPlan(root.profile, root.monitors, "otd", otdStdout.text, !root._hasProfile)
        if (plan.changed) root.run([root.helperPath, "otd-apply", JSON.stringify(plan.document)], true)
        if (plan.lua !== null && plan.lua !== undefined) root.run(["hyprctl", "eval", plan.lua])
        if (plan.note !== "") root.lastError = plan.note
      } else if (current) {
        root.lastError = "OpenTabletDriver did not answer; is the daemon running?"
      }
      if (root._otdAgain) root.applyDevice()
    }
  }

  Process {
    id: runProcess
    running: false
    command: []
    stdout: StdioCollector { id: runStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(runStdout.text || "").trim()
      root.lastError = exitCode === 0 && (out === "" || out === "ok") ? "" : "Hyprland refused the change: " + out
      root._otdJobRunning = false
      root.flush()
      // An OTD read deferred while an apply ran starts once the queue drains.
      if (root._otdAgain && !runProcess.running && root._queue.length === 0
          && Model.backendOf(root.tablet) === "otd") root.applyDevice()
    }
  }

  Process {
    id: saveProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (root._saveAgain) root.save()
    }
  }
}
