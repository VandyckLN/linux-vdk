"""Harness do vigia lumen-edr-notify: socket falso + pw-play/notify-send falsos.

Uso: edr_notify_harness.py <caso> <dir>
Imprime as chamadas registradas pelos comandos falsos (uma por linha) e, no stderr,
o que o vigia avisou. O tier 2 confere essa saída.
"""
import json
import os
import shutil
import socket
import subprocess
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


ID = "ab" * 16

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
    "markup": ([alerta(summary="Tom & Jerry <b>x</b>.sh")], "MEDIUM"),
    "clique": ([alerta()], "MEDIUM"),
    "pwplay_trava": ([alerta()], "MEDIUM"),
    "popup_falha": ([alerta()], "MEDIUM"),
    "zumbi": ([alerta("MEDIUM")], "MEDIUM"),
    # alertas da Mandacaru 0.4.0 com quarantine_id (arquivo isolado)
    "id_clique": ([alerta(quarantine_id=ID)], "MEDIUM"),
    "dismiss": ([alerta(quarantine_id=ID)], "MEDIUM"),
    "id_invalido": ([alerta(quarantine_id="../../etc"), alerta(quarantine_id="AB" * 16)], "MEDIUM"),
    "id_markup": ([alerta(summary="-x Tom & <b>y</b>", quarantine_id=ID)], "MEDIUM"),
    "id_traco": ([alerta(summary="--help", quarantine_id=ID)], "MEDIUM"),
    "id_medium": ([alerta("MEDIUM", quarantine_id=ID)], "MEDIUM"),
    # id valido abaixo do limiar: o Mandacaru ja isolou o arquivo, a pergunta nao pode sumir
    "id_abaixo_limiar": ([alerta("LOW", quarantine_id=ID)], "CRITICAL"),
    "sem_id_abaixo_limiar": ([alerta("LOW")], "CRITICAL"),
    # mesmo arquivo casando duas regras: dois alertas com o mesmo id, um popup so
    "id_repetido": ([alerta(quarantine_id=ID), alerta("MEDIUM", quarantine_id=ID)], "MEDIUM"),
    # numero = pausa (s) entre os envios
    # popup fechou sem clique: um novo alerta do mesmo caso volta a perguntar
    "id_reabre": ([alerta(quarantine_id=ID), 0.5, alerta(quarantine_id=ID)], "MEDIUM"),
    # popup aberto e clicado: o mesmo caso nao pergunta de novo
    "id_clicado_nao_reabre": ([alerta(quarantine_id=ID), 0.5, alerta(quarantine_id=ID)], "MEDIUM"),
    # severidade sobe: LOW depois CRITICAL do mesmo id anuncia de novo, no maximo uma vez por nivel
    "id_sobe": ([alerta("LOW", quarantine_id=ID), alerta("CRITICAL", quarantine_id=ID),
                 alerta("CRITICAL", quarantine_id=ID), alerta("LOW", quarantine_id=ID)], "MEDIUM"),
    # sem notify-send (nao inicia): o id nao fica marcado
    "id_sem_notify": ([alerta(quarantine_id=ID)], "MEDIUM"),
}

# Como os falsos se comportam em cada caso. Padrão: o popup fica aberto 3 s (como um
# HIGH que ninguém fechou) e o pw-play termina na hora.
#   NOTIFY_SLEEP: segundos até o popup fechar (fechar com 0 = clique ou expirou)
#   NOTIFY_RC: notify-send falha na hora com esse código (sem daemon de notificação)
#   PWPLAY_SLEEP: segundos que o pw-play leva (30 = travado, como na VM)
AMBIENTE = {
    "clique": {"NOTIFY_SLEEP": "0.1", "PWPLAY_SLEEP": "5", "NOTIFY_OUT": "default"},
    "pwplay_trava": {"PWPLAY_SLEEP": "30"},
    "popup_falha": {"NOTIFY_RC": "1"},
    "zumbi": {"NOTIFY_SLEEP": "0.5"},
    # NOTIFY_OUT: o que o notify-send imprime ao fechar ("default" = clique na ação)
    "id_clique": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "dismiss": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": ""},
    "id_invalido": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "id_markup": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "id_traco": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "id_medium": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "id_abaixo_limiar": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "sem_id_abaixo_limiar": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "id_repetido": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
    "id_reabre": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": ""},
    "id_clicado_nao_reabre": {"NOTIFY_SLEEP": "0.1", "NOTIFY_OUT": "default"},
}
# teto de cada pw-play no harness; no clique ele é alto para provar que quem parou foi o clique
TETO = {"clique": 5.0}
ESPERA = {"pwplay_trava": 1.8, "zumbi": 1.5}


