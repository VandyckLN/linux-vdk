# Elevação de Privilégios via polkit — Plano de Implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para implementar este plano tarefa por tarefa. Os passos usam checkbox (`- [ ]`) para acompanhamento.

**Objetivo:** permitir que o Assistente de Boas-Vindas execute as etapas administrativas pedindo a senha numa janela do polkit, sem quebrar o uso dos scripts pelo terminal.

**Arquitetura:** um executável `lumen-root-helper` concentra tudo que roda como root, com uma lista fechada de ações e de pacotes permitidos. Uma função `as_root` (`system/lib/elevate.sh`) escolhe entre executar direto (já root), `pkexec` (assistente, `LUMEN_ELEVATE=pkexec`) ou `sudo` (terminal). Uma policy do polkit autoriza `/usr/bin/lumen-root-helper`, e o `hyprpolkitagent` fornece a janela de senha nas sessões.

**Stack:** Bash (`set -euo pipefail`), Python 3 (`welcome/stack_installer.py`), polkit/pkexec, empacotamento Debian via `dpkg-deb`, suíte E2E em bash (`tests/e2e/`).

**Spec:** `docs/superpowers/specs/2026-11-16-elevacao-privilegios-design.md`

## Restrições Globais

- Nome do executável instalado: `/usr/bin/lumen-root-helper`; fonte: `system/lumen-root-helper`.
- Diretório de dados instalado: `/usr/share/lumen-os/system/`; no checkout, a pasta `system/` do repo, resolvida pelo caminho real do próprio helper.
- O helper **nunca** aceita caminho de arquivo vindo do chamador.
- Ações: `apt-install <pkg>...`, `system-tune [--no-snap]`, `docker-group`, `vscode-repo`.
- Regex de nome de pacote: `^[a-z0-9][a-z0-9+.-]*$`.
- Códigos de saída do helper: `0` sucesso, `2` ação/argumento inválido, `3` não é root, outros repassados.
- Ordem no helper: validar → (se `LUMEN_ROOT_HELPER_DRY_RUN=1`, imprimir e sair `0`) → exigir root → executar.
- Prefixo de toda linha de saída do helper: `[root-helper]`.
- Carimbo do `apt-get update`: `/var/lib/lumen-os/apt-updated.stamp`, validade de 10 minutos.
- `docker-group`: usuário vindo de `PKEXEC_UID` (via `getent passwd`) ou `SUDO_USER`, exigindo UID ≥ 1000.
- Mensagens do `as_root`: `126` → "Autenticação cancelada. Nada foi alterado."; `127` → "Sem permissão de administrador para esta ação."; helper ausente com pkexec → "O pkexec precisa do lumen-root-helper instalado (pacote lumen-system). Pelo terminal, execute o script diretamente que a elevação será feita via sudo."
- Policy: arquivo `packaging/templates/dev.lumenos.root-helper.policy`, ação `dev.lumenos.root-helper`, `allow_any`/`allow_inactive` = `auth_admin`, `allow_active` = `auth_admin_keep`, `allow_gui` = `true`. Textos padrão em PT-BR: description "Executar tarefas administrativas do Linux VDK", message "É preciso autenticar para instalar pacotes e aplicar ajustes de sistema"; inglês apenas como `xml:lang="en"`.
- Agente do polkit: pacote `hyprpolkitagent`, binário `/usr/libexec/hyprpolkitagent`.
- Versão fixa dos pacotes internos: `1.0.0-1ubuntu1` (no `build-debs.sh`, `$VERSION`).
- `packaging/debian/control` e os heredocs de `packaging/build-debs.sh` mudam **sempre juntos**.
- Todo texto novo (mensagens, comentários, descrições de teste) em português do Brasil.
- Testes novos entram nos arquivos de tier existentes, numa seção nova `FUNCIONALIDADE F7: Elevação de Privilégios`, antes de `# Finaliza a suíte`, com IDs `T1_F7_NN`, `T2_F7_NN`, `T3_PAIR7_*` e `T4_SCENARIO6_*`.

## Foco de Revisão

