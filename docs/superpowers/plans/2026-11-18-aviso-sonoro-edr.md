# Aviso sonoro e popup do Mandacaru — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** cada alerta MEDIUM ou mais grave do Mandacaru 0.3.0 toca um som e mostra um popup na sessão Hyprland do usuário, na live e no sistema instalado.

**Architecture:** o vigia `shell/edr_notify.py` roda na sessão (`exec-once`), conecta no `/run/mandacaru/alerts.sock`, lê as linhas JSON v1, toca o som com `pw-play` e mostra o popup com `notify-send`, exibido pelo `mako`. A distro passa a trazer o PipeWire, o mako e o libnotify, coloca os usuários no grupo `mandacaru` e fixa o Mandacaru 0.3.0 no lock.

**Tech Stack:** Python 3 só com a biblioteca padrão (`socket`, `json`, `subprocess`, `threading`). Bash E2E (`tests/e2e`, harness próprio). Empacotamento com `build-debs.sh` e `debian/control`, build com `build-iso.sh` e Calamares.

**Spec:** `docs/superpowers/specs/2026-11-17-aviso-sonoro-edr-design.md`

## Global Constraints

- **Socket:** `/run/mandacaru/alerts.sock`, contrato v1. Só aceita linha com `v == 1`, `severity` em `INFO|LOW|MEDIUM|HIGH|CRITICAL` e `rule` e `summary` como texto.
- **Padrões no `config/shell.default.json`:** `"edr": {"socket": "/run/mandacaru/alerts.sock", "notify_min_severity": "MEDIUM", "sound": true}`. Um `notify_min_severity` inválido vira `MEDIUM`, com aviso.
- **Sons:**
  - MEDIUM: `/usr/share/sounds/freedesktop/stereo/dialog-warning.oga`;
  - HIGH e CRITICAL: `/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga`;
  - no máximo 1 som a cada **5 s**.
- **Popup:** `notify-send --app-name=Mandacaru --urgency=<normal|critical> "Mandacaru: <SEVERIDADE>" "<rule>: <summary>"`. A urgência é `critical` só para HIGH e CRITICAL. Os popups saem todos, sem cooldown.
- **Reconexão:** espera 2 s, dobra a cada falha até o teto de 30 s e volta a 2 s ao conectar. `[edr-notify] aguardando o Mandacaru em <caminho>` sai uma vez por sequência de falhas. Com `PermissionError`, imprime `[edr-notify] sem permissão no socket: entre no grupo mandacaru` uma vez e tenta de novo a cada 30 s.
- **Leitura:** linha inválida é ignorada em silêncio, linha com mais de 64 KiB sem `\n` é descartada e um fragmento sem `\n` no EOF também é descartado.
- **Comandos externos:** `pw-play` e `notify-send` ausentes ou falhando geram um aviso no stderr na primeira falha de cada um, e o outro canal continua. Nada pode virar processo zumbi.
- **`Depends` do `lumen-desktop`:** `mandacaru (>= 0.3.0)`, `python3-bpfcc`, `pipewire`, `pipewire-pulse`, `wireplumber`, `mako-notifier`, `libnotify-bin` e `sound-theme-freedesktop`. O `control` e o `build-debs.sh` precisam continuar iguais (T3_PAIR7).
- **Lock:** `MANDACARU_VERSION=0.3.0`, `MANDACARU_URL=https://github.com/VandyckLN/mandacaru/releases/download/v0.3.0/mandacaru_0.3.0_all.deb` e `MANDACARU_SHA256=408d8a56e38d1b0c455d32c30455d777184ce1d9b5c02f6b2e2086f32acaa402`.
- **Strings de código:** mensagens e comentários em PT-BR, como no resto do shell. O `EXTRA_CSS` não está envolvido.
- **Branch:** o trabalho segue no `feat/mandacaru-edr`. Push e merge ficam só com o autor.
- **Suíte:** `bash tests/e2e/run-e2e-tests.sh` precisa passar 100%. Hoje são 131 testes.

## Review Focus

