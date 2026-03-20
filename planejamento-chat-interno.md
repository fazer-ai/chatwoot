## planejamento chat interno

vamos planejar uma feature de chat interno para o chatwoot

a ideia é implementar chats de texto para os agentes do sistema.

vamos nos inspirar em features comuns de softwares como slack e discord.

será um item na barra lateral. o nome será "Chat Interno"

teremos canais de texto e mensagens diretas.

### canais de texto

- existirão canais públicos e privados
  - canais públicos podem ser vistos por todos os agentes
  - canais privados só podem ser vistos por agentes que foram adicionados por um admin, ou agentes que participam de times associados ao canal
- admins podem criar canais e ver todos os canais
- devem existir categorias para organizar os canais, e cada canal deve pertencer a uma categoria
- todas as contas sempre são criadas com uma categoria padrão "Canais", e um canal "Geral" dentro dessa categoria, que é público
  - Não exibir categorias para um agente que não está em nenhum canal da categoria
  - na hora de criar a categoria/canal padrão, usar o locale da account
  - migration para criar canal default para contas que já existem
- canais devem ter descrição
- "digitando..."
- opção para deletar canal (admin)
- opção para arquivar canal (admin)
  - canais arquivados não aparecem mais na lista, mas podem ser buscados com filtro "archived"
- canais favoritos
- botão de scrollar para última mensagem
- abrir canal na última mensagem não lida
- copiar link para mensagem

### notificações

- criar notificações na caixa de entrada do usuário
- receber notificações para:
  - mensagens diretas
  - mensagens em canais que o usuário participa/públicos
- nas configurações de perfil, opções:
  - notificações para novas mensagens
  - notificações para mentions
  - (habilitadas por padrão)
- opção para silenciar canais específicos
  - ainda recebe notificações @-mentions
  - jogar canais silenciados pro final da categoria

### mensagens

- editar, deletar
- reações
- marcar como não lida
- rich text editor
  - atenção especial para formatação de código-fonte (a ferramenta será muito usada por desenvolvedores de software)
- enviar arquivos
- pinar mensagens
- reply para mensagem cria uma thread
  - opção "also send as direct message"
- referenciar "entidades"
  - `#` -> canais/conversas (separar o popover por seções)
    - Conversas -> renderizar um "balão" com informações da conversa (contato, última mensagem, ações rápidas (resolver, atribuir agente, etc...), etc...)
  - `@` -> agentes
- opção na conversa do Chatwoot: atalho de "forward" para um canal de texto
- @all (somente admins)

### enquetes

- pergunta
- 10 opções de resposta
- opção pode ser texto ou imagem
- campo de emoji separado para diferenciar as opções
- habilitar múltipla escolha
- duração:
  - 24h
  - 7d
  - 14d
  - 30d
- na hora de criar, opção "pinar enquete"
- enquetes com resultados públicos e privados (apenas admin vê)
- permitir remover votos e votar novamente

### dms

- dms individuais (sempre listar todos os agentes para iniciar uma dm)
- dms de "grupo" (selecionar múltiplos agentes para iniciar uma dm de grupo)
- decisão arquitetural muito importante: usar a mesma entidade de banco de dados de canais de texto para DMs?

### rascunhos

- salvar automaticamente mensagens que começaram a ser digitadas (igual já existe para conversas, mas salvando no banco ao invés de só no navegador)
- menu separado para rascunhos, opções: 
  - clicar no rascunho -> levar para o canal/dm onde a mensagem está sendo escrita
  - deletar rascunho
  - mostrar quando tempo atrás o rascunho foi salvo pela última vez

### busca

- usar busca global
- buscar por mensagens, canais, agentes, etc...

### Sistema de integração muito forte com API

- Robôs de chat interno
- API deve ser muito fácil de usar externamente
- Webhooks
