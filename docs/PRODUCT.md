# Accio Hub — Produto e experiência (PRODUCT)

> **Versão:** 0.1 (especificação inicial)  
> **Data-base:** 2026-10-09  
> **Estado:** rascunho para validação; decisões aprovadas e hipóteses estão identificadas  
> **Documentos relacionados:** [ARCHITECTURE.md](ARCHITECTURE.md) · [ROADMAP.md](ROADMAP.md)

## 1. Visão

O **Accio Hub** é uma central pessoal, modular e personalizável para **planejar, executar e registrar atividades**, reunir conhecimento em arquivos Markdown e acompanhar fontes de informação e serviços pessoais em um só lugar.

A referência de experiência é o **Super Productivity** para organização e foco; o módulo de conhecimento combina a liberdade de arquivos do **Obsidian** com a experiência visual de páginas do **Notion**; a tela inicial é um **dashboard modular**, não uma lista de tarefas ampliada.

**Objetivo principal:** o usuário abre o Accio Hub e consegue, em poucos segundos, identificar prioridades, iniciar uma atividade e consultar o que merece atenção, sem saltar entre diversas aplicações.

### 1.1 Princípios de produto

1. **Personalização real:** tema, cor de destaque, densidade, painéis e composição dos widgets; preferências persistentes.
2. **Arquivos sob controle do usuário:** notas como `.md` reais em um Vault configurável, acessível também por Obsidian/VS Code.
3. **Integração sem aprisionamento:** tarefas, notas, projetos e temporizador funcionam sem AccioFeed, Gmail, GitHub ou IA.
4. **Informação confiável:** cada integração exibe última atualização, estado de conexão e origem dos dados; não confundir *última execução bem-sucedida* com *saúde atual*.
5. **Segurança por padrão:** monitoramento do Ubuntu apenas informativo; nenhuma execução administrativa pela interface no MVP.
6. **Incremental e utilizável:** liberar uma versão pequena, completa e testável antes de adicionar integrações complexas.
7. **Baixa fricção:** captura e conclusão rápida de tarefas, edição confortável e navegação sem perda de contexto.

### 1.2 Escopo de uso

- **Primeiro ambiente:** desktop Ubuntu do usuário; aplicação pessoal hospedada localmente.
- **Evolução:** acesso autenticado via Tailscale do Windows do trabalho e do celular, desde que o Ubuntu esteja ligado.
- **Modelo de distribuição aprovado:** aplicação **Rails + PWA**, com interface semelhante a um programa em navegadores que suportam instalação; não haverá aplicativo Tauri no MVP.
- **Usuário do MVP:** uma pessoa. Múltiplos usuários, espaços de trabalho e permissões colaborativas ficam para depois.

## 2. Decisões já aprovadas

| ID | Decisão | Situação |
|---|---|---|
| DEC-001 | Tela Hoje = **dashboard modular** (opção B) | Aprovada |
| DEC-002 | Identidade visual própria, **cores/temas configuráveis** | Aprovada |
| DEC-003 | Conhecimento = **híbrido Obsidian + Notion**, com `.md` reais (opção C) | Aprovada |
| DEC-004 | Projetos = espaços de trabalho com tarefas, notas, foco e referências | Aprovada |
| DEC-005 | Notícias reutilizam o **AccioFeed** já existente | Aprovada |
| DEC-006 | Monitoramento do Ubuntu restrito a estados de backup e falhas; **somente leitura** | Aprovada |
| DEC-007 | Música = **player global na barra superior**, recolhível/expansível, opcional | Aprovada |
| DEC-008 | Player ligado ao Pomodoro; início com **web rádios**; YouTube/Spotify futuros | Aprovada |
| DEC-009 | Plataforma principal = Rails + PWA, com possibilidade de cliente desktop posterior | Direção técnica acordada |
| DEC-010 | ai-memory como inspiração e possível integração futura, **não** repositório primário de notas | Direção arquitetural acordada |

## 3. Navegação principal

Menu lateral recolhível, persistente no desktop e adaptado para navegação móvel:

