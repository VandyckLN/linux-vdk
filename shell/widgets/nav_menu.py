"""Menu de navegação dev expansível com submenus."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Pango  # noqa: E402


@dataclass
class NavSubItem:
    """Item filho acionável dentro de uma seção expansível."""

    item_id: str
    label: str
    command: str | None = None


@dataclass
class NavSection:
    """Item de navegação de nível superior na barra Curved Glass."""

    section_id: str
    icon: str
    label: str
    children: list[NavSubItem] = field(default_factory=list)
    command: str | None = None


class NavMenu(Gtk.Box):
    """Renderiza ícones de navegação no modo compacto e menus sanfona quando expandido."""

    def __init__(
        self,
        sections: list[NavSection],
        on_activate: Callable[[str, str | None], None],
    ) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._sections = sections
        self._on_activate = on_activate
        self._active_id = sections[0].section_id if sections else ""
        self._selected_sub_id = ""
        self._orientation = "vertical"
        self._expanded = False

        self._section_buttons: dict[str, Gtk.Button] = {}
        self._section_labels: dict[str, Gtk.Label] = {}
        self._section_chevrons: dict[str, Gtk.Label] = {}
        self._revealers: dict[str, Gtk.Revealer] = {}
        self._sub_buttons: dict[str, Gtk.Button] = {}

        self.menu_caption = Gtk.Label(label="WORKSPACE", xalign=0.0)
        self.menu_caption.add_css_class("section-label")
        self.append(self.menu_caption)

        self.items_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.append(self.items_box)

        self._build_items()
        self._refresh_styles()

    def _build_items(self) -> None:
        for sec in self._sections:
            row_container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)

            btn = Gtk.Button()
            btn.add_css_class("nav-item")
            btn.set_tooltip_text(sec.label)

            btn_content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            icon_lbl = Gtk.Label(label=sec.icon)
            icon_lbl.set_width_chars(2)

            text_lbl = Gtk.Label(label=sec.label, xalign=0.0)
            text_lbl.set_hexpand(True)
            text_lbl.set_ellipsize(Pango.EllipsizeMode.END)

            chevron = Gtk.Label(label="▾" if sec.children else "")

            btn_content.append(icon_lbl)
            btn_content.append(text_lbl)
            btn_content.append(chevron)
            btn.set_child(btn_content)
            btn.connect("clicked", self._handle_section_click, sec)

            self._section_buttons[sec.section_id] = btn
            self._section_labels[sec.section_id] = text_lbl
            self._section_chevrons[sec.section_id] = chevron
            row_container.append(btn)

            if sec.children:
                revealer = Gtk.Revealer()
                revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
                revealer.set_transition_duration(180)
                sub_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                sub_box.set_margin_start(22)

                for child in sec.children:
                    sub_btn = Gtk.Button(label=child.label)
                    sub_btn.set_halign(Gtk.Align.FILL)
                    sub_btn.add_css_class("sub-item")
                    if isinstance(sub_btn.get_child(), Gtk.Label):
                        sub_btn.get_child().set_xalign(0.0)
                    sub_btn.connect("clicked", self._handle_sub_click, sec.section_id, child)
                    self._sub_buttons[child.item_id] = sub_btn
                    sub_box.append(sub_btn)

                revealer.set_child(sub_box)
                self._revealers[sec.section_id] = revealer
                row_container.append(revealer)

            self.items_box.append(row_container)

    def _handle_section_click(self, _btn: Gtk.Button, sec: NavSection) -> None:
        self._active_id = sec.section_id
        self._refresh_styles()
        self._on_activate(sec.section_id, sec.command)

    def _handle_sub_click(self, _btn: Gtk.Button, section_id: str, child: NavSubItem) -> None:
        self._active_id = section_id
        self._selected_sub_id = child.item_id
        self._refresh_styles()
        self._on_activate(child.item_id, child.command)

    def _refresh_styles(self) -> None:
        show_labels = self._expanded and self._orientation == "vertical"
        for sec in self._sections:
            btn = self._section_buttons[sec.section_id]
            is_active = sec.section_id == self._active_id
            if is_active:
                btn.add_css_class("active")
            else:
                btn.remove_css_class("active")

            if show_labels:
                btn.remove_css_class("nav-item-compact")
            else:
                btn.add_css_class("nav-item-compact")

            revealer = self._revealers.get(sec.section_id)
            if revealer is not None:
                revealer.set_reveal_child(show_labels and is_active)

        for item_id, sub_btn in self._sub_buttons.items():
            if item_id == self._selected_sub_id:
                sub_btn.add_css_class("selected")
            else:
                sub_btn.remove_css_class("selected")

    def set_mode(self, orientation: str, expanded: bool) -> None:
        """Alterna entre trilho compacto, gaveta vertical expandida e dock horizontal."""
        self._orientation = orientation
        self._expanded = expanded
        is_vertical = orientation == "vertical"
        show_labels = is_vertical and expanded

        self.menu_caption.set_visible(show_labels)
        self.items_box.set_orientation(
            Gtk.Orientation.VERTICAL if is_vertical else Gtk.Orientation.HORIZONTAL
        )
        for sec_id, lbl in self._section_labels.items():
            lbl.set_visible(show_labels)
            self._section_chevrons[sec_id].set_visible(show_labels and bool(sec_id in self._revealers))

        self._refresh_styles()
