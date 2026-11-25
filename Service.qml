import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Schedule.js" as Schedule

// Night light service (replaces omarchy.nightlight via `omarchy plugin clone`).
//
// Owns hyprsunset: every couple of seconds it works out what the screen should
// be from the user's schedule and applies it. Settings live in
// ~/.config/omarchy/nightlight.json and are edited from the bar panel
// (Panel.qml) or by hand; the file is watched, so hand edits apply live.
//
// `enabled` (what the bar indicator and menu show) means "the schedule is on".
// Off means no tint at all.
Item {
  id: root

  // Injected by omarchy-shell (the service loader).
  property var shell: null

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/nightlight.json"

  readonly property int minTemperature: Schedule.MIN_TEMP
  readonly property int maxTemperature: Schedule.MAX_TEMP
  readonly property int neutralTemperature: Schedule.NEUTRAL_TEMP

  // ---- persisted settings ----
  property bool configLoaded: false
  property bool scheduleEnabled: true
  property var points: []
  property var override: null         // { temp, until: ms | null(=until changed) } or null

  // ---- live state ----
  property double now: Date.now()
  readonly property bool stateLoaded: configLoaded
  readonly property bool enabled: configLoaded && scheduleEnabled
  // Manual tint: with the schedule on it lasts until the next point; with
  // the schedule off it stays until changed (until === null).
  readonly property bool overrideActive: configLoaded && override !== null
    && (override.until === null ? !scheduleEnabled : (scheduleEnabled && override.until > now))
  readonly property int scheduledTemperature: Schedule.temperatureAt(points, Schedule.minutesOfDay(new Date(now)))
  readonly property int targetTemperature: overrideActive ? override.temp
    : (enabled ? scheduledTemperature : neutralTemperature)
  readonly property var upcoming: Schedule.upcoming(points, Schedule.minutesOfDay(new Date(now)))
  property var temperature: null       // last value applied to hyprsunset
  property int appliedTemperature: -1

  // ---------------- settings API (used by Panel.qml) ----------------

  function setNightlight(value) { setEnabled(!!value) }
  function toggle() { setEnabled(!enabled) }

  // Switching either way hands control to the new mode: the schedule, or no tint.
  function setEnabled(value) {
    scheduleEnabled = !!value
    override = null
    saveSoon()
    tick()
  }

  // Manual tint: until the next schedule point, or (schedule off) until changed.
  function setOverride(temp) {
    override = {
      temp: Schedule.clampTemp(temp),
      until: scheduleEnabled ? Schedule.nextPointMs(points, Date.now()) : null
    }
    saveSoon()
    tick()
  }

  function clearOverride() {
    override = null
    saveSoon()
    tick()
  }

  function setPoints(list) {
    points = Schedule.normalizePoints(list)
    // A changed schedule supersedes a manual tint
    override = null
    saveSoon()
    tick()
  }

  function updatePoint(index, patch) {
    if (index < 0 || index >= points.length) return false
    var next = points.slice()
    var p = Object.assign({}, next[index], patch)
    if (patch.time !== undefined && Schedule.parseTime(patch.time) < 0) return false
    next[index] = p
    setPoints(next)
    return true
  }

  function addPoint() {
    var next = points.slice()
    next.push(Schedule.suggestPoint(points))
    setPoints(next)
  }

  function removePoint(index) {
    if (index < 0 || index >= points.length) return
    var next = points.slice()
    next.splice(index, 1)
    setPoints(next)
  }

  function resetDefaults() {
    var d = Schedule.defaultConfig()
    scheduleEnabled = d.enabled
    setPoints(d.points)
  }

  // ---------------- warm accents ----------------
  // Orange accents whenever the screen is tinted (below 6500K), whatever set
  // the tint: the schedule or the slider, with the schedule on or off.
  // At 6500K ("No tint") the theme's colours (warm-accents.sh).
  readonly property string accentScript: Qt.resolvedUrl("warm-accents.sh").toString().replace("file://", "")
  property string accentState: ""
  readonly property bool accentsWarm: targetTemperature < neutralTemperature
  onAccentsWarmChanged: syncAccents()
  function syncAccents() {
    if (!configLoaded) return
    var want = accentsWarm ? "on" : "off"
    if (want === accentState) return
    accentState = want
    if (accentProcess.running) { accentPending = true; return }
    accentProcess.command = ["bash", accentScript, want]
    accentProcess.running = true
  }
  property bool accentPending: false
  Process {
    id: accentProcess
    onExited: function() {
      if (!root.accentPending) return
      root.accentPending = false
      command = ["bash", root.accentScript, root.accentState]
      running = true
    }
  }

  function refresh() {
    // External callers (omarchy-toggle-nightlight, menu) ask for a refresh;
    // force a re-check of what hyprsunset actually shows.
    appliedTemperature = -1
    tick()
  }

  // ---------------- persistence ----------------

  function applyConfig(raw) {
    var c = Schedule.normalizeConfig(raw)
    scheduleEnabled = c.enabled
    points = c.points
    override = c.override
    configLoaded = true
    syncAccents()
    tick()
  }

  function serialise() {
    return JSON.stringify({
      version: 1,
      enabled: scheduleEnabled,
      points: points,
      override: override
    }, null, 2) + "\n"
  }

  property string lastWritten: ""

  function saveSoon() { saveTimer.restart() }

  function saveNow() {
    var text = serialise()
    if (text === lastWritten) return
    lastWritten = text
    configFile.setText(text)
  }

  Timer { id: saveTimer; interval: 400; onTriggered: root.saveNow() }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var t = text()
      if (t === root.lastWritten && root.configLoaded) return
      var parsed = null
      try { parsed = JSON.parse(t) } catch (e) { parsed = null }
      if (parsed === null) {
        // Unreadable file: keep what we have (or defaults) and don't clobber it
        if (!root.configLoaded) root.applyConfig(null)
        return
      }
      root.lastWritten = t
      root.applyConfig(parsed)
    }
    onLoadFailed: function(error) {
      // No file yet: start from the defaults and create it
      if (!root.configLoaded) root.applyConfig(null)
      root.saveNow()
    }
    onFileChanged: reload()
  }

  // ---------------- engine ----------------

  property int driftCounter: 0

  function tick() {
    now = Date.now()
    if (!configLoaded) return
    if (override !== null && override.until !== null && override.until <= now) {
      override = null
      saveSoon()
    }
    var target = targetTemperature
    if (target !== appliedTemperature) {
      apply(target)
    } else if (++driftCounter >= 5) {
      // Every ~10 s: make sure nothing else (hyprsunset restart, the stock
      // toggle command) changed the screen behind our back
      driftCounter = 0
      if (!probe.running && !applyProcess.running) probe.running = true
    }
  }

  property int pendingTemperature: -1

  function apply(temp) {
    appliedTemperature = temp
    if (applyProcess.running) { pendingTemperature = temp; return }
    runApply(temp)
  }

  function runApply(temp) {
    var t = Number(temp)
    // 6500K is "no tint": hyprsunset still tints slightly at 6500, so also
    // restore the identity matrix (same as Omarchy's off state).
    var set = t >= root.neutralTemperature
      ? "hyprctl hyprsunset temperature " + root.neutralTemperature + " >/dev/null && hyprctl hyprsunset identity >/dev/null"
      : "hyprctl hyprsunset temperature " + t + " >/dev/null"
    applyProcess.command = ["bash", "-c",
      "pgrep -x hyprsunset >/dev/null || { setsid uwsm-app -- hyprsunset >/dev/null 2>&1 & sleep 2; }; " + set]
    applyProcess.running = true
    root.temperature = t
  }

  Process {
    id: applyProcess
    onExited: function() {
      if (root.pendingTemperature >= 0) {
        var t = root.pendingTemperature
        root.pendingTemperature = -1
        root.runApply(t)
      }
    }
  }

  Process {
    id: probe
    command: ["hyprctl", "hyprsunset", "temperature"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = String(text).match(/[0-9]+/)
        var reported = m ? Number(m[0]) : -1
        var expected = Math.min(root.appliedTemperature, root.neutralTemperature)
        if (reported !== expected) root.appliedTemperature = -1   // re-apply next tick
      }
    }
    onExited: function(code) { if (code !== 0) root.appliedTemperature = -1 }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.tick()
  }

  ShellIpc {
    target: "nightlight"

    function status(): string {
      return JSON.stringify({
        enabled: root.enabled,
        temperature: root.temperature,
        scheduled: root.scheduledTemperature,
        override: root.overrideActive ? root.override : null
      })
    }

    function refresh(): void { root.refresh() }

    function enable(): string { root.setEnabled(true); return "enabled" }
    function disable(): string { root.setEnabled(false); return "disabled" }

    function toggle(): string {
      var enabling = !root.enabled
      root.setEnabled(enabling)
      return enabling ? "enabled" : "disabled"
    }

    // Manual tint until the next schedule point: `omarchy-shell nightlight set 3000`
    function set(kelvin: string): string {
      root.setOverride(Number(kelvin))
      return String(root.override.temp)
    }

    function resume(): string { root.clearOverride(); return "schedule" }
  }
}
