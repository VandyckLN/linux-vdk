# Design: Elevação de Privilégios via polkit (`lumen-root-helper`)

- **Data:** 2026-11-16
- **Status:** Aprovado no brainstorming, aguardando revisão da spec
- **Subprojeto:** 1 de 2. É pré-requisito do subprojeto 2 (Login no GitHub + Fonte do Terminal, ver o Apêndice A)

## 1. Problema

O Assistente de Boas-Vindas (`welcome/`) é uma janela GTK **sem terminal**. Ao clicar em "Aplicar e Salvar Setup", ele roda `bash system/apply-system-tuning.sh` e `bash dev-stack/setup-dev-env.sh`, que juntos fazem **16 chamadas de `sudo`** (apt, sysctl, zram, systemctl, usermod, repositório do VS Code). Sem TTY, o `sudo` não tem onde pedir a senha e essas etapas falham.

Problemas relacionados encontrados na análise:

1. A policy do polkit `packaging/templates/dev.lumenos.welcome.policy` existe, mas **não é usada**. Ela aponta para `/usr/bin/lumen-system-tune` e ninguém invoca o `pkexec`.
2. **Nenhuma sessão (Hyprland/Wayfire) inicia um agente do polkit**, então hoje o `pkexec` falharia com "No authentication agent found".
3. O `setup-dev-env.sh` mistura tarefas de root (apt, usermod) com tarefas do usuário (dotfiles em `$HOME`, mise, starship em `~/.local`). Rodar o script inteiro como root gravaria os dotfiles em `/root`.

## 2. Objetivos

- O assistente consegue executar todas as etapas administrativas pedindo a senha **uma vez por etapa** (ajustes de sistema; setup dev) numa janela gráfica do polkit. *(Revisado em 2026-11-17 após o teste na VM: o "Aplicar" padrão pede a senha 2 vezes, e isso foi aceito.)*
- Os scripts **continuam funcionando no terminal** do jeito atual (o `sudo` pede a senha no TTY).
- As tarefas do usuário continuam rodando **sem privilégio**, com o `$HOME` e o `$USER` corretos.
- Tudo que roda como root fica concentrado num único executável auditável, com lista fechada de ações.

### Fora de escopo

- Unificar a duplicação entre `packaging/debian/control` e os heredocs de `packaging/build-debs.sh` (os dois são atualizados em paralelo, ver a §6).
- Login no GitHub e escolha de fonte (subprojeto 2).
- Mudanças na UI do assistente além de passar `LUMEN_ELEVATE=pkexec` aos scripts.

## 3. Abordagem escolhida

Um **helper de root com lista fechada de ações** (`lumen-root-helper`), uma **função `as_root`** compartilhada pelos scripts que escolhe o mecanismo de elevação, e uma **policy do polkit** apontando para o helper.

Alternativas descartadas:

- **`sudo -A` com askpass gráfico:** o próprio app capturaria a senha do usuário, o cache do `sudo` sem TTY é imprevisível e o polkit já existente ficaria sem uso.
- **`pkexec` no script inteiro + `runuser` para as partes do usuário:** exige reescrever bastante os scripts, e qualquer passo do usuário sem `runuser` cria arquivos do root na home.

## 4. Componentes

### 4.1 `lumen-root-helper`

- **Fonte:** `system/lumen-root-helper` (bash, `set -euo pipefail`).
- **Instalado em:** `/usr/bin/lumen-root-helper` (0755), pelo pacote `lumen-system`.
- **Diretório de dados:** `/usr/share/lumen-os/system/` quando instalado. Quando roda a partir de um checkout do repo (apenas via `sudo`, no terminal), usa a pasta `system/` do repo, resolvida a partir do caminho do próprio script.
- **Regra de segurança:** o helper **nunca aceita caminhos de arquivo vindos do chamador**. Todo arquivo copiado vem do seu diretório de dados.

**Ações (uma por invocação):**

