// Pure helpers for the TMail bar widget (no QML dependencies, unit-testable).
.pragma library

function formatTime(iso) {
  if (!iso) return ""
  var d = new Date(iso)
  if (isNaN(d.getTime())) return ""
  var now = new Date()
  var sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()
  if (sameDay) return Qt.formatTime(d, "HH:mm")
  var yesterday = new Date(now.getTime() - 86400000)
  if (d.getFullYear() === yesterday.getFullYear() && d.getMonth() === yesterday.getMonth() && d.getDate() === yesterday.getDate()) return "Yesterday"
  return Qt.formatDate(d, "d MMM")
}

function trim(s, n) {
  s = String(s || "")
  return s.length > n ? s.slice(0, n - 1) + "…" : s
}

// Parse TMail's settings.json (~/.config/TMail/settings.json) for the local API token/port.
function parseSettings(text) {
  try {
    var j = JSON.parse(text)
    return { token: String(j.mcpToken || ""), port: parseInt(j.mcpPort, 10) || 0, enabled: j.mcpEnabled !== false }
  } catch (e) {
    return { token: "", port: 0, enabled: false }
  }
}

// Parse the widget status response from TMail (GET /mcp).
function parseStatus(raw) {
  var j = JSON.parse(raw)
  return {
    unread: parseInt(j.unread, 10) || 0,
    accounts: Array.isArray(j.accounts) ? j.accounts : [],
    latest: Array.isArray(j.latest) ? j.latest : [],
    version: String(j.version || "")
  }
}

function barLabel(online, unread, showZero) {
  if (!online) return "󰇮"
  if (unread > 0) return "󰇮 " + (unread > 99 ? "99+" : unread)
  return showZero ? "󰇮" : ""
}

function rpcBody(tool, args) {
  return JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: tool, arguments: args || {} } })
}