1. **`allowed-packages.list` com CRLF ou espaços sobrando** (o repo é usado no WSL com `core.autocrlf=true`): o pacote deve continuar sendo reconhecido. O teste está na Tarefa 1.
2. **Helper rodando com ambiente vazio**, como o `pkexec` faz (sem `PATH`/`HOME`, cwd `/`): o dry-run precisa funcionar e achar o diretório de dados pelo próprio caminho. O teste está na Tarefa 1.
3. **`docker-group` com `PKEXEC_UID=0` ou UID < 1000**: precisa recusar com `2`, e não adicionar o root ao grupo docker. O teste está na Tarefa 2.
4. **Pacote novo adicionado ao `dev-stack/packages.list` sem entrar na lista permitida**: o `--cli` passa esses pacotes dinamicamente, então um teste precisa cruzar as duas listas. O teste está na Tarefa 4.
5. **Falha do helper propagada pelo `as_root`**: se o helper sair com `2`, o `as_root` precisa retornar `2`, e o script chamador (com `set -e`) deve abortar em vez de seguir como se nada tivesse acontecido. O teste está na Tarefa 3.

---

### Task 1: `lumen-root-helper`: validação, dry-run e `apt-install`

**Arquivos:**
- Criar: `system/lumen-root-helper` (0755)
- Criar: `system/root-helper/allowed-packages.list`
- Teste: `tests/e2e/tier1_feature_coverage.sh`, `tests/e2e/tier2_boundary_corner.sh` (seção F7)

**Interfaces:**
- Produz: CLI `lumen-root-helper <ação> [args...]`; variável `LUMEN_ROOT_HELPER_DRY_RUN=1`; no dry-run, cada comando é impresso numa linha `[root-helper] [dry-run] <comando>`.
- Produz: função interna `resolve_data_dir` (`/usr/share/lumen-os/system` se o caminho real for `/usr/bin/lumen-root-helper`; senão, o diretório do script).

- [ ] **Passo 1: Escrever os testes que falham**

Em `tier1_feature_coverage.sh`, na seção F7:
- `T1_F7_01` "Helper de root existe, é executável e tem sintaxe bash válida": `assert_file_executable "$helper"`, `assert_syntax_valid "$helper" "sh"`, com `helper="${WORKSPACE_ROOT}/system/lumen-root-helper"`.
- `T1_F7_02` "Lista de pacotes permitidos existe e não está vazia": `assert_file_not_empty "${WORKSPACE_ROOT}/system/root-helper/allowed-packages.list"`.

Em `tier2_boundary_corner.sh`, na seção F7 (todos com `LUMEN_ROOT_HELPER_DRY_RUN=1` exceto o de root):
- `T2_F7_01` "Helper recusa ação desconhecida": `assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" formatar-disco`.
- `T2_F7_02` "Helper recusa pacote fora da lista permitida": `assert_exit_code 2 … "$helper" apt-install nmap`.
- `T2_F7_03` "Helper recusa nomes de pacote maliciosos": três `assert_exit_code 2` com `-oAPT::X=1`, `'vim;rm -rf /'` e `'../etc'`.
- `T2_F7_04` "Helper recusa apt-install sem pacotes": `assert_exit_code 2 … "$helper" apt-install`.
- `T2_F7_05` "Ação válida sem root e sem dry-run sai com 3": `assert_exit_code 3 "$helper" apt-install git`. Pular com `test_case_skip` se a suíte estiver rodando como root (`EUID` 0).
- `T2_F7_06` "Dry-run de apt-install mostra update e install": saída de `env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" apt-install git jq` contém `apt-get update` e `apt-get install -y git jq`; exit `0`.
- `T2_F7_07` "Lista permitida com CRLF e espaços continua reconhecida" (Foco 1): copia o helper e uma lista com a linha `git \r` para `${SANDBOX_DIR}/rh/` (helper em `rh/lumen-root-helper`, lista em `rh/root-helper/allowed-packages.list`); `assert_exit_code 0 env LUMEN_ROOT_HELPER_DRY_RUN=1 "${SANDBOX_DIR}/rh/lumen-root-helper" apt-install git`.
- `T2_F7_08` "Helper funciona com ambiente vazio, como no pkexec" (Foco 2): `(cd / && assert_exit_code 0 env -i LUMEN_ROOT_HELPER_DRY_RUN=1 /bin/bash "$helper" apt-install git)`.

