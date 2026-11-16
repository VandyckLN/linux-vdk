"""Header and developer profile widget for the Curved Glass Shell."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Pango  # noqa: E402


class ProfileCard(Gtk.Box):
    """Displays distro brand, expand/collapse trigger, and user profile."""

    def __init__(
        self,
        distro_name: str,
        user_cfg: dict[str, Any],
        on_toggle_expand: Callable[[], None],
        on_toggle_orientation: Callable[[], None],
    ) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self._on_toggle_expand = on_toggle_expand
        self._on_toggle_orientation = on_toggle_orientation

        # Top header bar (only visible when expanded in vertical mode)
        self.header_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        brand = Gtk.Label(label=distro_name.upper(), xalign=0.0)
        brand.add_css_class("brand-title")
        brand.set_hexpand(True)

        self.orientation_btn = Gtk.Button(label="↔")
        self.orientation_btn.set_tooltip_text("Alternar barra Lateral / Horizontal")
        self.orientation_btn.add_css_class("icon-btn")
        self.orientation_btn.connect("clicked", lambda *_: self._on_toggle_orientation())

        self.collapse_btn = Gtk.Button(label="⇤")
        self.collapse_btn.set_tooltip_text("Recolher barra")
        self.collapse_btn.add_css_class("icon-btn")
        self.collapse_btn.connect("clicked", lambda *_: self._on_toggle_expand())

        self.header_row.append(brand)
        self.header_row.append(self.orientation_btn)
        self.header_row.append(self.collapse_btn)

        # Compact expand trigger (visible when collapsed in vertical mode)
        self.expand_btn = Gtk.Button(label="⇥")
        self.expand_btn.set_tooltip_text("Expandir painel")
        self.expand_btn.add_css_class("icon-btn")
        self.expand_btn.set_halign(Gtk.Align.CENTER)
        self.expand_btn.connect("clicked", lambda *_: self._on_toggle_expand())

        # User profile row
        self.profile_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.profile_row.set_valign(Gtk.Align.CENTER)

        name = str(user_cfg.get("name", "Nova"))
        initials = "".join(part[0].upper() for part in name.split()[:2]) or "N"
        avatar = Gtk.Label(label=initials)
        avatar.add_css_class("profile-avatar")
        avatar.set_halign(Gtk.Align.CENTER)
        avatar.set_valign(Gtk.Align.CENTER)

        self.text_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.text_col.set_hexpand(True)

        name_line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        name_lbl = Gtk.Label(label=name, xalign=0.0)
        name_lbl.add_css_class("profile-name")
        badge_lbl = Gtk.Label(label=str(user_cfg.get("badge", "DEV")))
        badge_lbl.add_css_class("profile-badge")
        name_line.append(name_lbl)
        name_line.append(badge_lbl)

        subtitle = Gtk.Label(label=str(user_cfg.get("subtitle", "Ubuntu Dev")), xalign=0.0)
        subtitle.add_css_class("profile-subtitle")
        subtitle.set_ellipsize(Pango.EllipsizeMode.END)

        self.text_col.append(name_line)
        self.text_col.append(subtitle)

        self.profile_row.append(avatar)
        self.profile_row.append(self.text_col)

        self.append(self.expand_btn)
        self.append(self.header_row)
        self.append(self.profile_row)

    def set_mode(self, orientation: str, expanded: bool) -> None:
        """Adjusts visibility for vertical/horizontal and collapsed/expanded states."""
        is_vertical = orientation == "vertical"
        self.set_orientation(
            Gtk.Orientation.VERTICAL if is_vertical else Gtk.Orientation.HORIZONTAL
        )
        self.expand_btn.set_visible(is_vertical and not expanded)
        self.header_row.set_visible(is_vertical and expanded)
        self.text_col.set_visible(is_vertical and expanded)
        self.profile_row.set_halign(
            Gtk.Align.CENTER if (is_vertical and not expanded) else Gtk.Align.FILL
        )