def fakes(base, com_pwplay=True, com_notify=True):
    bindir = os.path.join(base, "bin")
    os.makedirs(bindir)
    log = os.path.join(base, "calls.log")
    nomes = (["notify-send"] if com_notify else []) + (["pw-play"] if com_pwplay else [])
    var = {"notify-send": "NOTIFY", "pw-play": "PWPLAY"}
    for nome in nomes:
        p = os.path.join(bindir, nome)
        with open(p, "w") as fh:
            fh.write(f'#!/bin/sh\necho "${{0##*/}} $*" >> "{log}"\n'
                     f'echo $$ >> "{base}/{nome}.pids"\n'
                     + ('[ -n "$NOTIFY_OUT" ] && printf \'%s\\n\' "$NOTIFY_OUT"\n' if nome == "notify-send" else "") +
                     f'[ -n "${var[nome]}_RC" ] && exit "${var[nome]}_RC"\n'
                     f'exec /bin/sleep "${{{var[nome]}_SLEEP:-0}}"\n')
        os.chmod(p, 0o755)
    # janela de decisão falsa: só registra a chamada
    dlg = os.path.join(bindir, "lumen-quarentena")
    with open(dlg, "w") as fh:
        fh.write(f'#!/bin/sh\necho "${{0##*/}} $*" >> "{log}"\n'
                 f'printf \'%s\\0\' "$@" >> "{base}/dialog.argv"\n')
    os.chmod(dlg, 0o755)
    edr_notify.DIALOG_CMD = [dlg]
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
        if isinstance(linha, float):
            time.sleep(linha)
            continue
        conn.sendall(linha)
    return conn


def vivos(base, nome):
    """Quantos processos do falso `nome` ainda estão vivos (zumbi conta como morto)."""
    try:
        pids = [int(x) for x in open(os.path.join(base, f"{nome}.pids")).read().split()]
    except FileNotFoundError:
        return 0
    n = 0
    for pid in pids:
        try:
            estado = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[0]
        except FileNotFoundError:
            continue
        n += estado != "Z"
    return n


def zumbis():
    """Filhos deste processo que terminaram e ninguém recolheu."""
    n = 0
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            campos = open(f"/proc/{d}/stat").read().rsplit(")", 1)[1].split()
        except (FileNotFoundError, ProcessLookupError):
            continue
        n += campos[0] == "Z" and int(campos[1]) == os.getpid()
    return n


def instancia_unica(base):
    lock = os.path.join(base, "vigia.lock")
    segura = edr_notify.acquire_single_instance(lock)
    tenta = ("import sys; sys.path.insert(0, %r); from shell.edr_notify import acquire_single_instance as a; "
             "print(a(%r) is not None)") % (REPO, lock)
    segunda = subprocess.run([sys.executable, "-c", tenta], capture_output=True, text=True).stdout.strip()
    segura.close()
    depois = subprocess.run([sys.executable, "-c", tenta], capture_output=True, text=True).stdout.strip()
    print(f"primeira={segura is not None} segunda={segunda} depois={depois}")
    return 0


def aceita_e_fecha(base):
    """Produtor no teto de clientes: aceita e fecha na hora. O vigia nao pode girar sem pausa."""
    path = os.path.join(base, "s.sock")
    srv = servidor(path)
    srv.settimeout(0.05)
    stop = threading.Event()
    t = threading.Thread(target=edr_notify.run, args=(path, "MEDIUM", True),
                         kwargs={"stop": stop, "retry_base": 0.1, "retry_max": 0.5})
    t.start()
    conexoes = 0
    fim = time.monotonic() + 1.5
    while time.monotonic() < fim:
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            continue
        conexoes += 1
        conn.close()
    stop.set()
    t.join(5)
    srv.close()
    print(f"conexoes={conexoes}")
    return 0


def main():
    caso, base = sys.argv[1], sys.argv[2]
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    if caso == "instancia_unica":
        return instancia_unica(base)
    os.environ.update({"NOTIFY_SLEEP": "3", **AMBIENTE.get(caso, {})})
    edr_notify.SOUND_GAP = 0.05
    edr_notify.SOUND_MAX = {sev: TETO.get(caso, 0.3) for sev in ("MEDIUM", "HIGH", "CRITICAL")}
    log = fakes(base, com_pwplay=(caso != "sem_pwplay"), com_notify=(caso != "id_sem_notify"))
    if caso == "aceita_e_fecha":
        return aceita_e_fecha(base)
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

    time.sleep(ESPERA.get(caso, 0.8))  # tempo para o vigia avisar e os falsos gravarem
    if float(os.environ["NOTIFY_SLEEP"]) < 1:
        # popup curto: espera a thread do clique decidir (abrir a janela ou esquecer o id)
        fim = time.monotonic() + 3
        while time.monotonic() < fim and any(x.name == "edr-click" and x.is_alive()
                                             for x in threading.enumerate()):
            time.sleep(0.05)
        time.sleep(0.3)  # o falso da janela grava a chamada logo depois de iniciar
    print(f"anunciados={len(edr_notify._announced)}")
    print(f"pwplay_vivos={vivos(base, 'pw-play')} zumbis={zumbis()}")
    stop.set()
    t.join(5)
    conn.close()
    srv.close()
    for p in getattr(edr_notify, "_children", []):
        if p.poll() is None:
            p.kill()
    if t.is_alive():
        print("o vigia nao parou com o stop", file=sys.stderr)
        return 3
    argv_file = os.path.join(base, "dialog.argv")
    if os.path.exists(argv_file):
        # o argv exato que o vigia montou tem de passar pelo argparse da janela
        from shell import quarantine_dialog
        argv = open(argv_file).read().split("\0")[:-1]
        try:
            a = quarantine_dialog.parse_args(argv)
            print(f"dialog_parse={a.id}|{a.rule}|{a.summary}")
        except SystemExit as exc:
            print(f"dialog_parse=ERRO{exc.code}")
    if os.path.exists(log):
        with open(log) as fh:
            sys.stdout.write(fh.read())
    return 0


if __name__ == "__main__":
    sys.exit(main())
