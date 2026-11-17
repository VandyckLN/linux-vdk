"""Orquestração do instalador orientada a dados para o Assistente de Boas-Vindas."""

from __future__ import annotations

import os
import shlex
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SETUP_DEV_SCRIPT = PROJECT_ROOT / "dev-stack" / "setup-dev-env.sh"
SYSTEM_TUNING_SCRIPT = PROJECT_ROOT / "system" / "apply-system-tuning.sh"


@dataclass(frozen=True)
class StackOption:
    """Editor, runtime ou recurso de sistema selecionável."""

    option_id: str
    title: str
    subtitle: str


EDITORS: list[StackOption] = [
    StackOption("neovim", "Neovim", "Leve, direto no terminal com config limpa"),
    StackOption("vscode", "VS Code", "Repositório oficial Microsoft APT"),
    StackOption("zed", "Zed Editor", "Editor nativo rápido em Rust"),
    StackOption("cursor", "Cursor", "Instrução/download oficial .deb"),
]

RUNTIMES: list[StackOption] = [
    StackOption("node@lts", "Node.js LTS", "Via mise"),
    StackOption("python@3.12", "Python", "Via mise"),
    StackOption("go@latest", "Go", "Via mise"),
    StackOption("rust@latest", "Rust", "Via mise"),
]


@dataclass
class OnboardingSelection:
    """Escolhas do usuário coletadas pelo Assistente do 1º Boot."""

    orientation: str = "vertical"
    edge: str = "left"
    editor: str = "neovim"
    runtimes: list[str] | None = None
    install_cli: bool = True
    install_dotfiles: bool = True
    install_docker: bool = False
    apply_system_tuning: bool = True
    no_snap_pin: bool = False


def build_commands(sel: OnboardingSelection) -> list[list[str]]:
    """Traduz as escolhas do assistente em chamadas idempotentes de scripts de shell."""
    commands: list[list[str]] = []

    if sel.apply_system_tuning:
        cmd = ["bash", str(SYSTEM_TUNING_SCRIPT)]
        if sel.no_snap_pin:
            cmd.append("--no-snap")
        commands.append(cmd)

    dev_cmd = ["bash", str(SETUP_DEV_SCRIPT)]
    has_dev_work = False

    if sel.install_cli:
        dev_cmd.append("--cli")
        has_dev_work = True
    if sel.install_dotfiles:
        dev_cmd.append("--dotfiles")
        has_dev_work = True

    runtimes = sel.runtimes or []
    if runtimes:
        dev_cmd.extend(["--mise", "--runtimes", ",".join(runtimes)])
        has_dev_work = True

    if sel.install_docker:
        dev_cmd.append("--docker")
        has_dev_work = True

    if sel.editor:
        dev_cmd.extend(["--editor", sel.editor])
        has_dev_work = True

    if has_dev_work:
        commands.append(dev_cmd)

    return commands


def run_commands(
    commands: list[list[str]],
    on_log: Callable[[str], None],
    dry_run: bool = False,
) -> bool:
    """Executa os comandos de setup em sequência, enviando stdout/stderr para on_log."""
    for cmd in commands:
        printable = " ".join(shlex.quote(part) for part in cmd)
        on_log(f"$ {printable}")
        if dry_run:
            on_log("[dry-run] simulado com sucesso.")
            continue

        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env={**os.environ, "LUMEN_ELEVATE": "pkexec"},
            )
            assert proc.stdout is not None
            for line in proc.stdout:
                on_log(line.rstrip())
            code = proc.wait()
            if code != 0:
                on_log(f"[erro] comando retornou código {code}")
                return False
        except OSError as exc:
            on_log(f"[erro] falha ao iniciar comando: {exc}")
            return False

    return True
