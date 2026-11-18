"""Armazenamento persistente de configuração do Curved Glass Shell."""

from __future__ import annotations

import copy
import json
import os
import pwd
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "config" / "shell.default.json"
USER_CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lumen-os"
USER_CONFIG_PATH = USER_CONFIG_DIR / "shell.json"


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def display_name(user_cfg: dict[str, Any]) -> str:
    """Nome exibido no perfil: o da config ou, se vazio, o nome real do usuário do sistema."""
    name = str(user_cfg.get("name") or "").strip()
    if name:
        return name
    entry = pwd.getpwuid(os.getuid())
    return entry.pw_gecos.split(",")[0].strip() or entry.pw_name


class ConfigStore:
    """Carrega, valida e salva a configuração do shell do usuário."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or USER_CONFIG_PATH
        self.defaults = self._read_json(DEFAULT_CONFIG_PATH)
        self.data = self.load()

    @staticmethod
    def _read_json(file_path: Path) -> dict[str, Any]:
        if not file_path.exists():
            return {}
        try:
            with file_path.open("r", encoding="utf-8") as fh:
                parsed = json.load(fh)
            return parsed if isinstance(parsed, dict) else {}
        except (OSError, json.JSONDecodeError):
            return {}

    def load(self) -> dict[str, Any]:
        user_data = self._read_json(self.path)
        return _deep_merge(self.defaults, user_data)

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w", encoding="utf-8") as fh:
            json.dump(self.data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")

    @property
    def orientation(self) -> str:
        val = self.data.get("bar", {}).get("orientation", "vertical")
        return val if val in ("vertical", "horizontal") else "vertical"

    @orientation.setter
    def orientation(self, value: str) -> None:
        if value not in ("vertical", "horizontal"):
            raise ValueError(f"Orientação não suportada: {value}")
        self.data.setdefault("bar", {})["orientation"] = value
        self.save()

    @property
    def expanded(self) -> bool:
        return bool(self.data.get("bar", {}).get("expanded", False))

    @expanded.setter
    def expanded(self, value: bool) -> None:
        self.data.setdefault("bar", {})["expanded"] = bool(value)
        self.save()

    def get_edge(self) -> str:
        bar = self.data.get("bar", {})
        if self.orientation == "vertical":
            edge = bar.get("vertical_edge", "left")
            return edge if edge in ("left", "right") else "left"
        edge = bar.get("horizontal_edge", "bottom")
        return edge if edge in ("top", "bottom") else "bottom"

    def toggle_orientation(self) -> str:
        new_orientation = "horizontal" if self.orientation == "vertical" else "vertical"
        self.orientation = new_orientation
        return new_orientation
