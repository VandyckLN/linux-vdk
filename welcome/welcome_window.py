"""GTK4 Curved Glass First-Boot & Dev Setup Wizard."""

from __future__ import annotations

import threading
from pathlib import Path

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from shell.config_store import USER_CONFIG_DIR, ConfigStore  # noqa: E402

from .stack_installer import (  # noqa: E402
    EDITORS,
    RUNTIMES,
    OnboardingSelection,
    build_commands,
    run_commands,
)

BASE_CSS = Path(__file__).resolve().parent.parent / "shell" / "styles" / "curved_glass.css"

EXTRA_CSS = b"""
.welcome-card {
    background-color: rgba(24, 27, 34, 0.70);
    background-image: linear-gradient(
        155deg,
        rgba(255, 255, 255, 0.14) 0%,
        rgba(255, 255, 255, 0.04) 45%,
        rgba(10, 12, 18, 0.30) 100%
    );
    border: 1.5px solid rgba(255, 255, 255, 0.32);
    border-radius: 26px;
    box-shadow: 0 24px 54px rgba(0, 0, 0, 0.60), inset 0 1px 0 rgba(255, 255, 255, 0.42);
    color: #f3f5f8;
    padding: 24px;
}

.choice-card {
    background-color: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 14px;
    padding: 10px 14px;
    color: #eef2f8;
    transition: all 150ms ease;
}

.choice-card:hover {
    background-color: rgba(255, 255, 255, 0.12);
    border-color: rgba(255, 255, 255, 0.32);
}

.choice-card.selected {
    background-color: rgba(255, 255, 255, 0.90);
    border-color: #ffffff;
    color: #161920;
}

.primary-cta {
    background-image: linear-gradient(135deg, #748dff 0%, #9b70ff 100%);
    border: 1px solid rgba(255, 255, 255, 0.45);
    border-radius: 14px;
    color: #ffffff;
    font-weight: 700;
    padding: 10px 18px;
}

.primary-cta:hover {
    opacity: 0.92;
}

.log-view {
    background-color: rgba(10, 12, 16, 0.68);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 14px;
    color: #cfd8ea;
    font-family: monospace;
    font-size: 11px;
    padding: 10px;
}
"""


