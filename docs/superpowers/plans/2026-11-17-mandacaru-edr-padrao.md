# Mandacaru (EDR) instalado por padrão — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ISO do Linux VDK vem com o Mandacaru instalado, com eBPF e com o `mandacaru.service` ativo no boot.

**Architecture:** Um script novo baixa a `.deb` da release `v0.2.0` do GitHub e confere o SHA256 fixado em `packaging/third-party/mandacaru.lock`. Depois a `.deb` entra no repositório APT local (`dist/debs`). O metapacote `lumen-desktop` passa a depender de `mandacaru` e de `python3-bpfcc`, e o `build-iso.sh` instala também o `linux-headers-generic`.

**Tech Stack:** Bash (`set -euo pipefail`), `curl`, `sha256sum`, empacotamento Debian e a suíte E2E em `tests/e2e/` (bash + harness próprio).

**Spec:** `docs/superpowers/specs/2026-11-17-mandacaru-edr-padrao-design.md`

## Global Constraints

- Versão fixada: `MANDACARU_VERSION=0.2.0`.
- URL: `https://github.com/VandyckLN/mandacaru/releases/download/v0.2.0/mandacaru_0.2.0_all.deb`.
- SHA256: `3942e8e764005c18458c26985c940c7e5c081e4c896e00be18fcf09becbc90bf`.
- `lumen-desktop` ganha `mandacaru (>= 0.2.0), python3-bpfcc` no `Depends`, igual no `packaging/debian/control` e no `packaging/build-debs.sh`.
- O `build-iso.sh` instala `linux-headers-generic` junto com o `linux-generic`.
- Mensagens de erro, exatas:
  - `checksum do mandacaru não confere: esperado <X>, obtido <Y>`;
  - `não foi possível baixar o mandacaru de <URL>`;
  - `chave ausente no mandacaru.lock: <CHAVE>`.
- Todo erro do `fetch-third-party.sh` sai com código 1.
- Os testes não podem usar rede. Eles usam URL `file://` e um `.lock` próprio na sandbox.
- Textos, comentários e mensagens ficam em PT-BR com acentuação correta.

## Review Focus

1. **Cache corrompido ou truncado.** Um `dist/cache/mandacaru_0.2.0_all.deb` com hash errado não pode ser reaproveitado. O script baixa de novo e substitui o arquivo. Teste: T2_F8_05.
2. **Download interrompido.** Um `*.part` que sobrou de uma rodada anterior nunca conta como cache, e é sobrescrito. Teste: T2_F8_06.
3. **`.lock` com fim de linha CRLF.** Valores com `\r` no fim são normalizados, em vez de quebrar a comparação do hash. Teste: T2_F8_07.
4. **`.lock` lido como dado, nunca executado.** O `.lock` não é carregado com `source`. Um valor como `$(touch …)` não roda. Teste: T2_F8_08.
5. **Diretório de saída que ainda não existe.** O script cria o diretório em vez de falhar. Teste: T2_F8_09.

---

### Task 1: `fetch-third-party.sh` e o `.lock`

**Files:**
- Create: `packaging/third-party/mandacaru.lock`
- Create: `packaging/fetch-third-party.sh` (executável)
- Test: `tests/e2e/tier1_feature_coverage.sh` (nova seção F9, antes de `suite_finish`)
- Test: `tests/e2e/tier2_boundary_corner.sh` (nova seção F8, antes de `suite_finish`)

**Interfaces:**
- Produces: `packaging/fetch-third-party.sh <diretório-de-saída>`, que sai com 0 quando dá certo e com 1 em qualquer erro.
- Variáveis de ambiente:
  - `MANDACARU_LOCK`: caminho do `.lock`. O padrão é `<repo>/packaging/third-party/mandacaru.lock`.
  - `MANDACARU_URL` e `MANDACARU_SHA256`: quando definidas, têm precedência sobre o `.lock`.
  - `LUMEN_CACHE_DIR`: diretório de cache. O padrão é `<repo>/dist/cache`.
