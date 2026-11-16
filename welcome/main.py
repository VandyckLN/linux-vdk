"""CLI entrypoint for the Lumen OS First-Boot Welcome Wizard."""

from __future__ import annotations

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gio, Gtk  # noqa: E402

from shell.config_store import ConfigStore  # noqa: E402

from .welcome_window import WelcomeWindow  # noqa: E402


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Lumen OS First-Boot Welcome Wizard")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simula os comandos de sistema sem instalar pacotes reais.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    config = ConfigStore()

    app = Gtk.Application(
        application_id="dev.lumenos.Welcome",
        flags=Gio.ApplicationFlags.FLAGS_NONE,
    )

    def on_activate(gtk_app: Gtk.Application) -> None:
        win = WelcomeWindow(gtk_app, config=config, dry_run=args.dry_run)
        win.present()

    app.connect("activate", on_activate)
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