class WelcomeWindow(Gtk.ApplicationWindow):
    """Configures bar orientation, editor, runtimes, and Ubuntu dev tuning."""

    def __init__(self, app: Gtk.Application, config: ConfigStore, dry_run: bool = False) -> None:
        super().__init__(application=app, title="Linux VDK • Bem-vindo (1º Boot)")
        self.config = config
        self.dry_run = dry_run
        self._selected_orientation = config.orientation
        self._selected_editor = "neovim"
        self._editor_buttons: dict[str, Gtk.Button] = {}
        self._runtime_checks: dict[str, Gtk.CheckButton] = {}
        self._running = False

        self.add_css_class("curved-shell-preview")
        self.set_default_size(760, 680)

        self._load_css()
        self._build_ui()

    @staticmethod
    def _load_css() -> None:
        display = Gdk.Display.get_default()
        if display is None:
            return
        for provider_source in (BASE_CSS, EXTRA_CSS):
            provider = Gtk.CssProvider()
            if isinstance(provider_source, Path):
                provider.load_from_path(str(provider_source))
            else:
                provider.load_from_data(provider_source)
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

    def _build_ui(self) -> None:
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        outer.set_margin_start(24)
        outer.set_margin_end(24)
        outer.set_margin_top(20)
        outer.set_margin_bottom(20)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        card.add_css_class("welcome-card")

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        badge = Gtk.Label(label="UBUNTU 26.04 • LINUX VDK", xalign=0.0)
        badge.add_css_class("notice-badge")
        title = Gtk.Label(label="Bem-vindo ao Linux VDK", xalign=0.0)
        title.add_css_class("notice-title")
        subtitle = Gtk.Label(
            label="Escolha o estilo da barra e sua stack inicial de programação.",
            xalign=0.0,
        )
        subtitle.add_css_class("profile-subtitle")
        header.append(badge)
        header.append(title)
        header.append(subtitle)
        card.append(header)

        # 1. Orientação da barra
        card.append(self._section_title("1. POSIÇÃO DA BARRA CURVED GLASS"))
        orient_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        orient_row.set_homogeneous(True)

        self.btn_vertical = self._make_choice_card(
            "Barra Lateral",
            "Painel vertical expansível (estilo do vídeo)",
            lambda: self._select_orientation("vertical"),
        )
        self.btn_horizontal = self._make_choice_card(
            "Barra Horizontal",
            "Dock flutuante na base da tela",
            lambda: self._select_orientation("horizontal"),
        )
        orient_row.append(self.btn_vertical)
        orient_row.append(self.btn_horizontal)
        card.append(orient_row)

        # 2. Editor Principal
        card.append(self._section_title("2. EDITOR PRINCIPAL"))
        editor_grid = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        editor_grid.set_homogeneous(True)
        for opt in EDITORS:
            btn = self._make_choice_card(
                opt.title,
                opt.subtitle,
                lambda oid=opt.option_id: self._select_editor(oid),
            )
            self._editor_buttons[opt.option_id] = btn
            editor_grid.append(btn)
        card.append(editor_grid)

        # 3. Runtimes (mise)
        card.append(self._section_title("3. RUNTIMES VIA MISE"))
        rt_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        for rt in RUNTIMES:
            chk = Gtk.CheckButton(label=rt.title)
            chk.set_active(rt.option_id in ("node@lts", "python@3.12"))
            self._runtime_checks[rt.option_id] = chk
            rt_row.append(chk)
        card.append(rt_row)

        # 4. Otimizações & Ferramentas Base
        card.append(self._section_title("4. SISTEMA & CONTAINERS"))
        sys_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.chk_tuning = Gtk.CheckButton(
            label="Otimizações Ubuntu Dev (zram comprimido + inotify 524k watchers)"
        )
        self.chk_tuning.set_active(True)
        self.chk_cli = Gtk.CheckButton(
            label="Pacotes CLI leves (git, ripgrep, fd, fzf, btop, tmux, JetBrains Mono)"
        )
        self.chk_cli.set_active(True)
        self.chk_dotfiles = Gtk.CheckButton(
            label="Aplicar dotfiles (Kitty transparente + Starship + tmux + Neovim)"
        )
        self.chk_dotfiles.set_active(True)
        self.chk_docker = Gtk.CheckButton(label="Instalar Docker + Docker Compose")
        self.chk_no_snap = Gtk.CheckButton(label="Bloquear snapd via APT pinning (--no-snap)")

        for chk in (
            self.chk_tuning,
            self.chk_cli,
            self.chk_dotfiles,
            self.chk_docker,
            self.chk_no_snap,
        ):
            sys_box.append(chk)
        card.append(sys_box)

        # Log output
        self.log_buffer = Gtk.TextBuffer()
        self.log_view = Gtk.TextView(buffer=self.log_buffer)
        self.log_view.set_editable(False)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.log_view.add_css_class("log-view")
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_min_content_height(120)
        log_scroll.set_child(self.log_view)
        card.append(log_scroll)

        # Actions
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.status_lbl = Gtk.Label(
            label="Modo simulação (--dry-run)" if self.dry_run else "Pronto para aplicar",
            xalign=0.0,
        )
        self.status_lbl.add_css_class("profile-subtitle")
        self.status_lbl.set_hexpand(True)

        self.apply_btn = Gtk.Button(label="Aplicar e Salvar Setup")
        self.apply_btn.add_css_class("primary-cta")
        self.apply_btn.connect("clicked", lambda *_: self._on_apply())

        close_btn = Gtk.Button(label="Fechar")
        close_btn.add_css_class("icon-btn")
        close_btn.connect("clicked", lambda *_: self.close())

        actions.append(self.status_lbl)
        actions.append(close_btn)
        actions.append(self.apply_btn)
        card.append(actions)

        outer.append(card)
        scroll.set_child(outer)
        self.set_child(scroll)

        self._refresh_choice_styles()

    @staticmethod
    def _section_title(text: str) -> Gtk.Label:
        lbl = Gtk.Label(label=text, xalign=0.0)
        lbl.add_css_class("section-label")
        return lbl

    @staticmethod
    def _make_choice_card(title: str, subtitle: str, on_click) -> Gtk.Button:
        btn = Gtk.Button()
        btn.add_css_class("choice-card")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        t_lbl = Gtk.Label(label=title, xalign=0.0)
        t_lbl.add_css_class("profile-name")
        s_lbl = Gtk.Label(label=subtitle, xalign=0.0)
        s_lbl.add_css_class("profile-subtitle")
        s_lbl.set_wrap(True)
        box.append(t_lbl)
        box.append(s_lbl)
        btn.set_child(box)
        btn.connect("clicked", lambda *_: on_click())
        return btn

    def _select_orientation(self, orientation: str) -> None:
        self._selected_orientation = orientation
        self._refresh_choice_styles()

    def _select_editor(self, editor_id: str) -> None:
        self._selected_editor = editor_id
        self._refresh_choice_styles()

    def _refresh_choice_styles(self) -> None:
        for btn, active in (
            (self.btn_vertical, self._selected_orientation == "vertical"),
            (self.btn_horizontal, self._selected_orientation == "horizontal"),
        ):
            if active:
                btn.add_css_class("selected")
            else:
                btn.remove_css_class("selected")

        for oid, btn in self._editor_buttons.items():
            if oid == self._selected_editor:
                btn.add_css_class("selected")
            else:
                btn.remove_css_class("selected")

    def _append_log(self, line: str) -> None:
        def _insert() -> bool:
            end_iter = self.log_buffer.get_end_iter()
            self.log_buffer.insert(end_iter, line + "\n")
            return False

        GLib.idle_add(_insert)

    def _on_apply(self) -> None:
        if self._running:
            return
        self._running = True
        self.apply_btn.set_sensitive(False)
        self.status_lbl.set_text("Aplicando configurações...")
        self.log_buffer.set_text("")

        # Persiste escolha da barra imediatamente no ConfigStore da Fase 1
        self.config.orientation = self._selected_orientation
        self._append_log(f"[config] barra salva como '{self._selected_orientation}' em {self.config.path}")

        runtimes = [rid for rid, chk in self._runtime_checks.items() if chk.get_active()]
        selection = OnboardingSelection(
            orientation=self._selected_orientation,
            editor=self._selected_editor,
            runtimes=runtimes,
            install_cli=self.chk_cli.get_active(),
            install_dotfiles=self.chk_dotfiles.get_active(),
            install_docker=self.chk_docker.get_active(),
            apply_system_tuning=self.chk_tuning.get_active(),
            no_snap_pin=self.chk_no_snap.get_active(),
        )
        commands = build_commands(selection)

        def _worker() -> None:
            ok = run_commands(commands, on_log=self._append_log, dry_run=self.dry_run)
            if ok and not self.dry_run:
                USER_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
                (USER_CONFIG_DIR / "onboarding.done").write_text("ok\n", encoding="utf-8")

            def _finish() -> bool:
                self._running = False
                self.apply_btn.set_sensitive(True)
                self.status_lbl.set_text(
                    "Concluído com sucesso!" if ok else "Finalizado com avisos/erros."
                )
                return False

            GLib.idle_add(_finish)

        threading.Thread(target=_worker, daemon=True).start()
