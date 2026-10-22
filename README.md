# Omarchy Remote Hosts

[Russian version](README.ru.md)

An Omarchy bar plugin for managing remote development hosts. It combines SSH,
SFTP, VS Code Remote-SSH, strict host-key verification, and interactive AI CLI
launchers in one native QML/Quickshell panel.

Plugin ID: `vornashev.remote-hosts`

## Features

- Host catalog with groups, pins, notes, endpoint availability, and up to 100 hosts.
- Two layouts from one panel: a narrow list with an action dock, and a wide
  list with a detail pane. **Auto** switches to wide when the screen leaves at
  least 760 px for the panel.
- Search across name, address, group, and note; Enter connects to the best match.
- Latency uses theme colors only: neutral through 50 ms, accent from 51–99 ms,
  and urgent from 100 ms. Statuses refresh host by host with a progress line.
- SSH in Ghostty, Kitty, Alacritty, or foot.
- SFTP mounts through SSHFS and opens them in Nautilus.
- Isolated VS Code Remote-SSH profiles without changing `~/.ssh/config`.
- Per-host AI CLI selection and an optional project directory.
- Explicitly saved per-host scripts, launched in a terminal over SSH on demand.
- JSON import/export without passwords or claims that a saved secret exists.
  The import preview lists every incoming host as new, updated, or skipped;
  the export view shows a sample of the file for the chosen options. Pins are
  never exported, and replacement imports keep the local pin.
- Server-password and opt-in SSH key-passphrase storage through Secret Service only.
- English UI by default, with Russian selectable in global settings.

Supported interactive AI CLIs:

| Agent | Remote command |
| --- | --- |
| Pi | `pi` |
| Codex | `codex` |
| Claude | `claude` |
| OpenCode | `opencode` |
| Gemini CLI | `gemini` |
| Aider | `aider` |
| Goose | `goose session` |
| Amp | `amp` |
| GitHub Copilot CLI | `copilot` |
| Qwen Code | `qwen` |

The commands and Goose's `session` argument are fixed in the backend. The
AI launchers do not accept arbitrary executables, arguments, shell fragments,
or auto-approval flags. User-created scripts are a separate, explicitly
requested remote-execution feature; review their content before launching.

## Panel and keyboard

Opening the panel focuses the search field and restores the last selected host.
Click or use ↑↓ to select a host; the dock (narrow) or detail pane (wide)
follows the selection. Hover and keyboard cursor share one highlight.

| Key | Action |
| --- | --- |
| `/` | Focus search |
| ↑ ↓ | Move the selection |
| Tab | Next group tab (narrow) or switch between list and detail (wide) |
| Enter | SSH to the selected host or the best search match |
| Space / `P` | Pin or unpin |
| `F` / `C` / `Y` | Files (SFTP), VS Code, copy SSH endpoint |
| `A` / `S` | AI CLI or scripts picker; `1`–`9` launch from it |
| `E` / `K` / `R` / Del | Edit, verify host key, retry the status check, delete |
| Ctrl+Enter | Save the host form |
| Esc | Close a picker or confirmation, clear search, then close the panel |

Right-click a host for its context menu, double-click to connect. Deleting a
host or an empty group is confirmed inline. A launch that needs a host key
stops with a notification whose **Verify** action (`K`) opens the fingerprint
review; after trusting the key, the launch continues. Pins are saved with the
profile, while group tabs, collapse state, and selection are view state only.

## Host scripts

Select a host and choose **Add script** in its scripts list to enter a script or choose a local
executable `.sh` under your home directory. The file must be owned by you,
non-symlink, UTF-8, at most 16 KiB, and not writable by others. The plugin
stores a private **copy** in `scripts.json` (0600); changing the original file
will not change the saved script. Up to 32 scripts may be saved in total.
Scripts are local to this installation and excluded from profile import/export.
The file picker remembers its last successfully opened folder across shell
restarts in private `script-browser.json` (0600); if that folder disappears,
it opens your home directory instead. This path is never exported.
List responses carry only each script's first command line (no shebang or
comments, at most 120 characters) as a one-line preview; full contents are not
returned. Opening an editor
reads the saved copy over a local preview pipe; file-backed scripts display
read-only content and remember their original path. Selecting a different
`.sh` replaces that saved copy; renaming does not re-read the source file.
Scripts saved before this feature still show their contents, but their original
source path cannot be recovered. Manually entered scripts remain editable.
Changing a host's address, port, or login
invalidates access to its old scripts; delete the host to remove them.

