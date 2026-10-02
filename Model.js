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

function accountLabel(accounts, account) {
  var id = String(account || "")
  for (var i = 0; i < accounts.length; i++) {
    var item = accounts[i]
    if (item && (String(item.email || "") === id || String(item.id || "") === id)) {
      return String(item.email || item.name || id)
    }
  }
  return id || "Unknown account"
}

function filterLatest(messages, account) {
  if (!account) return messages
  return messages.filter(function(item) {
    return item && String(item.account || "") === String(account)
  })
}

function extractVerificationCode(text) {
  var content = String(text || "").slice(0, 30000)
  var patterns = [
    /\b(?:verification|verify|security|authentication|auth|one[- ]time|login|confirmation|confirm)\s+(?:verification\s+|security\s+|login\s+)?(?:code|password|passcode|otp)\s*(?:is|:|=|-)?\s*([A-Z0-9]{4,8})\b/ig,
    /\b(?:code|otp|passcode)\s*(?:is|:|=|-)\s*([A-Z0-9]{4,8})\b/ig,
    /\b([A-Z0-9]{4,8})\s+(?:is\s+)?(?:your\s+)?(?:verification|security|one[- ]time|login)\s+(?:code|otp)\b/ig,
    /\buse\s+([0-9]{4,8})\s+to\s+(?:verify|sign in|log in|confirm|authenticate)\b/ig
  ]
  for (var i = 0; i < patterns.length; i++) {
    var match
    while ((match = patterns[i].exec(content)) !== null) {
      var code = String(match[1] || "").replace(/[- ]/g, "")
      if (/\d/.test(code)) return code
    }
  }
  return ""
}

function rpcBody(tool, args) {
  return JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: tool, arguments: args || {} } })
}

function rpcErrorMessage(raw) {
  try {
    var response = JSON.parse(raw)
    if (response.error) return String(response.error.message || "TMail rejected the action.")
    var result = response.result
    if (result && result.isError) {
      var content = Array.isArray(result.content) ? result.content : []
      for (var i = 0; i < content.length; i++) {
        if (content[i] && content[i].text) return String(content[i].text)
      }
      return "TMail rejected the action."
    }
    return ""
  } catch (e) {
    return "TMail returned an unreadable response."
  }
}

// curl config fed over stdin (`curl -K -`) so the token never appears in a command line.
// The token is hex, but quote defensively: curl config strings use backslash escapes.
function curlConfig(token) {
  var t = String(token || "").replace(/[\\"\r\n]/g, "")
  return 'header = "Authorization: Bearer ' + t + '"\n'
}
