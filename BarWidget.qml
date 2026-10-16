import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar icon + popover. The icon is what you're looking at (sun or moon),
// warm-tinted while Night Shift is on. The popover holds the few things you
// might want to change; everything else is decided by the sun.
Panel {
  id: root
  moduleName: "io.github.benjaminsehl.circadian"
  ipcTarget: "io.github.benjaminsehl.circadian"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("io.github.benjaminsehl.circadian") : null
  readonly property var st: svc ? svc.status : ({})
  readonly property bool ready: !!svc && svc.ready
  readonly property string appearance: svc ? svc.appearance : "dark"
  readonly property bool nightShift: svc ? svc.nightShift : false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color warm: Qt.tint(fg, Qt.rgba(1.0, 0.6, 0.22, 0.7))
  readonly property string sun: String.fromCodePoint(0xF05A8)
  readonly property string moon: String.fromCodePoint(0xF0594)

  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : "" }

  function tooltip() {
    if (!ready) return "Circadian"
    var parts = [appearance === "other" ? st.themeName : cap(appearance)]
    if (nightShift) parts.push("Night Shift")
    return parts.join(" · ")
  }

  function themeOptions(mode, current) {
    var list = (svc ? svc.themes : []).filter(function(t) { return t.mode === mode || t.id === current })
    return list.map(function(t) { return { value: t.id, label: t.name } })
  }

  onOpenedChanged: if (opened && svc) { svc.loadThemes(); svc.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.appearance === "light" ? root.sun : root.moon
    foreground: root.nightShift ? root.warm : (root.bar ? root.bar.barForeground : Color.foreground)
    tooltipText: root.opened ? "" : root.tooltip()
    useActiveColor: false
    fontSize: Style.font.caption
    horizontalMargin: 5
    verticalPadding: 5
    fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1
    onPressed: function(b) { if (b === Qt.LeftButton) root.toggle() }

    Behavior on foreground { ColorAnimation { duration: 300 } }
  }

  // Debounce the warmth slider so dragging doesn't queue a hyprctl per pixel.
  property real draggedWarmth: 0
  Timer {
    id: warmthDebounce
    interval: 120
    onTriggered: if (root.svc) root.svc.setWarmth(root.draggedWarmth)
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: where the sun is ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.st.night ? root.moon : root.sun
            color: root.fg
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: !root.ready ? "Circadian" : (root.st.night ? "Night" : "Day")
              color: root.fg
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: !root.ready ? "" : (root.st.nextEvent + " at " + root.st.nextEventAt
                + (root.st.sunSource === "fallback" ? " · estimated" : "")).toUpperCase()
              color: Qt.darker(root.fg, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Appearance ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          SectionHeader {
            text: "APPEARANCE"
            note: root.st.darkAtNight && root.st.appearanceOverride ? "until " + root.st.nextEvent : ""
          }

          Row {
            id: appearanceRow
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: [
                { value: "light", label: "Light", icon: root.sun },
                { value: "dark", label: "Dark", icon: root.moon }
              ]
              Button {
                required property var modelData
                width: (appearanceRow.width - appearanceRow.spacing) / 2
                iconText: modelData.icon
                iconSize: Style.font.title
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.appearance === modelData.value
                onClicked: if (root.svc) root.svc.setAppearance(modelData.value)
              }
            }
          }

          Row {
            id: themeRow
            width: parent.width
            spacing: Style.space(6)

            Dropdown {
              width: (themeRow.width - themeRow.spacing) / 2
              label: "BY DAY"
              value: root.st.lightTheme || ""
              options: root.themeOptions("light", root.st.lightTheme)
              foreground: root.fg
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onChanged: function(v) { if (root.svc) root.svc.setOption("lightTheme", v) }
            }

            Dropdown {
              width: (themeRow.width - themeRow.spacing) / 2
              label: "BY NIGHT"
              value: root.st.darkTheme || ""
              options: root.themeOptions("dark", root.st.darkTheme)
              foreground: root.fg
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onChanged: function(v) { if (root.svc) root.svc.setOption("darkTheme", v) }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Night Shift ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(nightShiftHeader.implicitHeight, nightShiftSwitch.implicitHeight)

            SectionHeader {
              id: nightShiftHeader
              anchors.left: parent.left
              anchors.right: nightShiftSwitch.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "NIGHT SHIFT"
              note: root.st.nightShiftAtNight && root.st.nightShiftOverride ? "until " + root.st.nextEvent : ""
            }

            ToggleSwitch {
              id: nightShiftSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.nightShift
              foreground: root.fg
              onToggled: if (root.svc) root.svc.setNightShift(!root.nightShift)
            }
          }

          PanelSlider {
            id: warmthSlider
            width: parent.width
            bar: root.bar
            // Right is warmer: the slider runs over (min+max - kelvin).
            readonly property real lo: root.st.minWarmth || 2500
            readonly property real hi: root.st.maxWarmth || 5500
            minimum: lo
            maximum: hi
            step: 100
            value: lo + hi - (root.svc ? root.svc.warmth : 4000)
            opacity: root.nightShift ? 1 : 0.5
            onMoved: function(v) { root.draggedWarmth = lo + hi - v; warmthDebounce.restart() }
            onReleased: function(v) { warmthDebounce.stop(); if (root.svc) root.svc.setWarmth(lo + hi - v) }
          }

          Item {
            width: parent.width
            implicitHeight: lessWarm.implicitHeight
            Caption { id: lessWarm; anchors.left: parent.left; text: "Less warm" }
            Caption { anchors.right: parent.right; text: "More warm" }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Schedule ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          SectionHeader { text: "SUNSET TO SUNRISE" }

          Toggle {
            width: parent.width
            label: "Dark appearance"
            description: root.st.darkThemeName ? "Switch to " + root.st.darkThemeName : "Choose a theme for night"
            checked: root.st.darkAtNight === true
            foreground: root.fg
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            titleSize: Style.font.bodySmall
            onClicked: if (root.svc) root.svc.setOption("darkAtNight", !(root.st.darkAtNight === true))
          }

          Toggle {
            width: parent.width
            label: "Night Shift"
            description: "Warmer colours after dark"
            checked: root.st.nightShiftAtNight === true
            foreground: root.fg
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            titleSize: Style.font.bodySmall
            onClicked: if (root.svc) root.svc.setOption("nightShiftAtNight", !(root.st.nightShiftAtNight === true))
          }

          Caption {
            visible: root.ready
            text: "Sunrise " + root.st.sunrise + " · Sunset " + root.st.sunset
              + (root.st.sunSource === "fallback" ? " · estimated, offline" : "")
          }
        }
      }
    }
  }

  component SectionHeader: Item {
    property string text: ""
    property string note: ""
    width: parent ? parent.width : 0
    implicitHeight: headerText.implicitHeight

    PanelSectionHeader {
      id: headerText
      anchors.left: parent.left
      text: parent.text
      foreground: root.fg
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    }

    Text {
      anchors.right: parent.right
      anchors.baseline: headerText.baseline
      visible: parent.note !== ""
      text: parent.note.toUpperCase()
      color: root.fg
      opacity: 0.5
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.2
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.fg
    opacity: 0.6
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }
}