- [ ] **Passo 2: Rodar e confirmar a falha**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 1 && bash tests/e2e/run-e2e-tests.sh --tier 2`
Esperado: FALHA nos `T1_F7_*`/`T2_F7_*` (arquivo inexistente).

- [ ] **Passo 3: Criar `system/root-helper/allowed-packages.list`**

Um pacote por linha, `#` para comentários, nesta ordem: o conteúdo atual de `dev-stack/packages.list`; depois `systemd-zram-generator`, `docker.io`, `docker-compose-v2`, `neovim`, `wget`, `gpg`, `code`; depois, sob o comentário `# Reservados para o subprojeto 2 (GitHub + fonte do terminal)`, `gh`, `fonts-jetbrains-mono`, `fonts-firacode`, `fonts-cascadia-code`, `fonts-hack`.

- [ ] **Passo 4: Implementar `system/lumen-root-helper`**

Estrutura: `resolve_data_dir`; `log` (prefixo `[root-helper]`); `die_usage` (mensagem `[root-helper] ERRO: …` em stderr, `exit 2`); `run` (no dry-run imprime `[root-helper] [dry-run] <cmd>`, senão executa); `validate_packages` (cada argumento casa com a regex **e** está na lista; a leitura da lista remove `\r` e espaços das pontas e ignora linhas vazias e `#`); um `case` despachando a ação. Para `apt-install`: `apt-get update` só se o carimbo não existir ou tiver mais de 10 minutos (no dry-run, sempre imprime o update), depois `apt-get install -y "$@"` e `touch` no carimbo (com `mkdir -p /var/lib/lumen-os`). Defina `PATH=/usr/sbin:/usr/bin:/sbin:/bin` no topo, já que o `pkexec` limpa o ambiente. A checagem de root (`EUID -ne 0` → `exit 3`) vem depois da validação e do desvio de dry-run.

- [ ] **Passo 5: Rodar e confirmar que passou**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 1 && bash tests/e2e/run-e2e-tests.sh --tier 2`
Esperado: os dois tiers passam, sem regressão.

- [ ] **Passo 6: Commit**

```bash
git add system/lumen-root-helper system/root-helper/allowed-packages.list tests/e2e/tier1_feature_coverage.sh tests/e2e/tier2_boundary_corner.sh
git commit -m "feat(system): lumen-root-helper com validação, dry-run e apt-install"
```

---

### Task 2: Ações `system-tune`, `docker-group` e `vscode-repo`

**Arquivos:**
- Modificar: `system/lumen-root-helper`
- Teste: `tests/e2e/tier2_boundary_corner.sh` (seção F7)

**Interfaces:**
- Consome: `resolve_data_dir`, `run`, `die_usage` e o fluxo de `apt-install` (Tarefa 1).
- Produz: as ações `system-tune [--no-snap]`, `docker-group` e `vscode-repo`, com os efeitos da tabela da §4.1 da spec.

- [ ] **Passo 1: Escrever os testes que falham**

- `T2_F7_09` "Dry-run de system-tune --no-snap instala os 3 arquivos de configuração": a saída de `env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" system-tune --no-snap` contém `/etc/sysctl.d/99-lumen-dev.conf`, `/etc/systemd/zram-generator.conf` e `/etc/apt/preferences.d/99-no-snap`, e os caminhos de origem começam com o diretório `system/` do repo.
- `T2_F7_10` "system-tune sem --no-snap não aplica o pin do snap": a saída não contém `99-no-snap`.
- `T2_F7_11` "system-tune recusa argumento desconhecido": `assert_exit_code 2 … system-tune --forcar`.
- `T2_F7_12` "docker-group recusa quando não há usuário chamador": `assert_exit_code 2 env -u SUDO_USER -u PKEXEC_UID LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group`.
- `T2_F7_13` "docker-group recusa root e usuários de sistema" (Foco 3): `assert_exit_code 2` com `PKEXEC_UID=0` e com `PKEXEC_UID=1` (ambos com `-u SUDO_USER`).
- `T2_F7_14` "docker-group usa o usuário do PKEXEC_UID": com `PKEXEC_UID=$(id -u)` (o teste é pulado via `test_case_skip` se `id -u` < 1000), a saída contém `usermod -aG docker $(id -un)`.
- `T2_F7_15` "docker-group ignora argumentos extras": `assert_exit_code 2 … docker-group root`.
- `T2_F7_16` "vscode-repo usa apenas URLs fixas e não aceita argumentos": a saída do dry-run contém `https://packages.microsoft.com/keys/microsoft.asc` e `/etc/apt/sources.list.d/vscode.list`; `assert_exit_code 2 … vscode-repo https://exemplo.invalido`.

