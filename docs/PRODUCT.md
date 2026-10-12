# Accio Hub — Produto e experiência (PRODUCT)

> **Versão:** 0.3 (alinhamento documental da P0.4; alvo funcional v0.1)<br>
> **Data-base:** 2026-10-11<br>
> **Estado:** P0.4 homologada; P1.0 arquitetural aprovada; P1.1 encerrada e homologada; P1.2 não iniciada<br>
> **Documentos relacionados:** [DESIGN_BASELINE.md](DESIGN_BASELINE.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [ROADMAP.md](ROADMAP.md)

A P1.1 reproduz o shell aprovado em Rails com autenticação local e
personalização fundamental. Os módulos de produto utilizam fixtures sintéticas
e somente de leitura. Este registro não amplia funcionalidades autorizadas;
o transporte funcional segue o [plano P1.0 aprovado](P1.0_ARCHITECTURE_PLAN.md).

## 1. Visão

O **Accio Hub** é uma central pessoal, modular e personalizável para **planejar, executar e registrar atividades**, reunir conhecimento em arquivos Markdown e acompanhar fontes de informação e serviços pessoais em um só lugar.

A identidade aprovada é **Dock + Widgets**, com a sensação de um desktop pessoal e inspiração no **Homarr**. O **Super Productivity** orienta organização e foco; Conhecimento combina a liberdade de arquivos do **Obsidian** com a experiência visual de páginas do **Notion**. A tela inicial organiza widgets com hierarquia visual, conforme a P0.3 no commit `0018bb4` e o [DESIGN_BASELINE.md](DESIGN_BASELINE.md).

**Objetivo principal:** o usuário abre o Accio Hub e consegue, em poucos segundos, identificar prioridades, iniciar uma atividade e consultar o que merece atenção, sem saltar entre diversas aplicações.

### 1.1 Princípios de produto

1. **Personalização real, requisito central:** tema, cor de destaque, fundos, densidade, painéis, ordem/visibilidade dos aplicativos da dock e composição/tamanho dos widgets; preferências persistentes.
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

### 1.3 Estado atual e escopo da P0.4

O protótipo em `prototype/` usa HTML/CSS/JavaScript e localStorage, sem backend.
A P0.3 está **aprovada visualmente**; a P0.4 aprofundará Projetos e Conhecimento
preservando navegação, temas, fontes, personalização, widgets e Accio Music.
A Etapa 1 documental (`1d83387`) e a Etapa 2 de estado (`cd3589d`) foram aprovadas.
A Etapa 3 foi homologada após auditoria (`6c7a719`, `c759e61`).
A Etapa 4 foi aprovada e registrada no commit `e88d772`. A Etapa 5: Biblioteca e
Editor de Conhecimento foi homologada após auditoria e correção do BUG-01,
com registro em commit autorizado; a Etapa 6 depende de nova aprovação.

| Área | Implementação atual do protótipo | Evolução planejada |
|---|---|---|
| Meu espaço | Dock lateral compacta, dock do board, widgets reordenáveis e tamanhos predefinidos | Preservar na P0.4 |
| Aparência | Claro/escuro, destaque, quatro fundos, ordem e visibilidade de widgets/atalhos | Preservar preferências existentes |
| Tarefas | Criar e concluir; lista compartilhada com o widget | Criação/edição contextualizada por projeto na Etapa 4; domínio completo em P2 |
| Projetos | Biblioteca em grade, busca por nome/descrição, filtros, favoritos, ordenação, criar/editar ícone e cor, pausar/ativar e arquivar/restaurar; IDs e vínculos preservados | Espaço interno com Visão Geral, Tarefas, Conhecimento e Referências homologado na Etapa 4 |
| Conhecimento | Pastas/subpastas por ID; Recentes, Favoritos, Capturas e Diário; busca por título/corpo/tags, filtro por projeto; propriedades e Markdown com prévia segura/leitura/autosave | Etapa 5 homologada; Vault real apenas na implementação definitiva |
| Foco | Timer 25/45 minutos, pausa/reinício e contagem por timestamps | Preservar; vínculo e contabilização confiável pertencem à implementação funcional |
| Busca/captura | Ctrl+K busca telas/tarefas e notas por título, conteúdo e tags; Ctrl+Shift+N captura nota | Coleção Capturas integrada à biblioteca e ao widget de notas |
| Accio Music | Barra global opcional e painel expandido; sem áudio | Preservar; rádios e regras de foco em P5 |
| Agenda, Feed, Backups e E-mails | Exemplos visuais ou telas em preparação; sem dados reais conectados | Implementação definitiva nas fases previstas |

**Limites da P0.4:** sem Rails, APIs externas ou armazenamento real em arquivos
Markdown. Organização de pastas e relações será demonstrativa no navegador.
Dados e preferências existentes devem ser preservados por migrações versionadas,
não destrutivas e testáveis quando o modelo mudar. A Etapa 2 introduz schema 1,
IDs estáveis e vínculos por ID para projetos, tarefas e notas, com proteção de
estados incompatíveis e aviso de falhas de gravação. Esses requisitos não
existiam na P0.3 original. A Etapa 3 eleva o schema para 2 e acrescenta propriedades
dos projetos e preferências da biblioteca com cópia recuperável da origem.
A Etapa 4 eleva o schema para 3, com `references` por ID de projeto e backup
recuperável da origem. Notas compartilhadas usam um único registro com `projectIds`;
novas notas/edições recebem datas para ordenação recente. Referências aceitam links
http/https e descrições de materiais, sem upload de arquivos. Notas continuam no
navegador, preparando o futuro Vault.
A Etapa 5 eleva o schema para 4 com `noteFolders`, `folderId`, `tags`, `favorite`,
`collection` e `noteLinks` derivados por ID. Título, corpo e vínculos existentes
são preservados. Diário é uma coleção selecionável, sem criação automática por dia.
Autosave conserva o rascunho na sessão em caso de falha; exibe indicação pendente
ou não persistida e permite retentativa. Prévia e leitura geram apenas elementos
Markdown permitidos, sem interpretar HTML bruto ou buscar imagens externas.
Links externos aceitam somente HTTP/HTTPS sem credenciais. Links `[[Nota]]` com
título único podem navegar por ID; referências ausentes/ambíguas são indicadas.
Não há backlinks/grafo, exclusão de notas ou editor visual rico nesta entrega.

Na biblioteca atual, status são **ativo, pausado e arquivado**. Restaurar retorna
ao status anterior; arquivar preserva tarefas/notas. Favoritos e filtros/ordenação
ficam salvos; a pesquisa vale para a sessão. Atividade recente considera criação,
edição, mudança de status e alterações em tarefas/notas vinculadas. Dados antigos
sem datas aparecem como “Sem atividade registrada”. O widget mostra apenas
projetos ativos e suas tarefas abertas por ID. Modelos, conclusão e visualização
em lista continuam como planejamento funcional futuro, sem implementação nesta etapa.

## 2. Decisões já aprovadas

| ID | Decisão | Situação |
|---|---|---|
| DEC-001 | Tela Hoje com composição modular de widgets (opção B), apresentada como **Dock + Widgets** | Aprovada; visual consolidado na P0.3 |
| DEC-002 | Identidade visual própria, **cores/temas configuráveis** | Aprovada |
| DEC-003 | Conhecimento = **híbrido Obsidian + Notion**, com `.md` reais (opção C) | Aprovada |
| DEC-004 | Projetos = espaços de trabalho com tarefas, notas, foco e referências | Aprovada |
| DEC-005 | Notícias reutilizam o **AccioFeed** já existente | Aprovada |
| DEC-006 | Monitoramento do Ubuntu restrito a estados de backup e falhas; **somente leitura** | Aprovada |
| DEC-007 | Música = **player global na barra superior**, recolhível/expansível, opcional | Aprovada |
| DEC-008 | Player ligado ao Pomodoro; início com **web rádios**; YouTube/Spotify futuros | Aprovada |
| DEC-009 | Plataforma principal = Rails + PWA, com possibilidade de cliente desktop posterior | Direção técnica acordada |
| DEC-010 | ai-memory como inspiração e possível integração futura, **não** repositório primário de notas | Direção arquitetural acordada |
| DEC-011 | P0.3 = baseline visual **Dock + Widgets**, commit `0018bb4`, personalização central | Aprovada visualmente |

## 3. Navegação principal

Dock lateral compacta compartilhada entre telas e dock de aplicativos personalizável no board inicial, adaptadas a telas menores. O recolhimento da navegação continua como requisito funcional planejado para v0.1, com apresentação a validar conforme o baseline; não está implementado na P0.3.

A tabela abaixo descreve os módulos funcionais planejados. Hoje aparece no protótipo como **Início/Meu espaço**; Planejador como **Agenda/Calendário**; **Vault** é o atalho para Conhecimento. Entrada continua prevista, mas não possui acesso próprio na navegação atual. Esses nomes não exigem alterações de interface nesta etapa.

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

### 4.1 Hoje — Meu espaço, Dock + Widgets

**Cabeçalho:** pesquisa global (evolutiva), botão de captura rápida, preferências, indicador resumido do Pomodoro e **barra Accio Music**, se habilitada.

**Layout desktop aprovado:** dock lateral compacta, dock de aplicativos no board e grade responsiva de 12 colunas com largura máxima confortável. **Mobile:** widgets empilhados e dock adaptada. Preservar a hierarquia, os fundos e a tipografia da P0.3.

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

**Configuração v0.1:** preservar a personalização validada no protótipo: visibilidade, ordem por arraste ou botões, tamanhos predefinidos dos widgets, fundos e ordem/visibilidade dos aplicativos da dock. Ocultar atalhos não desativa módulos. **Futuro:** redimensionamento livre e presets por contexto.

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

**Fluxo B — Captura/estudo:** Ctrl+Shift+N ou botão global de captura → anotar informação → salvar no Inbox do Conhecimento → organizar em pasta/projeto → conectar nota a tarefa → agendar bloco de estudo. Ctrl+K abre a busca global.

**Fluxo C — Pesquisa técnica:** abrir projeto → procurar nota Markdown → seguir `[[links]]` → consultar tarefas e tempo ligados à nota → registrar decisão ou solução.

**Fluxo D — Falha de backup:** abrir Hoje → widget informa erro ou atraso com horário → clicar para ver etapa afetada e resumo não sensível → agir fora do Hub no Ubuntu.

**Fluxo E — Notícia útil:** ver artigo do AccioFeed → abrir no leitor original → salvar referência ou criar tarefa de leitura no Hub.

## 6. Personalização e acessibilidade

**Base a preservar:** claro/escuro, cor de destaque, fundos, fontes aprovadas, layout persistido, ordem por arraste/botões, visibilidade e tamanho predefinido dos widgets, ordem/visibilidade da dock e preferência de player global. **Requisitos adicionais v0.1:** tema automático, configuração de fonte/tamanho, densidade e recolhimento da navegação respeitando o baseline. **Depois:** redimensionamento livre, múltiplos layouts (casa/trabalho) e presets. As configurações adicionais não estão implementadas na P0.3.

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

1. Usabilidade da dock compacta e densidade dos novos conteúdos, preservando a composição visual aprovada.
2. Responsividade da ordem/tamanho dos widgets e das novas telas em desktop e no Poco X7 Pro.
3. Adequação do modal de captura existente aos fluxos de Projetos e Conhecimento.
4. Política de conclusão do Pomodoro interrompido e mudança de tarefa no meio da sessão.
5. Biblioteca/Editor: sincronização de alteração externa imediata ou por varredura periódica com botão de atualizar.
6. Preferência inicial de armazenamento do Vault (pasta proposta vs seleção na primeira execução).
7. Exibição do player recolhido: linha mínima ou ícone com popup.

Essas são **questões em aberto**, não decisões já aprovadas. Validar por protótipo e testes reais antes de consolidar.