1. **Zumbis e travamento por subprocesso:** `pw-play` é assíncrono, e um `notify-send` que trava (sem daemon de notificação, D-Bus lento) não pode congelar a leitura do socket. Os dois rodam com `Popen` e os filhos são colhidos (`poll()`). O `notify-send` nunca é chamado com `wait()` sem timeout.
2. **Rajada no arranque:** se o vigia sobe enquanto o Mandacaru já está despejando alertas, a fila não pode crescer sem limite nem gerar dezenas de sons. Vale o cooldown de 5 s.
3. **`ConfigStore` sem arquivo do usuário ou com JSON quebrado:** o vigia tem que subir com os padrões, porque o `ConfigStore` já devolve `{}` com JSON inválido.
4. **Sessão sem o grupo aplicado:** o usuário foi colocado no grupo, mas a sessão começou antes. O vigia cai no `PermissionError`, avisa uma vez e continua tentando sem gastar CPU.
5. **Texto com caracteres especiais no `summary`:** acento, `U+FFFD` ou aspas vão para o `notify-send` como **argumento** de lista, nunca por shell. Um summary começando com `-` não pode virar opção do `notify-send`, por isso entra um `--` antes dos argumentos posicionais. O teste `T2_F9_09` cobre isso.

---

### Task 1: vigia `lumen-edr-notify`

**Files:**
- Create: `shell/edr_notify.py`, `packaging/templates/lumen-edr-notify`, `tests/e2e/fixtures/edr_notify_harness.py`
- Modify: `config/shell.default.json` (seção `edr`), `tests/e2e/tier1_feature_coverage.sh` (F10), `tests/e2e/tier2_boundary_corner.sh` (F9)

**Interfaces:**
- Consumes: `shell.config_store.ConfigStore` (o `.data` já mesclado com os padrões).
- Produces:
  - `SEVERITIES = ("INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL")` e `SOUND_COOLDOWN = 5.0`;
  - `parse_alert(line: bytes) -> dict | None`;
  - `should_notify(alert: dict, min_severity: str) -> bool`;
  - `notify(alert: dict, sound_enabled: bool, now: float) -> None`, que guarda o horário do último som numa global do módulo;
  - `load_settings(data: dict) -> tuple[str, str, bool]`, que devolve `(socket, min_severity, sound)` já validados;
  - `run(socket_path: str, min_severity: str, sound_enabled: bool, stop: threading.Event | None = None, retry_base: float = 2.0, retry_max: float = 30.0) -> None`;
  - `main() -> int`, chamado por `python3 -m shell.edr_notify`;
  - o lançador `/usr/bin/lumen-edr-notify`.

- [ ] **Step 1: Escrever o harness e os testes que falham**

`tests/e2e/fixtures/edr_notify_harness.py <caso> <dir>` cuida de toda a montagem:
1. cria em `<dir>/bin` os falsos `pw-play` e `notify-send`, scripts `sh` que acrescentam `"$0 $*"` em `<dir>/calls.log`;
2. coloca `<dir>/bin` no início do `PATH`. No caso `sem_pwplay`, cria só o `notify-send`;
3. sobe um servidor `AF_UNIX` em `<dir>/s.sock`;
4. roda `edr_notify.run(..., stop=ev, retry_base=0.1, retry_max=0.5)` numa thread;
5. envia as linhas do caso, espera 0,5 s, liga o `stop`, faz o `join` e imprime o `calls.log`.

Ele importa o módulo com `sys.path.insert(0, <raiz do repo>)`. O `<dir>` é `$SANDBOX_DIR/edr`, que é curto o bastante para o `AF_UNIX`.

Os casos são:

| Caso | Linhas enviadas | Saída esperada no log |
|---|---|---|
| `high` | 1 HIGH | 1 `notify-send --app-name=Mandacaru --urgency=critical -- Mandacaru: HIGH behavior.revshell: Shell bash...` e 1 `pw-play .../alarm-clock-elapsed.oga` |
| `medium` | 1 MEDIUM | `--urgency=normal` e `dialog-warning.oga` |
| `low` | 1 LOW | log vazio |
| `limiar_high` | 1 MEDIUM, com `min_severity="HIGH"` | log vazio |
| `cooldown` | 2 HIGH seguidos | 2 `notify-send` e 1 `pw-play` |
| `lixo` | `{quebrado`, uma com `"v":2`, uma com `"severity":"PANICO"` e 1 HIGH | só o HIGH avisado |
| `reconecta` | servidor fecha, é recriado no mesmo caminho e manda 1 HIGH | o HIGH avisado |
| `sem_pwplay` | 1 HIGH | 1 `notify-send`, mais o aviso de `pw-play` no stderr |
| `traco` | HIGH com `summary` `"-x perigo"` | o `notify-send` recebe `-- Mandacaru: HIGH behavior.revshell: -x perigo` |
| `fragmento` | meia linha sem `\n` e o servidor fecha. Depois o servidor volta e manda 1 HIGH | só o HIGH avisado |

Testes novos em `tests/e2e/tier2_boundary_corner.sh`, numa seção nova `F9: Vigia do Mandacaru (lumen-edr-notify)`, antes de `suite_finish`. São T2_F9_01 a T2_F9_10, um por caso, cada um rodando o harness com `assert_exit_code 0 python3 "$harness" <caso> "$dir"` e conferindo o `LAST_CMD_OUTPUT` com `assert_contains` e `assert_not_contains`. A contagem, quando importa, sai de `grep -c`.

Testes novos em `tests/e2e/tier1_feature_coverage.sh`, na seção `F10`:
- **`T1_F10_01`:** o `packaging/templates/lumen-edr-notify` é executável, tem sintaxe bash válida e contém `exec /usr/bin/python3 -m shell.edr_notify`.
- **`T1_F10_02`:** o `config/shell.default.json` tem `edr.socket == "/run/mandacaru/alerts.sock"`, `edr.notify_min_severity == "MEDIUM"` e `edr.sound is True`. A conferência é feita com `python3 -c`.
- **`T1_F10_03`:** o `load_settings({"edr": {"notify_min_severity": "pânico"}})` devolve `MEDIUM` como severidade.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash tests/e2e/run-e2e-tests.sh --tier 1 && bash tests/e2e/run-e2e-tests.sh --tier 2`
Expected: os T1_F10_01 a 03 e os T2_F9_01 a 10 falham. O harness quebra com `ModuleNotFoundError: shell.edr_notify` e o lançador ainda não existe. Os testes que já existiam continuam passando.

- [ ] **Step 3: Implementar**

- `shell/edr_notify.py`:
  - **Leitura:** em `run`, o laço faz `connect`, depois `recv(65536)` num buffer e separa as linhas por `\n`. Um buffer maior que 64 KiB sem `\n` é zerado. No EOF, o fragmento é descartado e o laço volta a conectar.
  - **Reconexão:** segue a regra do Global Constraints. As esperas usam `stop.wait(t)`, para o teste conseguir parar o laço.
  - **Som:** `Popen` com `stdin/stdout/stderr=DEVNULL`.
  - **Popup:** também por `Popen`, com o `--` antes dos dois argumentos posicionais.
  - **Zumbis:** os `Popen` vivos ficam numa lista e levam `poll()` a cada alerta.
  - **Falta de comando:** um `FileNotFoundError` ou `OSError` de cada comando gera um aviso, uma vez por comando.
  - **`main`:** faz `load_settings(ConfigStore().data)` e depois `run(...)`.
  - **Encerramento:** com `KeyboardInterrupt`, sai com 0.
- `packaging/templates/lumen-edr-notify`: copiar o `packaging/templates/lumen-shell`, sem o bloco do `LD_PRELOAD`, e trocar o `exec` final por `exec /usr/bin/python3 -m shell.edr_notify "$@"`. O arquivo precisa ficar com `chmod +x`.
- `config/shell.default.json`: acrescentar a seção `edr` do Global Constraints depois de `bar`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash tests/e2e/run-e2e-tests.sh`
Expected: todos os tiers passam, com 131 + 13 testes.

