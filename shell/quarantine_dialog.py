"""Janela de decisão da quarentena do Mandacaru (Confio / Analisar / Manter isolado).

Esta parte é a lógica pura e não importa `gi` no topo: a máquina de dev não tem GTK.
A interface GTK4 fica em `run_window()`.
"""
import argparse
import json
import os
import re
import sys
from dataclasses import dataclass

CASE_ID = re.compile(r"[0-9a-f]{32}")
RELEASE = "/usr/libexec/mandacaru/quarantine-release"
DECIDE = "/usr/libexec/mandacaru/quarantine-decide"

INITIAL_BUTTONS = ("confiar", "analisar", "manter")
AFTER_ANALYSIS = ("confiar", "manter")
CLOSE_MS = 3000

VERDICTS = {
    "malicioso": "Malicioso. Recomendado manter isolado.",
    "legitimo_conhecido": "Arquivo legítimo conhecido (provável falso positivo).",
    "desconhecido": "Desconhecido. Nenhuma base conhece este arquivo.",
}


@dataclass(frozen=True)
class Outcome:
    message: str
    buttons: tuple[str, ...]
    close: bool
    verdict: str | None = None


def valid_id(value: object) -> bool:
    return isinstance(value, str) and CASE_ID.fullmatch(value) is not None


def commands(case_id: str) -> dict[str, list[str]]:
    """Comandos dos botões, sempre em lista e sem shell."""
    return {
        "confiar": ["pkexec", RELEASE, "confiar", case_id],
        "analisar": ["pkexec", DECIDE, "analisar", case_id, "--json"],
        "manter": ["pkexec", DECIDE, "manter", case_id],
    }


def _last_line(text: str) -> str:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    return lines[-1] if lines else ""


def decode_output(data: bytes | None) -> str:
    """Saída do filho em texto; bytes fora de UTF-8 (nomes de arquivo) viram U+FFFD."""
    if data is None:
        return ""
    raw = data.get_data() if hasattr(data, "get_data") else data  # GLib.Bytes ou bytes
    return bytes(raw or b"").decode("utf-8", "replace")


def _failed(rc: int, stderr: str, current: tuple[str, ...]) -> Outcome:
    message = f"Falhou (código {rc})."
    detail = _last_line(stderr)
    if detail:
        message += f"\n{detail}"
    return Outcome(message, current, False)


def outcome(action: str, rc: int, stdout: str, stderr: str,
            current: tuple[str, ...]) -> Outcome:
    """Traduz o resultado do pkexec em mensagem, botões ativos e se a janela fecha."""
    if rc == 3:
        return Outcome("Este caso não existe mais ou já foi resolvido.", (), False)
    if rc == 4:
        return Outcome("A quarentena foi adulterada. O arquivo não foi devolvido.", (), False)
    if rc in (126, 127):
        return Outcome("Autenticação cancelada.", current, False)
    if rc != 0:
        return _failed(rc, stderr, current)
    if action == "confiar":
        last = _last_line(stdout)
        return Outcome(f"Arquivo devolvido. {last}" if last else "Arquivo devolvido.", (), True)
    if action == "manter":
        return Outcome("Mantido isolado. Será apagado em 30 dias.", (), True)
    if action == "analisar":
        try:
            data = json.loads(stdout)
        except ValueError:
            return _failed(rc, stderr, current)
        if (not isinstance(data, dict) or type(data.get("v")) is not int or data["v"] != 1
                or not isinstance(data.get("verdict"), str)
                or data["verdict"] not in VERDICTS):
            return _failed(rc, stderr, current)
        verdict = data["verdict"]
        message = VERDICTS[verdict]
        summary = data.get("summary")
        if isinstance(summary, str) and summary:
            message += f"\n{summary}"
        return Outcome(message, AFTER_ANALYSIS, False, verdict)
    return _failed(rc, stderr, current)


def spawn_failed(action: str, case_id: str, current: tuple[str, ...]) -> Outcome:
    return Outcome("Não foi possível rodar o pkexec. No terminal: "
                   f"sudo mandacaru quarentena {action} {case_id}", current, False)


def _case_id(value: str) -> str:
    if not valid_id(value):
        raise argparse.ArgumentTypeError(f"id inválido: {value!r}")
    return value


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="lumen-quarentena")
    p.add_argument("id", type=_case_id)
    p.add_argument("--rule", default="")
    p.add_argument("--summary", default="")
    return p.parse_args(argv)  # id inválido: argparse sai com código 2


def lock_path(case_id: str) -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(runtime, f"lumen-quarentena-{case_id}.lock")


