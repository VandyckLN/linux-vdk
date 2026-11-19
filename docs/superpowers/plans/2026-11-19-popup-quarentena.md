# Popup da quarentena: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** quando um alerta do Mandacaru traz `quarantine_id`, o clique no popup do mako abre uma janela GTK4 com
Confio / Analisar / Manter isolado, que chama os auxiliares `pkexec` do Mandacaru 0.4.0.

**Architecture:** o vigia (`shell/edr_notify.py`) captura o stdout do `notify-send --wait`. Se o usuário clicou
num alerta com id, o vigia abre `shell/quarantine_dialog.py`, um processo curto. A janela separa a lógica pura do
GTK: `commands()`, `outcome()` e os argumentos da linha de comando não importam `gi`, porque a máquina de dev não
tem GTK. Só `run_window()` importa `gi`. Os testes seguem o estilo da distro, com harness Python mais asserções
no tier 2.

**Tech Stack:** Python ≥3.10, PyGObject + GTK 4 (`Gtk.Application`, `Gio.Subprocess`), notify-send/mako,
Hyprland 0.53, testes e2e em bash (`tests/e2e`).

**Spec:** `docs/superpowers/specs/2026-11-19-popup-quarentena-design.md`. Contrato do lado do Mandacaru:
`/home/vandyck/projetos/mandacaru/docs/superpowers/specs/2026-11-18-quarentena-design.md` §4, §5
("Contrato de saída") e §10.

## Global Constraints

- **Comandos dos botões**, sempre em lista e sem shell:
  - `["pkexec", "/usr/libexec/mandacaru/quarantine-release", "confiar", id]`;
  - `["pkexec", "/usr/libexec/mandacaru/quarantine-decide", "analisar", id, "--json"]`;
  - `["pkexec", "/usr/libexec/mandacaru/quarantine-decide", "manter", id]`.
- **id válido:** `^[0-9a-f]{32}$`. Um id inválido é tratado como alerta sem id (popup comum, sem janela).
- **Popup de alerta com id:**
  - título `Mandacaru: arquivo isolado (<SEV>)`;
  - ação `--action=default=O que fazer?`;
  - o resto das opções igual ao popup de hoje (`--app-name=Mandacaru --icon=mandacaru`, urgência e expire por
    severidade, `--wait`, `--` antes do título).
- **A janela só abre** se o stdout do `notify-send` for exatamente `default` (depois de `strip()`). Qualquer
  outra saída, como vazio no dismiss, expirar ou erro, não abre nada.
- **Id da aplicação GTK:** `io.github.vandyckln.lumen.quarentena`.
- **Trava de uma janela por caso:** `$XDG_RUNTIME_DIR/lumen-quarentena-<id>.lock` (fallback
  `/run/user/<uid>`). A segunda instância sai com 0.
- **Texto fixo da janela:**
  - título "Arquivo isolado pelo Mandacaru";
  - aviso "Se você não decidir, o arquivo é apagado em 30 dias.";
  - botões "Confio (pede senha)", "Analisar", "Manter isolado";
  - enquanto roda: "Aguardando…".
- **Mensagens por resultado** (exatas):
  - confiar 0: `Arquivo devolvido. <última linha não vazia do stdout>`. Fecha.
  - manter 0: `Mantido isolado. Será apagado em 30 dias.` Fecha.
  - analisar 0, conforme o `verdict` do JSON:
    - `malicioso`: `Malicioso. Recomendado manter isolado.`;
    - `legitimo_conhecido`: `Arquivo legítimo conhecido (provável falso positivo).`;
    - `desconhecido`: `Desconhecido. Nenhuma base conhece este arquivo.`;
    - em todos os casos, seguido de `\n<summary>` quando o `summary` não for vazio;
    - botões depois: confiar e manter.
  - 3: `Este caso não existe mais ou já foi resolvido.` Sem botões.
  - 4: `A quarentena foi adulterada. O arquivo não foi devolvido.` Sem botões.
  - 126/127: `Autenticação cancelada.` Os botões continuam os de antes.
  - outros, ou analisar 0 com JSON inválido (ou `v` ≠ 1, ou `verdict` desconhecido): `Falhou (código <rc>).`,
    mais `\n<última linha não vazia do stderr>` quando houver. Os botões continuam os de antes.
  - pkexec ausente: `Não foi possível rodar o pkexec. No terminal: sudo mandacaru quarentena <ação> <id>`.