- [ ] **Passo 2: Rodar e confirmar a falha**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 2`
Esperado: FALHA nos `T2_F7_09`–`T2_F7_16` (ação desconhecida → `2` ou saída sem os textos).

- [ ] **Passo 3: Implementar as três ações em `system/lumen-root-helper`**

`system-tune`: a sequência da §4.1, com origens em `$DATA_DIR/{sysctl,zram,apt}/…`; o `systemd-zram-generator` é instalado pelo mesmo caminho interno do `apt-install`. `docker-group`: resolver o usuário com `getent passwd "$PKEXEC_UID"`, senão com `SUDO_USER` → `id -u`; exigir UID ≥ 1000. `vscode-repo`: `wget -qO- <url> | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg`, depois gravar a linha `deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main` em `/etc/apt/sources.list.d/vscode.list` e remover o carimbo do apt. No dry-run, comandos com pipe ou redirecionamento são impressos como texto.

- [ ] **Passo 4: Rodar e confirmar que passou**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 2`
Esperado: PASSA, incluindo os `T2_F7_01`–`T2_F7_08` da Tarefa 1.

- [ ] **Passo 5: Commit**

```bash
git add system/lumen-root-helper tests/e2e/tier2_boundary_corner.sh
git commit -m "feat(system): ações system-tune, docker-group e vscode-repo no root-helper"
```

---

### Task 3: Função `as_root` (`system/lib/elevate.sh`)

**Arquivos:**
- Criar: `system/lib/elevate.sh` (0644)
- Teste: `tests/e2e/tier1_feature_coverage.sh`, `tests/e2e/tier2_boundary_corner.sh` (seção F7)

**Interfaces:**
- Consome: CLI do `lumen-root-helper` (Tarefas 1 e 2).
- Produz: a função bash `as_root <ação> [args...]`, que retorna o código de saída do helper (ou `126`/`127` do pkexec, após imprimir a mensagem traduzida em stderr). Variáveis lidas: `LUMEN_ELEVATE` (`pkexec` ativa o pkexec) e `LUMEN_ROOT_HELPER_BIN` (caminho do helper instalado; padrão `/usr/bin/lumen-root-helper`). O helper do repo é achado relativo ao próprio `elevate.sh` (`$(dirname BASH_SOURCE)/../lumen-root-helper`).

- [ ] **Passo 1: Escrever os testes que falham**

