"""Telemetria leve do sistema e de desenvolvimento, sem dependências pesadas."""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class SystemSnapshot:
    """Métricas pontuais exibidas nos cards de aviso e dev do shell."""

    cpu_percent: int
    ram_used_gb: float
    ram_total_gb: float
    ram_percent: int
    docker_running: int
    docker_available: bool
    listening_ports: list[str]
    recent_projects: list[Path]
    hostname: str


class SystemMetrics:
    """Lê o /proc diretamente para overhead mínimo e consulta serviços dev opcionais."""

    def __init__(self, projects_dir: str = "~/projetos") -> None:
        self.projects_dir = Path(os.path.expanduser(projects_dir))
        self._prev_idle = 0
        self._prev_total = 0

    def read_cpu_percent(self) -> int:
        try:
            with open("/proc/stat", "r", encoding="utf-8") as fh:
                line = fh.readline()
            parts = [int(x) for x in line.split()[1:9]]
            idle = parts[3] + parts[4]
            total = sum(parts)
            diff_idle = idle - self._prev_idle
            diff_total = total - self._prev_total
            self._prev_idle = idle
            self._prev_total = total
            if diff_total <= 0:
                return 0
            return max(0, min(100, int(100 * (diff_total - diff_idle) / diff_total)))
        except (OSError, ValueError, IndexError):
            return 0

    @staticmethod
    def read_memory() -> tuple[float, float, int]:
        meminfo: dict[str, int] = {}
        try:
            with open("/proc/meminfo", "r", encoding="utf-8") as fh:
                for line in fh:
                    key, _, rest = line.partition(":")
                    val_kb = int(rest.strip().split()[0])
                    meminfo[key] = val_kb
            total_kb = meminfo.get("MemTotal", 1)
            avail_kb = meminfo.get("MemAvailable", 0)
            used_kb = max(0, total_kb - avail_kb)
            total_gb = total_kb / (1024 * 1024)
            used_gb = used_kb / (1024 * 1024)
            pct = int(round((used_kb / total_kb) * 100)) if total_kb else 0
            return used_gb, total_gb, pct
        except (OSError, ValueError, IndexError):
            return 0.0, 0.0, 0

    @staticmethod
    def read_docker_containers() -> tuple[bool, int]:
        if not shutil.which("docker"):
            return False, 0
        try:
            proc = subprocess.run(
                ["docker", "ps", "-q"],
                capture_output=True,
                text=True,
                timeout=1.0,
                check=False,
            )
            if proc.returncode != 0:
                return False, 0
            lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
            return True, len(lines)
        except (OSError, subprocess.SubprocessError):
            return False, 0

    @staticmethod
    def read_listening_ports(limit: int = 4) -> list[str]:
        """Lê as portas TCP IPv4/IPv6 em escuta a partir de /proc/net/tcp* sem iniciar o ss."""
        ports: set[int] = set()
        for proc_file in ("/proc/net/tcp", "/proc/net/tcp6"):
            try:
                with open(proc_file, "r", encoding="utf-8") as fh:
                    next(fh, None)
                    for line in fh:
                        cols = line.split()
                        if len(cols) >= 4 and cols[3] == "0A":  # TCP_LISTEN
                            _, _, port_hex = cols[1].partition(":")
                            port = int(port_hex, 16)
                            if port >= 1024:
                                ports.add(port)
            except (OSError, ValueError):
                continue
        return [f":{p}" for p in sorted(ports)[:limit]]

    def list_recent_projects(self, limit: int = 4) -> list[Path]:
        if not self.projects_dir.exists() or not self.projects_dir.is_dir():
            return []
        candidates: list[tuple[float, Path]] = []
        try:
            for entry in self.projects_dir.iterdir():
                if entry.is_dir() and not entry.name.startswith("."):
                    candidates.append((entry.stat().st_mtime, entry))
        except OSError:
            return []
        candidates.sort(key=lambda item: item[0], reverse=True)
        return [item[1] for item in candidates[:limit]]

    def snapshot(self) -> SystemSnapshot:
        cpu = self.read_cpu_percent()
        used_gb, total_gb, ram_pct = self.read_memory()
        docker_ok, docker_count = self.read_docker_containers()
        return SystemSnapshot(
            cpu_percent=cpu,
            ram_used_gb=used_gb,
            ram_total_gb=total_gb,
            ram_percent=ram_pct,
            docker_running=docker_count,
            docker_available=docker_ok,
            listening_ports=self.read_listening_ports(),
            recent_projects=self.list_recent_projects(),
            hostname=socket.gethostname(),
        )
