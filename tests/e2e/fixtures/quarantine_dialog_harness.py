"""Harness da lógica da janela da quarentena (sem GTK).

Uso: quarantine_dialog_harness.py <caso>
Imprime `ok <nome>` ou `FALHA <nome>: <detalhe>` por verificação; sai com 1 se alguma falhou.
"""
import fcntl
import json
import os
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, REPO)

from shell import quarantine_dialog as qd  # noqa: E402

ID = "a" * 32
falhou = False


def check(nome, obtido, esperado):
    global falhou
    if obtido == esperado:
        print(f"ok {nome}")
    else:
        falhou = True
        print(f"FALHA {nome}: obtido {obtido!r}, esperado {esperado!r}")


def analise(verdict, summary="", v=1):
    return json.dumps({"v": v, "id": ID, "verdict": verdict, "sources": {}, "summary": summary})


def caso_commands():
    c = qd.commands(ID)
    check("analisar", c["analisar"],
          ["pkexec", "/usr/libexec/mandacaru/quarantine-decide", "analisar", ID, "--json"])
    check("confiar", c["confiar"],
          ["pkexec", "/usr/libexec/mandacaru/quarantine-release", "confiar", ID])
    check("manter", c["manter"],
          ["pkexec", "/usr/libexec/mandacaru/quarantine-decide", "manter", ID])


def caso_valid_id():
    check("valido", qd.valid_id("0123456789abcdef" * 2), True)
    for nome, v in [("maiuscula", "A" * 32), ("curto", "a" * 31), ("longo", "a" * 33),
                    ("traversal", "../../etc"), ("newline", "a" * 32 + "\n"),
                    ("none", None), ("int", 123)]:
        check(nome, qd.valid_id(v), False)


def caso_outcome_ok():
    o = qd.outcome("confiar", 0, "x\nRestaurado em /home/a/x.py\n", "", qd.INITIAL_BUTTONS)
    check("confiar_msg", o.message, "Arquivo devolvido. Restaurado em /home/a/x.py")
    check("confiar_fecha", (o.close, o.buttons), (True, ()))
    o = qd.outcome("manter", 0, "", "", qd.INITIAL_BUTTONS)
    check("manter_msg", o.message, "Mantido isolado. Será apagado em 30 dias.")
    check("manter_fecha", (o.close, o.buttons), (True, ()))


def caso_outcome_analisar():
    o = qd.outcome("analisar", 0, analise("malicioso", "Cymru: achou"), "", qd.INITIAL_BUTTONS)
    check("malicioso_msg", o.message, "Malicioso. Recomendado manter isolado.\nCymru: achou")
    check("malicioso_resto", (o.verdict, o.buttons, o.close),
          ("malicioso", qd.AFTER_ANALYSIS, False))
    o = qd.outcome("analisar", 0, analise("malicioso"), "", qd.INITIAL_BUTTONS)
    check("sem_summary", o.message, "Malicioso. Recomendado manter isolado.")
    o = qd.outcome("analisar", 0, analise("legitimo_conhecido"), "", qd.INITIAL_BUTTONS)
    check("legitimo", o.message, "Arquivo legítimo conhecido (provável falso positivo).")
    o = qd.outcome("analisar", 0, analise("desconhecido"), "", qd.INITIAL_BUTTONS)
    check("desconhecido", o.message, "Desconhecido. Nenhuma base conhece este arquivo.")


def caso_outcome_analisar_ruim():
    for nome, saida in [("quebrado", "{quebrado"), ("versao", analise("malicioso", v=2)),
                        ("veredito", json.dumps({"v": 1, "verdict": "talvez"})),
                        ("lista", json.dumps({"v": 1, "verdict": ["x"]})),
                        ("dict", json.dumps({"v": 1, "verdict": {"a": 1}}))]:
        o = qd.outcome("analisar", 0, saida, "", qd.INITIAL_BUTTONS)
        check(nome + "_msg", o.message.startswith("Falhou (código 0)"), True)
        check(nome + "_botoes", o.buttons, qd.INITIAL_BUTTONS)


def caso_outcome_codigos():
    cur = qd.AFTER_ANALYSIS
    o = qd.outcome("confiar", 3, "", "", cur)
    check("rc3", (o.message, o.buttons), ("Este caso não existe mais ou já foi resolvido.", ()))
    o = qd.outcome("confiar", 4, "", "", cur)
    check("rc4", (o.message, o.buttons),
          ("A quarentena foi adulterada. O arquivo não foi devolvido.", ()))
    for rc in (126, 127):
        o = qd.outcome("confiar", rc, "", "", cur)
        check(f"rc{rc}", (o.message, o.buttons), ("Autenticação cancelada.", cur))
    o = qd.outcome("confiar", 1, "", "a\nerro x\n\n", cur)
    check("rc1", (o.message, o.buttons), ("Falhou (código 1).\nerro x", cur))


def caso_spawn_failed():
    o = qd.spawn_failed("confiar", ID, qd.INITIAL_BUTTONS)
    check("msg", f"sudo mandacaru quarentena confiar {ID}" in o.message, True)
    check("botoes", o.buttons, qd.INITIAL_BUTTONS)


def caso_args():
    a = qd.parse_args([ID, "--rule", "r", "--summary", "-x <b>"])
    check("summary", (a.id, a.rule, a.summary), (ID, "r", "-x <b>"))
    check("padrao", qd.parse_args([ID]).summary, "")
    try:
        qd.parse_args(["../x"])
        check("id_invalido", "sem erro", "SystemExit(2)")
    except SystemExit as e:
        check("id_invalido", e.code, 2)


def caso_trava():
    with tempfile.TemporaryDirectory() as tmp:
        os.environ["XDG_RUNTIME_DIR"] = tmp
        check("lock_path", qd.lock_path(ID), f"{tmp}/lumen-quarentena-{ID}.lock")
        codigo = ("import sys; sys.path.insert(0, %r)\n"
                  "from shell import quarantine_dialog as q\n"
                  "q.run_window = lambda a: print('abriu') or 0\n"
                  "sys.exit(q.main([%r]))\n") % (REPO, ID)
        with open(qd.lock_path(ID), "a") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            r = subprocess.run([sys.executable, "-c", codigo], capture_output=True, text=True)
        check("trava_rc", r.returncode, 0)
        check("trava_sem_janela", "abriu" in r.stdout, False)
        r = subprocess.run([sys.executable, "-c", codigo], capture_output=True, text=True)
        check("livre_abre", "abriu" in r.stdout, True)


def caso_outcome_bordas():
    o = qd.outcome("confiar", 0, "", "", qd.INITIAL_BUTTONS)
    check("confiar_sem_saida", o.message, "Arquivo devolvido.")
    o = qd.outcome("analisar", 0, analise("malicioso", v=True), "", qd.INITIAL_BUTTONS)
    check("v_true_msg", o.message.startswith("Falhou (código 0)"), True)
    check("v_true_botoes", o.buttons, qd.INITIAL_BUTTONS)


def caso_sem_gi():
    r = subprocess.run([sys.executable, "-c",
                        "import sys; sys.path.insert(0, %r); import shell.quarantine_dialog; "
                        "print('gi' in sys.modules)" % REPO], capture_output=True, text=True)
    check("gi", r.stdout.strip(), "False")


if __name__ == "__main__":
    globals()["caso_" + sys.argv[1]]()
    sys.exit(1 if falhou else 0)