Os testes do Tier 2 criam um diretório de mocks próprio, `${SANDBOX_DIR}/elev_bin`, colocado **na frente** do PATH, com `sudo` e `pkexec` falsos que gravam `$0 $*` em `${SANDBOX_DIR}/elev.calls` e saem com o código definido em `MOCK_EXIT` (padrão `0`).
- `T1_F7_03` "elevate.sh existe e tem sintaxe bash válida": `assert_syntax_valid "${WORKSPACE_ROOT}/system/lib/elevate.sh" "sh"`.
- `T2_F7_17` "as_root usa sudo no terminal": `bash -c 'source "$1"; as_root apt-install git' _ "$elevate"` sem `LUMEN_ELEVATE` e com `LUMEN_ROOT_HELPER_BIN=/caminho/inexistente` (pra forçar o helper do repo); `elev.calls` contém `sudo` e `system/lumen-root-helper apt-install git`.
- `T2_F7_18` "as_root usa pkexec com o helper instalado quando LUMEN_ELEVATE=pkexec": com `LUMEN_ELEVATE=pkexec` e `LUMEN_ROOT_HELPER_BIN="${SANDBOX_DIR}/fake-installed-helper"` (arquivo existente e executável); `elev.calls` contém `pkexec ${SANDBOX_DIR}/fake-installed-helper apt-install git`.
- `T2_F7_19` "as_root com pkexec e helper não instalado falha com mensagem clara": `LUMEN_ROOT_HELPER_BIN=/caminho/inexistente`; exit diferente de 0 e saída contendo `O pkexec precisa do lumen-root-helper instalado`.
- `T2_F7_20` "as_root traduz o cancelamento do pkexec": `MOCK_EXIT=126`; exit `126` e saída contendo `Autenticação cancelada. Nada foi alterado.`
- `T2_F7_21` "as_root traduz falta de autorização do pkexec": `MOCK_EXIT=127`; saída contendo `Sem permissão de administrador para esta ação.`
- `T2_F7_22` "Falha do helper é propagada e aborta o script chamador" (Foco 5): `MOCK_EXIT=2` com o sudo falso; `bash -c 'set -e; source "$1"; as_root apt-install git; echo CONTINUOU' _ "$elevate"` sai com `2` e a saída **não** contém `CONTINUOU`.

- [ ] **Passo 2: Rodar e confirmar a falha**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 1 && bash tests/e2e/run-e2e-tests.sh --tier 2`
Esperado: FALHA nos `T1_F7_03` e `T2_F7_17`–`T2_F7_22`.

- [ ] **Passo 3: Implementar `as_root` em `system/lib/elevate.sh`**

Arquivo feito pra ser carregado com `source` (sem `set -e` próprio e sem `exit`; usa `return`). A lógica segue a §4.3 da spec: `EUID` 0 → helper direto; `LUMEN_ELEVATE=pkexec` → `pkexec "$LUMEN_ROOT_HELPER_BIN"`; senão `sudo` com o helper instalado, se existir, ou com o do repo. As mensagens dos códigos `126` e `127` estão nas Restrições Globais.

- [ ] **Passo 4: Rodar e confirmar que passou**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 1 && bash tests/e2e/run-e2e-tests.sh --tier 2`
Esperado: PASSA.

- [ ] **Passo 5: Commit**

```bash
git add system/lib/elevate.sh tests/e2e/tier1_feature_coverage.sh tests/e2e/tier2_boundary_corner.sh
git commit -m "feat(system): função as_root escolhe entre pkexec e sudo"
```

---

### Task 4: Scripts usando `as_root` + `LUMEN_ELEVATE` no assistente

**Arquivos:**
- Modificar: `system/apply-system-tuning.sh` (corpo inteiro)
- Modificar: `dev-stack/setup-dev-env.sh:63-72` (`--cli`), `:113-118` (`--docker`), `:120-132` (editores `neovim` e `vscode`)
- Modificar: `welcome/stack_installer.py:94-125` (`run_commands`)
- Teste: `tests/e2e/tier3_cross_feature.sh` (seção F7)

**Interfaces:**
- Consome: `as_root` (Tarefa 3) e as ações do helper (Tarefas 1 e 2).
- Produz: os scripts sem nenhum `sudo` direto; `run_commands(commands, on_log, dry_run=False) -> bool` inalterado na assinatura, mas executando cada comando com `LUMEN_ELEVATE=pkexec` no ambiente.

- [ ] **Passo 1: Escrever os testes que falham**

