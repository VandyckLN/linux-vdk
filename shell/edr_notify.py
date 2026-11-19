"""Vigia do Mandacaru (EDR): som e popup na sessão para cada alerta relevante.

Conecta no socket de alertas do Mandacaru (contrato v1, uma linha JSON por alerta),
toca um som com `pw-play` e mostra um popup com `notify-send` (exibido pelo mako).
Roda na sessão Hyprland via `exec-once = /usr/bin/lumen-edr-notify`.
"""

from __future__ import annotations

import fcntl
import html
import json
import os
import socket
import subprocess
import sys
import threading
import time
from collections import deque
from typing import Any

from .quarantine_dialog import valid_id

SEVERITIES = ("INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL")
SOUND_REPEATS = 3  # toques por ocorrência; o clique no popup para antes
SOUND_GAP = 1.0  # pausa entre um toque e outro
# teto de cada pw-play: em algumas VMs ele não termina no fim do arquivo e toca para sempre
SOUND_MAX = {"MEDIUM": 2.0, "HIGH": 8.0, "CRITICAL": 8.0}
MAX_LINE = 64 * 1024
MEDIUM_EXPIRE_MS = 10000  # MEDIUM some sozinho; HIGH/CRITICAL ficam até a pessoa fechar
HEALTHY_CONNECTION = 5.0  # conexão que durou isso (ou trouxe dados) zera o backoff
DEFAULT_SOCKET = "/run/mandacaru/alerts.sock"
DEFAULT_MIN_SEVERITY = "MEDIUM"
SOUNDS = {
    "MEDIUM": "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
    "HIGH": "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
    "CRITICAL": "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
}

# janela de decisão da quarentena (o harness troca por um falso)
DIALOG_CMD: list[str] = [sys.executable, "-m", "shell.quarantine_dialog"]

_children: list[subprocess.Popen] = []
_ringing = threading.Event()  # um toque por vez: alerta novo durante um toque não sobrepõe
_warned: set[str] = set()
# ids de casos já anunciados (últimos ANNOUNCED_MAX): um arquivo que casa N regras chega
# como N alertas com o mesmo id, mas a pergunta só pode aparecer uma vez
ANNOUNCED_MAX = 256
_announced_order: deque[str] = deque()
_announced: set[str] = set()


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


def _first_announcement(case_id: str) -> bool:
    """True na primeira vez que o caso aparece; guarda só os últimos ANNOUNCED_MAX ids."""
    if case_id in _announced:
        return False
    _announced.add(case_id)
    _announced_order.append(case_id)
    if len(_announced_order) > ANNOUNCED_MAX:
        _announced.discard(_announced_order.popleft())
    return True


def _reap() -> None:
    _children[:] = [p for p in _children if p.poll() is None]


def _popen(cmd: list[str], stdout: int = subprocess.DEVNULL) -> subprocess.Popen | None:
    try:
        return subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                stdout=stdout, stderr=subprocess.DEVNULL)
    except OSError as exc:
        _warn_once(cmd[0], f"não foi possível rodar {cmd[0]}: {exc.strerror or exc}")
        return None


def _spawn(cmd: list[str], stdout: int = subprocess.DEVNULL) -> subprocess.Popen | None:
    """Dispara sem esperar: um notify-send travado não pode congelar a leitura do socket."""
    proc = _popen(cmd, stdout)
    if proc is not None:
        _children.append(proc)
    return proc


def _clicked(popup: subprocess.Popen | None) -> bool:
    """O popup fechou normalmente (clique ou expirou). Falha do notify-send não conta."""
    return popup is not None and popup.poll() == 0


def _ring(sound: str, max_play: float, popup: subprocess.Popen | None) -> None:
    """Toca até SOUND_REPEATS vezes; para na hora se o popup fechar."""
    try:
        for i in range(SOUND_REPEATS):
            if _clicked(popup):
                return
            player = _popen(["pw-play", sound])
            if player is None:
                return
            deadline = time.monotonic() + max_play
            while player.poll() is None and time.monotonic() < deadline and not _clicked(popup):
                time.sleep(0.05)
            if player.poll() is None:
                player.kill()
                player.wait()
            if i < SOUND_REPEATS - 1:
                gap_end = time.monotonic() + SOUND_GAP
                while time.monotonic() < gap_end and not _clicked(popup):
                    time.sleep(0.05)
    finally:
        _ringing.clear()