| Grupo | Tela | Propósito | Entrega |
|---|---|---|---|
| Produtividade | **Hoje** | Visão do dia com widgets personalizáveis | v0.1 |
| Produtividade | **Entrada** | Captura rápida sem exigir categorização | v0.1 |
| Produtividade | **Tarefas** | Listar, priorizar, agendar, concluir e recorrer | v0.1 |
| Produtividade | **Planejador** | Calendário próprio, agenda e blocos de tempo | v0.1 |
| Produtividade | **Foco** | Pomodoro, cronômetro livre e histórico | v0.1 |
| Organização | **Projetos** | Espaços de trabalho e relações entre módulos | v0.1 |
| Organização | **Conhecimento** | Vault, Markdown, notas, tags e pesquisa | v0.1 |
| Informações | **AccioFeed** | Notícias de fontes previamente configuradas | v0.2 |
| Informações | **Backups** | Situação local/nuvem, histórico e avisos | v0.2 |
| Informações | **E-mails** | Resumo, prioridades e links para Gmail | Pós-MVP |
| Sistema | **Configurações** | Temas, widgets, atalhos, permissões e integrações | v0.1 |

**Regra:** módulo não implementado ou não configurado não se apresenta como funcional. Preferir indicador explícito “não configurado” a cards com números fictícios.

## 4. Telas e comportamentos

### 4.1 Hoje — dashboard modular

**Cabeçalho:** pesquisa global (evolutiva), botão de captura rápida, preferências, indicador resumido do Pomodoro e **barra Accio Music**, se habilitada.

**Layout desktop:** menu lateral + grade responsiva de até 12 colunas e largura máxima de conteúdo confortável. **Mobile:** widgets empilhados, ações acessíveis, menu compacto.

**Widgets planejados:**

| Widget | Resumo | Ações no próprio card |
|---|---|---|
| Minhas tarefas | Hoje, atrasadas, prioridades | Criar, concluir, abrir detalhes, iniciar foco |
| Pomodoro | Tempo restante, tarefa selecionada | Iniciar, pausar, continuar, encerrar |
| Minha agenda | Próximos compromissos e blocos | Abrir evento/calendário |
| Notas recentes | Últimas notas e capturas | Abrir ou capturar nota |
| Meus projetos | Favoritos e pendências | Abrir projeto |
| AccioFeed | Manchetes filtradas, hora de sincronização | Abrir notícia; ações extras se API suportar |
| Backups | Estado separado de backup local e cloud | Ver causa e histórico |
| E-mails | Quantidade e resumo de prioridades | Abrir Gmail (futuro) |

**Configuração v0.1:** ativar/ocultar widgets disponíveis, alterar ordem, escolher entre tamanhos predefinidos e salvar preferências. **Futuro:** drag-and-drop, redimensionamento livre, presets por contexto.

**Estados obrigatórios por widget:** carregando, vazio, normal, erro, sem configuração e dado desatualizado. Uma integração falha não pode derrubar a página.

### 4.2 Entrada e Tarefas

**Entrada:** registrar ideia, link ou tarefa de forma imediata, sem projeto/data obrigatórios; processar depois para tarefa organizada, nota ou descarte confirmado.

**Tarefas:** filtros Hoje / Próximas / Todas / Concluídas; agrupamento por atraso, dia e projeto; lista como modo inicial; Kanban posterior.

**Campos da tarefa:** ID estável, título obrigatório, descrição opcional, status, prioridade, projeto opcional, data planejada, prazo final, horário/blocos de tempo, estimativa, tags, subtarefas, recorrência e notas vinculadas.

**Painel lateral reutilizável:** editar propriedades, subtarefas, relações, tempo realizado e iniciar foco sem perder a tela de origem.

**Regras:** uma tarefa existe sem projeto ou data; calendário e projeto são *visões da mesma tarefa*, nunca cópias. Conclusões de recorrências são por ocorrência, sem concluir automaticamente outras datas.

### 4.3 Planejador

Três visualizações: **dia, semana e mês**. A semana é sugestão de padrão, configurável.

- **Evento:** compromisso com início/fim.
- **Tarefa:** algo a realizar, que pode ter data planejada e prazo distintos.
- **Bloco de tempo:** intervalo reservado para uma tarefa, que não a converte em evento.
- **MVP:** criar/editar por formulário, navegar pela agenda, ver conflitos e tarefas sem agendamento.
- **Futuro:** arrastar/redimensionar blocos, Google Calendar, sincronização bidirecional com política anti-duplicatas.

### 4.4 Foco — Pomodoro e tempo

