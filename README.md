# TMail for Omarchy

Unread-mail widget for the [Omarchy](https://omarchy.org) bar, powered by the
[TMail](https://sharks.pw/tmail/) desktop mail client.

- **Bar:** envelope icon with your unread count (all accounts)
- **Left click:** popup with the latest unread messages — click one to open it in TMail
- **Middle click:** bring TMail to the front (launches it if it is not running)
- **Right click:** new message
- Buttons in the popup: *Open TMail*, *New message*, *Refresh*

Everything stays on your machine: the widget talks to TMail's local API on
`127.0.0.1` using the token TMail stores in `~/.config/TMail/settings.json`.

## Requirements

1. TMail **2.10 or newer** installed and running (it lives in the tray):
   ```bash
   curl -fsSL https://sharks.pw/tmail/dist/install-linux.sh | bash
   ```
2. In TMail → Settings → *AI access (MCP server)* must be enabled (it is by default).

## Install the widget

```bash
omarchy plugin add https://sharks.pw/tmail/plugin.git --enable
```

The same plugin is mirrored on GitHub at
`https://github.com/taneltaluri/tmail-omarchy.git` (use either URL — both receive updates).

Update later with `omarchy plugin update io.github.taneltaluri.tmail`.

Then add **TMail** to your bar from the bar editor (category *Network*), or run
`omarchy-shell shell rescanPlugins` if the bar does not pick it up.

## Settings

| Key             | Default | Meaning |
|-----------------|---------|---------|
| `interval`      | `30`    | seconds between refreshes |
| `showZero`      | `true`  | keep the icon visible when there is no unread mail |
| `port`          | `8765`  | fallback port if TMail's settings file cannot be read |
| `launchCommand` | `tmail` | command used to start TMail |

## IPC

```bash
omarchy-shell shell summon io.github.taneltaluri.tmail   # open the popup
omarchy-shell ipc call io.github.taneltaluri.tmail compose
omarchy-shell ipc call io.github.taneltaluri.tmail refresh
```

## License

MIT
