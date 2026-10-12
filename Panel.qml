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

  property var queue: ({ direct: [], team: [], drafts: [], today: 0, history: [], notify: { mode: "all", until: 0 } })
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

  readonly property int total: queue.direct.length + queue.team.length
  readonly property bool createdSort: sortBy === "Newest PR" || sortBy === "Oldest PR"
  readonly property string notifyMode: queue.notify.mode
  readonly property var tabs: [
    { label: "Direct", list: queue.direct },
    { label: "Team", list: queue.team },
    { label: "Drafts", list: queue.drafts }
  ]
  readonly property var rows: sorted(tabs[tab].list)
  readonly property var shownHistory: queue.history.slice(-historyDays)
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
    fetchProc.command = ["bash", script]
    fetchProc.running = true
  }

  function setNotify(mode, minutes) {
    notifyProc.command = ["bash", script, "set-notify", mode, String(minutes || 0)]
    notifyProc.running = true
  }

  function cycleMode() {
    setNotify(notifyMode === "all" ? "direct" : notifyMode === "direct" ? "off" : "all", 0)
  }

  function cycleTimer() {
    var steps = [0, 30, 60, 240, 480]
    var left = queue.notify.until > 0 ? Math.round((queue.notify.until - Date.now() / 1000) / 60) : 0
    var cur = 0
    for (var i = steps.length - 1; i > 0; i--) if (left > steps[i] - 15) { cur = i; break }
    setNotify(notifyMode, steps[(cur + 1) % steps.length])
  }

  function timerLabel() {
    if (queue.notify.until <= 0) return "until I change it"
    var m = Math.max(1, Math.round((queue.notify.until - Date.now() / 1000) / 60))
    return m >= 60 ? "~" + Math.round(m / 60) + "h left" : m + "m left"
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
        root.queue = JSON.parse(root._out)
        root.lastError = ""
        root.loaded = true
      } catch (e) { root.lastError = "bad response" }
    }
  }

  Process {
    id: notifyProc
    onExited: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰊤 " + (root.loaded ? root.total : "…") + (root.notifyMode === "off" ? " 󰂛" : "")
    active: root.lastError !== "" || root.notifyMode !== "all"
    tooltipText: root.lastError !== "" ? root.lastError
                 : root.queue.direct.length + " direct + " + root.queue.team.length + " team awaiting your review"
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
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "1" || t === "2" || t === "3") { root.showHistory = false; root.tab = parseInt(t) - 1 }
        else if (t === "h" || t === "H") root.showHistory = !root.showHistory
      }

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
                text: "󰍡 " + root.queue.today
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

          // Footer: notification mode, optional lapse timer, refresh
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            CursorSurface {
              foreground: root.foreground
              hasCursor: bellMa.containsMouse
              implicitWidth: bellText.implicitWidth + Style.space(20)
              implicitHeight: bellText.implicitHeight + Style.spacing.rowPaddingX
              MouseArea {
                id: bellMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleMode()
              }
              Text {
                id: bellText
                anchors.centerIn: parent
                text: (root.notifyMode === "off" ? "󰂛 Off" : "󰂚 " + (root.notifyMode === "direct" ? "Only direct" : "All"))
                color: root.notifyMode === "all" ? root.foreground : "orange"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            CursorSurface {
              visible: root.notifyMode !== "all"
              foreground: root.foreground
              hasCursor: timerMa.containsMouse
              implicitWidth: timerText.implicitWidth + Style.space(20)
              implicitHeight: timerText.implicitHeight + Style.spacing.rowPaddingX
              MouseArea {
                id: timerMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleTimer()
              }
              Text {
                id: timerText
                anchors.centerIn: parent
                text: root.timerLabel()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.lastError !== "" ? root.lastError : "r refresh · 1-3 tabs · h history"
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