- **Padrões sugeridos:** foco 25 min, pausa curta 5 min, longa 15 min após 4 ciclos; tudo configurável.
- **Sessão única por usuário**, acessível de Hoje, Projeto, Tarefa e Foco.
- Associar opcionalmente a tarefa e projeto; permitir sessão livre.
- Controles: iniciar, pausar, retomar, finalizar, confirmar tempo contabilizado; histórico por dia/projeto/tarefa.
- Timer reconstruído por registros de horários, não apenas `setInterval`; se houver fechamento, suspensão ou perda de conexão, reconciliar sessão com confirmação quando necessário.
- Notificações com consentimento; sem garantias de execução quando o navegador/PC estiver fechado.
- Inatividade não deve ser contada automaticamente como trabalho válido.

### 4.5 Projetos — espaços de trabalho

**Biblioteca:** cards ou lista, status ativo/pausado/concluído/arquivado, favoritos, busca, ícone, cor e modelos (desenvolvimento, estudo, pessoal, em branco).

**Detalhe do projeto:** Visão Geral / Tarefas / Conhecimento / Planejamento / Tempo / Referências. O dashboard do projeto exibe subconjunto configurável de widgets.

**Relações:** nota Markdown pode ser vinculada ao projeto sem estar fisicamente dentro da pasta do projeto; renomear projeto não quebra a relação. Arquivar não apaga notas ou tarefas. Apagar definitivamente requer fluxo separado e confirmação.

### 4.6 Conhecimento — Accio Knowledge

**Modelo híbrido confirmado:** árvore de pastas e páginas/subpáginas na interface, mapeada a arquivos `.md` reais no Vault.

**Subtelas/áreas:**

- **Minha biblioteca:** Recentes, Favoritos, Capturas, Diário, Projetos, Estudos, pastas e pesquisa.
- **Editor:** painel da biblioteca, editor central e painel opcional de links/tarefas/propriedades, todos ajustáveis ou recolhíveis.
- **Modos:** Markdown + pré-visualização e leitura no MVP; editor visual rico, com preservação fiel de Markdown, em evolução posterior.
- **Notas:** criar, editar, mover, renomear, arquivar/excluir com confirmação; tags, favoritos, links `[[Nota]]`, backlinks básicos, templates simples e diário diário opcional.
- **Captura rápida:** salvar imediatamente no Inbox de notas; organizar depois.
- **Pesquisa:** títulos, tags e conteúdo via índice textual local.
- **Integração:** vincular notas a projetos e tarefas; criar uma tarefa a partir de uma nota/seleção, sem duplicar o conteúdo da nota.
- **Interoperabilidade:** arquivos abertos/editados por Obsidian/VS Code devem reaparecer no índice, sem sobrescrita silenciosa.

**Não fazer no MVP:** grafo visual completo, resumos automáticos, embeddings, reescrita autônoma, paridade completa com Notion.

### 4.7 Accio Music — player global

**Apresentações aprovadas:** barra superior como padrão; recolhido; expandido (estações, favoritos, preferências). O player continua montado ao navegar entre telas, evitando reiniciar a reprodução desnecessariamente.

**Fontes v0.1:** web rádios/streams compatíveis com o navegador; favoritos e volume. Arquivos locais como evolução condicionada a permissões e UX. **Depois:** YouTube via player oficial visível; Spotify via embed/SDK conforme requisitos e políticas vigentes.

**Comportamentos configuráveis com Pomodoro:** iniciar música ao começar foco *após interação autorizada*; pausar/reduzir volume no intervalo; restaurar estado ao retomar; permitir opt-out por projeto ou globalmente.

**Restrições:** navegador pode bloquear autoplay; a barra não significa extração de áudio do YouTube nem reprodução Spotify irrestrita. Som toca no dispositivo em uso; sincronizar áudio entre dispositivos não faz parte do MVP.

### 4.8 AccioFeed e Backups

**AccioFeed (v0.2):** consumidor de dados do aplicativo existente (Next.js + FastAPI + PostgreSQL). Exibir artigos recentes, categorias/fontes e estado de atualização; abrir a leitura no AccioFeed; permitir criar tarefa a partir de artigo. Favoritar e ler depois exigem validar contratos reais de API, autenticação e CORS. **Não duplicar o catálogo de artigos no Accio Hub.**

**Backups (v0.2):** estados separados para **backup local**, **backup de agentes**, **envio Restic ao Google Drive** e **manutenção/verificação**, quando houver telemetria disponível. Mostrar última tentativa, último sucesso, próxima execução, idade da informação e erro resumido. Estados: saudável / executando / falha / atrasado / desconhecido / não configurado. A interface **não** terá ações para executar, apagar ou restaurar backups.