| Ação | Efeito | Validação |
|---|---|---|
| `apt-install <pkg>...` | `apt-get update` (no máximo 1 vez a cada 10 min, controlado pelo carimbo de tempo `/var/lib/lumen-os/apt-updated.stamp`) + `apt-get install -y <pkgs>` | Pelo menos 1 pacote; cada nome casa com `^[a-z0-9][a-z0-9+.-]*$` **e** consta em `allowed-packages.list` |
| `system-tune [--no-snap]` | `install -Dm644` de `sysctl/99-lumen-dev.conf` → `/etc/sysctl.d/`; `sysctl --system`; `apt-install systemd-zram-generator` (interno); `install -Dm644` de `zram/zram-generator.conf` → `/etc/systemd/`; `systemctl daemon-reload`; `systemctl restart systemd-zram-setup@zram0.service \|\| true`; com `--no-snap`: `install -Dm644` de `apt/99-no-snap` → `/etc/apt/preferences.d/` | O único argumento aceito é `--no-snap` |
| `docker-group` | `usermod -aG docker <usuário chamador>` | **Não recebe o usuário por argumento.** Usa `PKEXEC_UID` (resolvido via `getent passwd`) ou `SUDO_USER`. Exige UID ≥ 1000. Sem essa informação, recusa |
| `vscode-repo` | Baixa a chave de `https://packages.microsoft.com/keys/microsoft.asc`, aplica `gpg --dearmor` e grava em `/usr/share/keyrings/packages.microsoft.gpg`; grava `/etc/apt/sources.list.d/vscode.list`; invalida o carimbo do `apt-get update` | Sem argumentos; URLs fixas no código |

**Ordem de execução:**

1. Valida a ação e os argumentos → se inválido, `exit 2` sem efeitos colaterais.
2. Se `LUMEN_ROOT_HELPER_DRY_RUN=1`: imprime os comandos que executaria e sai com `0` (não exige root).
3. Confere `EUID == 0` → senão, `exit 3`.
4. Executa.

**Códigos de saída:** `0` sucesso; `2` ação/argumento inválido; `3` não está rodando como root; outros valores são repassados do comando que falhou.

**Saída:** cada linha é prefixada com `[root-helper]`.

### 4.2 Lista de pacotes permitidos

- **Fonte:** `system/root-helper/allowed-packages.list` (um pacote por linha; `#` para comentários).
- **Instalada em:** `/usr/share/lumen-os/system/root-helper/allowed-packages.list` (0644).
- **Conteúdo inicial:** todos os pacotes de `dev-stack/packages.list` + `systemd-zram-generator`, `docker.io`, `docker-compose-v2`, `neovim`, `wget`, `gpg`, `code`.
- **Reservados para o subprojeto 2:** `gh`, `fonts-jetbrains-mono`, `fonts-firacode`, `fonts-cascadia-code`, `fonts-hack`. Eles entram na lista já neste subprojeto para não exigir uma nova mudança no helper. Existência confirmada via `apt-cache policy` no Ubuntu 26.04.1: `gh` 2.46.0-4, `fonts-jetbrains-mono` 2.304+ds-6, `fonts-firacode` 6.2-3, `fonts-cascadia-code` 2407.24-3 e `fonts-hack` 3.003-4.

### 4.3 `as_root` (`system/lib/elevate.sh`)

- **Instalado em:** `/usr/share/lumen-os/system/lib/elevate.sh` (0644), pelo `lumen-system`.
- **Uso:** `source "$ROOT_DIR/system/lib/elevate.sh"`. O layout do repo e o de `/usr/share/lumen-os/` são iguais, então o caminho funciona nos dois casos.

**Lógica de `as_root <ação> [args...]`:**

