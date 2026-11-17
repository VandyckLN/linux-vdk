# Infra de Testes E2E: Empacotamento da Distro e Pipeline de ISO do Lumen OS

## Filosofia de Testes
- **Orientada a Requisitos e Caixa-Preta**: As asserções dos testes derivam estritamente dos requisitos do usuário em `ORIGINAL_REQUEST.md` (R1-R6) e das interfaces arquiteturais em `PROJECT.md`, tratando os detalhes internos da implementação como uma caixa-preta.
- **Hermética e Não Destrutiva**: Os testes E2E devem rodar em ambientes normais de CI ou de desenvolvimento sem exigir privilégios de root (usando chroot simulado/fixtures ou flags de validação seguras quando apropriado), sem modificar os pacotes do sistema host e sem interferir no workspace de desenvolvimento ativo.
- **Testabilidade Progressiva**: A verificação não deve exigir funcionalidades mais complexas do que a funcionalidade testada. O Tier 1 funciona com os artefatos dos primeiros marcos e com interfaces isoladas.
- **Zero Falhas e Determinística**: A suíte completa deve produzir códigos de saída previsíveis e determinísticos (0 para sucesso, diferente de zero para qualquer falha), com saída de terminal colorida e padronizada e logs legíveis por máquina.

## Inventário de Funcionalidades e Mapeamento de Requisitos
| # | Área Funcional | Origem do Requisito | Escopo Principal de Verificação |
|---|----------------|---------------------|---------------------------------|
| F1 | Empacotamento .deb Modular | R1, Projeto §M1 | Validade das receitas, arquivos control, dependências, sintaxe do script de build, indexação do repositório local |
| F2 | Instalador Calamares e Branding | R2, Projeto §M2 | Sequência do `settings.conf`, tema QSS Curved Glass, branding.desc, slideshow QML, hook de pós-instalação |
| F3 | Pipeline de Geração da ISO | R3, Projeto §M3 | `build-iso.sh` idempotente, parâmetros do debootstrap minbase, manifestos do casper, opções zstd do squashfs, layout GRUB dual UEFI/BIOS, argumentos do xorriso |
| F4 | Automação de CI no GitHub Actions | R4, Projeto §M4 | Sintaxe do `.github/workflows/build-iso.yml`, gatilhos workflow_dispatch, etapas de limpeza de disco, cache, especificação de upload de artefatos |
| F5 | Script e Executor de Testes QEMU | R5, Projeto §M4 | Parsing das flags do `test-iso-qemu.sh` (`--uefi`, `--bios`, `--headless`, `--ram`, `--smp`), fallback de KVM para TCG, localização do firmware OVMF |
| F6 | Guia Prático de Build para o Usuário | R6, Projeto §M4 | Presença do `docs/BUILD_ISO.md`, comandos de pré-requisitos, comandos de build local passo a passo, orientações para WSL2, seção de solução de problemas |

## Arquitetura e Estrutura dos Testes
```
tests/e2e/
├── run-e2e-tests.sh               # Executor mestre unificado dos testes
├── harness.sh                     # Asserções comuns, cores, logs e auxiliares do executor
├── fixtures/                      # Entradas de exemplo, diretórios debian simulados, configs sintéticas
├── tier1_feature_coverage.sh      # Tier 1: Cobertura isolada do caminho feliz (>=5 testes / funcionalidade)
├── tier2_boundary_corner.sh       # Tier 2: Limites, entradas inválidas e tratamento de erros (>=5 testes / funcionalidade)
├── tier3_cross_feature.sh         # Tier 3: Testes de integração entre módulos, par a par
└── tier4_real_world.sh            # Tier 4: Fluxos de ponta a ponta do usuário e cenários realistas
```

## Invocação e Semântica de Sucesso/Falha
- Comando: `bash tests/e2e/run-e2e-tests.sh`
- Flags opcionais:
  - `--tier <1|2|3|4|all>`: Executa um tier específico (padrão: all)
  - `--verbose`: Exibe a saída completa dos subtestes
  - `--quiet`: Saída de resumo mínima
  - `--log <caminho>`: Grava o log de execução dos testes no arquivo indicado
- Código de saída:
  - `0`: Todos os testes passaram
  - `1`: Uma ou mais asserções falharam
  - `2`: Argumento inválido ou falha na preparação do ambiente de testes

## Metodologia de Design dos Casos de Teste
1. **Tier 1 — Cobertura de Funcionalidades (>=5 testes por funcionalidade)**:
   - Valida existência, estrutura, validade sintática, palavras-chave obrigatórias e interfaces operacionais de F1 a F6.
   - Meta: >= 30 casos de teste.
2. **Tier 2 — Casos de Limite e de Canto (>=5 testes por funcionalidade)**:
   - Arquivos de configuração ausentes, sintaxe corrompida, flags inválidas, dependências ausentes, permissões, casos de borda do dry-run.
   - Meta: >= 30 casos de teste.
3. **Tier 3 — Combinações Entre Funcionalidades (Cobertura Par a Par)**:
   - F1 ↔ F2: Binários e arquivos desktop dos pacotes correspondendo ao autostart e aos hooks de pós-instalação do Calamares.
   - F1/F2 ↔ F3: Gerador da ISO consumindo corretamente o repositório APT local e preparando o branding/módulos do Calamares no sistema de arquivos live.
   - F3 ↔ F4: Workflow de CI chamando exatamente os argumentos de build da ISO e as saídas de artefatos esperadas pelo build-iso.sh.
   - F3 ↔ F5: Lançador QEMU validando exatamente o caminho, o formato e as partições de bootloader da ISO gerada pelo xorriso.
   - Meta: >= 6 casos de teste de integração.
4. **Tier 4 — Cenários de Uso Real**:
   - Cenário 1: Simulação do fluxo de build limpo (pipeline em dry-run do estado limpo até o empacotamento e a configuração da ISO).
   - Cenário 2: Geração do repositório offline e validação do grafo de dependências dos pacotes.
   - Cenário 3: Autostart da sessão live do instalador Calamares e dry-run da execução do script de pós-instalação no chroot.
   - Cenário 4: Validação da invocação de VM QEMU headless e da geração da linha de comando.
   - Cenário 5: Verificação do guia de build do usuário (extração e validação de todos os trechos de shell e das verificações de pré-requisitos na documentação).
   - Meta: >= 5 cargas de trabalho realistas.

## Limiares de Cobertura
- **Tier 1**: ≥ 5 testes por funcionalidade (Total ≥ 30)
- **Tier 2**: ≥ 5 testes por funcionalidade (Total ≥ 30)
- **Tier 3**: Cobertura par a par das 6 áreas funcionais principais (Total ≥ 6)
- **Tier 4**: ≥ 5 cenários abrangentes de fluxo do usuário final (Total ≥ 5)
- **Total Mínimo de Testes**: ≥ 71 testes.