- **Fechar automaticamente** depois de Confio/Manter darem certo: 3000 ms.
- **Textos da janela** sempre com `Gtk.Label.set_text` (nunca markup).
- **Sem dependência nova:** `lumen-shell` já depende de `python3-gi`, `gir1.2-gtk-4.0`.
- **Commits:** e-mail `183553227+VandyckLN@users.noreply.github.com` (já é a config local do repo). Sem linha
  `Co-Authored-By` e sem rodapé do Claude.
- **Rodar os testes:** `bash tests/e2e/run-e2e-tests.sh --tier 2 -q` e `--tier 3 -q`. Hoje os dois estão verdes.

## Review Focus

1. **Clique depois de o popup expirar ou ser dispensado:** o `notify-send` devolve stdout vazio. Nenhuma janela
   pode abrir e nenhuma decisão pode ser registrada (Task 3, caso `dismiss`).
2. **`quarantine_id` hostil no socket** (`../../etc`, maiúsculas, 33 chars, não-string): não pode chegar a argv
   nenhum, nem a caminho de trava (Tasks 1 e 3, casos `id_invalido`).
3. **Resumo com markup ou começando com `-`** num alerta com id: continua escapado no popup e vai como texto
   puro para a janela, depois de `--summary` (Task 3, caso `id_markup`).
4. **JSON do `analisar` truncado ou de outra versão:** vira erro, não um veredito falso de "desconhecido"
   (Task 1, casos de `outcome`).
5. **Dois cliques no mesmo caso**, em popups repetidos: uma janela só (Task 1, trava).

---

### Task 1: lógica da janela (sem GTK)

**Files:**
- Create: `shell/quarantine_dialog.py`
- Create: `tests/e2e/fixtures/quarantine_dialog_harness.py`
- Modify: `tests/e2e/tier2_boundary_corner.sh` (novo bloco `T2_F10_*` no fim, antes do resumo)

**Interfaces:**
- Produces, em `shell/quarantine_dialog.py`, sem importar `gi` no topo do módulo:
  - `CASE_ID = re.compile(r"[0-9a-f]{32}")` e `valid_id(value: object) -> bool`, com `fullmatch` e só `str`;
  - `commands(case_id: str) -> dict[str, list[str]]`, com chaves `"confiar"`, `"analisar"` e `"manter"`
    (valores das Global Constraints);
  - `@dataclass(frozen=True) class Outcome: message: str; buttons: tuple[str, ...]; close: bool;
    verdict: str | None = None`;
  - `outcome(action: str, rc: int, stdout: str, stderr: str, current: tuple[str, ...]) -> Outcome`, onde
    `current` são os botões ativos antes do clique;
  - `spawn_failed(action: str, case_id: str, current: tuple[str, ...]) -> Outcome`, para o pkexec ausente;
  - `INITIAL_BUTTONS = ("confiar", "analisar", "manter")`, `AFTER_ANALYSIS = ("confiar", "manter")`,
    `CLOSE_MS = 3000`;
  - `parse_args(argv: list[str]) -> argparse.Namespace`, com o `id` posicional e `--rule` e `--summary`
    (padrão `""`). Id inválido: `SystemExit(2)`.
  - `lock_path(case_id: str) -> str`;
  - `main(argv=None) -> int`: valida, pega a trava com `shell.edr_notify.acquire_single_instance(lock_path(id))`,
    sai 0 se já houver janela, chama `run_window(args)` (Task 2) e devolve o código dela.
- Consumes: `shell.edr_notify.acquire_single_instance(path)` (existe). Importe dentro de `main()`: a Task 3 faz o `edr_notify` importar este módulo, e um import no topo daria import circular.

