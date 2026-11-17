"""Janela principal do Curved Glass Shell com suporte a Wayland Layer-Shell e modo Preview."""

from __future__ import annotations

import ctypes
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

# Garante que a libgtk4-layer-shell seja pré-carregada globalmente antes da libwayland-client, quando disponível.
for _lib_name in ("libgtk4-layer-shell.so.0", "libgtk4-layer-shell.so"):
    try:
        ctypes.CDLL(_lib_name, mode=ctypes.RTLD_GLOBAL)
        break
    except OSError:
        continue

import gi  # noqa: E402

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

try:
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell  # type: ignore[attr-defined]

    HAS_LAYER_SHELL = True
except (ImportError, ValueError):
    Gtk4LayerShell = None
    HAS_LAYER_SHELL = False

from .config_store import ConfigStore  # noqa: E402
from .system_metrics import SystemMetrics  # noqa: E402
from .widgets import NavMenu, NavSection, NoticeCard, ProfileCard  # noqa: E402
from .widgets.nav_menu import NavSubItem  # noqa: E402

CSS_PATH = Path(__file__).resolve().parent / "styles" / "curved_glass.css"


def _build_dev_sections(cfg: dict[str, Any]) -> list[NavSection]:
    term = str(cfg.get("terminal_cmd", "kitty"))
    editor = str(cfg.get("editor_cmd", "code"))
    return [
        NavSection(
            section_id="workspaces",
            icon="⌘",
            label="Workspaces",
            children=[
                NavSubItem("ws-term", "Terminal GPU", term),
                NavSubItem("ws-editor", "Editor / IDE", editor),
                NavSubItem("ws-projects", "Projetos (~/projetos)", f"{term} -e bash -lc 'cd ~/projetos && ls -la && exec bash'"),
            ],
        ),
        NavSection(
            section_id="services",
            icon="◫",
            label="Containers",
            children=[
                NavSubItem("svc-ps", "Docker Containers", f"{term} -e bash -lc 'docker ps -a; read -p \"Enter...\"'"),
                NavSubItem("svc-ports", "Portas Locais", f"{term} -e bash -lc 'ss -tulpn; read -p \"Enter...\"'"),
            ],
        ),
        NavSection(
            section_id="tools",
            icon="⚙",
            label="Dev Tools",
            children=[
                NavSubItem("tool-btop", "Monitor (btop/top)", f"{term} -e bash -lc 'command -v btop >/dev/null && btop || top'"),
                NavSubItem("tool-mise", "Runtimes (mise)", f"{term} -e bash -lc 'command -v mise >/dev/null && mise ls || echo Instale mise na Fase 2; read -p \"Enter...\"'"),
            ],
        ),
        NavSection(section_id="git", icon="⎇", label="Git / Repos", command=f"{term} -e bash -lc 'cd ~/projetos && git status 2>/dev/null; exec bash'"),
        NavSection(section_id="network", icon="◎", label="Rede & VPN"),
    ]