- Arquivos gerados:
  - cache final: `<cache>/mandacaru_<versão>_all.deb`;
  - temporário: `<cache>/mandacaru_<versão>_all.deb.part`;
  - saída: `<saída>/mandacaru_<versão>_all.deb`.

- [ ] **Step 1: Escrever os testes do tier1 (seção F9)**

Coloque os testes antes de `suite_finish`, com o cabeçalho `# FUNCIONALIDADE F9: Mandacaru (EDR) por padrão`:

```bash
# T1-F9-01
test_case_start "T1_F9_01" "mandacaru.lock fixa versão, URL https e SHA256"
lock="${WORKSPACE_ROOT}/packaging/third-party/mandacaru.lock"
assert_contains "$lock" "^MANDACARU_VERSION=0\.2\.0$" "Versão fixada em 0.2.0"
assert_contains "$lock" "^MANDACARU_URL=https://github\.com/VandyckLN/mandacaru/releases/download/v0\.2\.0/mandacaru_0\.2\.0_all\.deb$" "URL https da release v0.2.0"
assert_contains "$lock" "^MANDACARU_SHA256=[0-9a-f]{64}$" "SHA256 com 64 caracteres hex"
assert_contains "$lock" "^MANDACARU_SHA256=3942e8e764005c18458c26985c940c7e5c081e4c896e00be18fcf09becbc90bf$" "SHA256 da release v0.2.0"
test_case_end

# T1-F9-02
test_case_start "T1_F9_02" "fetch-third-party.sh existe, é executável e tem sintaxe bash válida"
assert_file_executable "${WORKSPACE_ROOT}/packaging/fetch-third-party.sh"
assert_syntax_valid "${WORKSPACE_ROOT}/packaging/fetch-third-party.sh" "sh"
assert_contains "${WORKSPACE_ROOT}/packaging/fetch-third-party.sh" "set -euo pipefail" "Modo estrito obrigatório"
test_case_end
```

- [ ] **Step 2: Escrever os testes do tier2 (seção F8)**

Todos usam a sandbox do tier2 (`$SANDBOX_DIR`), um `.deb` falso e um `.lock` próprio. Coloque este preparo antes dos casos:

```bash
fetch="${WORKSPACE_ROOT}/packaging/fetch-third-party.sh"
fx="${SANDBOX_DIR}/fetch"
mkdir -p "$fx"
printf 'deb falso do mandacaru\n' > "$fx/origem.deb"
fx_sha="$(sha256sum "$fx/origem.deb" | awk '{print $1}')"
write_lock() {  # write_lock <arquivo> <url> <sha>
    printf 'MANDACARU_VERSION=0.2.0\nMANDACARU_URL=%s\nMANDACARU_SHA256=%s\n' "$2" "$3" > "$1"
}
reset_fx() { rm -rf "$fx/cache" "$fx/out"; }
```

Escreva os casos com estes IDs e asserções. Cada caso começa com `reset_fx` e chama o script com `env MANDACARU_LOCK=… LUMEN_CACHE_DIR="$fx/cache" "$fetch" "$fx/out"`.