Em `tier3_cross_feature.sh`, seção F7:
- `T3_PAIR7_SCRIPTS_SEM_SUDO_DIRETO` "Scripts de setup não chamam sudo diretamente": `assert_not_contains` com o padrão `(^|[^_[:alnum:]])sudo[[:space:]]` em `system/apply-system-tuning.sh` e em `dev-stack/setup-dev-env.sh`; os dois contêm `system/lib/elevate.sh`.
- `T3_PAIR7_PACOTES_NA_LISTA_PERMITIDA` "Todo pacote instalado pelos scripts consta na lista permitida" (Foco 4): um script Python inline extrai os argumentos literais de cada `as_root apt-install …` em `setup-dev-env.sh` (ignorando argumentos que começam com `$` ou `"$`, como `"${PKGS[@]}"`) **e** todas as entradas de `dev-stack/packages.list` (removendo `\r`, espaços, vazios e `#`), e falha listando o que faltar em `system/root-helper/allowed-packages.list`.
- `T3_PAIR7_ASSISTENTE_DEFINE_PKEXEC` "O assistente executa os scripts com LUMEN_ELEVATE=pkexec": `python3 -I -c` com `sys.path.insert(0, WORKSPACE_ROOT)`, chama `run_commands([["bash","-c","echo ELEV=$LUMEN_ELEVATE"]], out.append)` e verifica que `"ELEV=pkexec"` está em `out`.

