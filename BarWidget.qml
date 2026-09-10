import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// TMail for the Omarchy bar.
//
// Shows the unread count from the TMail desktop client (which exposes a small
// local HTTP API on 127.0.0.1). Left click opens a popup with the latest unread
// messages, middle click brings TMail to the front (or launches it), right
// click opens a new message. Nothing leaves the machine: the token is read from
// TMail's own settings file and every request goes to localhost.
//
// The token is never placed in a command line: curl reads it as a config file
// from its stdin (`-K -`), so it is not visible through /proc or `ps`.
BarWidget {
  id: root
  moduleName: "io.github.taneltaluri.tmail"

  readonly property int intervalSec: Math.max(10, parseInt(setting("interval", 30)) || 30)
  readonly property bool showZero: setting("showZero", true) !== false
  readonly property string launchCommand: String(setting("launchCommand", "tmail"))

  // Token and port come from TMail's settings.json; the port setting here is only a fallback.
  property string token: ""
  property int port: parseInt(setting("port", 8765)) || 8765
  readonly property string baseUrl: "http://127.0.0.1:" + port + "/mcp"

  property bool online: false
  property int unread: 0
  property var latest: []
  property var accounts: []
  property bool popupOpen: false

  readonly property string label: Model.barLabel(online, unread, showZero)
  readonly property string tooltip: !online
    ? "TMail is not running — middle-click to launch"
    : (unread === 0 ? "No unread mail" : unread + " unread — click for details")

  // ---- Shape contract for shell.summon/hide/toggle routing
  readonly property bool opened: popupOpen
  function open() { if (online) popupOpen = true }
  function close() { popupOpen = false }
  function togglePanel() { if (popupOpen) close(); else open() }

  function refresh() {
    if (!token) { settingsFile.reload(); return }
    if (statusProc.running) return
    statusProc.stdinEnabled = true
    statusProc.running = true
  }

  // Feed the Authorization header to curl over stdin and close it (EOF) so curl proceeds.
  function feedCurlConfig(proc) {
    proc.write(Model.curlConfig(root.token))
    proc.stdinEnabled = false
  }

  function launchOrFocus() {
    if (online) rpc("focus_app", {})
    else if (root.bar) root.bar.run(launchCommand)
  }

  function compose() {
    if (online) rpc("open_compose", {})
    else if (root.bar) root.bar.run(launchCommand)
  }

  function openMessage(item) {
    if (!item) return
    rpc("open_message", { account: item.account, mailbox: item.mailbox, uid: item.uid })
    close()
  }

  // JSON-RPC tools/call against TMail's local server (same API local AI agents use)
  property string pendingRpcBody: ""
  function rpc(tool, args) {
    if (!token) return
    if (rpcProc.running) return
    pendingRpcBody = Model.rpcBody(tool, args)
    rpcProc.stdinEnabled = true
    rpcProc.running = true
  }

  visible: label !== "" || !online
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // TMail writes its local API token here on first run.
  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.config/TMail/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var s = Model.parseSettings(text())
      root.token = s.enabled ? s.token : ""
      if (s.port > 0) root.port = s.port
      root.refresh()
    }
    onLoadFailed: { root.token = ""; root.online = false }
  }

  // Shell startup can race the first read; one delayed reload self-corrects.
  Timer {
    interval: 1500
    running: true
    onTriggered: settingsFile.reload()
  }

  Timer {
    id: pollTimer
    interval: root.intervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    // -K -  → header (with the token) comes from stdin, not from argv
    command: ["curl", "-fsS", "--max-time", "4", "-K", "-", root.baseUrl + "?limit=8"]
    stdinEnabled: true
    onStarted: root.feedCurlConfig(statusProc)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) { root.online = false; return }
        try {
          var s = Model.parseStatus(raw)
          root.unread = s.unread
          root.latest = s.latest
          root.accounts = s.accounts
          root.online = true
        } catch (e) {
          root.online = false
        }
      }
    }
    onExited: function(code) { if (code !== 0) { root.online = false; root.popupOpen = false } }
  }

  Process {
    id: rpcProc
    // The JSON body (tool name, mailbox, uid) is not secret; the token again goes via stdin.
    command: ["curl", "-fsS", "--max-time", "6", "-K", "-",
      "-H", "Content-Type: application/json",
      "-X", "POST", "--data-binary", root.pendingRpcBody,
      root.baseUrl]
    stdinEnabled: true
    onStarted: root.feedCurlConfig(rpcProc)
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) { if (code === 0) refreshSoon.restart() }
  }

  Timer {
    id: refreshSoon
    interval: 800
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "io.github.taneltaluri.tmail"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function compose(): void { root.compose() }
    function launch(): void { root.launchOrFocus() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    hasVisualContent: root.label !== ""
    dimmed: !root.online
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.launchOrFocus()
      else if (b === Qt.RightButton) root.compose()
      else if (root.online) root.togglePanel()
      else root.launchOrFocus()
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: "󰇮"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.iconLarge
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(40)
          spacing: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            text: root.unread === 0 ? "No unread mail" : root.unread + " unread message" + (root.unread === 1 ? "" : "s")
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: {
              var parts = []
              for (var i = 0; i < root.accounts.length; i++) {
                var a = root.accounts[i]
                if (a && a.unread > 0) parts.push((a.name || a.email) + ": " + a.unread)
              }
              return parts.join("  ·  ")
            }
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      PanelSeparator {
        visible: root.latest.length > 0
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      Column {
        id: messageList
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.latest

          BorderSurface {
            id: messageRow
            required property var modelData

            width: messageList.width
            height: rowInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: rowHover.hovered ? Style.selectedFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent) : "transparent"
            borderSpec: Border.none()

            Column {
              id: rowInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(1)

              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: Model.trim(messageRow.modelData.from, 40)
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width - timeText.width - Style.space(6)
                }

                Text {
                  id: timeText
                  textFormat: Text.PlainText
                  text: Model.formatTime(messageRow.modelData.date)
                  color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                textFormat: Text.PlainText
                text: messageRow.modelData.subject || "(no subject)"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: Model.trim(messageRow.modelData.preview, 90)
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
                visible: text !== ""
              }
            }

            HoverHandler { id: rowHover }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openMessage(messageRow.modelData)
            }
          }
        }
      }

      PanelSeparator {
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰇮"
          text: "Open TMail"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: { root.launchOrFocus(); root.close() }
        }

        Button {
          iconText: "󰏫"
          text: "New message"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: { root.compose(); root.close() }
        }

        Button {
          iconText: "󰑐"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.refresh()
        }
      }
    }
  }
}
