import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mtib.prbar"
  ipcTarget: "mtib.prbar"
  manageIpc: false

  property var prState: ({ direct: [], team: [], drafts: [], today: 0, history: [], notify: { mode: "all", until: 0 } })
  property string lastError: ""
  property bool loaded: false
  property string _out: ""
  property int tab: 0            // 0 direct, 1 team, 2 drafts
  property bool showHistory: false
  property int historyDays: 7

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int refreshIntervalSec: Math.max(60, parseInt(String(setting("refreshIntervalSec", 60)), 10) || 60)
  readonly property string sortBy: String(setting("sortBy", "Recent activity"))
  readonly property string script: Quickshell.env("HOME") + "/.config/omarchy/plugins/mtib.prbar/fetch.sh"

  readonly property int total: prState.direct.length + prState.team.length
  readonly property bool createdSort: sortBy === "Newest PR" || sortBy === "Oldest PR"
  property var notify: ({ mode: "all", until: 0, minutes: 0 })
  property real notifyChangedAt: 0
  property real fetchStartedAt: 0
  readonly property string notifyMode: notify.mode
  readonly property var tabs: [
    { label: "Direct", list: prState.direct },
    { label: "Team", list: prState.team },
    { label: "Drafts", list: prState.drafts }
  ]
  readonly property var rows: sorted(tabs[tab].list)
  readonly property var shownHistory: prState.history.slice(-historyDays)
  readonly property int historyMax: Math.max(1, Math.max.apply(null, shownHistory.map(function(d) { return d.count })))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function sorted(list) {
    var key = createdSort ? "createdAt" : "updatedAt"
    var dir = (sortBy === "Least recent activity" || sortBy === "Oldest PR") ? 1 : -1
    return list.slice().sort(function(a, b) { return dir * (new Date(a[key]) - new Date(b[key])) })
  }

  function refresh() {
    if (fetchProc.running) return
    _out = ""
    fetchStartedAt = Date.now()
    fetchProc.command = ["bash", script]
    fetchProc.running = true
  }

  function setNotify(mode, minutes) {
    // Persist via a detached script, apply locally right away.
    notifyChangedAt = Date.now()
    notify = { mode: mode, until: (mode !== "all" && minutes > 0) ? Date.now() / 1000 + minutes * 60 : 0,
               minutes: mode !== "all" ? minutes : 0 }
    Quickshell.execDetached(["bash", script, "set-notify", mode, String(minutes || 0)])
  }

  property real nowSec: Date.now() / 1000
  function remaining() {
    var m = Math.max(1, Math.ceil((notify.until - nowSec) / 60))
    return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m"
  }

  function toggle() { if (root.opened) root.close(); else { root.open(); root.refresh() } }
  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function openPr(pr) {
    if (!pr || !pr.url) return
    Quickshell.execDetached(["omarchy-launch-browser", String(pr.url)])
    root.close()
  }

  function age(iso) {
    var s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Timer {
    interval: 15000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowSec = Date.now() / 1000
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._out = text }
    onExited: function(code) {
      if (code !== 0) { root.lastError = "gh query failed (is `gh auth login` done?)"; return }
      try {
        root.prState = JSON.parse(root._out)
        // Ignore prefs from a fetch that began before the user's last change.
        if (root.fetchStartedAt >= root.notifyChangedAt) {
          var n = root.prState.notify
          var left = n.until > 0 ? (n.until - Date.now() / 1000) / 60 : 0
          var steps = [30, 60, 240, 480], m = 0
          for (var k = 0; k < steps.length; k++) if (left > 0 && left <= steps[k] + 1) { m = steps[k]; break }
          root.notify = { mode: n.mode, until: n.until, minutes: n.until > 0 ? m : 0 }
        }
        root.lastError = ""
        root.loaded = true
      } catch (e) { root.lastError = "bad response" }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰊤 " + (root.loaded ? root.total : "…") + (root.notifyMode === "off" ? " 󰂛" : "")
    active: root.lastError !== "" || root.notifyMode !== "all"
    tooltipText: root.lastError !== "" ? root.lastError
                 : root.prState.direct.length + " direct + " + root.prState.team.length + " team awaiting your review"
    onPressed: function(b) {
      if (b === Qt.RightButton || b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(8)

          // Tabs + reviewed-today chip
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.tabs
              CursorSurface {
                id: tabItem
                required property var modelData
                required property int index
                Layout.fillWidth: true
                foreground: root.foreground
                hasCursor: tabMa.containsMouse || (!root.showHistory && root.tab === index)
                implicitHeight: tabText.implicitHeight + Style.spacing.rowPaddingX
                MouseArea {
                  id: tabMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.showHistory = false; root.tab = tabItem.index }
                }
                Text {
                  id: tabText
                  anchors.centerIn: parent
                  text: tabItem.modelData.label + " " + tabItem.modelData.list.length
                  color: !root.showHistory && root.tab === tabItem.index ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            CursorSurface {
              foreground: root.foreground
              hasCursor: chipMa.containsMouse || root.showHistory
              implicitWidth: chipText.implicitWidth + Style.space(20)
              implicitHeight: chipText.implicitHeight + Style.spacing.rowPaddingX
              MouseArea {
                id: chipMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showHistory = !root.showHistory
              }
              Text {
                id: chipText
                anchors.centerIn: parent
                text: "󰍡 " + root.prState.today
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Text {
            visible: !root.showHistory && root.rows.length === 0
            width: parent.width
            text: root.lastError !== "" ? root.lastError : "Nothing here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          // PR list
          Repeater {
            model: root.showHistory ? [] : root.rows
            CursorSurface {
              id: row
              required property var modelData
              width: column.width
              foreground: root.foreground
              hasCursor: ma.containsMouse
              implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

              MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openPr(row.modelData)
              }

              ColumnLayout {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(1)

                Text {
                  textFormat: Text.PlainText
                  Layout.fillWidth: true
                  text: row.modelData.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                Text {
                  textFormat: Text.PlainText
                  Layout.fillWidth: true
                  text: row.modelData.repo.split("/")[1] + " #" + row.modelData.number
                        + " · " + row.modelData.author + " · "
                        + root.age(root.createdSort ? row.modelData.createdAt : row.modelData.updatedAt)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          // Review history histogram
          Column {
            visible: root.showHistory
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "PRS YOU REVIEWED · LAST " + root.historyDays + " DAYS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              spacing: Style.space(8)
              Repeater {
                model: [7, 30]
                CursorSurface {
                  id: rangeItem
                  required property int modelData
                  foreground: root.foreground
                  hasCursor: rangeMa.containsMouse || root.historyDays === modelData
                  implicitWidth: rangeText.implicitWidth + Style.space(20)
                  implicitHeight: rangeText.implicitHeight + Style.spacing.rowPaddingX
                  MouseArea {
                    id: rangeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.historyDays = rangeItem.modelData
                  }
                  Text {
                    id: rangeText
                    anchors.centerIn: parent
                    text: rangeItem.modelData + " days"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Row {
              id: bars
              width: parent.width
              height: Style.space(130)
              spacing: Math.max(1, Style.space(root.historyDays === 7 ? 6 : 2))
              Repeater {
                model: root.shownHistory
                Item {
                  required property var modelData
                  width: (bars.width - bars.spacing * (root.shownHistory.length - 1)) / root.shownHistory.length
                  height: bars.height
                  Text {
                    visible: root.historyDays === 7 && parent.modelData.count > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: bar.top
                    text: parent.modelData.count
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Rectangle {
                    id: bar
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(parent.modelData.count > 0 ? 2 : 1,
                                     (parent.height - Style.space(16)) * parent.modelData.count / root.historyMax)
                    radius: 2
                    color: parent.modelData.count > 0 ? root.foreground : root.dim
                    opacity: parent.modelData.count > 0 ? 0.9 : 0.25
                  }
                }
              }
            }

            RowLayout {
              width: parent.width
              Text {
                text: root.shownHistory.length ? root.shownHistory[0].day : ""
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.shownHistory.length ? root.shownHistory[root.shownHistory.length - 1].day : ""
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
            }
          }

          // Footer: explicit notification mode + lapse timer. State is applied
          // locally at once; the script only persists it.
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              spacing: Style.space(6)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notify"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Repeater {
                model: [
                  { mode: "all", label: "All" },
                  { mode: "direct", label: "Only direct" },
                  { mode: "off", label: "Off" }
                ]
                CursorSurface {
                  id: modeItem
                  required property var modelData
                  foreground: root.foreground
                  hasCursor: modeMa.containsMouse || root.notifyMode === modelData.mode
                  implicitWidth: modeText.implicitWidth + Style.space(20)
                  implicitHeight: modeText.implicitHeight + Style.spacing.rowPaddingX
                  MouseArea {
                    id: modeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setNotify(modeItem.modelData.mode, 0)
                  }
                  Text {
                    id: modeText
                    anchors.centerIn: parent
                    text: modeItem.modelData.label
                    color: root.notifyMode === modeItem.modelData.mode && modeItem.modelData.mode !== "all" ? "orange" : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Quiet mode without a timer: offer durations. With a timer: show it.
              Repeater {
                model: root.notifyMode !== "all" && root.notify.until <= 0
                       ? [ { minutes: 30, label: "30m" }, { minutes: 60, label: "1h" },
                           { minutes: 240, label: "4h" }, { minutes: 480, label: "8h" } ]
                       : []
                CursorSurface {
                  id: timerItem
                  required property var modelData
                  foreground: root.foreground
                  hasCursor: timerMa.containsMouse
                  implicitWidth: timerText.implicitWidth + Style.space(14)
                  implicitHeight: timerText.implicitHeight + Style.spacing.rowPaddingX
                  MouseArea {
                    id: timerMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setNotify(root.notifyMode, timerItem.modelData.minutes)
                  }
                  Text {
                    id: timerText
                    anchors.centerIn: parent
                    text: timerItem.modelData.label
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Text {
                visible: root.notifyMode !== "all" && root.notify.until > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "back to All in " + root.remaining()
                color: "orange"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: root.lastError !== ""
              width: parent.width
              text: root.lastError
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