CSS = b".malicioso { color: #c01c28; font-weight: bold; }"

LABELS = {
    "confiar": "Confio (pede senha)",
    "analisar": "Analisar",
    "manter": "Manter isolado",
}


def run_window(args: argparse.Namespace) -> int:
    """Janela GTK4 de decisão. `gi` é importado aqui para o módulo seguir importável sem GTK."""
    import gi
    gi.require_version("Gdk", "4.0")
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gdk, Gio, GLib, Gtk

    cmds = commands(args.id)

    def on_activate(app):
        window = Gtk.ApplicationWindow(application=app)
        window.set_title("Arquivo isolado pelo Mandacaru")
        window.set_default_size(420, -1)

        provider = Gtk.CssProvider()
        if hasattr(provider, "load_from_string"):
            provider.load_from_string(CSS.decode())
        else:
            provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for side in ("top", "bottom", "start", "end"):
            getattr(box, f"set_margin_{side}")(18)
        window.set_child(box)

        def make_label(text, selectable=False):
            label = Gtk.Label()
            label.set_text(text)
            label.set_wrap(True)
            label.set_xalign(0)
            label.set_selectable(selectable)
            box.append(label)
            return label

        make_label(args.rule)
        make_label(args.summary, selectable=True)
        make_label("Se você não decidir, o arquivo é apagado em 30 dias.")
        status = make_label("", selectable=True)  # o aviso do pkexec traz um comando para copiar
        spinner = Gtk.Spinner()
        box.append(spinner)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        box.append(row)
        buttons = {}
        for action in INITIAL_BUTTONS:  # ordem: confiar, analisar, manter
            button = Gtk.Button(label=LABELS[action])
            row.append(button)
            buttons[action] = button
        window.set_default_widget(buttons["manter"])
        buttons["manter"].add_css_class("suggested-action")

        state = {"current": INITIAL_BUTTONS, "pending": False}

        def close_window():
            window.close()
            return GLib.SOURCE_REMOVE

        def apply(result):
            spinner.stop()
            status.set_text(result.message)
            if result.verdict == "malicioso":
                status.add_css_class("malicioso")
            else:
                status.remove_css_class("malicioso")
            state["current"] = result.buttons
            for name, button in buttons.items():
                button.set_sensitive(name in result.buttons)
            if result.close:
                GLib.timeout_add(CLOSE_MS, close_window)

        def on_done(proc, res, action, before):
            state["pending"] = False
            try:
                try:
                    _ok, out, err = proc.communicate_finish(res)
                    rc = proc.get_exit_status() if proc.get_if_exited() else -1
                except GLib.Error:
                    out, err, rc = None, None, -1
                result = outcome(action, rc, decode_output(out), decode_output(err), before)
            except Exception as exc:  # nunca deixar a janela travada em "Aguardando…"
                result = _failed(-1, str(exc), before)
            finally:
                app.release()
            if window.get_visible():
                apply(result)
            else:
                app.quit()  # janela fechada no meio do comando: o comando terminou, sai

        def on_close(_window):
            if state["pending"]:
                window.set_visible(False)  # esconde e segura a trava até o comando acabar
                return True
            return False

        window.connect("close-request", on_close)

        def on_click(_button, action):
            before = state["current"]
            for button in buttons.values():
                button.set_sensitive(False)
            spinner.start()
            status.remove_css_class("malicioso")
            status.set_text("Aguardando…")
            try:
                proc = Gio.Subprocess.new(
                    cmds[action],
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
            except GLib.Error:
                apply(spawn_failed(action, args.id, before))
                return
            # closure em vez de user_data variádico do PyGObject (mais previsível)
            try:
                proc.communicate_async(None, None, lambda p, r: on_done(p, r, action, before))
            except Exception as exc:  # erro síncrono: reabilita os botões, sem segurar o app
                apply(_failed(-1, str(exc), before))
                return
            state["pending"] = True
            app.hold()

        for action, button in buttons.items():
            button.connect("clicked", on_click, action)
        buttons["manter"].grab_focus()  # senão o foco cai no resumo selecionável (texto todo marcado)
        window.present()

    app = Gtk.Application(application_id="io.github.vandyckln.lumen.quarentena",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("activate", on_activate)
    return app.run([])


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    # import aqui: o edr_notify vai importar este módulo (evita import circular)
    from shell.edr_notify import acquire_single_instance
    lock = acquire_single_instance(lock_path(args.id))
    if lock is None:
        return 0  # já há uma janela para este caso
    try:
        return run_window(args)
    finally:
        lock.close()


if __name__ == "__main__":
    sys.exit(main())
