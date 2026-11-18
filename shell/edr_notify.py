"""Vigia do Mandacaru (EDR): som e popup na sessão para cada alerta relevante.

Conecta no socket de alertas do Mandacaru (contrato v1, uma linha JSON por alerta),
toca um som com `pw-play` e mostra um popup com `notify-send` (exibido pelo mako).
Roda na sessão Hyprland via `exec-once = /usr/bin/lumen-edr-notify`.
"""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import threading
import time
from typing import Any

SEVERITIES = ("INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL")
SOUND_COOLDOWN = 5.0
MAX_LINE = 64 * 1024
DEFAULT_SOCKET = "/run/mandacaru/alerts.sock"
DEFAULT_MIN_SEVERITY = "MEDIUM"
SOUNDS = {
    "MEDIUM": "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
    "HIGH": "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
    "CRITICAL": "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
}

_last_sound: float | None = None
_children: list[subprocess.Popen] = []
_warned: set[str] = set()


def _warn_once(key: str, msg: str) -> None:
    if key not in _warned:
        _warned.add(key)
        print(f"[edr-notify] {msg}", file=sys.stderr, flush=True)


def parse_alert(line: bytes) -> dict | None:
    """Alerta v1 válido ou None (linha quebrada, versão desconhecida, campo faltando)."""
    try:
        alert = json.loads(line)
    except (ValueError, UnicodeDecodeError):
        return None
    if not isinstance(alert, dict) or alert.get("v") != 1:
        return None
    if alert.get("severity") not in SEVERITIES:
        return None
    if not isinstance(alert.get("rule"), str) or not isinstance(alert.get("summary"), str):
        return None
    return alert


def should_notify(alert: dict, min_severity: str) -> bool:
    return SEVERITIES.index(alert["severity"]) >= SEVERITIES.index(min_severity)


def _reap() -> None:
    _children[:] = [p for p in _children if p.poll() is None]


def _spawn(cmd: list[str]) -> None:
    """Dispara sem esperar: um notify-send travado não pode congelar a leitura do socket."""
    try:
        _children.append(subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    except OSError as exc:
        _warn_once(cmd[0], f"não foi possível rodar {cmd[0]}: {exc.strerror or exc}")


def notify(alert: dict, sound_enabled: bool, now: float) -> None:
    global _last_sound
    _reap()
    sev = alert["severity"]
    if sound_enabled and sev in SOUNDS and (_last_sound is None or now - _last_sound >= SOUND_COOLDOWN):
        _last_sound = now
        _spawn(["pw-play", SOUNDS[sev]])
    urgency = "critical" if sev in ("HIGH", "CRITICAL") else "normal"
    # "--": um resumo começando com "-" não pode virar opção do notify-send
    _spawn(["notify-send", "--app-name=Mandacaru", f"--urgency={urgency}", "--",
            f"Mandacaru: {sev}", f"{alert['rule']}: {alert['summary']}"])


def load_settings(data: dict[str, Any]) -> tuple[str, str, bool]:
    """(socket, severidade mínima, som) da seção `edr`, com os padrões no que faltar ou for inválido."""
    edr = data.get("edr") if isinstance(data.get("edr"), dict) else {}
    sock = edr.get("socket")
    sock = sock if isinstance(sock, str) and sock else DEFAULT_SOCKET
    sev = str(edr.get("notify_min_severity", DEFAULT_MIN_SEVERITY)).upper()
    if sev not in SEVERITIES:
        _warn_once("sev", f"notify_min_severity inválido ({edr.get('notify_min_severity')!r}): usando MEDIUM")
        sev = DEFAULT_MIN_SEVERITY
    sound = edr.get("sound", True)
    return sock, sev, sound if isinstance(sound, bool) else True


def _read_alerts(conn: socket.socket, stop: threading.Event):
    """Gera as linhas completas da conexão até o EOF. Fragmento sem \\n no fim é descartado."""
    buf = b""
    conn.settimeout(0.5)  # para o stop ser visto mesmo sem alertas chegando
    while not stop.is_set():
        try:
            chunk = conn.recv(65536)
        except socket.timeout:
            continue
        except OSError:
            return
        if not chunk:
            return
        buf += chunk
        *lines, buf = buf.split(b"\n")
        yield from lines
        if len(buf) > MAX_LINE:
            buf = b""


def run(socket_path: str, min_severity: str, sound_enabled: bool, stop: threading.Event | None = None,
        retry_base: float = 2.0, retry_max: float = 30.0) -> None:
    stop = stop or threading.Event()
    wait = retry_base
    waiting = False
    while not stop.is_set():
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            conn.connect(socket_path)
        except PermissionError:
            conn.close()
            _warn_once("perm", "sem permissão no socket: entre no grupo mandacaru")
            stop.wait(retry_max)
            continue
        except OSError:
            conn.close()
            if not waiting:
                print(f"[edr-notify] aguardando o Mandacaru em {socket_path}", file=sys.stderr, flush=True)
                waiting = True
            stop.wait(wait)
            wait = min(wait * 2, retry_max)
            continue
        waiting = False
        wait = retry_base
        _warned.discard("perm")
        try:
            for line in _read_alerts(conn, stop):
                alert = parse_alert(line)
                if alert and should_notify(alert, min_severity):
                    notify(alert, sound_enabled, time.monotonic())
        finally:
            conn.close()


def main() -> int:
    from .config_store import ConfigStore

    sock, sev, sound = load_settings(ConfigStore().data)
    try:
        run(sock, sev, sound)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