### 4.9 E-mails (pós-MVP)

Gmail inicialmente em modo leitura, com resumo de mensagens, filtros por importância/remetente, link para origem e ação de converter e-mail em tarefa. Exigir OAuth e mínimo escopo de autorização. Não recriar um cliente de e-mail completo.

## 5. Fluxos principais do usuário

**Fluxo A — Dia produtivo:** abrir Hoje → ver prioridades → iniciar foco de uma tarefa → player opcional reproduz rádio → fazer anotação relacionada → concluir foco e, se desejado, concluir tarefa.

**Fluxo B — Captura/estudo:** Ctrl+K ou botão global de captura → anotar informação → salvar no Inbox do Conhecimento → organizar em pasta/projeto → conectar nota a tarefa → agendar bloco de estudo.

**Fluxo C — Pesquisa técnica:** abrir projeto → procurar nota Markdown → seguir `[[links]]` → consultar tarefas e tempo ligados à nota → registrar decisão ou solução.

**Fluxo D — Falha de backup:** abrir Hoje → widget informa erro ou atraso com horário → clicar para ver etapa afetada e resumo não sensível → agir fora do Hub no Ubuntu.

**Fluxo E — Notícia útil:** ver artigo do AccioFeed → abrir no leitor original → salvar referência ou criar tarefa de leitura no Hub.

## 6. Personalização e acessibilidade

**v0.1:** tema claro/escuro/automático; cor de destaque, fonte/tamanho, densidade; menu recolhível; layout persistido; ordem/visibilidade/tamanho dos widgets; preferência de player; atalhos documentados. **Depois:** drag-and-drop, múltiplos layouts (casa/trabalho), presets e reordenação avançada.

**Qualidade UX:** navegação por teclado, foco visível, contraste adequado, textos legíveis em monitor 27”, responsividade no celular, ausência de flashes/animacões excessivas, horários no fuso do usuário, labels acessíveis e suporte a movimento reduzido.

## 7. O que é MVP e o que não é

**v0.1 = núcleo de produtividade utilizável:** shell navegável, autenticação pessoal, Hoje configurável, Entrada/Tarefas, Projetos, calendário básico, Pomodoro persistente, Vault Markdown básico (editor + busca + links simples), Accio Music (rádios + integração opcional ao foco), preferências e exportação/backup inicial. Não depende de serviços externos.

**v0.2 = HUB informativo real:** integração AccioFeed, status de backups locais/nuvem, detalhes de falhas e notícias como origem de tarefas.

**Pós-MVP:** Gmail, Google Calendar, GitHub enriquecido, Spotify/YouTube, editor visual avançado, busca semântica, gráfico de conhecimento, integração com ai-memory, layouts por espaço, mobile offline independente.

> A versão **v0.1 é o primeiro MVP funcional**, não uma única sprint. O [ROADMAP.md](ROADMAP.md) fragmenta esse escopo em entregas menores verificáveis.

## 8. Critérios globais de sucesso

- Usuário consegue criar/concluir tarefa, iniciar foco, criar/recuperar nota `.md` e personalizar a tela Hoje sem ajuda técnica.
- Informação cadastrada uma vez se reflete nas visões pertinentes.
- Notas persistem como arquivos Markdown portáveis, sem perda silenciosa ao editar por outro programa.
- Uma integração fora do ar não impede produtividade local.
- Player não reinicia involuntariamente em navegação normal; rádio não toca sem autorização.
- Falhas de backup não são maquiadas como sucesso e incluem indicação temporal.
- Dados sensíveis não aparecem em logs/UI indevidos; não há ações administrativas do Ubuntu via interface.
- Existe procedimento documentado para backup **e restauração testável** de Vault + SQLite.

## 9. Questões a validar no protótipo

1. Largura do menu lateral e densidade ideal dos widgets no monitor principal.
2. Ordem padrão dos widgets em desktop e no Poco X7 Pro.
3. Melhor UX de captura rápida: modal simples, painel lateral ou comando global.
4. Política de conclusão do Pomodoro interrompido e mudança de tarefa no meio da sessão.
5. Biblioteca/Editor: sincronização de alteração externa imediata ou por varredura periódica com botão de atualizar.
6. Preferência inicial de armazenamento do Vault (pasta proposta vs seleção na primeira execução).
7. Exibição do player recolhido: linha mínima ou ícone com popup.

Essas são **questões em aberto**, não decisões já aprovadas. Validar por protótipo e testes reais antes de consolidar.