1. Helper: `/usr/bin/lumen-root-helper` se existir; senão, `$ROOT_DIR/system/lumen-root-helper`.
2. `EUID == 0` → executa o helper diretamente.
3. `LUMEN_ELEVATE == pkexec` → `pkexec /usr/bin/lumen-root-helper "$@"`. Se `/usr/bin/lumen-root-helper` não existir, falha com: *"O pkexec precisa do lumen-root-helper instalado (pacote lumen-system). Pelo terminal, execute o script diretamente que a elevação será feita via sudo."*
4. Caso contrário → `sudo "$helper" "$@"`.

**Tradução dos códigos do `pkexec`:**

- `126` → "Autenticação cancelada. Nada foi alterado."
- `127` → "Autenticação cancelada ou negada. Nada foi alterado." *(o `hyprpolkitagent` devolve 127 ao cancelar; ver §9)*
- Os demais são repassados sem alteração.

### 4.4 Alterações nos scripts existentes

- **`system/apply-system-tuning.sh`:** passa a apenas fazer `source` do `elevate.sh` e chamar `as_root system-tune [--no-snap]`.
- **`dev-stack/setup-dev-env.sh`:** cada `sudo …` vira `as_root apt-install …`, `as_root docker-group` ou `as_root vscode-repo`. As partes do usuário não mudam.
- **`welcome/stack_installer.py`:** `run_commands` executa os comandos com `env={**os.environ, "LUMEN_ELEVATE": "pkexec"}`.

### 4.5 Policy do polkit

- **Arquivo:** `packaging/templates/dev.lumenos.welcome.policy` é renomeado para `packaging/templates/dev.lumenos.root-helper.policy`.
- **Ação:** `dev.lumenos.root-helper`.
- `org.freedesktop.policykit.exec.path` → `/usr/bin/lumen-root-helper`; `org.freedesktop.policykit.exec.allow_gui` → `true`.
- **Defaults:** `allow_any` = `auth_admin`, `allow_inactive` = `auth_admin`, `allow_active` = `auth_admin_keep`.
- **Textos (PT-BR como padrão, inglês como `xml:lang="en"`):**
  - description: "Executar tarefas administrativas do Linux VDK"
  - message: "É preciso autenticar para instalar pacotes e aplicar ajustes de sistema"

### 4.6 Agente do polkit nas sessões

- **Pacote escolhido:** `hyprpolkitagent` (0.1.3-1, universe, verificado no Ubuntu 26.04.1). É Qt6 (já presente por causa do Calamares), tem cerca de 200 KB e não depende de nenhum ambiente de sessão. Binário: `/usr/libexec/hyprpolkitagent`.
  - Descartados: `lxqt-policykit` (depende de `lxqt-session`), `polkit-kde-agent-1` (puxa o stack do KDE) e `mate-polkit` (GTK3 + `accountsservice`).
- **Hyprland:** acrescentar `exec-once = /usr/libexec/hyprpolkitagent` em `compositor/hyprland/hyprland.conf` e em `packaging/templates/hyprland.conf`.
- **Wayfire:** acrescentar `polkit = /usr/libexec/hyprpolkitagent` na seção `[autostart]` de `compositor/wayfire/wayfire.ini` e de `packaging/templates/wayfire.ini`.

## 5. Fluxo de dados

```
WelcomeWindow ──"Aplicar"──▶ stack_installer.run_commands  (env LUMEN_ELEVATE=pkexec)
                                   │
                     bash setup-dev-env.sh / apply-system-tuning.sh   (usuário comum)
                                   │
                              as_root <ação>
                                   │
            ┌──────────────────────┼───────────────────────┐
         EUID=0            LUMEN_ELEVATE=pkexec          terminal
            │                      │                       │
   lumen-root-helper     pkexec ─▶ polkitd ─▶ hyprpolkitagent (janela de senha)
                                   │                       │
                          /usr/bin/lumen-root-helper   sudo lumen-root-helper
```

