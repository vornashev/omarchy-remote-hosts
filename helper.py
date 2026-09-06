#!/usr/bin/python3
"""One JSON request/response per invocation; no shell, server or polling daemon."""
import base64
import binascii
import concurrent.futures
import contextlib
import copy
import datetime
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import select
import shlex
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from typing import Any

APP = "tema.remote-devices"
HERE = Path(__file__).resolve().parent
MAX_BYTES = 1024 * 1024
MAX_DEVICES = 100
MAX_KEYSCAN_BYTES = 64 * 1024
KEYSCAN_TYPES = "rsa,ecdsa,ed25519"
KEY_ALGORITHMS = {"ssh-rsa", "ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521"}
DEFAULT_GROUP = "00000000-0000-4000-8000-000000000001"
AI_COMMANDS = {
    "pi": ("pi",),
    "codex": ("codex",),
    "claude": ("claude",),
    "opencode": ("opencode",),
    "gemini": ("gemini",),
    "aider": ("aider",),
    "goose": ("goose", "session"),
    "amp": ("amp",),
    "copilot": ("copilot",),
    "qwen": ("qwen",),
}
TERMINALS = {
    "ghostty": ("Ghostty", ("ghostty", "--wait-after-command=true", "-e")),
    "kitty": ("Kitty", ("kitty", "--hold")),
    "alacritty": ("Alacritty", ("alacritty", "--hold", "-e")),
    "foot": ("foot", ("foot", "--hold", "--")),
}
# Legacy values remain readable so existing profiles are never bricked.
LEGACY_LAUNCH_MODES = {"shell", "custom", *AI_COMMANDS}
DEVICE_FIELDS = {"id", "name", "host", "port", "login", "group", "note", "auth", "keyPath",
                 "client", "remoteFolder", "launchMode", "customExecutable", "agents", "agentFolder"}


class Error(Exception):
    """Only these fixed, non-secret messages may cross the UI boundary."""


def require(ok, message):
    if not ok:
        raise Error(message)


def text(value, label, maximum=200, empty=False, multiline=False):
    require(isinstance(value, str), f"{label}: требуется строка")
    require((empty or bool(value.strip())) and len(value) <= maximum,
            f"{label}: пустое или слишком длинное значение")
    require(all(ord(c) >= 32 and ord(c) != 127 or (multiline and c == "\n") for c in value),
            f"{label}: управляющие символы запрещены")
    return value


def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}", value),
            "Некорректный идентификатор")
    return value


def host_value(value):
    value = text(value, "Адрес", 253)
    require("%" not in value, "IPv6 zone ID не поддерживается")
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        require(":" not in value, "IPv6: используйте адрес без квадратных скобок")
    labels = value.rstrip(".").split(".")
    require(all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", p) for p in labels),
            "Адрес: только IPv4, IPv6 или ASCII-домен (IDN: punycode)")
    require(not re.fullmatch(r"[0-9.]+", value), "Некорректный IPv4")
    return value.rstrip(".").lower()


def safe_path(value, label):
    value = text(value, label, 1024, empty=True)
    # Conservative shared policy: safe for argv and future SSH config/remote URI use.
    # No shell quoting, percent expansion, tilde expansion or relative paths.
    require(not value or (value.startswith("/") and re.fullmatch(r"/[\w ./@+,-]*", value, re.ASCII)
                          and ".." not in value.split("/")),
            f"{label}: нужен абсолютный путь; спецсимволы и .. запрещены")
    return value


def executable_name(value):
    value = text(value, "Исполняемый файл", 64, empty=True)
    require(not value or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", value),
            "Исполняемый файл: только имя из PATH без пути и аргументов")
    return value


def device(value):
    require(isinstance(value, dict) and not (set(value) - DEVICE_FIELDS), "Неизвестные поля устройства (секреты запрещены)")
    d = dict(value)
    d["id"] = identifier(d.get("id"))
    d["name"] = text(d.get("name"), "Имя", 100)
    d["host"] = host_value(d.get("host"))
    require(type(d.get("port")) is int and 1 <= d["port"] <= 65535, "SSH-порт: 1–65535")
    require(isinstance(d.get("login"), str) and re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}", d["login"]),
            "Логин: буквы ASCII, цифры, _, точка, дефис")
    d["group"] = identifier(d.get("group"))
    d["note"] = text(d.get("note", ""), "Заметка", 4000, empty=True, multiline=True)
    require(d.get("auth") in ("agent", "password"), "Неизвестный способ входа")
    require(d.get("client") in ("ghostty", "vscode"), "Неизвестный клиент")
    d["keyPath"] = safe_path(d.get("keyPath", ""), "Путь к ключу")
    d["remoteFolder"] = safe_path(d.get("remoteFolder", ""), "Удалённая папка")
    d["launchMode"] = d.get("launchMode", "shell")
    require(d["launchMode"] in LEGACY_LAUNCH_MODES, "Неизвестный устаревший режим запуска SSH")
    d["customExecutable"] = executable_name(d.get("customExecutable", ""))
    legacy_agents = [d["launchMode"]] if d["launchMode"] in AI_COMMANDS else []
    d["agents"] = d.get("agents", legacy_agents)
    require(isinstance(d["agents"], list) and len(d["agents"]) <= len(AI_COMMANDS)
            and all(isinstance(a, str) and a in AI_COMMANDS for a in d["agents"])
            and len(set(d["agents"])) == len(d["agents"]),
            "AI-агенты: выберите поддерживаемые CLI без повторов")
    d["agentFolder"] = safe_path(d.get("agentFolder", ""), "Рабочая папка AI")
    require(d["auth"] != "password" or not d["keyPath"], "Для пароля путь к ключу должен быть пустым")
    return d


def endpoint(d):
    return d["host"], d["port"], d["login"]


def document(value):
    require(isinstance(value, dict) and set(value) == {"version", "groups", "devices"}
            and type(value["version"]) is int and value["version"] == 1, "Неподдерживаемый формат: требуется version 1, groups, devices")
    require(isinstance(value["groups"], list) and 1 <= len(value["groups"]) <= 50, "Нужно от 1 до 50 групп")
    require(isinstance(value["devices"], list) and len(value["devices"]) <= MAX_DEVICES, "Лимит: 100 устройств")
    groups = []
    for g in value["groups"]:
        require(isinstance(g, dict) and set(g) == {"id", "name", "collapsed"}, "Некорректные поля группы")
        require(type(g["collapsed"]) is bool, "Некорректное состояние группы")
        groups.append({"id": identifier(g["id"]), "name": text(g["name"], "Группа", 100), "collapsed": g["collapsed"]})
    ids = [g["id"] for g in groups]
    require(len(set(ids)) == len(ids) and len({g["name"].casefold() for g in groups}) == len(groups), "Повтор группы")
    devices = [device(d) for d in value["devices"]]
    require(all(d["group"] in ids for d in devices), "Группа устройства не найдена")
    require(len({d["id"] for d in devices}) == len(devices), "Повтор идентификатора устройства")
    require(len({endpoint(d) for d in devices}) == len(devices), "Повтор адреса/порта/логина")
    return {"version": 1, "groups": groups, "devices": devices}