- [ ] **Step 5: Commit**

```bash
git add shell/edr_notify.py packaging/templates/lumen-edr-notify config/shell.default.json tests/e2e/fixtures/edr_notify_harness.py tests/e2e/tier1_feature_coverage.sh tests/e2e/tier2_boundary_corner.sh
git commit -m "feat(shell): vigia lumen-edr-notify toca som e mostra popup dos alertas do Mandacaru"
```

### Task 2: integração na sessão, nos pacotes e na ISO

**Files:**
- Modify:
  - `packaging/templates/hyprland.conf` e `compositor/hyprland/hyprland.conf` (`exec-once`);
  - `packaging/build-debs.sh` (instala o lançador no `lumen-shell` e muda o `Depends` do `lumen-desktop`);
  - `packaging/debian/control` (o mesmo `Depends`);
  - `scripts/build-iso.sh` (`useradd`);
  - `installer/calamares/modules/users.conf`;
  - `packaging/third-party/mandacaru.lock`.
- Test: `tests/e2e/tier1_feature_coverage.sh` (T1_F9_01), `tests/e2e/tier3_cross_feature.sh` (PAIR9)

**Interfaces:**
- Consumes: o `/usr/bin/lumen-edr-notify` e o `python3 -m shell.edr_notify` da Task 1.
- Produces: a ISO com o vigia na sessão, o áudio, as notificações, o grupo `mandacaru` e o Mandacaru 0.3.0.

- [ ] **Step 1: Ajustar e escrever os testes que falham**

- **`T1_F9_01`:** as asserções de versão, URL e SHA256 passam a usar os valores 0.3.0 do Global Constraints.
- **`tier3_cross_feature.sh`:**
  - no bloco `need(...)` do T3_PAIR7, trocar o `need("lumen-desktop","mandacaru (>= 0.2.0)")` por `>= 0.3.0`;
  - acrescentar `need("lumen-desktop", X)` para cada um de `pipewire`, `pipewire-pulse`, `wireplumber`, `mako-notifier`, `libnotify-bin` e `sound-theme-freedesktop`.