- [ ] **Step 1: harness com os casos.** `quarantine_dialog_harness.py <caso>` imprime uma linha por verificação,
  no estilo `ok <nome>` / `FALHA <nome>: <detalhe>`, e sai com 1 se alguma falhou. Casos e asserções:
  - `commands`: `commands("a"*32)["analisar"] == ["pkexec", "/usr/libexec/mandacaru/quarantine-decide",
    "analisar", "a"*32, "--json"]`, e o mesmo para confiar e manter.
  - `valid_id`: `True` para `"0123456789abcdef"*2`. `False` para `"A"*32`, `"a"*31`, `"a"*33`, `"../../etc"`,
    `"a"*32+"\n"`, `None` e `123`.
  - `outcome_ok`:
    - `outcome("confiar", 0, "x\nRestaurado em /home/a/x.py\n", "", INITIAL_BUTTONS)` dá a mensagem
      `"Arquivo devolvido. Restaurado em /home/a/x.py"`, com `close` True e `buttons == ()`;
    - `manter` 0 dá a mensagem fixa e fecha.
  - `outcome_analisar`:
    - JSON `{"v":1,"id":…,"verdict":"malicioso","sources":{},"summary":"Cymru: achou"}` dá
      `"Malicioso. Recomendado manter isolado.\nCymru: achou"`, com `verdict == "malicioso"`,
      `buttons == AFTER_ANALYSIS` e `close` False;
    - `summary` vazio fica sem `\n`;
    - os outros dois vereditos dão as mensagens exatas.
  - `outcome_analisar_ruim`: stdout `"{quebrado"`, `{"v":2,...}` e `{"v":1,"verdict":"talvez"}` dão
    `message.startswith("Falhou (código 0)")` e mantêm `current`.
  - `outcome_codigos`:
    - 3 e 4 dão as mensagens exatas e `buttons == ()`;
    - 126 e 127 dão `"Autenticação cancelada."` e mantêm `current`;
    - 1 com stderr `"a\nerro x\n\n"` dá `"Falhou (código 1).\nerro x"` e mantém `current`.
  - `spawn_failed`: a mensagem contém `sudo mandacaru quarentena confiar <id>` e mantém `current`.
  - `args`: `parse_args([id, "--rule", "r", "--summary", "-x <b>"])` preserva `"-x <b>"`. Id inválido dá
    `SystemExit` com código 2.
  - `trava`: com `XDG_RUNTIME_DIR=<tmp>`, `lock_path(id) == <tmp>/lumen-quarentena-<id>.lock`. Uma trava segura
    pelo harness faz `main([id])` num subprocess devolver 0 sem chamar `run_window`. Para provar isso, o
    subprocess troca `run_window` por uma função que imprime `abriu`, e a saída não pode conter `abriu`.
  - `sem_gi`: `python3 -c "import sys; sys.path.insert(0, REPO); import shell.quarantine_dialog;
    print('gi' in sys.modules)"` imprime `False`.
- [ ] **Step 2: casos `T2_F10_01..` no tier 2.** Um `test_case_start` por caso do harness, cada um com
  `assert_exit_code 0 python3 "$harness" <caso>` e `assert_not_contains "$LAST_CMD_OUTPUT" "FALHA"`.
- [ ] **Step 3: rodar e ver falhar.** `bash tests/e2e/run-e2e-tests.sh --tier 2 -q` deve dar FAIL nos
  `T2_F10_*`, porque o módulo ainda não existe.
- [ ] **Step 4: implementar as funções acima em `shell/quarantine_dialog.py`.** `run_window` fica como stub que
  levanta `NotImplementedError` (Task 2 implementa).
- [ ] **Step 5: rodar e ver passar.** O tier 2 inteiro deve ficar verde.
- [ ] **Step 6: commit.** `git add shell/quarantine_dialog.py tests/e2e/fixtures/quarantine_dialog_harness.py
  tests/e2e/tier2_boundary_corner.sh && git commit -m "feat(shell): logica da janela de decisao da quarentena"`

### Task 2: janela GTK4

**Files:**
- Modify: `shell/quarantine_dialog.py` (`run_window`)

