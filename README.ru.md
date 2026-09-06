# Удалённые хосты для Omarchy

[English version](README.md)

Плагин для панели Omarchy, объединяющий каталог удалённых хостов, SSH, SFTP,
VS Code Remote-SSH, строгую проверку host key и запуск интерактивных AI CLI в
нативной панели QML/Quickshell.

Идентификатор плагина: `vornashev.remote-hosts`

## Возможности

- Каталог с группами, заметками, проверкой доступности и лимитом 100 хостов.
- SSH в Ghostty, Kitty, Alacritty или foot.
- SFTP через SSHFS с открытием в Nautilus.
- Изолированные профили VS Code Remote-SSH без изменения `~/.ssh/config`.
- Выбор AI CLI и необязательной рабочей папки для каждого хоста.
- Импорт и экспорт JSON без паролей.
- Хранение паролей только через Secret Service.
- Английский интерфейс по умолчанию; русский выбирается в общих настройках.

Поддерживаемые интерактивные AI CLI:

| Агент | Команда на сервере |
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

Команды и аргумент `session` для Goose зафиксированы в backend. Плагин не
принимает произвольные executable, аргументы, shell-фрагменты или флаги
автоматического разрешения действий.

## Зависимости

- Omarchy Shell / Quickshell.
- Python 3, только стандартная библиотека.
- OpenSSH: `ssh`, `ssh-keyscan` и `ssh-keygen`.
- Один из поддерживаемых терминалов.
- Необязательно: `secret-tool` и разблокируемый Secret Service для паролей.
- Необязательно: `sshfs`, FUSE 3 и Nautilus для SFTP.
- Необязательно: VS Code с официальным расширением `ms-vscode-remote.remote-ssh`.
- Необязательно: `wl-copy` для копирования адресов.

AI CLI должны быть заранее установлены и авторизованы в `PATH` login shell
удалённого пользователя. Плагин не устанавливает программы на сервер.

## Установка

```bash
git clone https://github.com/vornashev/omarchy-remote-hosts.git
cd omarchy-remote-hosts

PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s tests
omarchy plugin validate "$PWD"
scripts/qml-lint
scripts/deploy-local

omarchy plugin enable vornashev.remote-hosts
# Необязательно:
omarchy bar move vornashev.remote-hosts --section right
```

`scripts/deploy-local` валидирует исходники, копирует их в
`~/.config/omarchy/plugins/vornashev.remote-hosts`, устанавливает executable bit для
askpass и обновляет реестр плагинов. Скрипт не устанавливает пакеты и не меняет
`~/.ssh/config`.

## Язык и терминал

Откройте каталог и выберите **Settings / Настройки**:

- **Language / Язык:** English или Русский. Для новой установки выбран English.
- **Default terminal / Терминал по умолчанию:** Ghostty, Kitty, Alacritty или foot.

Терминал используется новыми окнами SSH и AI CLI для всех хостов. Недоступный
терминал сохранить нельзя; автоматического fallback нет. VS Code и SFTP остаются
отдельными действиями. Язык и терминал локальны для машины и не входят в импорт
или экспорт профилей.

## Хранение и обновление

Профили и глобальные настройки находятся в:

```text
$XDG_DATA_HOME/vornashev.remote-hosts/
```

Путь по умолчанию — `~/.local/share/vornashev.remote-hosts/`. Каталог имеет права
0700, файлы данных и lock — 0600. Запись использует временный файл в том же
каталоге, `fsync` и атомарную замену.

При первом запуске версия 0.7 безопасно перемещает приватный каталог данных из
любого предыдущего namespace, если новый каталог ещё не существует. Небезопасные
права и symlink приводят к отказу. Пароль переносится из прежних атрибутов
application Secret Service при первом чтении, после чего найденная старая запись
удаляется.

Схема профилей остаётся версией 1:

```text
{version, groups, devices}
```

Неизвестные и секретные поля, повторяющиеся JSON-ключи, некорректные связи групп
и повтор endpoint отклоняются.

## Модель безопасности

- Пароли не попадают в argv, переменные окружения, JSON профилей, логи, буфер
  обмена и ответы helper.
- Пароль передаётся только через stdin/pipe минимального askpass.
- SSH использует фиксированные argv и `-F /dev/null`; local commands и forwarding
  отключены.
- Для входа по паролю обязателен `StrictHostKeyChecking=yes`.
- Новый host key требует просмотра SHA256 fingerprint и явного доверия.
- Конфликтующие, изменённые, revoked и certificate-authority записи не заменяются.
- Плагин не читает содержимое приватных ключей.
- Импортированные профили не заявляют наличие пароля.
- Runtime-файлы, mount, владелец, права, symlink и размеры проверяются до работы.

`ssh-keyscan` не доказывает подлинность сервера. Сверяйте каждый fingerprint по
независимому доверенному каналу.

## Разработка

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s tests
omarchy plugin validate "$PWD"
scripts/qml-lint
```

Тесты используют синтетические endpoint, временные каталоги и поддельные внешние
программы. Они не подключаются к реальным хостам и не читают реальные credentials,
ключи, mount, профили или `known_hosts`.

## Лицензия

[MIT](LICENSE) © 2026 vornashev.