- [ ] **Passo 2: Rodar e confirmar a falha**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 3`
Esperado: FALHA nos três `T3_PAIR7_*`.

- [ ] **Passo 3: Reescrever `system/apply-system-tuning.sh`**

Mantém `ROOT_DIR`, as mensagens `echo` atuais e o argumento `--no-snap`; faz `source "$ROOT_DIR/system/lib/elevate.sh"` e substitui todas as linhas `sudo` por um único `as_root system-tune` (com `--no-snap` quando recebido).

- [ ] **Passo 4: Trocar os `sudo` de `dev-stack/setup-dev-env.sh`**

`source "$ROOT_DIR/system/lib/elevate.sh"` logo após o `ROOT_DIR`. `--cli` → `as_root apt-install "${PKGS[@]}"` (o `apt-get update` deixa de ser chamado à parte). `--docker` → `as_root apt-install docker.io docker-compose-v2` + `as_root docker-group`. `neovim` → `as_root apt-install neovim`. `vscode` → `as_root apt-install wget gpg` + `as_root vscode-repo` + `as_root apt-install code`. As partes do usuário não mudam.

- [ ] **Passo 5: Passar `LUMEN_ELEVATE=pkexec` em `run_commands`**

Em `welcome/stack_installer.py`, `import os` e `env={**os.environ, "LUMEN_ELEVATE": "pkexec"}` no `subprocess.Popen`.

- [ ] **Passo 6: Rodar e confirmar que passou**

Rodar: `bash tests/e2e/run-e2e-tests.sh`
Esperado: os 4 tiers passam.

- [ ] **Passo 7: Commit**

```bash
git add system/apply-system-tuning.sh dev-stack/setup-dev-env.sh welcome/stack_installer.py tests/e2e/tier3_cross_feature.sh
git commit -m "refactor: scripts de setup elevam via as_root; assistente usa pkexec"
```

---

### Task 5: Policy do polkit e empacotamento

**Arquivos:**
- Renomear: `packaging/templates/dev.lumenos.welcome.policy` → `packaging/templates/dev.lumenos.root-helper.policy` (e reescrever o conteúdo)
- Modificar: `packaging/debian/control` (stanzas `lumen-system`, `lumen-dev-stack`, `lumen-compositor`)
- Modificar: `packaging/build-debs.sh` (blocos `lumen-system`, `lumen-dev-stack`, `lumen-welcome`, `lumen-compositor`)
- Modificar: `packaging/debian/lumen-system.install`, `packaging/debian/lumen-welcome.install`
- Teste: `tier1_feature_coverage.sh`, `tier3_cross_feature.sh`, `tier4_real_world.sh` (seção F7)

**Interfaces:**
- Consome: os arquivos `system/lumen-root-helper`, `system/lib/elevate.sh` e `system/root-helper/allowed-packages.list` (Tarefas 1–3).
- Produz: `lumen-system` instalando `/usr/bin/lumen-root-helper` (0755, a única cópia do helper no pacote), `/usr/share/lumen-os/system/lib/elevate.sh`, `/usr/share/lumen-os/system/root-helper/allowed-packages.list` e `/usr/share/polkit-1/actions/dev.lumenos.root-helper.policy`.

- [ ] **Passo 1: Escrever os testes que falham**

- `T1_F7_04` "Policy do polkit é XML válido e autoriza o lumen-root-helper": `python3 -I -c` com `xml.etree.ElementTree` lê a policy e verifica `action[@id='dev.lumenos.root-helper']`, o annotate `org.freedesktop.policykit.exec.path` = `/usr/bin/lumen-root-helper`, `allow_gui` = `true` e `allow_active` = `auth_admin_keep`; `assert_file_not_exists` na policy antiga.
- `T3_PAIR7_DEPENDS_SINCRONIZADOS` "Os Depends do control e do build-debs.sh são iguais": um Python inline compara, por pacote, a lista de `Depends` das stanzas de `packaging/debian/control` (descartando `${misc:Depends}`) com a dos heredocs `cat <<EOF > "$stage_dir/DEBIAN/control"` do `build-debs.sh` (trocando `$VERSION` por `1.0.0-1ubuntu1`), tudo normalizado e ordenado. Também confere que `lumen-system` inclui `pkexec` e `polkitd`, que `lumen-dev-stack` inclui `lumen-system (= 1.0.0-1ubuntu1)` e que `lumen-compositor` inclui `hyprpolkitagent`.
- `T4_SCENARIO6_PACOTES_COM_HELPER_E_POLICY` "Pacote lumen-system traz helper, elevate.sh, lista e policy; lumen-welcome não traz policy": roda `bash packaging/build-debs.sh "${SANDBOX_DIR}/debs"` e usa `dpkg-deb -c` em `lumen-system_*.deb` pra exigir `./usr/bin/lumen-root-helper` (permissão `-rwxr-xr-x`), `./usr/share/lumen-os/system/lib/elevate.sh`, `./usr/share/lumen-os/system/root-helper/allowed-packages.list` e `./usr/share/polkit-1/actions/dev.lumenos.root-helper.policy`, e em `lumen-welcome_*.deb` pra garantir que não aparece `polkit-1/actions`.

- [ ] **Passo 2: Rodar e confirmar a falha**

Rodar: `bash tests/e2e/run-e2e-tests.sh`
Esperado: FALHA nos `T1_F7_04`, `T3_PAIR7_DEPENDS_SINCRONIZADOS` e `T4_SCENARIO6_*`.

- [ ] **Passo 3: Reescrever a policy**

`git mv` para o nome novo. Conteúdo conforme as Restrições Globais (ação, defaults, annotates e os textos em PT-BR padrão com o inglês em `xml:lang="en"`).

- [ ] **Passo 4: Atualizar `control`, `build-debs.sh` e `.install`**

No `build-debs.sh`, bloco `lumen-system`: criar `usr/share/lumen-os/system/lib`, `usr/share/lumen-os/system/root-helper` e `usr/share/polkit-1/actions`; copiar o helper para `usr/bin/lumen-root-helper`, o `elevate.sh`, a lista e a policy; `Depends: procps, systemd-zram-generator, pkexec, polkitd`. Bloco `lumen-welcome`: remover a cópia da policy e o `mkdir` de `polkit-1/actions`. `lumen-dev-stack`: acrescentar `lumen-system (= $VERSION)`. `lumen-compositor`: acrescentar `hyprpolkitagent`. Refletir as mesmas dependências no `control` e as mesmas cópias no `lumen-system.install`; remover a linha da policy do `lumen-welcome.install`. A normalização de permissões existente (`build-debs.sh:270-279`) já cobre os dois casos: `usr/bin/*` → 0755 e `*.sh` → 0755. O `elevate.sh` sai portanto com 0755 em vez dos 0644 da spec, o que é inofensivo para um arquivo carregado via `source`. Não é preciso mudar essa regra.

- [ ] **Passo 5: Rodar e confirmar que passou**

Rodar: `bash tests/e2e/run-e2e-tests.sh`
Esperado: os 4 tiers passam.

- [ ] **Passo 6: Commit**

```bash
git add -A packaging/ tests/e2e/
git commit -m "build(packaging): lumen-system empacota root-helper, elevate.sh e policy do polkit"
```

---

### Task 6: Agente do polkit nas sessões Hyprland e Wayfire

**Arquivos:**
- Modificar: `compositor/hyprland/hyprland.conf`, `packaging/templates/hyprland.conf` (logo após o `exec-once` do shell)
- Modificar: `compositor/wayfire/wayfire.ini`, `packaging/templates/wayfire.ini` (seção `[autostart]`)
- Teste: `tests/e2e/tier3_cross_feature.sh` (seção F7)

**Interfaces:**
- Consome: a dependência `hyprpolkitagent` do `lumen-compositor` (Tarefa 5).

- [ ] **Passo 1: Escrever o teste que falha**

- `T3_PAIR7_SESSOES_INICIAM_AGENTE_POLKIT` "As sessões Hyprland e Wayfire iniciam o agente do polkit": `assert_contains` com `^exec-once[[:space:]]*=[[:space:]]*/usr/libexec/hyprpolkitagent` nos dois `hyprland.conf` e com `^polkit[[:space:]]*=[[:space:]]*/usr/libexec/hyprpolkitagent` nos dois `wayfire.ini`.

- [ ] **Passo 2: Rodar e confirmar a falha**

Rodar: `bash tests/e2e/run-e2e-tests.sh --tier 3`
Esperado: FALHA no `T3_PAIR7_SESSOES_INICIAM_AGENTE_POLKIT`.

- [ ] **Passo 3: Acrescentar as linhas de autostart**

Hyprland: `exec-once = /usr/libexec/hyprpolkitagent`, com o comentário `# Agente do polkit (janela de senha do pkexec)`. Wayfire: `polkit = /usr/libexec/hyprpolkitagent` dentro de `[autostart]`.