- **Casos novos em `tier3_cross_feature.sh`:**
  - `T3_PAIR9_SESSAO_SOBE_VIGIA`: os dois `hyprland.conf` têm `exec-once = mako`. O `packaging/templates/hyprland.conf` tem `exec-once = /usr/bin/lumen-edr-notify`, e o `compositor/hyprland/hyprland.conf` tem `exec-once = python3 -m shell.edr_notify`.
  - `T3_PAIR9_PACOTE_INSTALA_VIGIA`: o `build-debs.sh` copia `packaging/templates/lumen-edr-notify` para `$stage_dir/usr/bin/lumen-edr-notify` no bloco do `lumen-shell`.
  - `T3_PAIR9_GRUPO_MANDACARU`: o `useradd` do `build-iso.sh` tem `-G sudo,video,audio,render,mandacaru`, e o `users.conf` tem `- mandacaru` em `defaultGroups`.
  - `T3_PAIR9_GRUPO_DEPOIS_DO_EDR`: no `build-iso.sh`, o `useradd ... mandacaru` aparece **depois** do `apt-get install -y lumen-desktop`, que é o que cria o grupo. A conferência segue o mesmo estilo Python do `T3_PAIR8_ISO_EXIGE_EDR`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash tests/e2e/run-e2e-tests.sh --tier 1 && bash tests/e2e/run-e2e-tests.sh --tier 3`
Expected: o T1_F9_01 falha na versão 0.2.0, o T3_PAIR7 falha nos `need` novos e os quatro T3_PAIR9 falham.

- [ ] **Step 3: Implementar**

- **`hyprland.conf`:** nos dois arquivos, depois do agente do polkit, entram o comentário e os dois `exec-once` da spec §3.2. Na cópia de desenvolvimento, o vigia é `python3 -m shell.edr_notify`.
- **`build-debs.sh`:** no bloco do `lumen-shell`, `cp "$WORKSPACE_ROOT/packaging/templates/lumen-edr-notify" "$stage_dir/usr/bin/lumen-edr-notify"`. O `chmod 0755` de `usr/bin` já existe.
- **`Depends` do `lumen-desktop`:** no `build-debs.sh` (linha com `mandacaru (>= 0.2.0), python3-bpfcc`) e no `packaging/debian/control`, trocar por `mandacaru (>= 0.3.0), python3-bpfcc, pipewire, pipewire-pulse, wireplumber, mako-notifier, libnotify-bin, sound-theme-freedesktop`, nessa ordem.
- **`build-iso.sh`:** `useradd -m -s /bin/bash -G sudo,video,audio,render,mandacaru $LIVE_USER`.
- **`users.conf`:** `- mandacaru` em `defaultGroups`, depois de `- render`.
- **`mandacaru.lock`:** as três chaves do Global Constraints, mantendo o comentário da primeira linha.

- [ ] **Step 4: Rodar e ver passar, e conferir o download real**

Run:
- `bash tests/e2e/run-e2e-tests.sh`;
- `./scripts/package-debs.sh --clean`;
- `dpkg-deb -f dist/debs/mandacaru_0.3.0_all.deb Version`;
- `grep -A1 'Package: mandacaru' dist/debs/Packages`;
- `dpkg-deb -f dist/debs/lumen-desktop_*.deb Depends`.

Expected:
- a suíte inteira passa, com 144 + 4 testes;
- o `package-debs` baixa a `.deb` 0.3.0, confere o hash e termina sem erro;
- a `Version` é `0.3.0`, e o `Packages` lista o `mandacaru` 0.3.0;
- o `Depends` do `lumen-desktop` termina em `mandacaru (>= 0.3.0), python3-bpfcc, pipewire, pipewire-pulse, wireplumber, mako-notifier, libnotify-bin, sound-theme-freedesktop`.

- [ ] **Step 5: Commit**

```bash
git add packaging/ compositor/hyprland/hyprland.conf scripts/build-iso.sh installer/calamares/modules/users.conf tests/e2e/tier1_feature_coverage.sh tests/e2e/tier3_cross_feature.sh
git commit -m "feat(iso): aviso sonoro do Mandacaru 0.3.0 com PipeWire, mako e grupo mandacaru"
```

### Task 3: teste manual na VM (feito pelo autor e pelo agente)

**Files:**
- Modify: `docs/superpowers/specs/2026-11-17-aviso-sonoro-edr-design.md` (resultado na §6)

- [ ] **Step 1: O autor gera a ISO**

O autor roda no terminal dele:

```bash
sudo UBUNTU_MIRROR=https://archive.ubuntu.com/ubuntu ./scripts/build-iso.sh --clean </dev/null 2>&1 | tee dist/build-iso.log
```

Expected: `ISO gerada com sucesso!`, e o `dpkg -s` da checagem do EDR passa.

- [ ] **Step 2: Bootar na VM `Lumen-OS-Teste`**

A VM precisa estar com a placa de som habilitada (HDA). Depois do boot, rodar os 5 itens do teste manual da spec §6, mais os pendentes da spec anterior:
- `systemctl is-active mandacaru`;
- `journalctl -u mandacaru -b`, com o eBPF ativo;
- `systemd-analyze blame | grep mandacaru`;
- `free -h`.

Expected:
- o socket `srw-rw---- root mandacaru`, e o usuário `lumen` no grupo;
- o `mako` e o `edr_notify` rodando;
- o MEDIUM gera popup normal e `dialog-warning`;
- o HIGH gera popup crítico e `alarm-clock-elapsed`;
- o EICAR não gera nenhum aviso.

- [ ] **Step 3: Registrar e commitar**

Acrescentar na §6 da spec um bloco "Resultado na VM (data)", com o que passou e as medidas, e commitar:

```bash
git add docs/superpowers/specs/2026-11-17-aviso-sonoro-edr-design.md
git commit -m "docs(spec): resultado do teste do aviso sonoro do Mandacaru na VM"
```