O `auth_admin_keep` mantém a autorização em cache por alguns minutos **para o mesmo processo chamador**: as chamadas seguintes de `pkexec` feitas pelo mesmo script não pedem a senha de novo, mas cada etapa (processo bash separado) pede a sua. Confirmado no teste na VM em 2026-11-17: `system-tune` (1ª senha), `apt-install` dos pacotes CLI (2ª senha) e `apt-install neovim` (sem senha, mesmo processo).

## 6. Empacotamento

As alterações são feitas em **`packaging/debian/control` e nos heredocs de `packaging/build-debs.sh`**, mantidos em sincronia, e nos arquivos `packaging/debian/*.install`:

| Pacote | Alteração |
|---|---|
| `lumen-system` | Instala `/usr/bin/lumen-root-helper`, `/usr/share/lumen-os/system/lib/elevate.sh`, `/usr/share/lumen-os/system/root-helper/allowed-packages.list` e `/usr/share/polkit-1/actions/dev.lumenos.root-helper.policy`. Acrescenta `Depends: pkexec, polkitd` |
| `lumen-welcome` | Deixa de instalar a policy. Mantém `Depends: pkexec` |
| `lumen-dev-stack` | Acrescenta `Depends: lumen-system (= 1.0.0-1ubuntu1)`, a mesma versão fixa usada pelas demais dependências internas (no `build-debs.sh`, `(= $VERSION)`) |
| `lumen-compositor` | Acrescenta `Depends: hyprpolkitagent` |

O wrapper `packaging/templates/lumen-system-tune` não muda.

## 7. Tratamento de erros

| Situação | Comportamento |
|---|---|
| Ação ou argumento inválido | Helper sai com `2`, sem efeitos colaterais; mensagem `[root-helper] ERRO: …` |
| Pacote fora da lista permitida | `2`, citando o pacote recusado |
| Helper sem root | `3` |
| Usuário cancela a janela do polkit | `as_root` mostra "Autenticação cancelada. Nada foi alterado." e o script retorna o código diferente de zero; o assistente exibe "Finalizado com avisos/erros." |
| Sem agente do polkit em execução | O `pkexec` falha; a mensagem original é repassada ao log (mitigado pela §4.6) |
| `LUMEN_ELEVATE=pkexec` sem o helper instalado | Mensagem da §4.3, passo 3 |
| Falha no `apt-get` | Código repassado; a saída completa aparece no log do assistente |

## 8. Testes

Os testes entram na suíte E2E existente (`tests/e2e/`), usando `harness.sh` e os mocks de ferramentas de root.

| Tier | Casos |
|---|---|
| 1 | Helper e `elevate.sh` existem, são executáveis/legíveis e têm sintaxe bash válida; a policy é um XML válido com `exec.path` = `/usr/bin/lumen-root-helper`; a `allowed-packages.list` existe e não está vazia |
| 2 | Ação desconhecida → `2`; pacote fora da lista → `2`; nomes maliciosos (`-oAPT::X=1`, `vim;rm -rf /`) → `2`; `apt-install` sem pacotes → `2`; `docker-group` sem `PKEXEC_UID`/`SUDO_USER` → `2`; ação válida sem root e sem dry-run → `3`; o dry-run de `system-tune --no-snap` lista os 3 arquivos de destino esperados |
| 2 | `as_root` com `sudo`/`pkexec` falsos no PATH: o padrão chama o `sudo`; com `LUMEN_ELEVATE=pkexec`, chama `pkexec /usr/bin/lumen-root-helper`; `pkexec` retornando `126` → mensagem "Autenticação cancelada" |
| 3 | Todo pacote passado a `as_root apt-install` nos scripts consta na lista permitida; não sobra nenhum `sudo` cru em `apply-system-tuning.sh` e `setup-dev-env.sh`; os `Depends` de cada pacote são iguais em `control` e `build-debs.sh`; `stack_installer.py` define `LUMEN_ELEVATE=pkexec`; as configs do Hyprland e do Wayfire iniciam o `hyprpolkitagent` |
| 4 | Gera os pacotes e confere via `dpkg-deb -c` que o `lumen-system` contém o helper, o `elevate.sh`, a lista e a policy, e que o `lumen-welcome` não contém mais a policy |