| ID | Preparo | Asserções |
|---|---|---|
| T2_F8_01 | `.lock` com `file://$fx/origem.deb` e o `$fx_sha` | Sai com 0. Existem `$fx/out/mandacaru_0.2.0_all.deb` e `$fx/cache/mandacaru_0.2.0_all.deb`. O `cmp` com a origem confere. |
| T2_F8_02 | `.lock` com o `sha` errado (64 zeros) | Sai com 1. A saída contém `checksum do mandacaru não confere: esperado 0000…` (com os 64 zeros) e `obtido $fx_sha`. Não sobra `.deb` nem `.part` em `$fx/out` nem em `$fx/cache`. |
| T2_F8_03 | Cache válido copiado antes, e o `.lock` aponta pra `file://$fx/nao-existe.deb` com o `$fx_sha` | Sai com 0, e a `.deb` aparece na saída. |
| T2_F8_04 | `.lock` com `file://$fx/nao-existe.deb`, sem cache | Sai com 1. A saída contém `não foi possível baixar o mandacaru de file://$fx/nao-existe.deb`. |
| T2_F8_05 | Cache com conteúdo `lixo`, e o `.lock` válido | Sai com 0. O cache passa a ser igual à origem (`cmp`). |
| T2_F8_06 | Existe um `$fx/cache/mandacaru_0.2.0_all.deb.part` com `lixo`, e o `.lock` aponta pra um arquivo inexistente | Sai com 1, e a saída contém `não foi possível baixar`, ou seja, o `.part` não foi usado como cache. |
| T2_F8_07 | `.lock` válido convertido pra CRLF (`sed -i 's/$/\r/'`) | Sai com 0, e a `.deb` aparece na saída. |
| T2_F8_08 | `.lock` válido mais a linha `MANDACARU_EXTRA=$(touch $fx/executou)` | Sai com 0, e `$fx/executou` **não** existe. |
| T2_F8_09 | `.lock` válido, e a saída `$fx/out/nova/pasta` não existe | Sai com 0, e a `.deb` aparece em `$fx/out/nova/pasta`. |
| T2_F8_10 | `.lock` sem a linha `MANDACARU_SHA256` | Sai com 1, e a saída contém `chave ausente no mandacaru.lock: MANDACARU_SHA256`. |
| T2_F8_11 | `.lock` com o `sha` errado, mais `MANDACARU_SHA256=$fx_sha` no ambiente | Sai com 0, porque o ambiente tem precedência. |

- [ ] **Step 3: Rodar e confirmar que falha**

Run: `bash tests/e2e/tier1_feature_coverage.sh 2>&1 | grep -E 'T1_F9'; bash tests/e2e/tier2_boundary_corner.sh 2>&1 | grep -E 'T2_F8'`

Expected: todos os T1_F9 e T2_F8 com `[FAIL]`, porque o script e o `.lock` não existem.

- [ ] **Step 4: Criar o `packaging/third-party/mandacaru.lock`**

O arquivo leva um comentário de uma linha em PT-BR explicando que atualizar o Mandacaru é trocar as três chaves, e depois as três linhas dos Global Constraints.

- [ ] **Step 5: Implementar o `packaging/fetch-third-party.sh`**

- Cabeçalho no estilo dos outros scripts de `packaging/`, com `set -euo pipefail`.
- O repositório é resolvido relativo ao próprio script.
- Leia o `.lock` linha a linha com `while IFS='=' read -r chave valor`. Remova o `\r` do fim de cada valor e ignore as linhas vazias e as que começam com `#`. Guarde só as chaves conhecidas. **Não use `source`.**
- Depois de ler o `.lock`, as variáveis de ambiente `MANDACARU_URL` e `MANDACARU_SHA256` sobrescrevem os valores. Se alguma das três chaves continuar vazia, mostre a mensagem de chave ausente e saia com 1.
- Cache:
  1. Se o arquivo final existir e o hash conferir, use ele.
  2. Senão, baixe com `curl --fail --silent --show-error --location --proto '=https,file' -o "<final>.part" "$URL"`. Se o download falhar, mostre a mensagem de download, apague o `.part` e saia com 1.
  3. Confira o hash do `.part`. Se não conferir, mostre a mensagem de checksum, apague o `.part` e saia com 1.
  4. Se conferir, faça `mv` do `.part` pro nome final.
- No fim, rode `mkdir -p` na saída, copie o arquivo do cache pra lá e imprima uma linha de log com a versão e o destino.

- [ ] **Step 6: Rodar e confirmar que passa**

Run: `bash tests/e2e/tier1_feature_coverage.sh 2>&1 | grep -E 'T1_F9|Aprovados'; bash tests/e2e/tier2_boundary_corner.sh 2>&1 | grep -E 'T2_F8|Aprovados'`