def decode(raw):
    require(len(raw.encode("utf-8")) <= MAX_BYTES, "JSON превышает 1 МиБ")
    def pairs(items):
        result = {}
        for k, v in items:
            require(k not in result, "Повтор JSON-поля")
            result[k] = v
        return result
    try:
        return json.loads(raw, object_pairs_hook=pairs)
    except (ValueError, RecursionError):
        raise Error("Некорректный JSON") from None


def private_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    s = path.lstat()
    require(stat.S_ISDIR(s.st_mode) and s.st_uid == os.getuid() and not s.st_mode & 0o077,
            "Каталог данных должен принадлежать вам и иметь права 0700 (не symlink)")


def check_file(path):
    s = path.lstat()
    require(stat.S_ISREG(s.st_mode) and s.st_uid == os.getuid() and not s.st_mode & 0o077,
            "Файл данных должен принадлежать вам и иметь права 0600 (не symlink)")


def encoded_document(value):
    raw = json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    require(len(raw) <= MAX_BYTES, "JSON превышает 1 МиБ")
    return raw


def atomic_private_bytes(path, raw, overwrite=True):
    require(isinstance(raw, bytes) and len(raw) <= MAX_BYTES, "Файл превышает 1 МиБ")
    if path.exists() or path.is_symlink():
        check_file(path)
        require(overwrite, "Файл уже существует; выберите новое имя")
    fd, temp = tempfile.mkstemp(prefix=".remote-devices-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as out:
            out.write(raw)
            out.flush()
            os.fsync(out.fileno())
        if overwrite:
            os.replace(temp, path)
        else:
            os.link(temp, path)  # atomic no-clobber publication
            os.unlink(temp)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def atomic_write(path, value, overwrite=True):
    atomic_private_bytes(path, encoded_document(value), overwrite)


def atomic_text(path, value):
    require(isinstance(value, str), "Некорректный текстовый файл")
    atomic_private_bytes(path, value.encode("utf-8"))


def global_settings(value):
    require(isinstance(value, dict) and set(value) == {"version", "defaultTerminal"},
            "Некорректные поля глобальных настроек")
    require(type(value["version"]) is int and value["version"] == 1, "Неизвестная версия настроек")
    require(isinstance(value["defaultTerminal"], str) and value["defaultTerminal"] in TERMINALS,
            "Неизвестный терминал")
    return dict(value)


def settings_response(value):
    return {"globalSettings": value,
            "terminals": [{"value": name, "label": label, "available": shutil.which(argv[0]) is not None}
                          for name, (label, argv) in TERMINALS.items()]}


class Store:
    def __init__(self, root=None):
        base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
        require(Path(base).is_absolute(), "XDG_DATA_HOME должен быть абсолютным")
        self.root = Path(root) if root is not None else Path(base) / APP
        self.path = self.root / "profiles.json"
        self.settings_path = self.root / "settings.json"

    @contextlib.contextmanager
    def locked(self):
        private_dir(self.root)
        fd = os.open(self.root / ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            check_file(self.root / ".lock")
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def load(self):
        if not self.path.exists() and not self.path.is_symlink():
            return {"version": 1, "groups": [{"id": DEFAULT_GROUP, "name": "Устройства", "collapsed": False}], "devices": []}
        check_file(self.path)
        with self.path.open(encoding="utf-8") as src:
            return document(decode(src.read(MAX_BYTES + 1)))

    def save(self, data):
        atomic_write(self.path, document(data))

    def load_settings(self):
        if not self.settings_path.exists() and not self.settings_path.is_symlink():
            return {"version": 1, "defaultTerminal": "ghostty"}
        check_file(self.settings_path)
        with self.settings_path.open(encoding="utf-8") as src:
            return global_settings(decode(src.read(MAX_BYTES + 1)))

    def save_settings(self, value):
        value = global_settings(value)
        require(shutil.which(TERMINALS[value["defaultTerminal"]][1][0]) is not None,
                "Выбранный терминал не установлен или отсутствует в PATH")
        atomic_write(self.settings_path, value)
        return value


def secret_args(d):
    digest = hashlib.sha256(json.dumps(endpoint(d)).encode()).hexdigest()
    return ["application", APP, "profile", d["id"], "endpoint", digest]


def secret(operation, d, password=None):
    require(shutil.which("secret-tool") is not None, "Secret Service: secret-tool не найден; пароль не сохранён")
    argv = ["secret-tool", operation]
    if operation == "store":
        text(password, "Пароль", 4096)
        argv += ["--label=Omarchy remote device"]
    argv += secret_args(d)
    try:
        p = subprocess.run(argv, input=password if operation == "store" else None,
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        raise Error("Secret Service недоступен или не ответил; операция отменена") from None
    require(p.returncode == 0, "Secret Service: операция не выполнена; разблокируйте хранилище")
    if operation == "lookup":
        result = p.stdout.removesuffix("\n")
        text(result, "Сохранённый пароль", 4096)
        return result
    return None


def find_device(data, id_):
    identifier(id_)
    d = next((d for d in data["devices"] if d["id"] == id_), None)
    if d is None:
        raise Error("Устройство не найдено; обновите список")
    return d


def save_device(store, data, raw, password):
    require(isinstance(raw, dict), "Некорректное устройство")
    raw = dict(raw)
    if not raw.get("id"):
        raw["id"] = str(uuid.uuid4())
    d = device(raw)
    old = next((x for x in data["devices"] if x["id"] == d["id"]), None)
    if old and (endpoint(old) != endpoint(d) or old["remoteFolder"] != d["remoteFolder"]):
        require_sftp_disconnected(old)
    updated = {**data, "devices": [x for x in data["devices"] if x["id"] != d["id"]] + [d]}
    encoded_document(document(updated))  # validate size before any secret operation
    same_secret = old and old["auth"] == "password" and endpoint(old) == endpoint(d)
    require(d["auth"] != "password" or same_secret or password, "Введите пароль для нового адреса/логина/порта")
    require(not password or d["auth"] == "password", "Пароль допустим только при входе по паролю")
    if password:
        secret("store", d, password)
    try:
        # Publish before clearing the old credential: a disk failure must never
        # leave the still-current profile without its working password.
        store.save(updated)
    except Exception:
        if password and not same_secret:
            # Best-effort cleanup of the unpublished credential; the original
            # profile and its distinct secret remain untouched.
            with contextlib.suppress(Error):
                secret("clear", d)
        raise
    # Clearing after publication may leave an inert orphan on Secret Service
    # failure, but can no longer break the profile that remains on disk.
    if old and old["auth"] == "password" and (d["auth"] != "password" or not same_secret):
        secret("clear", old)
    return updated


def export_document(data, notes=False, paths=False):
    result = copy.deepcopy(data)
    for d in result["devices"]:
        d["auth"] = "agent"  # imports never claim a password exists
        if not notes:
            d["note"] = ""
        if not paths:
            d["keyPath"] = ""
            d["remoteFolder"] = ""
            d["agentFolder"] = ""
    return result


def import_preview(current, raw, policy):
    require(policy in ("skip", "replace"), "Дубликаты: skip или replace")
    incoming = document(decode(raw))
    incoming = export_document(incoming, True, True)
    result = copy.deepcopy(current)
    names = {g["name"].casefold(): g["id"] for g in result["groups"]}
    mapping = {}
    for g in incoming["groups"]:
        key = g["name"].casefold()
        if key not in names:
            names[key] = str(uuid.uuid4())
            result["groups"].append({**g, "id": names[key]})
        mapping[g["id"]] = names[key]
    summary = {"added": 0, "skipped": 0, "replaced": 0}
    for d in incoming["devices"]:
        existing = next((x for x in result["devices"] if endpoint(x) == endpoint(d)), None)
        if existing:
            if policy == "skip":
                summary["skipped"] += 1
                continue
            # Preserve local authentication, never import secret references/key material.
            d.update(id=existing["id"], auth=existing["auth"], keyPath=existing["keyPath"])
            result["devices"].remove(existing)
            summary["replaced"] += 1
        else:
            d["id"] = str(uuid.uuid4())
            summary["added"] += 1
        d["group"] = mapping[d["group"]]
        result["devices"].append(d)
    result = document(result)
    encoded_document(result)  # A confirmed preview must remain readable after publication.
    return result, summary


def read_import(path):
    path = Path(safe_path(path, "Файл импорта"))
    require(path.is_file(), "Файл импорта не найден")
    with path.open(encoding="utf-8") as src:
        raw = src.read(MAX_BYTES + 1)
    require(len(raw.encode("utf-8")) <= MAX_BYTES, "JSON превышает 1 МиБ")
    return raw


def revision(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def known_host_token(d):
    """OpenSSH known_hosts spelling; brackets are only for a non-default port."""
    return d["host"] if d["port"] == 22 else f"[{d['host']}]:{d['port']}"


def read_ssh_string(blob, offset):
    require(offset + 4 <= len(blob), "Некорректный ключ SSH")
    size = int.from_bytes(blob[offset:offset + 4], "big")
    require(size <= 16384 and offset + 4 + size <= len(blob), "Некорректный ключ SSH")
    start = offset + 4
    return blob[start:start + size], start + size


def parse_public_key(algorithm, encoded, accepted=None):
    require(isinstance(algorithm, str) and isinstance(encoded, str), "Некорректный ключ SSH")
    if accepted is not None:
        require(algorithm in accepted, "ssh-keyscan вернул незапрошенный алгоритм")
    require(1 <= len(encoded) <= 32768 and re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", encoded) is not None,
            "Некорректный ключ SSH")
    try:
        blob = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise Error("Некорректный ключ SSH") from None
    require(4 <= len(blob) <= 16384, "Некорректный ключ SSH")
    name, offset = read_ssh_string(blob, 0)
    try:
        embedded = name.decode("ascii")
    except UnicodeDecodeError:
        raise Error("Некорректный ключ SSH") from None
    require(embedded == algorithm, "Тип ключа SSH не совпадает с его содержимым")

    # Parse the complete RFC 4253 key blob rather than accepting base64 whose
    # first string merely claims a supported algorithm.
    if algorithm == "ssh-ed25519":
        public, offset = read_ssh_string(blob, offset)
        require(len(public) == 32, "Некорректный ключ SSH")
    elif algorithm == "ssh-rsa":
        exponent, offset = read_ssh_string(blob, offset)
        modulus, offset = read_ssh_string(blob, offset)
        require(exponent and modulus and int.from_bytes(exponent, "big") >= 3
                and int.from_bytes(exponent, "big") % 2 == 1 and int.from_bytes(modulus, "big") > 0,
                "Некорректный ключ SSH")
    elif algorithm.startswith("ecdsa-sha2-"):
        curve, offset = read_ssh_string(blob, offset)
        point, offset = read_ssh_string(blob, offset)
        expected_curve = algorithm.removeprefix("ecdsa-sha2-")
        sizes = {"nistp256": 65, "nistp384": 97, "nistp521": 133}
        try:
            curve_name = curve.decode("ascii")
        except UnicodeDecodeError:
            raise Error("Некорректный ключ SSH") from None
        require(curve_name == expected_curve and len(point) == sizes.get(curve_name)
                and point.startswith(b"\x04"), "Некорректный ключ SSH")
    else:
        # ssh-keygen already parsed existing known_hosts entries; keyscan input
        # never reaches this branch because accepted is restricted above.
        require(accepted is None, "Некорректный ключ SSH")
        offset = len(blob)
    require(offset == len(blob), "Некорректный ключ SSH")
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(blob).digest()).decode("ascii").rstrip("=")
    return fingerprint


def parse_keyscan_output(raw, d):
    require(isinstance(raw, str) and len(raw.encode("utf-8")) <= MAX_KEYSCAN_BYTES,
            "Ответ ssh-keyscan слишком велик")
    expected = known_host_token(d)
    keys = set()
    for line in raw.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        require(len(parts) == 3 and parts[0] == expected,
                "ssh-keyscan вернул ключ для другого адреса или некорректную строку")
        fingerprint = parse_public_key(parts[1], parts[2], KEY_ALGORITHMS)
        keys.add((parts[1], parts[2], fingerprint))
    require(keys, "SSH-сервер не вернул host key")
    require(len(keys) <= 16, "SSH-сервер вернул слишком много host key")
    return [{"algorithm": algorithm, "key": key, "fingerprint": fingerprint}
            for algorithm, key, fingerprint in sorted(keys)]


def bounded_keyscan(argv):
    """Capture at most MAX_KEYSCAN_BYTES; kill a noisy child before buffering more."""
    try:
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, env={**os.environ, "LC_ALL": "C"},
                                   close_fds=True)
    except OSError:
        raise Error("Не удалось запустить ssh-keyscan") from None
    output = bytearray()
    deadline = time.monotonic() + 8
    try:
        stdout = process.stdout
        if stdout is None:
            raise Error("Не удалось прочитать ssh-keyscan")
        fd = stdout.fileno()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise Error("Сканирование host key превысило 8 секунд")
            ready, _, _ = select.select([fd], [], [], remaining)
            if not ready:
                raise Error("Сканирование host key превысило 8 секунд")
            chunk = os.read(fd, min(8192, MAX_KEYSCAN_BYTES + 1 - len(output)))
            if not chunk:
                break
            output.extend(chunk)
            require(len(output) <= MAX_KEYSCAN_BYTES, "Ответ ssh-keyscan слишком велик")
        returncode = process.wait(timeout=max(0.1, deadline - time.monotonic()))
    except (subprocess.TimeoutExpired, OSError):
        raise Error("Сканирование host key превысило 8 секунд") from None
    finally:
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
        if process.stdout is not None:
            process.stdout.close()
    require(returncode == 0, "ssh-keyscan не получил ключи; проверьте адрес и SSH-порт")
    try:
        return bytes(output).decode("utf-8")
    except UnicodeDecodeError:
        raise Error("ssh-keyscan вернул некорректный текст") from None


def keyscan(d):
    require(shutil.which("ssh-keyscan") is not None, "ssh-keyscan не найден")
    argv = ["ssh-keyscan", "-T", "5", "-p", str(d["port"]), "-t", KEYSCAN_TYPES, "--", d["host"]]
    return parse_keyscan_output(bounded_keyscan(argv), d)


def user_home():
    """OpenSSH expands ~/.ssh from the account database, not a substituted HOME."""
    home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    require(home.is_absolute(), "Домашний каталог пользователя некорректен")
    return home


def check_ssh_directory(path):
    s = path.lstat()
    require(stat.S_ISDIR(s.st_mode) and s.st_uid == os.getuid() and not s.st_mode & 0o022,
            "~/.ssh должен быть вашим каталогом без групповой/общей записи (не symlink)")


def check_known_hosts_file(path, private=False):
    s = path.lstat()
    forbidden = 0o077 if private else 0o022
    require(stat.S_ISREG(s.st_mode) and s.st_uid == os.getuid() and not s.st_mode & forbidden,
            "known_hosts/lock должен быть вашим обычным файлом без небезопасных прав (не symlink)")


def check_open_file(fd, path, private=False):
    opened, current = os.fstat(fd), path.lstat()
    forbidden = 0o077 if private else 0o022
    require(stat.S_ISREG(opened.st_mode) and opened.st_uid == os.getuid()
            and not opened.st_mode & forbidden
            and (opened.st_dev, opened.st_ino) == (current.st_dev, current.st_ino),
            "known_hosts/lock изменился во время операции; запись отменена")


def known_hosts_paths(home=None):
    home = user_home() if home is None else Path(home)
    require(home.is_absolute(), "Домашний каталог пользователя некорректен")
    ssh_dir = home / ".ssh"
    if ssh_dir.exists() or ssh_dir.is_symlink():
        check_ssh_directory(ssh_dir)
        user_paths = [ssh_dir / "known_hosts", ssh_dir / "known_hosts2"]
    else:
        user_paths = [ssh_dir / "known_hosts"]
    return ssh_dir, user_paths + [Path("/etc/ssh/ssh_known_hosts"), Path("/etc/ssh/ssh_known_hosts2")]


def parse_known_output(raw):
    entries = []
    for line in raw.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        marker = parts[0] if parts and parts[0].startswith("@") else ""
        offset = 1 if marker else 0
        require(len(parts) >= offset + 3, "known_hosts содержит некорректную запись для этого адреса")
        algorithm, key = parts[offset + 1:offset + 3]
        fingerprint = parse_public_key(algorithm, key)
        entries.append({"marker": marker, "algorithm": algorithm, "key": key,
                        "fingerprint": fingerprint})
    return entries


def known_entries(d, paths):
    require(shutil.which("ssh-keygen") is not None, "ssh-keygen не найден")
    entries = []
    for path in paths:
        if not path.exists() and not path.is_symlink():
            continue
        if path.parent.name == ".ssh":
            check_known_hosts_file(path)
        try:
            result = subprocess.run(["ssh-keygen", "-F", known_host_token(d), "-f", str(path)],
                                    capture_output=True, text=True, timeout=5,
                                    env={**os.environ, "LC_ALL": "C"})
        except (OSError, subprocess.TimeoutExpired):
            raise Error("Не удалось безопасно проверить known_hosts через ssh-keygen") from None
        require(result.returncode in (0, 1), "ssh-keygen не смог прочитать known_hosts")
        require(len(result.stdout.encode("utf-8")) <= MAX_KEYSCAN_BYTES,
                "Слишком много записей known_hosts для этого адреса")
        if result.returncode == 0:
            entries.extend(parse_known_output(result.stdout))
    return entries


def host_key_state(scanned, existing):
    if not existing:
        return "new"
    if any(entry["marker"] for entry in existing):
        return "special"
    scanned_pairs = {(item["algorithm"], item["key"]) for item in scanned}
    existing_pairs = {(item["algorithm"], item["key"]) for item in existing}
    if existing_pairs.issubset(scanned_pairs):
        return "known"
    return "conflict"


def has_known_host_entry(d, home=None):
    _, paths = known_hosts_paths(home)
    return bool(known_entries(d, paths))


def host_key_preview(d, home=None):
    scanned = keyscan(d)
    _, paths = known_hosts_paths(home)
    existing = known_entries(d, paths)
    state = host_key_state(scanned, existing)
    token = revision({"endpoint": list(endpoint(d)), "hostToken": known_host_token(d),
                      "keys": [[item["algorithm"], item["key"]] for item in scanned]})
    messages = {
        "new": "Ключи ещё не записаны. Сверьте каждый fingerprint по доверенному каналу.",
        "known": "Этот адрес уже имеет совпадающие ключи в known_hosts; добавление не требуется.",
        "conflict": "В known_hosts есть другой ключ. Возможна атака или смена ключа; плагин ничего не заменит.",
        "special": "Для адреса есть специальная запись @cert-authority/@revoked; плагин её не изменит.",
    }
    return {"hostKeys": {"deviceId": d["id"], "endpoint": known_host_token(d), "keys": scanned,
                         "token": token, "state": state, "message": messages[state]}}


def validated_preview_keys(value):
    require(isinstance(value, list) and 1 <= len(value) <= 16, "Повторите сканирование host key")
    result = []
    seen = set()
    for item in value:
        require(isinstance(item, dict) and set(item) == {"algorithm", "key", "fingerprint"},
                "Повторите сканирование host key")
        fingerprint = parse_public_key(item.get("algorithm"), item.get("key"), KEY_ALGORITHMS)
        require(item.get("fingerprint") == fingerprint, "Fingerprint изменён; повторите сканирование")
        pair = (item["algorithm"], item["key"])
        require(pair not in seen, "Повтор ключа; повторите сканирование")
        seen.add(pair)
        result.append({"algorithm": pair[0], "key": pair[1], "fingerprint": fingerprint})
    return sorted(result, key=lambda item: (item["algorithm"], item["key"], item["fingerprint"]))


def ensure_ssh_directory(home):
    ssh_dir = Path(home) / ".ssh"
    try:
        ssh_dir.mkdir(mode=0o700)
    except FileExistsError:
        pass
    check_ssh_directory(ssh_dir)
    return ssh_dir


def trust_host_keys(d, preview_keys, token, home=None):
    preview = validated_preview_keys(preview_keys)
    expected_token = revision({"endpoint": list(endpoint(d)), "hostToken": known_host_token(d),
                               "keys": [[item["algorithm"], item["key"]] for item in preview]})
    require(isinstance(token, str) and token == expected_token,
            "Адрес или просмотренные ключи изменились; повторите сканирование")
    rescanned = keyscan(d)
    require(rescanned == preview, "Host key изменился после просмотра; доверие не сохранено")

    home = user_home() if home is None else Path(home)
    ssh_dir = ensure_ssh_directory(home)
    lock_path = ssh_dir / ".tema.remote-devices-known-hosts.lock"
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        check_open_file(lock_fd, lock_path, private=True)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        check_open_file(lock_fd, lock_path, private=True)
        primary = ssh_dir / "known_hosts"
        fd = os.open(primary, os.O_CREAT | os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        try:
            check_open_file(fd, primary)
            _, paths = known_hosts_paths(home)
            existing = known_entries(d, paths)
            check_open_file(fd, primary)
            state = host_key_state(rescanned, existing)
            require(state == "new", {
                "known": "Ключ уже известен; повторная запись не нужна",
                "conflict": "Обнаружен другой известный ключ; существующие записи не изменены",
                "special": "Специальная запись known_hosts не изменена",
            }.get(state, "known_hosts изменился; повторите проверку"))
            payload = "".join(f"{known_host_token(d)} {item['algorithm']} {item['key']}\n" for item in rescanned).encode("ascii")
            require(len(payload) <= MAX_KEYSCAN_BYTES, "Слишком много данных host key")
            written = os.write(fd, payload)
            require(written == len(payload), "Не удалось полностью записать known_hosts")
            os.fsync(fd)
        finally:
            os.close(fd)
        directory = os.open(ssh_dir, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        os.close(lock_fd)
    return {"message": "Host key добавлен в ~/.ssh/known_hosts; строгий вход по паролю теперь разрешён"}


def ssh_remote_command(d, agent=None):
    if agent is None:
        return ""
    require(agent in d["agents"] and agent in AI_COMMANDS,
            "Этот AI-агент не включён для сервера")
    commands = []
    if d["agentFolder"]:
        # safe_path excludes quotes/metacharacters; shlex still preserves spaces exactly.
        commands.append("cd -- " + shlex.quote(d["agentFolder"]))
    commands.append("exec " + shlex.join(AI_COMMANDS[agent]))
    inner = " && ".join(commands)
    # Re-enter the user's login shell so CLI tools installed in its PATH are visible.
    return f'exec "${{SHELL:-/bin/sh}}" -lic {shlex.quote(inner)}'


def ssh_argv(d, agent=None):
    d = device(d)
    args = ["ssh", "-F", "/dev/null", "-o", "PermitLocalCommand=no", "-o", "ClearAllForwardings=yes",
            "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=" + ("yes" if d["auth"] == "password" else "ask"),
            "-p", str(d["port"]), "-l", d["login"]]
    if d["auth"] == "password":
        args += ["-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no",
                 "-o", "KbdInteractiveAuthentication=no", "-o", "NumberOfPasswordPrompts=1"]
    elif d["keyPath"]:
        args += ["-i", d["keyPath"], "-o", "IdentitiesOnly=yes"]
    command = ssh_remote_command(d, agent)
    if command:
        args.append("-t")
    args += ["--", d["host"]]
    if command:
        args.append(command)
    return args


def sftp_runtime_root(create=True):
    raw = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    runtime = Path(raw)
    require(runtime.is_absolute() and runtime.exists() and not runtime.is_symlink(),
            "SFTP: runtime-каталог недоступен")
    mode = runtime.lstat()
    require(stat.S_ISDIR(mode.st_mode) and mode.st_uid == os.getuid() and not mode.st_mode & 0o022,
            "SFTP: небезопасный runtime-каталог")
    root = runtime / APP
    if create:
        private_dir(root)
    elif root.exists() or root.is_symlink():
        root_mode = root.lstat()
        require(stat.S_ISDIR(root_mode.st_mode) and root_mode.st_uid == os.getuid()
                and not root_mode.st_mode & 0o022,
                "SFTP: runtime-каталог плагина небезопасен")
    return root


def sftp_mountpoint(d, create=True):
    root = sftp_runtime_root(create)
    suffix = revision([list(endpoint(d)), d["remoteFolder"]])[:16]
    return root / f"{d['id']}-{suffix}"


def mountinfo(path: str | Path = "/proc/self/mountinfo"):
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except OSError:
        raise Error("SFTP: состояние mount недоступно") from None
    require(len(raw.encode("utf-8")) <= MAX_BYTES, "SFTP: список mount слишком велик")
    result = {}
    for line in raw.splitlines():
        parts = line.split()
        try:
            separator = parts.index("-")
            encoded = parts[4]
            decoded = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match.group(1), 8)), encoded)
            source = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match.group(1), 8)), parts[separator + 2])
            result[decoded] = {"filesystem": parts[separator + 1], "source": source}
        except (ValueError, IndexError):
            continue
    return result


