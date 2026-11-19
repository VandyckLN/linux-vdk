"""Janela de decisão da quarentena do Mandacaru (Confio / Analisar / Manter isolado).

Esta parte é a lógica pura e não importa `gi` no topo: a máquina de dev não tem GTK.
A interface GTK4 fica em `run_window()`.
"""
import argparse
import json
import os
import re
import sys
from dataclasses import dataclass

CASE_ID = re.compile(r"[0-9a-f]{32}")
RELEASE = "/usr/libexec/mandacaru/quarantine-release"
DECIDE = "/usr/libexec/mandacaru/quarantine-decide"

INITIAL_BUTTONS = ("confiar", "analisar", "manter")
AFTER_ANALYSIS = ("confiar", "manter")
CLOSE_MS = 3000

VERDICTS = {
    "malicioso": "Malicioso. Recomendado manter isolado.",
    "legitimo_conhecido": "Arquivo legítimo conhecido (provável falso positivo).",
    "desconhecido": "Desconhecido. Nenhuma base conhece este arquivo.",
}


@dataclass(frozen=True)
class Outcome:
    message: str
    buttons: tuple[str, ...]
    close: bool
    verdict: str | None = None


def valid_id(value: object) -> bool:
    return isinstance(value, str) and CASE_ID.fullmatch(value) is not None


def commands(case_id: str) -> dict[str, list[str]]:
    """Comandos dos botões, sempre em lista e sem shell."""
    return {
        "confiar": ["pkexec", RELEASE, "confiar", case_id],
        "analisar": ["pkexec", DECIDE, "analisar", case_id, "--json"],
        "manter": ["pkexec", DECIDE, "manter", case_id],
    }


def _last_line(text: str) -> str:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    return lines[-1] if lines else ""


def _failed(rc: int, stderr: str, current: tuple[str, ...]) -> Outcome:
    message = f"Falhou (código {rc})."
    detail = _last_line(stderr)
    if detail:
        message += f"\n{detail}"
    return Outcome(message, current, False)


def outcome(action: str, rc: int, stdout: str, stderr: str,
            current: tuple[str, ...]) -> Outcome:
    """Traduz o resultado do pkexec em mensagem, botões ativos e se a janela fecha."""
    if rc == 3:
        return Outcome("Este caso não existe mais ou já foi resolvido.", (), False)
    if rc == 4:
        return Outcome("A quarentena foi adulterada. O arquivo não foi devolvido.", (), False)
    if rc in (126, 127):
        return Outcome("Autenticação cancelada.", current, False)
    if rc != 0:
        return _failed(rc, stderr, current)
    if action == "confiar":
        return Outcome(f"Arquivo devolvido. {_last_line(stdout)}", (), True)
    if action == "manter":
        return Outcome("Mantido isolado. Será apagado em 30 dias.", (), True)
    if action == "analisar":
        try:
            data = json.loads(stdout)
        except ValueError:
            return _failed(rc, stderr, current)
        if (not isinstance(data, dict) or data.get("v") != 1
                or data.get("verdict") not in VERDICTS):
            return _failed(rc, stderr, current)
        verdict = data["verdict"]
        message = VERDICTS[verdict]
        summary = data.get("summary")
        if isinstance(summary, str) and summary:
            message += f"\n{summary}"
        return Outcome(message, AFTER_ANALYSIS, False, verdict)
    return _failed(rc, stderr, current)


def spawn_failed(action: str, case_id: str, current: tuple[str, ...]) -> Outcome:
    return Outcome("Não foi possível rodar o pkexec. No terminal: "
                   f"sudo mandacaru quarentena {action} {case_id}", current, False)


def _case_id(value: str) -> str:
    if not valid_id(value):
        raise argparse.ArgumentTypeError(f"id inválido: {value!r}")
    return value


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="lumen-quarentena")
    p.add_argument("id", type=_case_id)
    p.add_argument("--rule", default="")
    p.add_argument("--summary", default="")
    return p.parse_args(argv)  # id inválido: argparse sai com código 2


def lock_path(case_id: str) -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(runtime, f"lumen-quarentena-{case_id}.lock")


def run_window(args: argparse.Namespace) -> int:
    raise NotImplementedError  # a janela GTK4 vem na Task 2


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    # import aqui: o edr_notify vai importar este módulo (evita import circular)
    from shell.edr_notify import acquire_single_instance
    lock = acquire_single_instance(lock_path(args.id))
    if lock is None:
        return 0  # já há uma janela para este caso
    try:
        return run_window(args)
    finally:
        lock.close()


if __name__ == "__main__":
    sys.exit(main())