Click a script (or pick it with `S` and a number) to open a terminal and run it remotely via SSH using
`sh -s` or `bash -s` according to a supported shebang (`#!/bin/sh`,
`#!/usr/bin/env sh`, `#!/bin/bash`, `#!/usr/bin/env bash`). Its contents travel through stdin, never command-line arguments or
environment variables. A verified host key is required and strict checking is
always enabled. This deliberately runs user-supplied code on the host: do not
include passwords, tokens, or private keys in scripts. Scripts are not uploaded
as persistent remote files. The terminal shows the remote exit result; closing
it or losing the connection can interrupt execution.

## Requirements

- Omarchy Shell / Quickshell.
- Python 3 standard library.
- OpenSSH client tools: `ssh`, `ssh-keyscan`, and `ssh-keygen`.
- One supported terminal.
- Optional: `secret-tool` and an unlocked Secret Service for passwords or saved key passphrases.
- Optional: `sshfs`, FUSE 3, and Nautilus for SFTP.
- Optional: VS Code with the official `ms-vscode-remote.remote-ssh` extension.
- Optional: `wl-copy` for copying SSH endpoints. The copy is `login@host`, with ` -p port` appended for a non-default port.

Remote AI CLIs must already be installed, authenticated, and available in the
remote user's login-shell `PATH`. The plugin does not install remote software.

## Installation

```bash
git clone https://github.com/vornashev/omarchy-remote-hosts.git
cd omarchy-remote-hosts

PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s tests
omarchy plugin validate "$PWD"
scripts/qml-lint
scripts/deploy-local

omarchy plugin enable vornashev.remote-hosts
# Optional:
omarchy bar move vornashev.remote-hosts --section right
```

`scripts/deploy-local` validates the source, copies it to
`~/.config/omarchy/plugins/vornashev.remote-hosts`, sets the askpass executable bit,
and rescans shell plugins. It does not install packages or edit
`~/.ssh/config`.

## Bar icon

The icon keeps its 27 px slot and shows one signal at a time, in priority
order: a pinned host is unreachable (urgent badge), a status check is running
(dimmed, pulsing), an SFTP mount is active (dimmed lower plate), address
hiding is on (solid plates), otherwise the plain stack.

| Input | Action |
| --- | --- |
| Left click | Open or close the panel |
| Middle click | Check every host (ping and SSH port) |
| Right click | Quick menu: up to five pinned hosts (connect over SSH), check all, disconnect active SFTP mounts, toggle address hiding, open the panel |
| Hover | Summary: host and pin counts, unreachable pinned hosts, active mounts, last check |
| Wheel | Browse pinned hosts in the tooltip; scrolling never starts anything |

The tooltip and quick menu show host names only, never `user@host`. Quick
menu connections use the same launch path as the panel, including strict
host-key verification and askpass; if a launch fails or needs a host key, the
panel opens with the notification. Escape or a click outside closes the menu.

The catalog is read from local files when the shell starts, so the icon and
tooltip work before the panel is first opened; no host is contacted until you
check. **Settings → Check pinned hosts** optionally re-checks pinned hosts
every 5, 15, 30, or 60 minutes (off by default).

## Language and terminal

Open the catalog and select **Settings**:

- **Language:** English or Russian. English is the default for a fresh install.
- **Panel layout:** Auto, Compact (narrow), or Wide.
- **Check pinned hosts:** Off, or a background check every 5–60 minutes.
- **Default terminal:** Ghostty, Kitty, Alacritty, or foot.

