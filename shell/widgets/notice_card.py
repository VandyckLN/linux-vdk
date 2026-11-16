"""Bottom Notice / Live System Telemetry card modeled after the Curved Sidebar UI."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk  # noqa: E402

from ..system_metrics import SystemSnapshot  # noqa: E402


class NoticeCard(Gtk.Box):
    """Displays CPU, RAM, Docker, and local ports in compact or expanded glass form."""

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=6)

        # Compact gem/badge shown when sidebar is collapsed
        self.compact_badge = Gtk.Label(label="◆\nDEV")
        self.compact_badge.set_justify(Gtk.Justification.CENTER)
        self.compact_badge.add_css_class("notice-compact-badge")
        self.compact_badge.set_halign(Gtk.Align.CENTER)

        # Expanded notice card
        self.card_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.card_box.add_css_class("notice-card")

        top_line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.badge_lbl = Gtk.Label(label="SYSTEM • LIVE", xalign=0.0)
        self.badge_lbl.add_css_class("notice-badge")
        self.badge_lbl.set_hexpand(True)
        gem = Gtk.Label(label="◆")
        top_line.append(self.badge_lbl)
        top_line.append(gem)

        self.title_lbl = Gtk.Label(label="NOTICE", xalign=0.0)
        self.title_lbl.add_css_class("notice-title")

        self.metrics_lbl = Gtk.Label(label="CPU 0%  •  RAM 0.0 GB", xalign=0.0)
        self.metrics_lbl.add_css_class("notice-detail")

        self.dev_lbl = Gtk.Label(label="Docker off  •  Ports: none", xalign=0.0)
        self.dev_lbl.add_css_class("notice-detail")

        self.card_box.append(top_line)
        self.card_box.append(self.title_lbl)
        self.card_box.append(self.metrics_lbl)
        self.card_box.append(self.dev_lbl)

        # Horizontal chip shown in horizontal dock mode
        self.horizontal_chip = Gtk.Label(label="◆ CPU 0% | RAM 0%")
        self.horizontal_chip.add_css_class("notice-detail")

        self.append(self.compact_badge)
        self.append(self.card_box)
        self.append(self.horizontal_chip)

    def update_snapshot(self, snap: SystemSnapshot) -> None:
        docker_txt = f"Docker {snap.docker_running} up" if snap.docker_available else "Docker idle"
        ports_txt = " ".join(snap.listening_ports) if snap.listening_ports else "no dev ports"
        self.compact_badge.set_text(f"◆\n{snap.ram_percent}%")
        self.compact_badge.set_tooltip_text(
            f"CPU {snap.cpu_percent}% • RAM {snap.ram_used_gb:.1f}/{snap.ram_total_gb:.1f} GB"
        )
        self.title_lbl.set_text(f"DEV STATUS • {snap.hostname}")
        self.metrics_lbl.set_text(
            f"CPU {snap.cpu_percent}%  •  RAM {snap.ram_used_gb:.1f}/{snap.ram_total_gb:.1f} GB ({snap.ram_percent}%)"
        )
        self.dev_lbl.set_text(f"{docker_txt}  •  {ports_txt}")
        self.horizontal_chip.set_text(
            f"◆ CPU {snap.cpu_percent}% • RAM {snap.ram_used_gb:.1f}G • {docker_txt}"
        )

    def set_mode(self, orientation: str, expanded: bool) -> None:
        is_vertical = orientation == "vertical"
        self.compact_badge.set_visible(is_vertical and not expanded)
        self.card_box.set_visible(is_vertical and expanded)
        self.horizontal_chip.set_visible(not is_vertical)