Expected: todos os T1_F9 e T2_F8 com `[PASS]`.

- [ ] **Step 7: Conferir o download real uma vez**

Esse passo usa rede e não faz parte da suíte.

Run: `LUMEN_CACHE_DIR=$(mktemp -d) packaging/fetch-third-party.sh "$(mktemp -d)"`

Expected: sai com 0 e o log cita `0.2.0`.

- [ ] **Step 8: Commit**

```bash
git add packaging/third-party/mandacaru.lock packaging/fetch-third-party.sh tests/e2e/tier1_feature_coverage.sh tests/e2e/tier2_boundary_corner.sh
git commit -m "feat(packaging): baixa e confere a .deb do Mandacaru pelo SHA256 fixado"
```

---

### Task 2: Mandacaru no repositório local, no metapacote e na ISO

**Files:**
- Modify: `scripts/package-debs.sh`, a partir da linha 98:
  - passo novo de fetch entre o build e o índice;
  - mensagens renumeradas de `[x/4]` pra `[x/5]`;
  - `mandacaru` adicionado no `EXPECTED_PACKAGES`.
- Modify: `packaging/debian/control:114-119` (o `Depends` do `lumen-desktop`).
- Modify: `packaging/build-debs.sh:254` (o `Depends` do `lumen-desktop`).
- Modify: `scripts/build-iso.sh:183` (a linha do `linux-generic`).
- Modify: `docs/BUILD_ISO.md:33`. A frase dos "6 pacotes" passa a citar que o Mandacaru é baixado da release e conferido pelo SHA256.
- Test: `tests/e2e/tier3_cross_feature.sh`, com os testes novos antes de `suite_finish` e o `need` extra no T3_PAIR7_DEPENDS_SINCRONIZADOS.

**Interfaces:**
- Consumes: `packaging/fetch-third-party.sh <diretório-de-saída>`, da Task 1.

- [ ] **Step 1: Escrever os testes do tier3**

No bloco python do `T3_PAIR7_DEPENDS_SINCRONIZADOS`, junto dos outros `need(...)`, acrescente `need("lumen-desktop", "mandacaru (>= 0.2.0)")` e `need("lumen-desktop", "python3-bpfcc")`.

Depois crie estes casos:

```bash
test_case_start "T3_PAIR8_FETCH_ANTES_DO_INDICE" "package-debs.sh baixa o Mandacaru depois do build e antes do índice"
order_out="$(python3 -I - "${WORKSPACE_ROOT}/scripts/package-debs.sh" <<'PYEOF' 2>&1
import sys
src = open(sys.argv[1], encoding="utf-8").read()
b, f, r = (src.find(x) for x in ("build-debs.sh", "fetch-third-party.sh", "create-local-repo.sh"))
print("ok" if -1 not in (b, f, r) and b < f < r else f"ordem errada: build={b} fetch={f} repo={r}")
PYEOF
)"
assert_eq "ok" "$order_out" "O fetch deve ficar entre o build-debs.sh e o create-local-repo.sh"
assert_contains "${WORKSPACE_ROOT}/scripts/package-debs.sh" '"mandacaru"' "O manifesto deve listar o mandacaru"
test_case_end

test_case_start "T3_PAIR8_ISO_INSTALA_HEADERS" "build-iso.sh instala linux-headers-generic junto do kernel"
assert_contains "${WORKSPACE_ROOT}/scripts/build-iso.sh" "linux-generic linux-headers-generic" "Os headers do kernel são necessários para o eBPF do Mandacaru"
test_case_end
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `bash tests/e2e/tier3_cross_feature.sh 2>&1 | grep -E 'FAIL|->'`

Expected: falham o T3_PAIR7_DEPENDS_SINCRONIZADOS (`lumen-desktop deve depender de mandacaru (>= 0.2.0)`) e os dois casos T3_PAIR8.

- [ ] **Step 3: Implementar**

- **`package-debs.sh`:** chama `"$WORKSPACE_ROOT/packaging/fetch-third-party.sh" "$OUTPUT_DIR"` como passo `[4/5]`, no mesmo estilo de verificação de `-x`/`-f` dos outros passos. O índice vira `[5/5]`.
- **`control` e `build-debs.sh`:** acrescentam `mandacaru (>= 0.2.0), python3-bpfcc` no fim do `Depends` do `lumen-desktop`. No `control`, cada item vai numa linha indentada, como os outros.
- **`build-iso.sh`:** `linux-generic` vira `linux-generic linux-headers-generic`.

- [ ] **Step 4: Rodar a suíte inteira e confirmar que passa**

Run: `bash tests/e2e/run-e2e-tests.sh 2>&1 | grep -E '\[FAIL\]|->|Total de Testes|Status Final'`

Expected: `Status Final: [TODOS OS TIERS PASSARAM]`.

- [ ] **Step 5: Gerar os pacotes de verdade**

Esse passo usa rede.

Run: `./scripts/package-debs.sh --clean 2>&1 | tail -12 && grep -A3 '^Package: mandacaru' dist/debs/Packages && dpkg-deb -f dist/debs/lumen-desktop_*.deb Depends`

Expected:
- o manifesto lista o `mandacaru 0.2.0`;
- o `Packages` tem a stanza `Package: mandacaru`;
- o `Depends` do `lumen-desktop` termina em `mandacaru (>= 0.2.0), python3-bpfcc`.

- [ ] **Step 6: Commit**

```bash
git add scripts/package-debs.sh packaging/debian/control packaging/build-debs.sh scripts/build-iso.sh docs/BUILD_ISO.md tests/e2e/tier3_cross_feature.sh
git commit -m "feat(iso): Mandacaru com eBPF instalado por padrão via lumen-desktop"
```

---

### Task 3: Teste manual na VM e registro na spec

O usuário roda o build da ISO no próprio terminal, porque ele precisa de root. A VM é a `Lumen-OS-Teste` da VirtualBox: 6 GB de RAM, 3D desligado e o Hyprland com `LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=kms_swrast`.

- [ ] **Step 1: Pedir o build ao usuário**

Run (no terminal do usuário): `sudo UBUNTU_MIRROR=https://archive.ubuntu.com/ubuntu ./scripts/build-iso.sh --clean`

Expected: a ISO sai em `dist/` e o `build/iso-work/chroot/var/lib/dpkg/status` tem `Package: mandacaru` com `Status: install ok installed`.

- [ ] **Step 2: Bootar a ISO na VM e checar o serviço**

Copie a ISO pra `D:\VMS\Lumen-OS-Teste\` e boote a VM. Faça login como `lumen` no tty e rode `systemctl is-active mandacaru; systemctl is-enabled mandacaru; journalctl -u mandacaru -b --no-pager | tail -20`.

Expected:
- `active` e `enabled`;
- o journal mostra o coletor eBPF, sem a mensagem de fallback pro psutil.

- [ ] **Step 3: Gerar um alerta**

Siga um exemplo de detecção do README do Mandacaru, por exemplo um script ofuscado executado a partir de `~/Downloads`. Depois rode `sudo tail -3 /var/log/mandacaru/alerts.jsonl`.

Expected: aparece uma linha JSON nova com a detecção.

- [ ] **Step 4: Medir o custo no boot**

Run: `systemd-analyze blame | grep mandacaru; free -h`

Expected: os números ficam anotados pro risco "Custo na sessão live" da spec.

- [ ] **Step 5: Registrar na spec e commitar**

Acrescente na §8 da spec um bloco "Resultado do teste manual (data)" com os resultados dos Steps 2 a 4.

```bash
git add docs/superpowers/specs/2026-11-17-mandacaru-edr-padrao-design.md
git commit -m "docs(spec): resultado do teste do Mandacaru na VM"
```
