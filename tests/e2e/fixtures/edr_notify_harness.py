"""Harness do vigia lumen-edr-notify: socket falso + pw-play/notify-send falsos.

Uso: edr_notify_harness.py <caso> <dir>
Imprime as chamadas registradas pelos comandos falsos (uma por linha) e, no stderr,
o que o vigia avisou. O tier 2 confere essa saída.
"""
import json
import os
import shutil
import socket
import sys
import threading
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, REPO)

from shell import edr_notify  # noqa: E402


def alerta(sev="HIGH", summary="Shell bash com conexao de rede ativa", **extra):
    d = {"v": 1, "ts": 1794872689.2, "severity": sev, "rule": "behavior.revshell",
         "summary": summary, "mitre": ["T1059"]}
    d.update(extra)
    return (json.dumps(d, ensure_ascii=False) + "\n").encode()


CASOS = {
    # caso: (linhas enviadas, min_severity)
    "high": ([alerta()], "MEDIUM"),
    "medium": ([alerta("MEDIUM")], "MEDIUM"),
    "low": ([alerta("LOW")], "MEDIUM"),
    "limiar_high": ([alerta("MEDIUM")], "HIGH"),
    "cooldown": ([alerta(), alerta()], "MEDIUM"),
    "lixo": ([b"{quebrado\n", alerta(v=2), alerta("PANICO"), alerta()], "MEDIUM"),
    "sem_pwplay": ([alerta()], "MEDIUM"),
    "traco": ([alerta(summary="-x perigo")], "MEDIUM"),
}


def fakes(base, com_pwplay=True):
    bindir = os.path.join(base, "bin")
    os.makedirs(bindir)
    log = os.path.join(base, "calls.log")
    nomes = ["notify-send"] + (["pw-play"] if com_pwplay else [])
    for nome in nomes:
        p = os.path.join(bindir, nome)
        with open(p, "w") as fh:
            fh.write(f'#!/bin/sh\necho "${{0##*/}} $*" >> "{log}"\n')
        os.chmod(p, 0o755)
    os.environ["PATH"] = bindir  # so os falsos: um pw-play real do host nao pode atrapalhar
    return log


def servidor(path):
    if os.path.exists(path):
        os.unlink(path)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    s.listen(1)
    s.settimeout(5)
    return s


def atender(srv, linhas):
    conn, _ = srv.accept()
    for linha in linhas:
        conn.sendall(linha)
    return conn


def main():
    caso, base = sys.argv[1], sys.argv[2]
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    log = fakes(base, com_pwplay=(caso != "sem_pwplay"))
    path = os.path.join(base, "s.sock")
    srv = servidor(path)
    stop = threading.Event()
    min_sev = CASOS.get(caso, ([], "MEDIUM"))[1]
    t = threading.Thread(target=edr_notify.run, args=(path, min_sev, True),
                         kwargs={"stop": stop, "retry_base": 0.1, "retry_max": 0.5})
    t.start()

    if caso in CASOS:
        conn = atender(srv, CASOS[caso][0])
    elif caso == "reconecta":
        atender(srv, []).close()          # Mandacaru reiniciou: conexao cai e o socket some
        srv.close()
        time.sleep(0.3)
        srv = servidor(path)
        conn = atender(srv, [alerta()])
    elif caso == "fragmento":
        primeira = atender(srv, [alerta()[:30]])  # derrubado no meio de um envio
        primeira.close()
        srv.close()
        time.sleep(0.3)
        srv = servidor(path)
        conn = atender(srv, [alerta()])
    else:
        print(f"caso desconhecido: {caso}", file=sys.stderr)
        return 2

    time.sleep(0.8)  # tempo para o vigia avisar e os falsos gravarem
    stop.set()
    t.join(5)
    conn.close()
    srv.close()
    if t.is_alive():
        print("o vigia nao parou com o stop", file=sys.stderr)
        return 3
    if os.path.exists(log):
        with open(log) as fh:
            sys.stdout.write(fh.read())
    return 0


if __name__ == "__main__":
    sys.exit(main())
