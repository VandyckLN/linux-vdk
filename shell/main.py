"""CLI entrypoint for the Lumen Curved Glass Shell."""

from __future__ import annotations

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gio, Gtk  # noqa: E402

from .config_store import ConfigStore  # noqa: E402
from .curved_sidebar import CurvedSidebarWindow  # noqa: E402


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Lumen Curved Glass Shell (Ubuntu Dev Distro)")
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Abre em janela comum de preview (para testar fora de sessão Hyprland/Wayfire).",
    )
    parser.add_argument(
        "--orientation",
        choices=("vertical", "horizontal"),
        help="Sobrescreve a orientação inicial da barra (vertical=lateral, horizontal=dock).",
    )
    parser.add_argument(
        "--expanded",
        action="store_true",
        help="Inicia a barra lateral já expandida.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    config = ConfigStore()
    if args.orientation:
        config.orientation = args.orientation
    if args.expanded:
        config.expanded = True

    app = Gtk.Application(
        application_id="dev.lumenos.CurvedShell",
        flags=Gio.ApplicationFlags.FLAGS_NONE,
    )

    def on_activate(gtk_app: Gtk.Application) -> None:
        win = CurvedSidebarWindow(gtk_app, config=config, preview=args.preview)
        win.present()

    app.connect("activate", on_activate)
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