**Interfaces:**
- Consumes: tudo da Task 1.
- Produces: `run_window(args: argparse.Namespace) -> int`, que importa `gi` dentro da função, roda um
  `Gtk.Application(application_id="io.github.vandyckln.lumen.quarentena",
  flags=Gio.ApplicationFlags.NON_UNIQUE)` e devolve o `run([])`.

- [ ] **Step 1: montar a janela.** `Gtk.ApplicationWindow` de ~420 px de largura, com o título fixo:
  - um label da regra, um do resumo (quebra de linha, selecionável) e um do aviso dos 30 dias;
  - um label de status;
  - um `Gtk.Spinner`;
  - os três botões, na ordem confiar, analisar, manter. "Manter isolado" é o botão padrão.

  Todos os textos usam `set_text`.
- [ ] **Step 2: clique.** Desliga todos os botões, liga o spinner e mostra "Aguardando…".
  - Roda `commands(id)[ação]` com `Gio.Subprocess.new(cmd, STDOUT_PIPE | STDERR_PIPE)` e
    `communicate_utf8_async`.
  - `GLib.Error` ao criar o processo: aplica `spawn_failed(...)`.
  - No callback, `rc = proc.get_exit_status()` se `get_if_exited()`. Se não, `rc = -1`.
  - Aplica `outcome(...)`: status = `message`, liga só os `buttons`, e no `verdict == "malicioso"` acrescenta a
    classe CSS `malicioso` ao status (vermelho, via `Gtk.CssProvider`).
  - Com `close` True: `GLib.timeout_add(CLOSE_MS, window.close)`.
- [ ] **Step 3: fechar a janela no meio de um comando** não mata o processo. A trava é solta na saída do
  processo, ao fechar o arquivo.
- [ ] **Step 4: verificar.** `python3 -m py_compile shell/quarantine_dialog.py`; tier 2 verde (o caso `sem_gi`
  continua `False`). Não há GTK na máquina de dev: o teste visual fica na VM (Task 5).
- [ ] **Step 5: commit.** `git commit -am "feat(shell): janela GTK4 de decisao da quarentena"`

### Task 3: vigia abre a janela no clique

**Files:**
- Modify: `shell/edr_notify.py`
- Modify: `tests/e2e/fixtures/edr_notify_harness.py`
- Modify: `tests/e2e/tier2_boundary_corner.sh` (novos `T2_F9_19..`)

**Interfaces:**
- Consumes: `shell.quarantine_dialog.valid_id` (importável sem `gi`).
- Produces, em `edr_notify`:
  - `DIALOG_CMD: list[str] = [sys.executable, "-m", "shell.quarantine_dialog"]`. O harness troca por um falso.
  - `notify(alert, sound_enabled)` igual para alerta sem id válido.

- [ ] **Step 1: falsos do harness.**
  - O `notify-send` falso passa a fazer `printf '%s\n' "$NOTIFY_OUT"` antes do `sleep` quando `NOTIFY_OUT` estiver
    definido.
  - Novo falso `lumen-quarentena` em `bin/`, que só registra a chamada no `calls.log`.
  - O harness põe `edr_notify.DIALOG_CMD = [<bin>/lumen-quarentena]`.
- [ ] **Step 2: casos novos.** A asserção é sobre a saída do harness.
  - `id_clique`: alerta HIGH com `quarantine_id="ab"*16`, `NOTIFY_SLEEP=0.1`, `NOTIFY_OUT=default`.
    - O popup chama `notify-send --app-name=Mandacaru --icon=mandacaru --urgency=critical --wait --action=default=O
      que fazer? -- Mandacaru: arquivo isolado (HIGH) behavior.revshell: …`.
    - O falso registra `lumen-quarentena abab…ab --rule behavior.revshell --summary Shell bash com conexao de rede
      ativa`.
  - `dismiss`: igual, mas com `NOTIFY_OUT` vazio. Nenhuma linha `lumen-quarentena`.
  - `id_invalido`: `quarantine_id` igual a `"../../etc"` e a `"AB"*16`. O popup sai como o de hoje
    (`--action=default=Silenciar`, título `Mandacaru: HIGH`). Nenhuma `lumen-quarentena`, mesmo com
    `NOTIFY_OUT=default`.
  - `id_markup`: summary `"-x Tom & <b>y</b>"` com id e clique. O corpo do popup sai escapado
    (`Tom &amp; &lt;b&gt;y&lt;/b&gt;`). A janela recebe `--summary -x Tom & <b>y</b>` cru.
  - `id_medium`: um MEDIUM com id continua com `--expire-time=10000` e o título `Mandacaru: arquivo isolado
    (MEDIUM)`.
  - O caso `clique` já existente (sem id, `NOTIFY_OUT=default`) não abre a janela.