- [ ] **Passo 4: Rodar a suíte completa**

Rodar: `bash tests/e2e/run-e2e-tests.sh`
Esperado: `[TODOS OS TIERS PASSARAM]`.

- [ ] **Passo 5: Commit**

```bash
git add compositor/ packaging/templates/hyprland.conf packaging/templates/wayfire.ini tests/e2e/tier3_cross_feature.sh
git commit -m "feat(compositor): inicia hyprpolkitagent nas sessões Hyprland e Wayfire"
```

---

### Task 7: Verificação manual na VM

Sem arquivos novos. É o critério de pronto da §8 da spec.

- [ ] **Passo 1:** gerar os pacotes e a ISO (`./scripts/package-debs.sh` e `sudo ./scripts/build-iso.sh`) e subir com `./scripts/test-iso-qemu.sh --uefi`.
- [ ] **Passo 2:** na sessão Hyprland, abrir o assistente, marcar "Instalar Docker + Docker Compose" e clicar em "Aplicar e Salvar Setup". Esperado: **uma** janela de senha do polkit; o log mostra linhas `[root-helper]`; termina com "Concluído com sucesso!".
- [ ] **Passo 3:** repetir marcando também "Otimizações Ubuntu Dev" e confirmar que **não** aparece uma segunda janela de senha. Se aparecer, registrar como achado (o plano B da §9 da spec, `lumen-root-helper batch`, fica para um ajuste posterior).
- [ ] **Passo 4:** repetir e cancelar a janela de senha. Esperado: "Autenticação cancelada. Nada foi alterado." no log e "Finalizado com avisos/erros." no status.
- [ ] **Passo 5:** repetir o Passo 2 numa sessão Wayfire.
- [ ] **Passo 6:** no terminal da VM, rodar `/usr/share/lumen-os/dev-stack/setup-dev-env.sh --cli` e confirmar que o `sudo` pede a senha no terminal, como antes.