def sftp_source(d):
    host = "[" + d["host"] + "]" if ":" in d["host"] else d["host"]
    return f"{d['login']}@{host}:{d['remoteFolder']}"


def sftp_marker(d):
    return Path(str(sftp_mountpoint(d, create=False)) + ".mount.json")


def sftp_binding(d):
    return {"version": 1, "endpoint": [d["host"], d["port"], d["login"], d["remoteFolder"]]}


def sftp_marker_matches(d):
    marker = sftp_marker(d)
    if not marker.exists() and not marker.is_symlink():
        return False
    check_file(marker)
    try:
        raw = marker.read_text(encoding="utf-8")
        require(len(raw.encode("utf-8")) <= MAX_KEYSCAN_BYTES, "SFTP: marker слишком велик")
        return json.loads(raw) == sftp_binding(d)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return False


def remove_sftp_marker(d):
    marker = sftp_marker(d)
    if marker.exists() or marker.is_symlink():
        check_file(marker)
        marker.unlink()


def sftp_mount_kind(d, mounts=None):
    mountpoint = sftp_mountpoint(d, create=False)
    entry = (mounts if mounts is not None else mountinfo()).get(str(mountpoint))
    if entry is None:
        return "unmounted"
    owned = entry == {"filesystem": "fuse.sshfs", "source": sftp_source(d)} and sftp_marker_matches(d)
    return "mounted" if owned else "foreign"


