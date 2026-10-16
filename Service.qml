import QtQuick
import Quickshell
import Quickshell.Io

// Circadian's one long-lived instance. bin/circadian owns all state and
// decisions; this keeps a copy of its status for the bar widgets, runs
// `apply` once a minute so the sun is followed, and serialises changes.
//
// Changes are optimistic: `appearance`/`nightShift` reflect a click at once
// and settle when the engine reports back.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string engine: String(Qt.resolvedUrl("bin/circadian")).replace(/^file:\/\//, "")

  property var status: ({})
  property var themes: []
  readonly property bool ready: status.appearance !== undefined

  property string pendingAppearance: ""
  property var pendingNightShift: null
  property var pendingWarmth: null

  readonly property string appearance: pendingAppearance !== "" ? pendingAppearance : (status.appearance || "dark")
  readonly property bool nightShift: pendingNightShift !== null ? pendingNightShift === true : status.nightShift === true
  readonly property int warmth: pendingWarmth !== null ? pendingWarmth : (status.warmth || 4000)

  // --- actions ---------------------------------------------------------------

  function setAppearance(value) {
    pendingAppearance = value
    queueAction("appearance", ["appearance", value])
  }

  function toggleAppearance() {
    setAppearance(appearance === "light" ? "dark" : "light")
  }

  function setNightShift(on) {
    pendingNightShift = on
    queueAction("nightshift", ["nightshift", on ? "on" : "off"])
  }

  function setWarmth(kelvin) {
    pendingWarmth = Math.round(kelvin)
    queueAction("warmth", ["set", "warmth", String(pendingWarmth)])
  }

  function setOption(key, value) {
    var next = Object.assign({}, status)
    next[key] = value
    status = next
    queueAction("set:" + key, ["set", key, typeof value === "boolean" ? (value ? "on" : "off") : String(value)])
  }

  function refresh() {
    if (poll.running) { pollAgain = true; return }
    pollGen = actionGen
    poll.command = [root.engine, "apply", "--json"]
    poll.running = true
  }

  function loadThemes() {
    if (!themesProc.running) themesProc.running = true
  }

  // --- plumbing --------------------------------------------------------------

  // Latest wins per key, so a burst of clicks or a dragged slider sends only
  // what's needed.
  property var queue: []
  property int actionGen: 0
  property int pollGen: 0
  property bool pollAgain: false

  function queueAction(key, args) {
    var next = queue.filter(function(item) { return item.key !== key })
    next.push({ key: key, args: args })
    queue = next
    pump()
  }

  function pump() {
    if (action.running || queue.length === 0) return
    var item = queue[0]
    queue = queue.slice(1)
    action.command = [root.engine].concat(item.args)
    action.running = true
  }

  function settled() {
    return !action.running && queue.length === 0 && pollGen === actionGen
  }

  Process {
    id: action
    environment: ({ CIRCADIAN_FROM_SHELL: "1" })
    onExited: {
      if (root.queue.length > 0) { root.pump(); return }
      root.actionGen++
      root.refresh()
    }
  }

  Process {
    id: poll
    environment: ({ CIRCADIAN_FROM_SHELL: "1" })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(String(text || "").trim().split("\n").pop()) } catch (e) {}
        if (!parsed || parsed.appearance === undefined) return
        root.status = parsed
        if (root.settled()) {
          root.pendingAppearance = ""
          root.pendingNightShift = null
          root.pendingWarmth = null
        }
      }
    }
    onExited: {
      if (root.pollAgain) { root.pollAgain = false; root.refresh() }
    }
  }

  Process {
    id: themesProc
    command: [root.engine, "themes"]
    environment: ({ CIRCADIAN_FROM_SHELL: "1" })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.themes = JSON.parse(String(text || "[]")) } catch (e) {}
      }
    }
  }

  // Follow changes made elsewhere: the theme switcher, the CLI, a config edit.
  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); debounce.restart() }
  }

  FileView {
    path: root.home + "/.config/circadian/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); debounce.restart() }
  }

  Timer {
    id: debounce
    interval: 250
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()

  // `circadian ...` from a terminal or keybinding pings this to refresh;
  // keybindings can also drive it directly:
  //   omarchy-shell circadian toggleAppearance
  IpcHandler {
    target: "circadian"

    function refresh(): void { root.refresh() }
    function toggleAppearance(): void { root.toggleAppearance() }
    function toggleNightShift(): void { root.setNightShift(!root.nightShift) }
    function status(): string { return JSON.stringify(root.status) }
  }
}