class CurvedSidebarWindow(Gtk.ApplicationWindow):
    """Barra de shell flutuante em glassmorphism com modos de barra lateral vertical e dock horizontal."""

    def __init__(self, app: Gtk.Application, config: ConfigStore, preview: bool = False) -> None:
        super().__init__(application=app, title="Lumen Curved Shell")
        self.config = config
        self.preview = preview
        self.metrics = SystemMetrics(str(config.data.get("projects_dir", "~/projetos")))
        self._use_layer_shell = (
            not preview and HAS_LAYER_SHELL and Gtk4LayerShell.is_supported()
        )

        self.add_css_class("curved-shell-window")
        if not self._use_layer_shell:
            self.add_css_class("curved-shell-preview")
            self.set_default_size(980, 740)
        else:
            self._init_layer_shell()

        self._load_css()
        self._build_ui()
        self._apply_layout_mode()
        self._refresh_metrics()
        GLib.timeout_add_seconds(2, self._refresh_metrics)

    def _init_layer_shell(self) -> None:
        Gtk4LayerShell.init_for_window(self)
        Gtk4LayerShell.set_namespace(self, "curved-shell")
        Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.TOP)
        Gtk4LayerShell.set_keyboard_mode(self, Gtk4LayerShell.KeyboardMode.ON_DEMAND)

    @staticmethod
    def _load_css() -> None:
        provider = Gtk.CssProvider()
        provider.load_from_path(str(CSS_PATH))
        display = Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

    def _build_ui(self) -> None:
        # O palco externo permite que o modo preview centralize/ancore a barra flutuante sobre um fundo escuro
        self.stage = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.stage.set_hexpand(True)
        self.stage.set_vexpand(True)

        self.shell_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.shell_box.add_css_class("glass-shell")

        self.profile_card = ProfileCard(
            distro_name=str(self.config.data.get("distro_name", "LUMEN")),
            user_cfg=self.config.data.get("user", {}),
            on_toggle_expand=self.toggle_expand,
            on_toggle_orientation=self.toggle_orientation,
        )

        self.nav_menu = NavMenu(
            sections=_build_dev_sections(self.config.data),
            on_activate=self._on_nav_activate,
        )

        self.spacer = Gtk.Box()
        self.spacer.set_vexpand(True)
        self.spacer.set_hexpand(True)

        self.notice_card = NoticeCard()

        self.divider = Gtk.Box()
        self.divider.add_css_class("glass-divider")

        # Controles do rodapé: alternador de orientação (visível no modo horizontal/compacto) + Configurações + Energia
        self.footer_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)

        self.orient_pill = Gtk.Button(label="↔ Lateral / Horizontal")
        self.orient_pill.add_css_class("orientation-pill")
        self.orient_pill.set_tooltip_text("Alternar posição da barra (Lateral ↔ Horizontal)")
        self.orient_pill.connect("clicked", lambda *_: self.toggle_orientation())

        self.settings_btn = self._make_footer_btn("⚙", "Configurações", self._on_open_settings)
        self.logout_btn = self._make_footer_btn("⎋", "Sessão / Sair", self._on_logout)

        self.footer_box.append(self.orient_pill)
        self.footer_box.append(self.settings_btn)
        self.footer_box.append(self.logout_btn)

        self.shell_box.append(self.profile_card)
        self.shell_box.append(self.nav_menu)
        self.shell_box.append(self.spacer)
        self.shell_box.append(self.notice_card)
        self.shell_box.append(self.divider)
        self.shell_box.append(self.footer_box)

        self.stage.append(self.shell_box)
        self.set_child(self.stage)

    @staticmethod
    def _make_footer_btn(icon: str, label_text: str, handler: Any) -> Gtk.Button:
        btn = Gtk.Button()
        btn.add_css_class("nav-item")
        btn.set_tooltip_text(label_text)
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        ic = Gtk.Label(label=icon)
        ic.set_width_chars(2)
        lbl = Gtk.Label(label=label_text, xalign=0.0)
        box.append(ic)
        box.append(lbl)
        btn.set_child(box)
        btn.connect("clicked", lambda *_: handler())
        return btn

    def _set_footer_labels_visible(self, visible: bool) -> None:
        for btn in (self.settings_btn, self.logout_btn):
            box = btn.get_child()
            if isinstance(box, Gtk.Box):
                lbl = box.get_last_child()
                if lbl is not None:
                    lbl.set_visible(visible)
            if visible:
                btn.remove_css_class("nav-item-compact")
            else:
                btn.add_css_class("nav-item-compact")

    def toggle_expand(self) -> None:
        self.config.expanded = not self.config.expanded
        self._apply_layout_mode()

    def toggle_orientation(self) -> None:
        self.config.toggle_orientation()
        self._apply_layout_mode()

    def _apply_layout_mode(self) -> None:
        orientation = self.config.orientation
        expanded = self.config.expanded
        is_vertical = orientation == "vertical"
        edge = self.config.get_edge()

        self.shell_box.set_orientation(
            Gtk.Orientation.VERTICAL if is_vertical else Gtk.Orientation.HORIZONTAL
        )
        self.footer_box.set_orientation(
            Gtk.Orientation.VERTICAL if is_vertical else Gtk.Orientation.HORIZONTAL
        )

        # Alterna as classes CSS de modo
        for cls in ("compact", "horizontal"):
            self.shell_box.remove_css_class(cls)

        if not is_vertical:
            self.shell_box.add_css_class("horizontal")
            self.shell_box.set_size_request(-1, 60)
            self.shell_box.set_halign(Gtk.Align.CENTER)
            self.shell_box.set_valign(Gtk.Align.START if edge == "top" else Gtk.Align.END)
            self.orient_pill.set_label("↕ Lateral")
            self.orient_pill.set_visible(True)
            self.divider.set_visible(False)
        else:
            width = 272 if expanded else 66
            self.shell_box.set_size_request(width, -1)
            self.shell_box.set_halign(Gtk.Align.END if edge == "right" else Gtk.Align.START)
            self.shell_box.set_valign(Gtk.Align.CENTER)
            if not expanded:
                self.shell_box.add_css_class("compact")
                self.orient_pill.set_label("↔")
                self.orient_pill.set_visible(True)
            else:
                self.orient_pill.set_visible(False)
            self.divider.set_visible(True)

        self.shell_box.set_margin_start(16)
        self.shell_box.set_margin_end(16)
        self.shell_box.set_margin_top(16)
        self.shell_box.set_margin_bottom(16)

        self.profile_card.set_mode(orientation, expanded)
        self.nav_menu.set_mode(orientation, expanded)
        self.notice_card.set_mode(orientation, expanded)
        self._set_footer_labels_visible(is_vertical and expanded)

        if self._use_layer_shell:
            self._update_layer_anchors(is_vertical, edge)

    def _update_layer_anchors(self, is_vertical: bool, edge: str) -> None:
        all_edges = (
            Gtk4LayerShell.Edge.LEFT,
            Gtk4LayerShell.Edge.RIGHT,
            Gtk4LayerShell.Edge.TOP,
            Gtk4LayerShell.Edge.BOTTOM,
        )
        for e in all_edges:
            Gtk4LayerShell.set_anchor(self, e, False)
            Gtk4LayerShell.set_margin(self, e, 0)

        if is_vertical:
            anchor = (
                Gtk4LayerShell.Edge.RIGHT if edge == "right" else Gtk4LayerShell.Edge.LEFT
            )
            Gtk4LayerShell.set_anchor(self, anchor, True)
            Gtk4LayerShell.set_margin(self, anchor, 14)
        else:
            anchor = (
                Gtk4LayerShell.Edge.TOP if edge == "top" else Gtk4LayerShell.Edge.BOTTOM
            )
            Gtk4LayerShell.set_anchor(self, anchor, True)
            Gtk4LayerShell.set_margin(self, anchor, 14)

        if self.config.data.get("bar", {}).get("exclusive_zone", False):
            Gtk4LayerShell.auto_exclusive_zone_enable(self)
        else:
            Gtk4LayerShell.set_exclusive_zone(self, 0)

    def _refresh_metrics(self) -> bool:
        snap = self.metrics.snapshot()
        self.notice_card.update_snapshot(snap)
        return True

    def _on_nav_activate(self, item_id: str, command: str | None) -> None:
        if command:
            self._spawn_command(command)

    @staticmethod
    def _spawn_command(command: str) -> None:
        parts = shlex.split(command)
        if not parts:
            return
        if not shutil.which(parts[0]):
            return
        subprocess.Popen(
            parts,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def _on_open_settings(self) -> None:
        project_root = Path(__file__).resolve().parent.parent
        subprocess.Popen(
            [sys.executable, "-m", "welcome.main"],
            cwd=str(project_root),
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def _on_logout(self) -> None:
        self.close()