def sftp_state(d, mounts=None):
    try:
        state = sftp_mount_kind(d, mounts)
    except Error:
        state = "unavailable"
    return {"endpoint": [d["host"], d["port"], d["login"], d["remoteFolder"]], "state": state}


def sftp_states(devices):
    try:
        mounts = mountinfo()
    except Error:
        return {d["id"]: {"endpoint": [d["host"], d["port"], d["login"], d["remoteFolder"]],
                           "state": "unavailable"} for d in devices}
    return {d["id"]: sftp_state(d, mounts) for d in devices}


def require_sftp_disconnected(d):
    require(sftp_mount_kind(d) == "unmounted",
            "Сначала отключите SFTP этого устройства")


def require_catalog_mounts_compatible(current, updated):
    replacements = {d["id"]: d for d in updated["devices"]}
    for old in current["devices"]:
        new = replacements.get(old["id"])
        if new is None or endpoint(old) != endpoint(new) or old["remoteFolder"] != new["remoteFolder"]:
            require_sftp_disconnected(old)


def cleanup_sftp_runtime():
    try:
        root = sftp_runtime_root(create=False)
        if not root.exists():
            return
        mounts = mountinfo()
        pattern = re.compile(r"[0-9a-f-]{36}-[0-9a-f]{16}")
        for path in root.iterdir():
            base_name = path.name.removesuffix(".mount.json")
            if not pattern.fullmatch(base_name) or path.is_symlink():
                continue
            mount_path = root / base_name
            if str(mount_path) in mounts:
                continue
            mode = path.lstat()
            if path.name.endswith(".mount.json") and stat.S_ISREG(mode.st_mode) and mode.st_uid == os.getuid():
                path.unlink()
            elif stat.S_ISDIR(mode.st_mode) and mode.st_uid == os.getuid() and not any(path.iterdir()):
                path.rmdir()
    except (Error, OSError):
        return