**Teste manual (VM via `scripts/test-iso-qemu.sh`):** abrir o assistente, marcar "Docker" e clicar em "Aplicar". Deve aparecer **uma** janela de senha do polkit e as etapas seguintes não devem pedir a senha de novo. Cancelar a janela deve registrar "Autenticação cancelada" no log.

**Critério de pronto:** suíte E2E 100% aprovada (os 4 tiers atuais sem regressão + os casos novos) e o teste manual na VM aprovado.

## 9. Riscos

- **O cache do `auth_admin_keep` é por processo/sessão do polkit:** se ele não cobrir chamadas sucessivas de `pkexec` vindas de processos bash diferentes, o usuário pode ver mais de uma janela de senha. **Confirmado no teste na VM (2026-11-17): 2 janelas no "Aplicar" padrão, aceito como "uma por etapa".** O agrupamento das ações numa invocação só do helper fica fora de escopo.
- **`hyprpolkitagent` sem `qt6-wayland`:** o pacote do Ubuntu não declara os plugins `wayland-shell-integration`; sem eles o agente aborta ao abrir a janela. Mitigação: `lumen-compositor` depende de `qt6-wayland` (achado no teste na VM).
- **Cancelar a janela devolve 127, não 126:** com o `hyprpolkitagent`, o `pkexec` responde "Not authorized" ao cancelar. Por isso o `as_root` traduz o 127 como "Autenticação cancelada ou negada. Nada foi alterado."
- **Agente sem reinício:** o `exec-once` sobe o agente uma vez só; se ele cair, as janelas de senha param de aparecer até a próxima sessão.
- **`hyprpolkitagent` no Wayfire:** o pacote é voltado ao Hyprland. Por ser Qt6/Wayland comum, deve funcionar, mas é preciso validar no teste manual da sessão Wayfire.

---

## Apêndice A: Decisões já tomadas para o subprojeto 2 (Login no GitHub + Fonte do Terminal)

Registradas aqui para não se perderem. O subprojeto 2 terá spec própria.

- **Escopo:** login no GitHub (`gh`) e fonte do terminal. Identidade git e geração de chave SSH ficaram de fora.
- **Protocolo:** HTTPS, com o `gh` como credential helper (`gh auth login --git-protocol https --web` + `gh auth setup-git`).
- **Fonte:** aplicada **somente no Kitty** (`font_family`/`font_size` no `~/.config/kitty/kitty.conf`), com o pacote da fonte instalado via apt. Opções: JetBrains Mono (padrão), Fira Code, Cascadia Code e Hack; tamanho de 8 a 20, passo 0,5, padrão 11. Corrige de quebra o `kitty.conf` atual, que usa "JetBrainsMono Nerd Font" sem que essa família esteja instalada.
- **UI:** seções "5. FONTE DO TERMINAL (KITTY)" e "6. CONTA DO GITHUB" após a seção 4. A fonte é aplicada pelo "Aplicar"; o login tem **botão próprio** ("Entrar no GitHub"), independente do "Aplicar", mostrando o código de uso único com "Copiar código"/"Abrir navegador" e o estado "Conectado como @usuario".
- **Arquitetura:** módulos sem GTK, `welcome/github_auth.py` e `welcome/terminal_fonts.py`, testáveis isoladamente. A instalação do `gh` usa `as_root apt-install gh` (depende deste subprojeto).
- **Login:** regex do código `[A-Z0-9]{4}-[A-Z0-9]{4}`; envio de `\n` ao stdin + abertura de `https://github.com/login/device`; timeout de 10 min; aviso de "sem conexão" se o código não aparecer em 30 s; dry-run com o código `ABCD-1234` e o usuário `@dry-run`.
- **Textos da UI:** PT-BR informal e amigável, **sem** gírias.