- [ ] **Step 3: rodar o tier 2 e ver falhar** os casos novos.
- [ ] **Step 4: implementar.**
  - Para alerta com `valid_id(alert.get("quarantine_id"))`, monta o popup com o título e a ação das Global
    Constraints e `stdout=PIPE`. Para isso, `_popen` ganha `stdout=` opcional, com padrão `DEVNULL`.
  - Uma thread daemon faz `out = popup.stdout.read()` e `popup.wait()`. Se `out.decode(errors="replace").strip()
    == "default"`, chama `_spawn([*DIALOG_CMD, id, "--rule", rule, "--summary", summary])`.
  - O `_ring` continua parando com `_clicked(popup)`.
- [ ] **Step 5: tier 2 inteiro verde**, sem regressão nos `T2_F9_01..18`.
- [ ] **Step 6: commit.** `git commit -am "feat(edr-notify): clique num alerta isolado abre a janela de decisao"`

### Task 4: empacotamento e Hyprland

**Files:**
- Modify: `compositor/hyprland/hyprland.conf` e `packaging/templates/hyprland.conf`
- Modify: `packaging/build-debs.sh:255` e `packaging/debian/control:120`, de `mandacaru (>= 0.3.0)` para
  `mandacaru (>= 0.4.0)`
- Modify: `tests/e2e/tier3_cross_feature.sh` (`need("lumen-desktop", "mandacaru (>= 0.4.0)")` e um caso novo
  para as regras de janela)

- [ ] **Step 1: teste no tier 3.** Os dois `hyprland.conf` precisam conter exatamente
  `windowrule = float on, match:class io.github.vandyckln.lumen.quarentena` e
  `windowrule = center on, match:class io.github.vandyckln.lumen.quarentena`. Atualizar o `need(...)` para 0.4.0.
- [ ] **Step 2: rodar o tier 3 e ver falhar.**
- [ ] **Step 3: aplicar.** As duas linhas `windowrule` vão logo depois dos `layerrule`, com o comentário
  `# Janela de decisao da quarentena do Mandacaru: flutuante e no centro`. Trocar `0.3.0` por `0.4.0` nos dois
  `Depends`.
- [ ] **Step 4: tiers 2 e 3 verdes.**
- [ ] **Step 5: commit.** `git commit -am "build: janela da quarentena flutuante no Hyprland e mandacaru >= 0.4.0"`

### Task 5: lock 0.4.0 e teste na VM (controlador, depois da release)

Não é tarefa de subagente. Depende do merge do PR VandyckLN/mandacaru#5 e da release v0.4.0, e as duas coisas
pedem autorização do usuário.

- [ ] Atualizar `packaging/third-party/mandacaru.lock` (versão, URL e SHA256 da `.deb` da release).
- [ ] Montar a ISO e testar na VM:
  - um arquivo de teste que dispara alerta HIGH numa pasta vigiada;
  - o popup aparece como "arquivo isolado";
  - o clique abre a janela centralizada;
  - Analisar mostra o veredito;
  - Manter fecha;
  - num segundo caso, Confio pede senha e devolve o arquivo;
  - as decisões aparecem em `sudo tail /var/log/mandacaru/decisions.jsonl`.
- [ ] Conferir a sintaxe do `windowrule` no Hyprland 0.53 real. Se a regra não pegar, corrigir e ajustar o
  teste do tier 3.
