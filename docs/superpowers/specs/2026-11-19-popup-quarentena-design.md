# Popup da quarentena do Mandacaru: janela com botões. Design

Data: 2026-11-19. Tamanho: mudança pequena (um módulo novo no shell e um ajuste no vigia).
Depende do Mandacaru 0.4.0 (quarentena; PR VandyckLN/mandacaru#5).

## Intenção

Quando o Mandacaru isola um arquivo, o usuário **sempre** recebe a pergunta: confia, quer analisar ou prefere
manter isolado (apagado em 30 dias). O mako, que desenha os popups da Lumen, não mostra botões, porque as ações
do `notify-send` ficam escondidas. Por isso o popup continua avisando e tocando o som, e o clique nele abre uma
janela GTK com os botões de verdade.

## Objetivos / não-objetivos / anti-objetivos

- **Objetivos:**
  - os três botões do contrato do Mandacaru (spec da quarentena, §10), com o resultado mostrado na própria janela;
  - nenhuma dependência nova: GTK4 e PyGObject já estão na ISO.
- **Não-objetivos:**
  - lista de todos os casos em quarentena (o terminal tem `mandacaru quarentena listar`);
  - botão "Apagar agora";
  - envio do arquivo ao VirusTotal (`--enviar` exige TTY).
- **Anti-objetivos:**
  - uma decisão registrada sem o clique do usuário;
  - a janela travar enquanto o `pkexec` roda;
  - texto do alerta interpretado como markup;
  - várias janelas do mesmo caso.

## Abordagens

1. **Janela GTK própria (escolhida pelo usuário).** O popup do mako continua igual. Quando o clique cai num
   alerta com `quarantine_id`, abre uma janela pequena com os botões. A pergunta fica clara e não depende do mako.
2. Ações do mako com o menu `makoctl menu` + `fuzzel`. Descartada: traz pacote novo, e as opções ficam
   escondidas até o clique, numa lista de texto.
3. Trocar o mako pelo `swaync`. Descartada: troca o daemon de todas as notificações para resolver um caso só.

## Design

**Vigia (`shell/edr_notify.py`):**
- Alerta com `quarantine_id` válido (32 hex minúsculos) muda em três coisas:
  - título `Mandacaru: arquivo isolado (<SEV>)`;
  - ação padrão `--action=default=O que fazer?`;
  - `stdout` capturado.
- Uma thread espera o `notify-send` terminar. Se a saída for `default` (clique), ela abre a janela:
  `python3 -m shell.quarantine_dialog <id> --rule <rule> --summary <summary>`, sempre em lista, sem shell.
- Fechar o popup pelo botão direito (dismiss) ou o popup expirar não abre a janela. Nenhuma decisão é registrada
  e vale o prazo de 30 dias.
- Alerta sem `quarantine_id` continua exatamente como hoje. O som para no clique, como já acontece.

**Janela (`shell/quarantine_dialog.py`, novo):**
- `Gtk.ApplicationWindow` comum, sem layer-shell, com o id de app `io.github.vandyckln.lumen.quarentena`.
- Uma regra no `hyprland.conf` deixa a janela flutuante e centralizada, nos dois arquivos: `compositor/` e
  `packaging/templates/`.
- Uma janela por caso: `flock` em `$XDG_RUNTIME_DIR/lumen-quarentena-<id>.lock`. Se já houver outra janela, sai
  com 0 sem fazer nada.
- Conteúdo:
  - título "Arquivo isolado pelo Mandacaru";
  - regra e resumo em `Gtk.Label` com `set_text` (nunca markup);
  - a frase "Se você não decidir, o arquivo é apagado em 30 dias."
- Botões, e o que cada um executa (`Gio.Subprocess`, assíncrono):
  - **Confio** (avisa "pede senha de administrador"):
    `pkexec /usr/libexec/mandacaru/quarantine-release confiar <id>`;
  - **Analisar**: `pkexec /usr/libexec/mandacaru/quarantine-decide analisar <id> --json`;
  - **Manter isolado**: `pkexec /usr/libexec/mandacaru/quarantine-decide manter <id>`.
- Enquanto um comando roda, os botões ficam desligados e aparece um spinner com "Aguardando…".
- Resultado por código de saída:
  - `0` + confiar: "Arquivo devolvido ao lugar original." e a janela fecha em 3 s. Se o stdout falar em
    `.restaurado-`, a mensagem mostra esse texto.
  - `0` + manter: "Mantido isolado. Será apagado em 30 dias." e a janela fecha em 3 s.
  - `0` + analisar: lê a linha JSON e mostra o veredito e o `summary`. Os botões passam a ser só **Confio** e
    **Manter isolado**.
    - `malicioso`: "Malicioso. Recomendado manter isolado." (destaque vermelho, classe CSS);
    - `legitimo_conhecido`: "Arquivo legítimo conhecido (provável falso positivo).";
    - `desconhecido`: "Desconhecido. Nenhuma base conhece este arquivo.";
    - JSON inválido: tratado como erro.
  - `3`: "Este caso não existe mais ou já foi resolvido." Botões desligados.
  - `4`: "A quarentena foi adulterada. O arquivo não foi devolvido." Botões desligados.
  - `126`/`127`: "Autenticação cancelada." Botões religados, dá para tentar de novo.
  - outros: "Falhou (código N)", com a última linha do stderr. Botões religados.
  - `pkexec` ausente (`GLib.Error` ao iniciar): mensagem de erro com o comando de terminal equivalente.
- Fechar a janela sem clicar não registra nada. Fechar durante um comando não cancela o comando, que já está no
  auxiliar root e registra a própria decisão.

**Empacotamento:**
- `shell/` já é copiado inteiro para `lumen-shell`.
- `Depends` do metapacote passa a `mandacaru (>= 0.4.0)`.
- `packaging/third-party/mandacaru.lock` vai para a 0.4.0 depois da release (URL + SHA256).

**Testes:**
- No estilo do tier 2 (harness com `notify-send` falso):
  - alerta com id + clique abre a janela, ou seja, chama o comando da janela com os argumentos certos;
  - dismiss não abre;
  - id inválido cai no popup comum.
- Para a janela, a lógica fica separada da UI numa função pura `outcome(action, rc, stdout, stderr)`, que diz a
  mensagem, os botões e se fecha. Ela é testada em todos os códigos.
- Teste da trava de instância única.
- Na VM: alerta real, clique, os três botões.

## Calls minhas (pra conferir)

- O "Analisar" usa `--json`: o auxiliar aceita, e a janela precisa do veredito estruturado. O §10 escreve
  `analisar <id>` sem a flag.
- O texto do botão do popup fica "O que fazer?". O mako não mostra esse texto, mas outros daemons mostram.
- Sem botão "Apagar agora" (o spec do Mandacaru lista `apagar`, mas não no popup).
- A janela fecha sozinha 3 s depois de Confio/Manter darem certo.
- Os commits desta distro passam a usar o e-mail noreply do GitHub (config local do repositório).