The saved terminal applies to new SSH and AI CLI windows on every host. Missing
terminals cannot be selected, and there is no silent fallback. VS Code and SFTP
remain separate actions. Language, layout, background check, and terminal settings are
machine-local, take effect after **Save**, and are excluded from profile
import/export.

## Authentication secrets

Password profiles store the server password in Secret Service. Key / SSH-agent
profiles may name an absolute private-key path and enable **Save key
passphrase**. The passphrase is stored in a separate Secret Service namespace;
the profile contains only the boolean setting and the key path.

Enabling the option, creating the profile, or changing its address, port,
login, or key path requires the passphrase again. An empty field keeps the
existing passphrase only while all of those bindings remain unchanged.
Disabling the option or deleting the host clears the matching passphrase after
the profile change is safely published.

Saved key passphrases are supplied only to terminal SSH, AI CLI SSH, and SFTP.
VS Code Remote-SSH retains its own passphrase prompt and handling. Exports
always reset the saved-passphrase setting; new imported hosts start with it
disabled, while replacement imports preserve the local authentication,
key path, and setting.

## Screen-sharing privacy

Use the eye button in the panel header to blur logins and addresses in host
rows, the dock and detail pane, the editor, notifications, script previews,
import and export previews, and host-key review. Endpoint
fields cannot be edited while hidden, and a host key cannot be trusted until
addresses are shown again.

This is a transient visual mode for screen sharing, not cryptographic
redaction. It does not change saved profiles or the real endpoint copied from a
host, and it does not cover the clipboard, external terminals, or text in
arbitrary names and notes. The mode is shared by panel instances until the
shell process restarts; it is not saved to disk.

## Stored data and upgrades

Profiles and global settings are stored under:

```text
$XDG_DATA_HOME/vornashev.remote-hosts/
```

The default is `~/.local/share/vornashev.remote-hosts/`. The directory uses mode
0700; data files and the lock use 0600. Writes use a same-directory temporary
file, `fsync`, and atomic replacement.

On first start, version 0.7 safely moves a valid private data directory from
either previous plugin namespace when the new directory does not exist. Unsafe
permissions and symlinks fail closed. Password entries are migrated from
previous Secret Service application attributes on first lookup, then the
matching old entry is cleared.

Profile schema remains version 1:

```text
{version, groups, devices}
```

Hosts may carry an optional boolean `pinned`; older profiles without it load
unchanged. Unknown fields, secret-bearing fields, duplicate JSON keys, invalid
group references, and duplicate endpoint tuples are rejected.

## Security model

- Passwords and key passphrases never enter argv, environment variables,
  profile JSON, logs, clipboard contents, or helper responses. Scripts must not
  contain credentials.
- Secret flow is stdin/pipe-based through a minimal askpass executable. It
  accepts only the exact OpenSSH prompt bound to the saved profile endpoint
  and, for a passphrase, the exact configured key path.
- SSH uses fixed argv arrays and `-F /dev/null`; local commands and forwarding
  are disabled.
- Password authentication and saved key-passphrase delivery require
  `StrictHostKeyChecking=yes`. The latter also disables password and
  keyboard-interactive authentication.
- A new host key must be reviewed by SHA256 fingerprint and explicitly trusted.
- Conflicting, changed, revoked, or certificate-authority entries are never
  replaced automatically.
- The plugin does not read private-key contents.
- Imported profiles never claim that a password or key passphrase is available.
- Runtime files, mounts, ownership, permissions, symlinks, and file sizes are
  validated before use.

`ssh-keyscan` does not authenticate a server. Verify every displayed
fingerprint through an independent trusted channel before accepting it.

## Development

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s tests
omarchy plugin validate "$PWD"
scripts/qml-lint
```

Tests use synthetic endpoints, temporary directories, and fake external
programs. They do not connect to real hosts or read real credentials, keys,
mounts, profiles, or `known_hosts`.

## License

[MIT](LICENSE) © 2026 vornashev.