def unmount_sftp(d):
    mountpoint = sftp_mountpoint(d, create=False)
    kind = sftp_mount_kind(d)
    require(kind != "foreign", "SFTP: точка занята посторонним mount; отключение запрещено")
    require(kind == "mounted", "SFTP: устройство не подключено")
    require(shutil.which("fusermount3") is not None, "SFTP: fusermount3 не найден")
    try:
        result = subprocess.run(["fusermount3", "-u", "--", str(mountpoint)],
                                capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        raise Error("SFTP: размонтирование не выполнено") from None
    require(result.returncode == 0 and sftp_mount_kind(d) == "unmounted",
            "SFTP: размонтирование не выполнено; закройте открытые файлы")
    remove_sftp_marker(d)
    with contextlib.suppress(OSError):
        mountpoint.rmdir()
    return "SFTP отключён"


def sshfs_argv(d, mountpoint):
    source = sftp_source(d)
    # SSHFS accepts only its own -o options. Put OpenSSH controls in the
    # documented ssh_command override; shlex.join preserves a key path with
    # spaces without invoking a local shell or accepting free-form input.
    ssh = ["ssh", "-F", "/dev/null", "-o", "StrictHostKeyChecking=yes",
           "-o", "PermitLocalCommand=no", "-o", "ClearAllForwardings=yes",
           "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=30",
           "-o", "ServerAliveCountMax=3"]
    if d["auth"] == "password":
        ssh += ["-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no",
                "-o", "KbdInteractiveAuthentication=no", "-o", "NumberOfPasswordPrompts=1"]
    elif d["keyPath"]:
        ssh += ["-i", d["keyPath"], "-o", "IdentitiesOnly=yes"]
    args = ["sshfs", "-o", "ssh_command=" + shlex.join(ssh),
            "-p", str(d["port"]), "-o", "idmap=user"]
    if d["auth"] == "password":
        args += ["-o", "password_stdin"]
    return args + [source, str(mountpoint)]


def mount_sftp(d):
    d = device(d)
    require(shutil.which("sshfs") is not None,
            "SFTP: sshfs не установлен; выполните в терминале: omarchy pkg add sshfs")
    require(shutil.which("nautilus") is not None, "SFTP: Nautilus не найден")
    mountpoint = sftp_mountpoint(d)
    kind = sftp_mount_kind(d)
    require(kind != "foreign", "SFTP: точка занята посторонним mount")
    if kind == "unmounted":
        private_dir(mountpoint)
        atomic_write(sftp_marker(d), sftp_binding(d))
        password = secret("lookup", d) if d["auth"] == "password" else None
        try:
            result = subprocess.run(sshfs_argv(d, mountpoint),
                                    input=password + "\n" if password is not None else None,
                                    capture_output=True, text=True, timeout=25)
        except (OSError, subprocess.TimeoutExpired):
            remove_sftp_marker(d)
            with contextlib.suppress(OSError):
                mountpoint.rmdir()
            raise Error("SFTP: подключение не выполнено или превысило время ожидания") from None
        finally:
            password = None
        if result.returncode != 0:
            remove_sftp_marker(d)
            with contextlib.suppress(OSError):
                mountpoint.rmdir()
            raise Error("SFTP: SSHFS отклонил подключение; проверьте пароль, ключ и SFTP на сервере")
        require(sftp_mount_kind(d) == "mounted", "SFTP: SSHFS завершился без точки монтирования")
    subprocess.Popen(["nautilus", mountpoint.as_uri()], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True, close_fds=True)
    return "SFTP подключён через SSHFS и открыт в Nautilus"


def vscode_extension_available():
    require(shutil.which("code") is not None, "VS Code не найден")
    try:
        result = subprocess.run(["code", "--list-extensions"], capture_output=True,
                                text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        raise Error("VS Code: не удалось проверить Remote-SSH") from None
    require(result.returncode == 0 and len(result.stdout.encode("utf-8")) <= MAX_KEYSCAN_BYTES,
            "VS Code: не удалось проверить Remote-SSH")
    extensions = {line.strip().lower() for line in result.stdout.splitlines()}
    require("ms-vscode-remote.remote-ssh" in extensions,
            "VS Code: установите официальное расширение Remote-SSH")


def vscode_runtime(d):
    root = sftp_runtime_root()
    runtime = root / ("vscode-" + d["id"] + "-" + revision(list(endpoint(d)))[:16])
    private_dir(runtime)
    private_dir(runtime / "User")
    return runtime


def vscode_alias(d):
    return "remote-device-" + d["id"]


def vscode_config(d, alias):
    lines = [f"Host {alias}", f"    HostName {d['host']}", f"    User {d['login']}",
             f"    Port {d['port']}", "    StrictHostKeyChecking yes",
             "    PermitLocalCommand no", "    ForwardAgent no", "    ForwardX11 no",
             "    PreferredAuthentications publickey", "    PasswordAuthentication no",
             "    KbdInteractiveAuthentication no", "    ConnectTimeout 10",
             "    ServerAliveInterval 30", "    ServerAliveCountMax 3"]
    if d["keyPath"]:
        lines += [f'    IdentityFile "{d["keyPath"]}"', "    IdentitiesOnly yes"]
    return "\n".join(lines) + "\n"


def vscode_argv(d):
    d = device(d)
    require(d["auth"] == "agent",
            "VS Code Remote-SSH пока поддерживает только ключ или SSH-agent; пароль профиля не передаётся")
    vscode_extension_available()
    runtime = vscode_runtime(d)
    config = runtime / "ssh_config"
    atomic_text(config, vscode_config(d, vscode_alias(d)))
    atomic_write(runtime / "User" / "settings.json", {"remote.SSH.configFile": str(config)})
    args = ["code", "--new-window", "--user-data-dir", str(runtime),
            "--remote", "ssh-remote+" + vscode_alias(d)]
    if d["remoteFolder"]:
        args.append(d["remoteFolder"])
    return args


def launch_argv(d, client, agent=None):
    if isinstance(client, str) and client in TERMINALS:
        args = [*TERMINALS[client][1], sys.executable, str(HERE / "helper.py"), "--terminal", d["id"]]
        if agent is not None:
            require(agent in d["agents"], "Этот AI-агент не включён для сервера")
            args += ["--agent", agent]
        return args
    if client == "vscode":
        return vscode_argv(d)
    raise Error("Неизвестный клиент")


def launch(d, client, agent=None):
    if client == "sftp":
        require(agent is None, "AI CLI запускается только в терминале")
        return mount_sftp(d)
    args = launch_argv(d, client, agent)
    require(shutil.which(args[0]) is not None, "Клиент не найден в PATH")
    subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
    return "Клиент запущен (результат подключения смотрите в клиенте)"


def askpass(prompt, env=None, store=None):
    env = os.environ if env is None else env
    require(env.get("SSH_ASKPASS_PROMPT", "") == "", "Запрос подтверждения запрещён")
    store = store or Store()
    with store.locked():
        d = find_device(store.load(), env.get("REMOTE_DEVICES_PROFILE"))
    require(d["auth"] == "password" and env.get("REMOTE_DEVICES_ENDPOINT") == revision(list(endpoint(d))),
            "Профиль входа изменился")
    # OpenSSH password auth uses this literal prompt. No regex/fuzzy matching,
    # no keyboard-interactive challenges, no host-key/passphrase confirmations.
    require(prompt == f"{d['login']}@{d['host']}'s password: ", "Неожиданный запрос пароля")
    return secret("lookup", d)


def terminal(id_, agent=None):
    store = Store()
    with store.locked():
        d = find_device(store.load(), id_)
    if agent is not None:
        require(agent in d["agents"] and agent in AI_COMMANDS,
                "Этот AI-агент не включён для сервера")
    require(shutil.which("ssh") is not None, "ssh не найден")
    if d["keyPath"]:
        require(Path(d["keyPath"]).is_file(), "Файл ключа не найден")
    env = os.environ.copy()
    # Remote hosts may lack the selected terminal's terminfo entry.
    # Advertise a broadly supported compatible terminal for remote TUIs.
    env["TERM"] = "xterm-256color"
    for name in ("SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "SSH_ASKPASS_PROMPT", "REMOTE_DEVICES_PROFILE", "REMOTE_DEVICES_ENDPOINT"):
        env.pop(name, None)
    if d["auth"] == "password":
        require(shutil.which("secret-tool") is not None, "secret-tool не найден")
        env.update(SSH_ASKPASS=str(HERE / "askpass.py"), SSH_ASKPASS_REQUIRE="force",
                   REMOTE_DEVICES_PROFILE=d["id"], REMOTE_DEVICES_ENDPOINT=revision(list(endpoint(d))), LC_ALL="C")
    os.execvpe("ssh", ssh_argv(d, agent), env)


def probe(d):
    """Executed in a killable child: DNS is not safely cancellable in a thread."""
    result = {"ping": "error", "ms": None, "ssh": "error"}
    try:
        p = subprocess.run(["ping", "-n", "-c", "1", "-W", "1", "--", d["host"]],
                           capture_output=True, text=True, timeout=2, env={**os.environ, "LC_ALL": "C"})
        match = re.search(r"time[=<]([0-9.]+)\s*ms", p.stdout)
        result["ping"] = "ok" if p.returncode == 0 else "unreachable" if p.returncode == 1 else "error"
        if p.returncode == 0 and match:
            result["ms"] = float(match.group(1))
    except subprocess.TimeoutExpired:
        result["ping"] = "timeout"
    except OSError:
        result["ping"] = "unavailable"
    deadline = time.monotonic() + 2
    try:
        addresses = socket.getaddrinfo(d["host"], d["port"], type=socket.SOCK_STREAM)
        result["ssh"] = "closed"
        for family, kind, proto, _, addr in addresses[:8]:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                result["ssh"] = "timeout"
                break
            try:
                with socket.socket(family, kind, proto) as sock:
                    sock.settimeout(remaining)
                    sock.connect(addr)
                result["ssh"] = "open"
                break
            except TimeoutError:
                result["ssh"] = "timeout"
            except OSError:
                pass
    except socket.gaierror:
        result["ssh"] = "dns-error"
    except OSError:
        result["ssh"] = "error"
    return result


def bounded_probe(d):
    try:
        p = subprocess.run([sys.executable, str(HERE / "helper.py"), "--probe"],
                           input=json.dumps(d), capture_output=True, text=True, timeout=6)
        if p.returncode != 0:
            raise Error("probe")
        result = decode(p.stdout)
        require(isinstance(result, dict) and set(result) == {"ping", "ms", "ssh"}, "probe")
    except subprocess.TimeoutExpired:
        result = {"ping": "timeout", "ms": None, "ssh": "timeout"}
    except (Error, OSError):
        result = {"ping": "error", "ms": None, "ssh": "error"}
    result["checkedAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    result["endpoint"] = list(endpoint(d))
    return d["id"], result


def checks(devices):
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        return dict(pool.map(bounded_probe, devices))


def dispatch(req, store=None) -> dict[str, Any]:
    require(isinstance(req, dict), "Требуется JSON-объект")
    op = req.get("op")
    if op == "checkEndpoint":
        # Deliberately accept only network coordinates: an unsaved form's
        # login, password, note and paths never reach the probe process.
        require(set(req) == {"op", "host", "port"}, "Проверка принимает только адрес и SSH-порт")
        host = host_value(req.get("host"))
        port = req.get("port")
        require(type(port) is int and 1 <= port <= 65535, "SSH-порт: 1–65535")
        target = {"id": "00000000-0000-4000-8000-000000000002", "name": "Probe",
                  "host": host, "port": port, "login": "probe", "group": DEFAULT_GROUP,
                  "note": "", "auth": "agent", "keyPath": "", "client": "ghostty",
                  "remoteFolder": "", "launchMode": "shell", "customExecutable": ""}
        _, status = bounded_probe(target)
        status["endpoint"] = [host, port]
        return {"draftStatus": status}
    store = store or Store()
    with store.locked():
        if op in ("getSettings", "saveSettings"):
            require(set(req) == ({"op"} if op == "getSettings" else {"op", "settings"}),
                    "Настройки принимают только параметры терминала")
            value = store.load_settings() if op == "getSettings" else store.save_settings(req.get("settings"))
            result = settings_response(value)
            if op == "saveSettings":
                result["message"] = "Настройки сохранены"
            return result
        data = store.load()
        if op == "list":
            cleanup_sftp_runtime()
            return {"data": data, "sftpStates": sftp_states(data["devices"]),
                    **settings_response(store.load_settings())}
        if op == "saveDevice":
            data = save_device(store, data, req.get("device"), req.get("password", ""))
            return {"data": data, "message": "Устройство сохранено"}
        if op == "deleteDevice":
            d = find_device(data, req.get("id"))
            require_sftp_disconnected(d)
            if d["auth"] == "password":
                secret("clear", d)
            data["devices"].remove(d)
            store.save(data)
            return {"data": data, "message": "Устройство удалено"}
        if op == "saveGroup":
            id_ = req.get("id") or str(uuid.uuid4())
            old = next((g for g in data["groups"] if g["id"] == id_), None)
            g = {"id": identifier(id_), "name": text(req.get("name"), "Группа", 100),
                 "collapsed": req.get("collapsed", old["collapsed"] if old else False)}
            data["groups"] = [g if x["id"] == id_ else x for x in data["groups"]] if old else data["groups"] + [g]
            store.save(data)
            return {"data": data}
        if op == "deleteGroup":
            id_ = identifier(req.get("id"))
            require(not any(d["group"] == id_ for d in data["devices"]), "Сначала перенесите/удалите устройства группы")
            require(any(g["id"] == id_ for g in data["groups"]), "Группа не найдена")
            data["groups"] = [g for g in data["groups"] if g["id"] != id_]
            store.save(data)
            return {"data": data}
        if op == "export":
            require(type(req.get("notes", False)) is bool and type(req.get("paths", False)) is bool, "Некорректные параметры экспорта")
            path = Path(safe_path(req.get("path"), "Файл экспорта"))
            require(path.is_absolute() and path.parent.is_dir(), "Каталог экспорта не найден")
            require(path.resolve() not in (store.path.resolve(), store.settings_path.resolve()),
                    "Нельзя экспортировать поверх данных плагина")
            atomic_write(path, export_document(data, req.get("notes", False), req.get("paths", False)), overwrite=False)
            return {"message": "Экспорт записан без паролей; права 0600"}
        if op in ("previewImport", "import"):
            raw = read_import(req.get("path"))
            merged, summary = import_preview(data, raw, req.get("policy", "skip"))
            token = revision([data, raw, req.get("policy", "skip")])
            if op == "import":
                require(req.get("token") == token, "Файл или профили изменились; повторите просмотр импорта")
                require_catalog_mounts_compatible(data, merged)
                store.save(merged)
                return {"data": merged, "message": "Импорт завершён; новые устройства используют ключ/агент"}
            return {"preview": summary, "token": token, "previewDevices": merged["devices"]}
        if op in ("launch", "launchAgent"):
            d = find_device(data, req.get("id"))
            agent = req.get("agent") if op == "launchAgent" else None
            if op == "launchAgent":
                require(set(req) == {"op", "id", "agent"}, "Запуск AI принимает только id и выбранного агента")
                require(agent in d["agents"] and agent in AI_COMMANDS,
                        "Этот AI-агент не включён для сервера")
            client = req.get("client") if op == "launch" else None
            if client is None:
                client = store.load_settings()["defaultTerminal"]
            require(isinstance(client, str) and (client in TERMINALS or client in ("sftp", "vscode")),
                    "Неизвестный клиент")
            # Password askpass is password-only. Every terminal/client must
            # complete explicit fingerprint verification before first use.
            if not has_known_host_entry(d):
                return host_key_preview(d)
            result: dict[str, Any] = {"message": launch(d, client, agent)}
            if client == "sftp":
                result["sftpStates"] = {d["id"]: sftp_state(d)}
            return result
        if op == "unmountSftp":
            d = find_device(data, req.get("id"))
            message = unmount_sftp(d)
            cleanup_sftp_runtime()
            return {"message": message, "sftpStates": {d["id"]: sftp_state(d)}}
        if op == "scanHostKey":
            d = find_device(data, req.get("id"))
            return host_key_preview(d)
        if op == "trustHostKey":
            d = find_device(data, req.get("id"))
            return trust_host_keys(d, req.get("keys"), req.get("token"))
        if op == "copy":
            d = find_device(data, req.get("id"))
            require(shutil.which("wl-copy") is not None, "wl-copy не найден")
            p = subprocess.run(["wl-copy"], input=d["host"], text=True, capture_output=True, timeout=3)
            require(p.returncode == 0, "Буфер обмена недоступен")
            return {"message": "Адрес скопирован (не пароль)"}
        if op == "checkDevice":
            require(set(req) == {"op", "id"}, "Проверка устройства принимает только его id")
            devices = [find_device(data, req.get("id"))]
        elif op == "check":
            devices = data["devices"]
        else:
            raise Error("Неизвестная операция")
    # Do not hold the persistence lock while doing network I/O.
    return {"statuses": checks(devices)}


def main():
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "--probe":
            print(json.dumps(probe(device(decode(sys.stdin.read(MAX_BYTES + 1))))))
            return
        if len(sys.argv) in (3, 5) and sys.argv[1] == "--terminal":
            require(len(sys.argv) == 3 or sys.argv[3] == "--agent", "Неизвестные аргументы терминала")
            terminal(sys.argv[2], sys.argv[4] if len(sys.argv) == 5 else None)
            return
        require(len(sys.argv) == 1, "Неизвестные аргументы")
        raw = sys.stdin.buffer.readline(MAX_BYTES + 1)
        require(len(raw) <= MAX_BYTES, "Запрос превышает 1 МиБ")
        result = dispatch(decode(raw.decode("utf-8")))
        print(json.dumps({"ok": True, **result}, ensure_ascii=False))
    except Error as e:
        if "--terminal" in sys.argv:
            print(str(e), file=sys.stderr)
            sys.exit(1)
        else:
            print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
    except Exception:
        # Never serialize exception text or tracebacks: requests may contain passwords.
        error = "Операция не выполнена: проверьте данные, права и зависимости"
        print(json.dumps({"ok": False, "error": error}, ensure_ascii=False))


if __name__ == "__main__":
    main()