# "--opcao=valor" (e não duas palavras): um valor que começa com "-" não vira opção do argparse
def _open_on_click(popup: subprocess.Popen, case_id: str, rule: str, summary: str) -> None:
    """Espera o popup fechar; só a saída exata "default" (clique na ação) abre a janela."""
    try:
        out = popup.stdout.read()
        popup.wait()  # recolhe o notify-send
    except (OSError, ValueError):
        return
    finally:
        popup.stdout.close()
    if out.decode(errors="replace").strip() == "default":
        _spawn([*DIALOG_CMD, case_id, f"--rule={rule}", f"--summary={summary}"])


def notify(alert: dict, sound_enabled: bool) -> None:
    _reap()
    sev = alert["severity"]
    if sev in ("HIGH", "CRITICAL"):
        opts = ["--urgency=critical"]
    else:
        opts = ["--urgency=normal", f"--expire-time={MEDIUM_EXPIRE_MS}"]
    # o corpo do popup é markup Pango no mako: um "&" ou "<b>" num nome de arquivo
    # quebraria ou forjaria o texto
    body = html.escape(f"{alert['rule']}: {alert['summary']}", quote=False)
    # --wait com ação padrão: o notify-send só termina quando o popup fecha (clique ou
    # expirou), e é isso que para o som. "--": um resumo começando com "-" não vira opção.
    case_id = alert.get("quarantine_id")
    if valid_id(case_id):
        # arquivo isolado: o clique abre a janela de decisão, então lemos o stdout do popup
        popup = _spawn(["notify-send", "--app-name=Mandacaru", "--icon=mandacaru", *opts, "--wait",
                        "--action=default=O que fazer?", "--", f"Mandacaru: arquivo isolado ({sev})", body],
                       stdout=subprocess.PIPE)
        if popup is not None:
            threading.Thread(target=_open_on_click, args=(popup, case_id, alert["rule"], alert["summary"]),
                             daemon=True).start()
    else:
        popup = _spawn(["notify-send", "--app-name=Mandacaru", "--icon=mandacaru", *opts, "--wait",
                        "--action=default=Silenciar", "--", f"Mandacaru: {sev}", body])
    if sound_enabled and sev in SOUNDS and not _ringing.is_set():
        _ringing.set()
        threading.Thread(target=_ring, args=(SOUNDS[sev], SOUND_MAX[sev], popup), daemon=True).start()


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


def acquire_single_instance(path: str):
    """Trava de um vigia por usuário. Devolve o arquivo (mantenha aberto) ou None se já há outro.

    Sem isso, sair e entrar de novo no Hyprland deixa o vigia antigo vivo (ele não depende
    do Wayland) e cada alerta vira N popups e N sons.
    """
    fh = open(path, "a")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.close()
        return None
    return fh


def _read_alerts(conn: socket.socket, stop: threading.Event, got_data: list[bool]):
    """Gera as linhas completas da conexão até o EOF. Fragmento sem \\n no fim é descartado."""
    buf = b""
    conn.settimeout(0.5)  # para o stop ser visto mesmo sem alertas chegando
    while not stop.is_set():
        try:
            chunk = conn.recv(65536)
        except socket.timeout:
            _reap()  # popup que fechou sem alerta novo chegando não pode virar zumbi
            continue
        except OSError:
            return
        if not chunk:
            return
        got_data[0] = True
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
        _warned.discard("perm")
        got_data = [False]
        started = time.monotonic()
        try:
            for line in _read_alerts(conn, stop, got_data):
                alert = parse_alert(line)
                if not alert:
                    continue
                case_id = alert.get("quarantine_id")
                if valid_id(case_id):
                    # arquivo já isolado: toda decisão pendente vira pergunta, qualquer que
                    # seja o limiar, mas uma vez só por caso
                    if _first_announcement(case_id):
                        notify(alert, sound_enabled)
                elif should_notify(alert, min_severity):
                    notify(alert, sound_enabled)
        finally:
            conn.close()
        if got_data[0] or time.monotonic() - started >= HEALTHY_CONNECTION:
            wait = retry_base
        else:
            # aceitou e fechou na hora (produtor no teto de clientes): sem pausa,
            # o vigia giraria a ~1 núcleo de CPU
            stop.wait(wait)
            wait = min(wait * 2, retry_max)


def main() -> int:
    from .config_store import ConfigStore

    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    lock = acquire_single_instance(os.path.join(runtime, "lumen-edr-notify.lock"))
    if lock is None:
        print("[edr-notify] já existe um vigia rodando para este usuário", file=sys.stderr, flush=True)
        return 0
    sock, sev, sound = load_settings(ConfigStore().data)
    try:
        run(sock, sev, sound)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
