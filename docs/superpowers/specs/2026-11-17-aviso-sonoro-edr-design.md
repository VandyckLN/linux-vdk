# Design: aviso sonoro e popup dos alertas do Mandacaru

- **Data:** 2026-11-17
- **Status:** Aprovado no brainstorming, aguardando revisão da spec
- **Depende de:** Mandacaru v0.3.0 com o socket de alertas (spec em `~/projetos/mandacaru/docs/superpowers/specs/2026-11-17-socket-de-alertas-design.md`) e da spec [Mandacaru instalado por padrão](2026-11-17-mandacaru-edr-padrao-design.md)

## 1. Problema

O Mandacaru já vem ligado na ISO, mas um alerta só aparece no journal e num log que só o root lê. Quem está usando o desktop não fica sabendo de nada na hora. Além disso, a distro não traz stack de áudio (`pipewire`) nem daemon de notificação, então nem um bipe simples sai hoje.

## 2. Objetivos

- Cada alerta do Mandacaru com severidade **MEDIUM ou mais alta** toca um som e mostra um popup na sessão Hyprland do usuário, em poucos segundos.
- O popup diz a severidade, a regra e o resumo. Nos alertas HIGH e CRITICAL, ele fica na tela até ser fechado.
- O aviso funciona na sessão live e no sistema instalado pelo Calamares, sem nenhuma ação do usuário.
- O vigia aguenta o Mandacaru reiniciar, a ausência do socket e linhas inválidas, sem cair e sem encher o log.

### Fora de escopo

- Histórico de alertas, painel no shell ou ações no popup ("ver detalhes", "bloquear").
- Tela de configuração do aviso. A configuração é por JSON.
- Ler o `alerts.jsonl` ou o journal. A única fonte é o socket.

## 3. Componentes

### 3.1 Vigia `shell/edr_notify.py` (novo)

Ponto de entrada: `python3 -m shell.edr_notify`. Interfaces internas, que são o que os testes exercitam:

- `parse_alert(line: bytes) -> dict | None`: devolve o alerta se a linha é um JSON com `v == 1`, `severity` entre as conhecidas (`INFO`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`) e `rule` e `summary` em texto. Se não, devolve `None`.
- `should_notify(alert, min_severity: str) -> bool`: compara as severidades pela ordem acima.
- `notify(alert, sound_enabled: bool, now: float) -> None`:
  - **Som:** com `sound_enabled`, e se o último som foi há mais de **5 s**, roda `pw-play` em segundo plano, sem esperar terminar. Os arquivos são:
    - MEDIUM: `/usr/share/sounds/freedesktop/stereo/dialog-warning.oga`;
    - HIGH e CRITICAL: `/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga`.
  - **Popup:** sempre roda `notify-send --app-name=Mandacaru --urgency=<u> "Mandacaru: <SEVERIDADE>" "<rule>: <summary>"`. A urgência é `normal` para MEDIUM e `critical` para HIGH e CRITICAL.
- `run(socket_path: str, min_severity: str, sound_enabled: bool) -> None`: o laço que conecta no socket, lê linha por linha e chama as funções acima.

**Configuração:** lida pelo `ConfigStore` que já existe, na seção nova do `config/shell.default.json`:

```json
"edr": {
  "socket": "/run/mandacaru/alerts.sock",
  "notify_min_severity": "MEDIUM",
  "sound": true
}
```

Um `notify_min_severity` inválido cai para `MEDIUM`, com um aviso no stderr.

**Lançador:** `packaging/templates/lumen-edr-notify` (novo), igual ao `lumen-shell`. Ele faz `export PYTHONPATH=/usr/share/lumen-os` e `exec /usr/bin/python3 -m shell.edr_notify`. O pacote `lumen-shell` instala esse lançador em `/usr/bin`. O módulo já vai junto com o `cp -r shell/`.

### 3.2 Sessão Hyprland

`packaging/templates/hyprland.conf` e `compositor/hyprland/hyprland.conf` ganham, depois do agente do polkit:

```
# Notificações (popup) e aviso sonoro dos alertas do Mandacaru (EDR)
exec-once = mako
exec-once = /usr/bin/lumen-edr-notify
```

No `compositor/hyprland/hyprland.conf`, que é a cópia de desenvolvimento, o vigia roda como `python3 -m shell.edr_notify`, seguindo o padrão do `shell.main` nesse arquivo.

### 3.3 Pacotes

O `Depends` do `lumen-desktop`, em `packaging/debian/control` e `packaging/build-debs.sh`, que devem continuar iguais (T3_PAIR7):
- troca `mandacaru (>= 0.2.0)` por `mandacaru (>= 0.3.0)`;
- acrescenta `pipewire, pipewire-pulse, wireplumber, mako-notifier, libnotify-bin, sound-theme-freedesktop`.

O `pw-play` vem do `pipewire-bin`, que é dependência do `pipewire`.

### 3.4 Grupo `mandacaru`

- `scripts/build-iso.sh`: o `useradd` do usuário da live passa a usar `-G sudo,video,audio,render,mandacaru`. O grupo já existe nesse ponto, porque o `postinst` do Mandacaru 0.3.0 rodou no `apt-get install -y lumen-desktop`.
- `installer/calamares/modules/users.conf`: `defaultGroups` ganha `mandacaru`.

### 3.5 Mandacaru 0.3.0 no build

`packaging/third-party/mandacaru.lock` passa para `MANDACARU_VERSION=0.3.0`, com a URL e o SHA256 da `.deb` da release `v0.3.0`. Isso só é possível depois que o autor publicar a release. O checksum é conferido baixando a `.deb` publicada.

## 4. Fluxo

1. No boot, o systemd sobe o `mandacaru.service`, que cria o `/run/mandacaru/alerts.sock` (`0660 root:mandacaru`).
2. O usuário entra na sessão Hyprland. O `exec-once` sobe o `mako` e o `lumen-edr-notify`. O PipeWire e o WirePlumber sobem pela sessão `systemd --user`, ativados por socket, como os pacotes do Ubuntu já configuram.
3. O vigia conecta no socket. O Mandacaru detecta algo e envia a linha JSON. O vigia filtra por severidade, toca o som e mostra o popup pelo `mako`.

## 5. Tratamento de erros

| Situação | Comportamento |
|---|---|
| Socket ausente ou conexão recusada | Tenta de novo depois de 2 s e dobra a espera a cada falha, até o teto de 30 s. Na primeira falha da sequência imprime `[edr-notify] aguardando o Mandacaru em <caminho>`, e depois disso fica quieto. Ao conectar, a espera volta a 2 s. |
| `PermissionError` | Imprime `[edr-notify] sem permissão no socket: entre no grupo mandacaru` uma vez e tenta de novo a cada 30 s. |
| Conexão cai (o Mandacaru reiniciou) | Volta ao laço de reconexão. |
| Linha inválida (JSON quebrado, `v` diferente de 1, campo faltando, severidade desconhecida) | Ignorada em silêncio. |
| Linha maior que 64 KiB sem `\n` | O buffer é descartado e a leitura segue a partir da próxima linha. |
| `pw-play` ou `notify-send` ausente ou falhando | Um aviso no stderr na primeira falha de cada um. O outro canal continua funcionando. |
| Rajada de alertas | No máximo 1 som a cada 5 s. Os popups saem todos (o Mandacaru já descarta repetidos em 30 s). |

## 6. Testes

Testes E2E nos tiers que já existem, sem rede e sem root:

| Tier | Caso |
|---|---|
| 1 | `shell/edr_notify.py` compila (já coberto pelo T1_F8_07) e o lançador `lumen-edr-notify` é executável e tem sintaxe bash válida. |
| 1 | O `shell.default.json` tem `edr.socket`, `edr.notify_min_severity = "MEDIUM"` e `edr.sound = true`. |
| 2 | Com um servidor de socket falso (Python, em `$SANDBOX_DIR`) e `pw-play` e `notify-send` falsos no `PATH` que gravam os argumentos num arquivo: um alerta HIGH gera `notify-send --urgency=critical` com `Mandacaru: HIGH` e toca o `alarm-clock-elapsed.oga`. |
| 2 | Um MEDIUM gera `--urgency=normal` e o `dialog-warning.oga`. Um LOW não gera nada. |
| 2 | Com `notify_min_severity = "HIGH"`, o MEDIUM não gera nada. |
| 2 | Dois HIGH em menos de 5 s geram 2 popups e 1 som. |
| 2 | Uma linha de JSON inválido, uma com `v: 2` e uma com severidade desconhecida são ignoradas, e o alerta seguinte ainda é avisado. |
| 2 | O servidor cai e volta no mesmo caminho, e o alerta enviado depois da volta é avisado. |
| 2 | Com `pw-play` ausente do `PATH`, o popup sai mesmo assim. |
| 3 | O `Depends` do `lumen-desktop` tem `mandacaru (>= 0.3.0)` e os seis pacotes da §3.3, no `control` e no `build-debs.sh`. |
| 3 | Os dois `hyprland.conf` sobem o `mako` e o vigia, e o `build-debs.sh` instala o `lumen-edr-notify` em `/usr/bin`. |
| 3 | O `useradd` da live tem o grupo `mandacaru` e o `users.conf` tem `mandacaru` em `defaultGroups`. |
| 3 | O `mandacaru.lock` aponta para a versão `0.3.0`. |

**Teste manual na VM**, com a ISO nova:
1. `ls -l /run/mandacaru/alerts.sock` mostra `srw-rw---- root mandacaru`, e `id` mostra o usuário da live no grupo `mandacaru`.
2. `pgrep -a mako` e `pgrep -af edr_notify` mostram os dois rodando na sessão.
3. Um alerta HIGH forçado (um executável copiado para o `/tmp` e executado de lá) gera o popup vermelho e o alarme no áudio da VM.

**Critério de pronto:** suíte E2E 100% verde e teste manual na VM aprovado.

## 7. Riscos

- **Ordem de entrega:** esta spec só fecha depois que a v0.3.0 do Mandacaru estiver publicada, por causa do lock. Até lá, dá para implementar e testar tudo com o socket falso, deixando o lock para o fim.
- **Tamanho da ISO:** o PipeWire, o WirePlumber e o mako somam algo como 15 a 25 MB instalados. Isso é pouco perto do BCC.
- **Áudio na VM:** o VirtualBox precisa de uma placa de som habilitada (ICH AC97 ou HDA) para o teste manual ouvir o alarme. O popup pode ser validado sem áudio.
- **Sessão sem `systemd --user`:** se o Hyprland for iniciado fora do logind, o PipeWire não sobe e só o som falha. O popup continua saindo.
