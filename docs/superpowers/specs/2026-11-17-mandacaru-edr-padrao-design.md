# Design: Mandacaru (EDR) instalado por padrão

- **Data:** 2026-11-17
- **Status:** Aprovado no brainstorming, aguardando revisão da spec
- **Projeto externo:** [VandyckLN/mandacaru](https://github.com/VandyckLN/mandacaru), um antivírus/EDR em Python com licença GPLv3

## 1. Problema

O Linux VDK não vem com nenhuma proteção contra malware ou ataque em execução. O Mandacaru é um EDR do mesmo autor, focado em ataques gerados ou conduzidos por IA, e já é distribuído como pacote Debian (`mandacaru_0.2.0_all.deb` na release `v0.2.0`). Hoje ele só pode ser instalado à mão, depois que o sistema está pronto.

## 2. Objetivos

- A ISO do Linux VDK traz o Mandacaru instalado, e o `mandacaru.service` sobe **ativo no boot**, tanto na sessão live quanto no sistema instalado pelo Calamares.
- O Mandacaru roda com o coletor **eBPF** (`python3-bpfcc`), que enxerga cada `execve` pelo kernel. Por isso a ISO leva junto os headers do kernel (`linux-headers-generic`).
- O build é reproduzível. O build fixa a versão do Mandacaru e confere a `.deb` baixada por um SHA256 fixado no repositório. Se o checksum não conferir, o build para.
- Atualizar o Mandacaru na distro exige editar um único arquivo.

### Fora de escopo

- Mostrar alertas ou o status do Mandacaru na interface do shell ou do welcome.
- Repositório APT próprio do Mandacaru com atualização automática pelo `apt upgrade`. Ver o §9.
- Alterar a configuração padrão do Mandacaru (`/etc/mandacaru/config.toml`).
- Compilar o Mandacaru a partir do código-fonte.

## 3. Abordagem escolhida

**Baixar a `.deb` da release, com versão e SHA256 fixados.** Ela entra no repositório APT local (`dist/debs`) que o `build-iso.sh` já usa para os pacotes do Lumen, e o metapacote `lumen-desktop` passa a depender dela.

Alternativas descartadas:
- **Submódulo git e build do código-fonte:** exigiria `debhelper`, `dh-python` e `pybuild-plugin-pyproject` no host de build e no CI, e deixaria entrar código sem release.
- **Repositório APT próprio:** resolveria as atualizações, mas exige chave GPG, hospedagem e pipeline de publicação no lado do Mandacaru. Fica para depois.

## 4. O pacote do Mandacaru (v0.2.0, verificado)

| Item | Valor |
|---|---|
| Arquivo | `mandacaru_0.2.0_all.deb` (19.368 bytes) |
| SHA256 | `3942e8e764005c18458c26985c940c7e5c081e4c896e00be18fcf09becbc90bf` |
| Depends | `python3-psutil, python3-tomli \| python3-supported-min (>= 3.11), python3-watchdog, python3-yara, python3:any` |
| Recommends | `python3-bpfcc, logrotate` |
| Serviço | `/usr/lib/systemd/system/mandacaru.service`, com `NoNewPrivileges`, `ProtectSystem=full` e `ProtectHome=read-only` |
| `postinst` | `dh_installsystemd` habilita a unit na primeira instalação e só tenta iniciá-la se existir `/run/systemd/system` |

Todas as dependências existem no Ubuntu 26.04 (Resolute): `python3-yara 4.5.4`, `python3-psutil 7.1.0`, `python3-watchdog 6.0.0` e `python3-bpfcc 0.35.0`.

## 5. Componentes

### 5.1 `packaging/third-party/mandacaru.lock` (novo)

Arquivo `chave=valor` lido pelo shell, com três chaves:

```
MANDACARU_VERSION=0.2.0
MANDACARU_URL=https://github.com/VandyckLN/mandacaru/releases/download/v0.2.0/mandacaru_0.2.0_all.deb
MANDACARU_SHA256=3942e8e764005c18458c26985c940c7e5c081e4c896e00be18fcf09becbc90bf
```

Atualizar o Mandacaru é trocar essas três linhas.

### 5.2 `packaging/fetch-third-party.sh` (novo)

Uso: `fetch-third-party.sh <diretório-de-saída>`.

1. Lê o `.lock`. As variáveis de ambiente `MANDACARU_URL` e `MANDACARU_SHA256` têm precedência, e são o ponto de troca para os testes.
2. Verifica se já existe `dist/cache/mandacaru_<versão>_all.deb` com o hash certo. Se existir, reaproveita o arquivo sem baixar, o que permite rebuild offline. O diretório de cache pode ser trocado por `LUMEN_CACHE_DIR`.
3. Se não existir, baixa com `curl --fail --location --proto '=https,file'` para um arquivo temporário no cache.
4. Confere o SHA256. Se ele conferir, move o arquivo para o nome final no cache e o copia para o diretório de saída. Se não conferir, apaga o temporário e sai com código 1.

Usa `set -euo pipefail`, como os outros scripts de `packaging/`.

### 5.3 `scripts/package-debs.sh`

Chama o `fetch-third-party.sh "$OUTPUT_DIR"` **depois** do `build-debs.sh` e **antes** do `create-local-repo.sh`, para o `mandacaru` entrar no índice `Packages` do repositório local.

### 5.4 Metapacote `lumen-desktop`

No `packaging/debian/control` e no `packaging/build-debs.sh`, que devem continuar iguais (o teste T3_PAIR7 confere isso), o `Depends` ganha:

```
mandacaru (>= 0.2.0), python3-bpfcc
```

O `python3-bpfcc` vira dependência direta, em vez de depender do `Recommends` do Mandacaru, porque o eBPF é requisito da distro.

### 5.5 `scripts/build-iso.sh`

Adiciona `linux-headers-generic` na lista do `apt-get install` do kernel (junto de `linux-generic`). O BCC precisa dos headers do kernel em execução para compilar o programa eBPF.

## 6. Fluxo

1. O `package-debs.sh` gera os pacotes do Lumen, baixa e confere o Mandacaru, e indexa tudo em `dist/debs`.
2. O `build-iso.sh` instala `linux-generic` e `linux-headers-generic` no chroot, monta o `dist/debs` como repositório local e roda `apt-get install -y lumen-desktop`.
3. O APT puxa o `mandacaru`, o `python3-bpfcc` e as outras dependências. O `postinst` do Mandacaru cria o link de habilitação da unit e não tenta iniciá-la, porque o chroot não tem `/run/systemd/system`.
4. No boot da live, o systemd sobe o `mandacaru.service`. O Calamares copia o sistema da live, então o sistema instalado já vem com o serviço habilitado.

## 7. Tratamento de erros

| Situação | Comportamento |
|---|---|
| SHA256 não confere | Sai com código 1 e a mensagem `checksum do mandacaru não confere: esperado <X>, obtido <Y>`. O arquivo baixado é apagado. |
| Sem rede e sem cache válido | O `curl` falha e o script sai com código 1 e a mensagem `não foi possível baixar o mandacaru de <URL>`. Não existe modo "ISO sem EDR". |
| `.lock` ausente ou com chave vazia | Sai com código 1 e diz qual chave falta. |
| eBPF indisponível em execução | O próprio Mandacaru cai para o coletor psutil. A distro não trata esse caso. |

## 8. Testes

Testes E2E novos, todos sem rede (usam `MANDACARU_URL=file://...` com um arquivo falso e o SHA256 dele):

| Tier | Caso |
|---|---|
| 1 | O `.lock` tem `MANDACARU_VERSION`, `MANDACARU_URL` começando com `https://` e `MANDACARU_SHA256` com 64 caracteres hex. |
| 1 | O `fetch-third-party.sh` existe, é executável e tem sintaxe bash válida. |
| 2 | Com o hash certo, a `.deb` é copiada para o diretório de saída e para o cache. |
| 2 | Com o hash errado, o script sai com código 1, mostra a mensagem de checksum e não deixa a `.deb` na saída nem no cache. |
| 2 | Com um cache válido e a URL apontando para um arquivo inexistente, o script reaproveita o cache e conclui com sucesso. |
| 2 | Com a URL inexistente e sem cache, o script sai com código 1 e mostra a mensagem de download. |
| 3 | O `Depends` do `lumen-desktop` tem `mandacaru` e `python3-bpfcc` no `control` e no `build-debs.sh`. |
| 3 | O `package-debs.sh` chama o `fetch-third-party.sh` antes do `create-local-repo.sh`. |
| 3 | O `build-iso.sh` instala o `linux-headers-generic`. |

**Teste manual na VM**, com a ISO nova:
1. `systemctl is-active mandacaru` responde `active` logo depois do boot, sem nenhuma ação.
2. `journalctl -u mandacaru` mostra o coletor eBPF em uso, e não o fallback para psutil.
3. Uma ação suspeita simples gera uma linha em `/var/log/mandacaru/alerts.jsonl`. O caso exato sai dos exemplos do README do Mandacaru.

**Critério de pronto:** suíte E2E 100% aprovada e o teste manual na VM aprovado.

### Resultado do teste manual (2026-11-18)

Feito com a ISO do aviso sonoro (Mandacaru 0.3.0), na VM de 6 GB.

| Item | Resultado |
|---|---|
| 1. Serviço ativo no boot | Aprovado: `systemctl is-active mandacaru` responde `active` sem nenhuma ação. |
| 2. Coletor eBPF | Aprovado: o journal mostra `processos: eBPF (kernel)`, sem fallback para psutil. Do start do serviço até o eBPF pronto levou 13 s. |
| 3. Alerta no `alerts.jsonl` | Aprovado: os 5 alertas do teste (MEDIUM, HIGH ×3 e o EICAR LOW) estão em `/var/log/mandacaru/alerts.jsonl`. |
| Custo na sessão live | O serviço usa ~232 MiB (`MemoryCurrent`). Com o Hyprland aberto, o sistema inteiro fica em ~950 MiB de 5,8 GiB. |

## 9. Riscos

- **Sem atualização no sistema instalado:** como não existe repositório APT online, o Mandacaru instalado só muda com uma nova ISO ou instalação manual. Mitigação futura: repositório APT próprio (a abordagem C).
- **Tamanho da ISO:** o LLVM e o Clang do BCC (~190 MB instalados) mais os headers do kernel aumentam a ISO em algo como 60 a 100 MB comprimidos. Isso foi aceito no brainstorming.
- **Custo na sessão live:** o BCC compila o programa eBPF ao iniciar, o que consome CPU e RAM por alguns segundos no boot. É preciso medir no teste manual.
- **Alertas legíveis só por root:** o serviço grava os logs com `LogsDirectoryMode=0750`, então o usuário comum não lê os alertas sem `sudo`. Isso é aceitável enquanto não houver integração com a interface.
- **Release trocada no GitHub:** se o asset da release for substituído, o SHA256 fixado barra o build. Esse é o comportamento desejado.
