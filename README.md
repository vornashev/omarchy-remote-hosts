# Omarchy Remote Hosts

[Russian version](README.ru.md)

An Omarchy bar plugin for managing remote development hosts. It combines SSH,
SFTP, VS Code Remote-SSH, strict host-key verification, and interactive AI CLI
launchers in one native QML/Quickshell panel.

Plugin ID: `tema.remote-hosts`

## Features

- Host catalog with groups, notes, endpoint availability, and up to 100 hosts.
- SSH in Ghostty, Kitty, Alacritty, or foot.
- SFTP mounts through SSHFS and opens them in Nautilus.
- Isolated VS Code Remote-SSH profiles without changing `~/.ssh/config`.
- Per-host AI CLI selection and an optional project directory.
- JSON import/export without passwords.
- Password storage through Secret Service only.
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
plugin does not accept arbitrary executables, arguments, shell fragments, or
auto-approval flags.

## Requirements

- Omarchy Shell / Quickshell.
- Python 3 standard library.
- OpenSSH client tools: `ssh`, `ssh-keyscan`, and `ssh-keygen`.
- One supported terminal.
- Optional: `secret-tool` and an unlocked Secret Service for passwords.
- Optional: `sshfs`, FUSE 3, and Nautilus for SFTP.
- Optional: VS Code with the official `ms-vscode-remote.remote-ssh` extension.
- Optional: `wl-copy` for copying host addresses.

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

omarchy plugin enable tema.remote-hosts
# Optional:
omarchy bar move tema.remote-hosts --section right
```

`scripts/deploy-local` validates the source, copies it to
`~/.config/omarchy/plugins/tema.remote-hosts`, sets the askpass executable bit,
and rescans shell plugins. It does not install packages or edit
`~/.ssh/config`.

## Language and terminal

Open the catalog and select **Settings**:

- **Language:** English or Russian. English is the default for a fresh install.
- **Default terminal:** Ghostty, Kitty, Alacritty, or foot.

The saved terminal applies to new SSH and AI CLI windows on every host. Missing
terminals cannot be selected, and there is no silent fallback. VS Code and SFTP
remain separate actions. Language and terminal settings are machine-local and
excluded from profile import/export.

## Stored data and upgrades

Profiles and global settings are stored under:

```text
$XDG_DATA_HOME/tema.remote-hosts/
```

The default is `~/.local/share/tema.remote-hosts/`. The directory uses mode
0700; data files and the lock use 0600. Writes use a same-directory temporary
file, `fsync`, and atomic replacement.

On first start, version 0.7 safely moves a valid private data directory from
the previous plugin namespace when the new directory does not exist. Unsafe
permissions and symlinks fail closed. Password entries are migrated from the
previous Secret Service application attribute on first lookup, then the old
entry is cleared.

Profile schema remains version 1:

```text
{version, groups, devices}
```

Unknown fields, secret-bearing fields, duplicate JSON keys, invalid group
references, and duplicate endpoint tuples are rejected.

## Security model

- Passwords never enter argv, environment variables, profile JSON, logs,
  clipboard contents, or helper responses.
- Password flow is stdin/pipe-based through a minimal askpass executable.
- SSH uses fixed argv arrays and `-F /dev/null`; local commands and forwarding
  are disabled.
- Password authentication requires `StrictHostKeyChecking=yes`.
- A new host key must be reviewed by SHA256 fingerprint and explicitly trusted.
- Conflicting, changed, revoked, or certificate-authority entries are never
  replaced automatically.
- The plugin does not read private-key contents.
- Imported profiles never claim that a password is available.
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
