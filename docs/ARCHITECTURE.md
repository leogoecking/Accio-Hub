# Accio Hub — Arquitetura (ARCHITECTURE)

> **Versão:** 0.3 (protótipo atual e arquitetura definitiva planejada)<br>
> **Data-base:** 2026-10-11<br>
> **Estado:** P0.4 homologada; P1.0 aprovada; P1.1 encerrada e homologada; P1.2 não iniciada<br>
> **Documentos relacionados:** [DESIGN_BASELINE.md](DESIGN_BASELINE.md) · [PRODUCT.md](PRODUCT.md) · [ROADMAP.md](ROADMAP.md)

## Fundação homologada — P1.1

O [plano arquitetural P1.0](P1.0_ARCHITECTURE_PLAN.md) foi aprovado em 2026-10-11.
Ele rege a evolução incremental P1.1–P1.5 e prevalece sobre os desenhos futuros
das seções seguintes quando houver divergência de etapa ou tecnologia.

A fundação está em `rails/`: Rails 8.1.3.1, Ruby 3.3.6, SQLite, ERB,
Turbo Drive, Stimulus, Importmap e Propshaft. O CSS homologado é preservado;
Tailwind e Solid Queue não são adicionados nesta etapa. Fontes são locais.

Somente `User` e `AuthSession` persistem no SQLite. A conta única é criada
localmente, sem cadastro público; segredo e bancos são ignorados pelo Git.
O launcher/Puma usam loopback, com middleware que também rejeita pares remotos.
`bin/rails admin:reset` permite recuperação local interativa, sem endpoint HTTP,
com validações de senha e revogação transacional das sessões.
`Studio` normaliza preferências limitadas em cookie criptografado e compõe
fixtures estáticas de leitura. Não há importação de localStorage, modelos de
produto, timer funcional ou Vault. Personalização transacional será P1.2.

O protótipo em `prototype/` permanece intacto. Interfaces e comportamentos de
produto ainda não transportados são explicitamente demonstrativos. Estrutura,
execução e limites em [../rails/README.md](../rails/README.md); evidências em
[P1.1_FOUNDATION_VERIFICATION.md](P1.1_FOUNDATION_VERIFICATION.md).

## 0. Arquitetura atual do protótipo e limites da P0.4

O código executável atual está em `prototype/`. A baseline visual aprovada é
P0.3, commit `0018bb4`; sua identidade é definida em
[DESIGN_BASELINE.md](DESIGN_BASELINE.md). As seções 1–13 descrevem a implementação
definitiva planejada, não infraestrutura já instalada neste checkout.

| Arquivo | Responsabilidade atual |
|---|---|
| `prototype/index.html` | Entrada HTML, fontes, CSS e script de módulo |
| `prototype/style.css` | Tokens, claro/escuro, fundos, docks, widgets e breakpoints |
| `prototype/app.js` | Estado compartilhado, templates HTML, eventos e navegação por hash |
| `prototype/state.mjs` | Validação, migração pura, IDs e adapter de persistência local |
| `prototype/projects.mjs` | Regras de projetos, validação, busca/ordenação, status, atividade e contagens por ID |
| `prototype/project-library.mjs` | Biblioteca, formulário, feedback, preferências e gestão de foco/teclado |
| `prototype/project-space.mjs` | Rotas por ID, seleção contextual, tarefas/notas/referências e composição de widgets |
| `prototype/project-space-view.mjs` | Quatro abas, formulários contextuais, compartilhamento e gestão de foco/teclado |
| `prototype/knowledge.mjs` | Pastas e notas por ID, propriedades, busca, coleções, vínculos derivados e validação |
| `prototype/markdown.mjs` | Subconjunto Markdown seguro por lista de permissões; HTML bruto escapado |
| `prototype/knowledge-view.mjs` | Biblioteca/editor/leitura, painéis, autosave e foco/teclado |

**Fluxo atual:** evento de interface → alteração de `state` → `persist()` no
localStorage → `render()`. A renderização recria o shell, incluindo a barra
Accio Music; o estado é compartilhado entre telas, mas não há componente de
áudio persistente. Os únicos recursos remotos carregados pela entrada atual são
fontes Google Fonts, com fallbacks no CSS; não há integração de dados com APIs.

**Persistência atual:** chave `accio-hub-p0.3-studio`, contendo tarefas, notas,
layout e preferências, agora com `schemaVersion: 4`. A chave `accio-hub-p0-v1`
permanece intacta; suas coleções são importadas somente quando ausentes na P0.3.
Projetos são persistidos com IDs; tarefas usam `projectId` e notas `projectIds`.
IDs numéricos legados são mantidos, novos registros recebem UUIDs, e nome/título
não definem identidade. `Pessoal` significa ausência de projeto (salvo projeto
explícito com esse nome). A seleção usa `projectId`/`noteId`.

A migração valida antes de gravar e conserva o JSON original em uma chave
`accio-hub-p0.3-studio:backup:pre-schema-4` (com sufixo único se já houver outra
cópia). Sem backup confirmado, o formato antigo não é substituído. JSON inválido,
schema desconhecido/futuro e estruturas incompatíveis bloqueiam gravações;
os dados existentes permanecem intactos. Falhas de gravação são visíveis e podem
ser tentadas novamente; alterações ficam somente em memória até sucesso.
Uma alteração externa detectada na chave bloqueia a sessão antiga.
Cópias `pre-schema-1`, `pre-schema-2` e `pre-schema-3` das etapas anteriores permanecem intactas. A migração de schema 1
valida e copia seus dados, conservando IDs, conteúdo e campos extras. Projetos
recebem `status`, `favorite`, `color`, `createdAt`, `updatedAt` e `archivedFrom`;
o estado recebe `projectLibrary: {status, sort, favoritesOnly}`. Cores legadas
continuam em `tint` com `color: null`; datas antigas não são inventadas.

Detalhes históricos da preparação e recuperação em
[P0.4_STATE_VERIFICATION.md](P0.4_STATE_VERIFICATION.md); evolução e evidências
da Biblioteca em [P0.4_PROJECTS_VERIFICATION.md](P0.4_PROJECTS_VERIFICATION.md);
espaço interno em [P0.4_PROJECT_SPACE_VERIFICATION.md](P0.4_PROJECT_SPACE_VERIFICATION.md).

**Contrato para a evolução da P0.4:**

- Preservar dados e preferências existentes; não reinicializar o estado como
  estratégia de atualização.
- Quando houver mudança de schema, usar versão explícita e migrações não
  destrutivas, testáveis e seguras para reaplicação. Validar antes de substituir
  o estado salvo e preservar a origem diante de falha.
- Preservar IDs existentes das notas ou manter mapeamento explícito se uma
  conversão for necessária; atribuir IDs estáveis aos projetos. Nome, título e
  caminho não definem identidade.
- Relações por ID devem sobreviver a renomeação e permitir associar nota a
  projeto independentemente da pasta. Arquivar projeto preserva seus dados.
- Separar apenas responsabilidades necessárias, reutilizando componentes,
  tokens e shell existentes; evitar refatoração ampla.

Biblioteca, propriedades e pastas do Conhecimento continuarão simuladas no
navegador. A P0.4 não inicia Rails, não conecta APIs externas e não escreve
arquivos Markdown reais. Accio Music permanece global, opcional e visual.
Etapas 1 (`1d83387`), 2 (`cd3589d`) e 3 (`6c7a719`, `c759e61`) homologadas;
Etapa 4 homologada no commit `e88d772`;
Etapa 5 homologada após auditoria independente e correção do BUG-01,
com registro das alterações verificadas autorizado em commit específico.
O widget usa projetos ativos e contagens de tarefas por ID. Arquivamento apenas
altera status, com restauração ao estado anterior, sem excluir vínculos.
Duplicações de nome equivalente são rejeitadas nas operações, inclusive entre
arquivados; registros legados não são mesclados ou eliminados automaticamente.
A ordenação recente registra mudanças do projeto e das tarefas/notas vinculadas,
sem alterar a ordem persistida da coleção. Favoritar não inventa atividade.
A Etapa 6 e as correções finais foram homologadas; histórico preservado em [P0.4_FINAL_VERIFICATION.md](P0.4_FINAL_VERIFICATION.md).

**Espaço interno:** rotas `#/projects/<ID codificado>/<aba>`, com retorno à
Biblioteca e estado de projeto inexistente. Arquivados são consultáveis; criação
e edição contextual ficam bloqueadas até restauração. `SPACE_WIDGETS` define a
composição modular da Visão Geral sem alterar `state.widgets` do dashboard.
O widget de foco reutiliza o mesmo template, timestamps e controles globais.

Schema 2 → 3 valida a origem, copia-a antes de gravar e acrescenta `references: []`.
Cada referência possui `id`, `projectId`, `title`, `kind` (`link`/`material`),
`url`, `description`, `createdAt`, `updatedAt`. URL é obrigatória para links;
materiais podem ser descritos sem URL. Somente http/https sem credenciais;
links externos usam `noopener noreferrer`. Não há leitura de arquivos ou uploads.

Notas usam um único registro, título e corpo Markdown textual, compartilhado
por `projectIds`. O formulário fixa o projeto de origem e permite outros vínculos;
notas existentes podem ser vinculadas sem cópia. Edições atualizam a atividade de
todos os projetos envolvidos. Notas sem datas preservam sua ordem de origem;
datas são atribuídas apenas às novas notas ou às edições observadas.

**Accio Knowledge:** schema 3 → 4 valida a origem, copia o JSON exatamente para
`backup:pre-schema-4` e acrescenta pastas/propriedades sem mudar conteúdo, IDs,
relações e preferências. Extensões preexistentes compatíveis são preservadas;
extensões incompatíveis protegem a origem. `noteFolders` contém `{id,name,parentId}`;
a validação rejeita ciclos. `folderId` da nota aponta para a pasta, nunca para seu
nome/caminho. Mover ou renomear não altera seu ID ou `projectIds`.

Notas recebem `tags`, `favorite`, `collection` (`notes`, `capture`, `journal`) e
`noteLinks: [{label,targetId}]`. O corpo é mantido literalmente; a prévia não é
fonte de verdade. `[[Título]]` pode resolver título único e guardar destino por ID,
preservando links após renomeação. Ausências/ambiguidades não escolhem um destino.
Não há grafo ou motor de backlinks. Metadados prepararam contratos futuros;
nenhum frontmatter é escrito em arquivos nesta fase.

A biblioteca filtra os mesmos registros usados nos projetos e no dashboard.
O editor modifica a nota em memória e tenta salvar após 450 ms sem digitação;
seleção, navegação, troca de modo e Ctrl+S também tentam salvar. O indicador só
confirma persistência após sucesso do adapter. Falhas preservam o JSON anterior e
o rascunho em memória; há retentativa e aviso antes de sair. Conflito com outra aba
continua bloqueando sobrescrita. Isso não é sincronização ou merge entre abas.

`markdown.mjs` escapa texto e produz somente tags permitidas para títulos, listas,
citações, links HTTP/HTTPS, ênfase e código. Não interpreta HTML, imagens externas,
scripts ou eventos. Não usa parser de HTML não confiável nem `eval`. O formato é
um subconjunto de Markdown; não promete paridade completa com CommonMark.

## 1. Direção arquitetural

**Forma de entrega definitiva planejada:** aplicação web local em **Ruby on Rails 8 + Hotwire + CSS homologado preservado**, com manifest/PWA e interface desktop-first responsiva, preservando Dock + Widgets. O servidor rodará no Ubuntu; numa etapa posterior poderá ser exposto apenas aos dispositivos autorizados por Tailscale, com autenticação da aplicação. Iniciar P1 exige aprovação do protótipo navegável e autorização específica; a aprovação visual da P0.3 não basta.

**Persistência mista deliberada:**
- **SQLite:** entidades transacionais (tarefas, projetos, eventos, blocos de tempo, sessões de foco, preferências e relacionamentos). Pode haver bancos SQLite separados para fila/cache conforme configuração Rails.
- **Arquivos `.md`:** fonte de verdade do conteúdo das notas, sob um **Vault configurável fora do checkout de código**.
- **Índice derivado no SQLite/FTS5:** títulos, conteúdos, tags, links e metadados das notas para consulta rápida; reconstruível a partir do Vault.
- **Integrações externas:** APIs/artefatos somente de leitura e adapters independentes; não mesclar banco de dados do AccioFeed e do Hub.

O sistema terá um único backend Rails para o MVP. **Não** introduzir microserviços, Redis, motor vetorial ou frontend React só por antecipação de necessidades futuras.

### 1.1 Diagrama lógico

```text
                         UBUNTU (host pessoal)
                                  │
                    ┌─────────────┴──────────────┐
                    │  Navegador / PWA           │
                    │  HTML + Hotwire + Stimulus │
                    │  Player global de áudio    │
                    └──────────────┬─────────────┘
                                   │ HTTP autenticado
                    ┌──────────────▼──────────────┐
                    │         RAILS 8             │
                    │ Controllers + Services      │
                    │ Background Jobs             │
                    │ Adapters / Presenters       │
                    └──────┬────────┬────────────┘
                           │        │
               ┌───────────▼─┐   ┌──▼──────────────────┐
               │ SQLite      │   │ Vault Markdown       │
               │ + FTS5      │   │ arquivos reais `.md` │
               └─────────────┘   └─────────────────────┘
                           │
          ┌────────────────┼─────────────────────────┐
          │                │                         │
    ┌─────▼──────┐  ┌──────▼────────┐      ┌────────▼─────────┐
    │ AccioFeed  │  │ Status backups│      │ APIs futuras     │
    │ API HTTP   │  │ JSON local    │      │ Gmail, GitHub,   │
    │ (v0.2)     │  │ (v0.2)        │      │ Google Calendar  │
    └────────────┘  └───────────────┘      └──────────────────┘
```

### 1.2 Módulos no monólito Rails

| Módulo | Responsabilidade | Depende de |
|---|---|---|
| `Identity` | Autenticação, sessão e preferências do usuário | SQLite |
| `Dashboard` | Composição de widgets e estado isolado por widget | Serviços internos/adapters |
| `Projects` | Projetos, modelos, estados, referências | SQLite |
| `Tasks` | Entrada, tarefas, subtarefas e recorrências | SQLite |
| `Scheduling` | Eventos, blocos de tempo, datas e fuso | SQLite |
| `Focus` | Pomodoro, estados de sessão e contabilização | SQLite |
| `Knowledge` | Vault, Markdown, links, indexação, templates | Disco + índice FTS5 |
| `Music` | Preferências, estações, integração de UI com foco | SQLite + navegador |
| `Integrations::AccioFeed` | Consulta ao AccioFeed | HTTP independente |
| `Integrations::Backups` | Leitura de relatórios da rotina de backup | JSON local independente |
| `Integrations::Gmail` | Leitura autorizada de resumos de e-mail | API externa (futuro) |

**Regra de isolamento:** indisponibilidade de integração não bloqueia sessão, tarefas, calendário, conhecimento ou foco.

## 2. Estrutura de diretórios proposta

```text
Accio-HUB/                 # checkout existente; estrutura Rails futura
├── AGENTS.md
├── prototype/             # referência P0.3 e evolução P0.4
├── app/                    # Rails (models/controllers/views/jobs/services)
├── config/                 # configuração Rails, segredos via env/credentials
├── db/                     # migrations + índices
├── test/                   # testes automatizados
├── docs/
│   ├── PRODUCT.md
│   ├── ARCHITECTURE.md
│   ├── ROADMAP.md
│   └── DESIGN_BASELINE.md
└── ...

# Dados do usuário, FORA do checkout:
~/Documents/AccioHub/Vault/
├── Inbox/
├── Diario/
├── Projetos/
├── Estudos/
├── Referencias/
└── Anexos/

# Dados operacionais do Rails: volume ou diretório persistente privado,
# separado do repositório; caminhos definidos por configuração.
```

**Observação:** o caminho do Vault é uma proposta de padrão; poderá ser escolhido na configuração inicial. Nunca embutir `/home/goecking` como caminho obrigatório no código. A PWA não escreve diretamente no disco pela API do navegador: o Rails gerencia os arquivos no host.

## 3. Modelo de dados inicial

As tabelas abaixo são conceituais; nomes finais e migrations serão estabilizados após o spike.

| Entidade | Campos/chaves essenciais | Regras importantes |
|---|---|---|
| `users` | `id`, `email/login`, `password_digest`, locale/timezone | Conta local única no MVP; identidade preparada para isolamento |
| `user_preferences` | `user_id`, `theme`, `accent`, `wallpaper`, `density`, `sidebar`, settings JSON | Validação e valores padrão; navegação conforme baseline; nunca segredos em JSON público |
| `dashboard_widgets` | `user_id`, `context`, `kind`, `visible`, `position`, `size`, options JSON | Contexto `home` ou `project:{id}`; allowlist de tipos/opções |
| `dock_apps` | `user_id`, `kind`, `visible`, `position` | Ordem/visibilidade dos atalhos do board; ocultar não desativa módulo |
| `projects` | ID estável, nome, descrição, status, cor, ícone, template | Arquivamento não exclui dados relacionados |
| `tasks` | ID, título, descrição, status, prioridade, `project_id?`, `parent_id?`, `planned_on?`, `due_at?`, estimativa | Sem projeto/data obrigatórios; subtarefa sem ciclos |
| `task_occurrences` | ID, `task_id`, data, status, conclusão | Para recorrência; não concluir ocorrências futuras |
| `recurrence_rules` | `task_id`, regra e timezone | Recorrência determinística e testável |
| `events` | ID, nome, `starts_at`, `ends_at`, `project_id?` | Evento != tarefa; início anterior ao fim |
| `time_blocks` | ID, `task_id`, início/fim, projeto derivável | Reserva agenda sem duplicar tarefa |
| `focus_sessions` | ID, `user_id`, `task_id?`, `project_id?`, tipo, status, timestamps, duração confirmada | Uma sessão ativa por usuário; estados explícitos |
| `note_index` | `note_id`, vault-relative path, title, checksum, mtime, tags, indexed_at | **Índice derivado**, reconstruído pelos arquivos Markdown |
| `note_links` | `source_note_id`, `target_note_id?`, texto do link | Backlinks e referências não resolvidas |
| `note_task_links` | `note_id`, `task_id` | Relações transacionais; precisa de backup do SQLite |
| `project_note_links` | `project_id`, `note_id` | Independente do caminho físico |
| `music_stations` | ID, nome, `stream_url`, favorita, ordem | URLs validadas; conexão no navegador |
| `music_preferences` | `user_id`, estação, volume, modo, regras de foco | Sem autoplay incondicional |
| `integration_states` | `provider`, última tentativa/sucesso, status, erro resumido, atualizado em | Estado explícito com TTL, sem dados sensíveis |

**Datas:** persistir instantes em UTC e apresentar conforme timezone configurado. Campos de dia civil (ex.: `planned_on`) permanecem *date-only* e não devem ganhar fuso por conversão indevida.

**Integridade:** IDs estáveis, FK onde aplicável, índices para filtros por dia/projeto e unicidade transacional de sessão ativa; não inferir identidade de entidade de seu nome ou do título de nota.

## 4. Vault Markdown: contrato v0.1

Este contrato descreve a implementação futura do Vault. A P1.0 aprovada define
sua entrega básica na P1.3 e a migração na P1.4, com contratos detalhados no plano.
As notas da P0.4 permanecem no localStorage até exportação/importação autorizadas.
A P1.1 não escreve notas no disco. Recursos avançados deste desenho continuam
fora da fundação; organização visual em pastas não equivale a escrita no disco.

### 4.1 Fonte de verdade

Os arquivos `.md` são a fonte de verdade do **conteúdo e dos metadados portáveis** das notas. O índice de notas (incluindo FTS) deve poder ser reconstruído por varredura completa.

O **SQLite transacional** é a fonte de verdade de tarefas, projetos, agenda, sessões, layouts e vínculos externos às notas (por exemplo, nota ↔ tarefa). Para recuperação total de relações, **Vault e SQLite devem ser restaurados juntos**.

### 4.2 Formato de nota

```markdown
---
id: "9a7d4a7e-5ed2-4f1a-81eb-15a85dfcc0bb"
title: "Exportação DXF"
created_at: "2026-10-09T19:00:00-03:00"
updated_at: "2026-10-09T19:30:00-03:00"
tags:
  - cad
  - python
project_ids: []
---

# Exportação DXF

Documentação e experimentos.

Relacionadas: [[Arquitetura do AccioCAD]]
```

- `id` estável e único, gerado ao criar. A identidade **não** depende do nome do arquivo.
- `project_ids` opcional como pista portável; associação operacional pode existir também no SQLite, reconciliada explicitamente. Se alterar o frontmatter externamente, definir política de atualização sem produzir loops.
- Tags explícitas, legíveis fora do Hub. Formato versionado e documentado.
- Para novos arquivos importados **sem frontmatter**, gerar identidade e metadados de modo controlado, sem regravar silenciosamente conteúdos externos antes de confirmação ou política estabelecida.

### 4.3 Fluxo seguro de escrita e leitura

1. Validar o Vault configurado, permissões e caminho relativo normalizado.
2. Rejeitar travessia de diretórios (`..`), acesso fora do Vault e symlinks que escapem da raiz; validar de novo no momento da abertura.
3. Ler conteúdo + **etag/checksum** de versão; usuário edita sobre uma revisão conhecida.
4. Ao salvar, usar escrita temporária no mesmo filesystem, `fsync` onde apropriado, e substituição atômica; nunca truncar arquivo original antes de confirmar escrita.
5. Se o checksum mudou desde a abertura, **recusar sobrescrita silenciosa** e oferecer recarregar, comparar/mesclar ou salvar cópia.
6. Atualizar índice e backlinks depois de confirmar escrita; falha de indexação **não** deve apagar a nota.
7. Usar watcher de filesystem **mais** reconciliação periódica/ao iniciar; alterações por Obsidian/VS Code reindexadas, não sobrescritas.
8. Excluir uma nota requer confirmação; preferir lixeira reversível dentro do Vault e checagem de backlinks.

### 4.4 Editor e pesquisa

- **v0.1:** editor Markdown com prévia, leitura, autosave protegido, tags, árvore de pastas, templates simples, notas diárias, links `[[Título]]`, backlinks básicos, buscas com FTS5.
- Resolver `[[Título]]` por contexto/ID e detectar ambiguidade (dois títulos iguais). Links com alias ou ID explícito serão considerados para evolução.
- Renderizar Markdown com sanitização HTML/XSS; imagens e anexos sempre resolvidos com autorização e validação de caminho.
- **Editor visual rico futuro:** só liberar após testes de round-trip que preservem blocos de código, tabelas, links, frontmatter, listas e trechos que o editor não compreenda.
- A busca semântica/embeddings é **opt-in futuro**, não pré-requisito para pesquisa funcional.

### 4.5 Relação com ai-memory

O ai-memory já usa Markdown versionado e índice derivado, mas é uma solução dedicada a memória de agentes. **Não montar o Vault do Hub dentro do wiki do ai-memory**, nem compartilhar diretamente SQLite ou regras de retenção/compactação. Integração futura por API autorizada para busca/importação explícita, preservando origem e permissões; nenhuma reescrita de notas sem revisão.

## 5. Eventos e coordenação de produtividade

### 5.1 Tarefas, calendário e foco

- Criar/editar tarefa dispara atualização da visualização Hoje, de projeto e calendário, sem criar duplicata.
- Recorrências geram ocorrências individuais dentro de janela de planejamento (geração idempotente), evitando tarefas repetidas infinitas.
- **Sessão de foco:** máquina de estados `idle → running ↔ paused → completed|interrupted|cancelled` com tempos efetivamente trabalhados.
- Garantir **uma sessão ativa** por usuário no banco, mesmo com duas abas ou dispositivos.
- Persistir checkpoints em transições; após reabrir, recalcular pelo relógio e exigir reconciliação se houver suspensão/inatividade significativa.
- Totais por projeto/tarefa derivam de sessões confirmadas, sem arredondamentos que inflacionem tempo.

### 5.2 Player global

- Um controlador de mídia no layout compartilhado; compatível com navegação Hotwire/Turbo, utilizando persistência de componente quando aplicável (`data-turbo-permanent` após teste).
- Fontes de rádio: áudio via `<audio>` HTML5 e controles de volume/pausa. Reprodução fica do lado do navegador; o backend guarda **preferências/estações**, não o stream.
- Eventos explícitos de `Focus` atualizam regras opcionais do player; nenhuma ação de Pomodoro pode contornar políticas de autoplay/consentimento do navegador.
- Proteger contra múltiplos players por abas, quando possível, por coordenação no browser (ex.: BroadcastChannel) e comportamento claro de transferência.
- Evitar proxy arbitrário de URLs externas pelo Rails; dados remotos devem respeitar protocolos e restrições de conteúdo misto/CORS aplicáveis.
- Integrações Spotify/YouTube futuras devem usar SDKs/embeds oficiais sob seus termos; não planejar extração de áudio.

## 6. Widgets e personalização

Personalização é requisito central. A implementação definitiva deve preservar
a baseline: docks, temas, fontes, fundos, widgets, reordenação por arraste/botões,
tamanhos predefinidos e Accio Music global. O protótipo já guarda `wallpaper`,
`dockOrder`, `dockHidden` e `widgets` no estado local; o contrato futuro deve
contemplar essas preferências. Redimensionamento livre e layouts por contexto
continuam como evolução posterior.

Cada widget expõe contrato interno conceitual:

```json
{
  "kind": "backup_status",
  "state": "healthy|running|error|stale|unknown|unconfigured",
  "updated_at": "2026-10-09T20:02:00-03:00",
  "source": "local_backup_report",
  "data": {},
  "actions": ["open_details"]
}
```

Esse JSON é **ilustrativo**, não endpoint implementado. Na renderização inicial, as telas podem usar partials Hotwire e presenters Ruby, sem obrigar a criação de uma API pública para todos os widgets.

**Persistência do layout:** tipo conhecido, posição, visibilidade, tamanho validado, opções por widget; fallback para padrão ao encontrar opção obsoleta. Evitar `eval`, HTML arbitrário e acesso direto de plugins às tabelas do sistema.

## 7. Integrações e limites de confiança

### 7.1 AccioFeed

O projeto existente **AccioFeed** usa **Next.js 15+/React 19** no frontend, **FastAPI/Python** no backend, **PostgreSQL 16** e worker de coleta, conforme seu README. Nas configurações locais documentadas, frontend usa `localhost:3001` e API `localhost:8001` (portas configuráveis).

**Integração proposta:** cliente Rails → API HTTP do AccioFeed → lista resumida de notícias e metadados. Abrir interface de leitura do AccioFeed; não fazer consultas diretas ao banco Postgres e não reimplementar RSS no Hub.

**A validar no spike:** endpoints reais de listagem, filtros, favoritos/ler depois; autenticação e proteção da API; timeouts, paginação e contrato estável; se necessário, criar endpoint específico e pequeno no AccioFeed. O README documenta funcionalidades mas **não é garantia** dos contratos HTTP.

**Resiliência:** timeout curto, limite de itens, cache com TTL, limite de tentativas e estado `stale` quando apenas dados antigos estiverem disponíveis. Desligamento do AccioFeed não afeta tarefas/notas.

### 7.2 Monitor de backups do Ubuntu

Infraestrutura atual (a ser consumida, não alterada diretamente pelo browser):

```text
systemd --user
├── ai-memory-backup.timer                   # diário, 20h
│   └── ai-memory-backup.service
│       ├── backup-ai-memory                # arquivo local
│       ├── backup-ai-memory-agents         # pós-execução, não fatal
│       └── OnSuccess → ai-memory-cloud-backup.service
│                    └── backup-ai-memory-cloud (Restic/rclone)
└── ai-memory-cloud-maintenance.timer       # domingo, 21h
    └── ai-memory-cloud-maintenance.service # retenção/prune + check
```

**Observações para leitura correta:** o `ExecStartPost=-` do backup de agentes pode falhar sem reprovar a unidade principal; sucesso do serviço local não garante sucesso da cópia na nuvem; timer habilitado não garante que uma execução realmente aconteceu. O painel deve monitorar **cada etapa independentemente**.

**Contrato proposto (a implementar nos scripts/collector)**: após cada tentativa, gravar JSON de status separado por etapa no diretório privado do usuário, por exemplo `~/.local/state/accio-hub/backup-status/`, com escrita atômica, sem segredo:

```json
{
  "schema_version": 1,
  "job": "ai-memory-cloud",
  "attempted_at": "2026-10-09T20:00:00-03:00",
  "finished_at": "2026-10-09T20:02:00-03:00",
  "result": "success",
  "last_success_at": "2026-10-09T20:02:00-03:00",
  "error_code": null,
  "error_summary": null
}
```

**Estado atual:** os relatórios JSON **ainda não existem por padrão** nos scripts versionados; serão acrescentados na v0.2 com cuidado para não alterar o comportamento comprovado dos backups. Podemos usar `systemctl --user show`/journal para diagnóstico local pontual, sem torná-los interface web de execução arbitrária.

- Collector **fora da request web** agrega os relatórios, verifica freshness/horário esperado e normaliza status.
- A página apenas lê informação produzida por processo local autorizado, em diretório de permissões restritas.
- **Nunca** montar `docker.sock`, senha Restic, `rclone.conf` ou chave Gemini no Rails; não executar `restic prune`, shell ou `systemctl` a partir de requisições de usuário.
- Manter separados `last_attempt`, `last_success`, `last_integrity_check`, `next_expected_at`; alerta se não rodou no prazo com tolerância configurável.
- Alertas no dashboard exigem leitura da app; notificações externas com PC desligado exigiriam monitor fora dessa máquina (não previsto no MVP).

### 7.3 Gmail/Google Calendar/GitHub (futuro)

Adapters separados, OAuth quando aplicável, menor escopo possível, tokens criptografados e fora de logs/JSON. Gmail inicialmente leitura. Calendário externo exige política clara de conflitos, fonte de verdade, eventos recorrentes e duplicação. GitHub fornece dados auxiliares e não substitui tarefas do Hub.

## 8. Segurança e privacidade

### 8.1 Acesso e autenticação

- Mesmo em `localhost`, ter sessão autenticada e proteção CSRF/headers/secure cookies; armazenar senhas via hash robusto.
- Primeira implantação restrita a **`127.0.0.1`**. Acesso remoto futuro por **Tailscale Serve/reverse proxy restrito**, não porta aberta na internet.
- Definir trusted hosts/origins, HTTPS do proxy, proteção de sessões, limite de tentativas e revogação de acesso.
- Evitar acesso a dados de clientes/empresa sem autorização explícita da organização; separação de contexto pessoal e profissional será uma evolução, não promessa implícita de segurança.

### 8.2 Arquivos e conteúdo externo

- Proteção contra path traversal, links simbólicos, corridas TOCTOU, uploads perigosos, XSS e arquivos excessivamente grandes.
- Frontmatter YAML com parser seguro, sem desserialização de objetos arbitrários.
- Links RSS e URLs externas exibidos de forma segura; proteção SSRF em qualquer fetch **servidor-side** (AccioFeed já documenta barreiras próprias).
- Sanitizar conteúdo Markdown exibido e mensagens de erro, sem inserir HTML bruto confiando em fontes externas.
- Dados do Vault e e-mails podem ser sensíveis; restringir permissões locais, backups e exportações.

### 8.3 Gestão de segredos

- Tokens/API keys/Restic password/rclone config **nunca** em Git, `.md` de documentação, HTML, localStorage ou logs.
- Usar variáveis de ambiente protegidas/credentials Rails para chaves de aplicação quando necessário.
- O Hub pode ler status de backups, **não** ter capacidade para restaurar ou remover snapshots.

## 9. Backups e restauração do Accio Hub

**Novo escopo a proteger:** arquivos Markdown + anexos + base(s) SQLite + configurações não secretas necessárias para reconstrução. Rotina independente, depois incorporada à estratégia de Restic já existente.

- Não confiar em cópia direta de arquivos SQLite em uso; gerar snapshot consistente via API de backup do SQLite, `VACUUM INTO` em condições controladas ou mecanismo validado equivalente para cada base ativa.
- Capturar Vault com consistência suficiente e manifesto de versão/horário; validar lista e checksums, quando aplicável.
- Backup criptografado com Restic; reter snapshots conforme política acordada, sem misturar automaticamente o Vault com repositórios públicos ou privados GitHub.
- **Teste de restauração isolada obrigatório** antes de considerar a proteção concluída: abrir nota, recuperar tarefa, sessão Pomodoro, configurações e referências.
- Expor na UI apenas resultado da proteção do Hub depois que a rotina existir e estiver testada.

## 10. Jobs, deploy e observabilidade

- Solid Queue/Active Job para indexação assíncrona e integrações futuras, preservando operações locais essenciais mesmo sem jobs remotos.
- Job de reconciliação do Vault na inicialização e periodicamente; jobs de sincronização de notícias em horários com timeout/limites.
- PWA: manifest, service worker/cache de assets e estratégia de atualização; **não** prometer edição offline em outro dispositivo sem projeto específico de sync e resolução de conflitos.
- Deploy local por Docker Compose ou serviço systemd a decidir após spike de Rails e integração com filesystem. O Vault deve ficar em volume explícito, sem permissão de escrita fora do caminho autorizado.
- Logs estruturados com identificadores de erro, tempos e estados, mas sem texto integral de notas/e-mails/tokens.
- Saúde separada em app, DB, Vault, jobs e integrações; nenhum status “verde geral” baseado apenas no processo Rails estar no ar.

## 11. Testes essenciais

| Camada | Testes mínimos |
|---|---|
| Domínio | tarefas/ocorrências, estados do foco, blocos/limites de calendário, integridade das relações |
| Knowledge | criação, round-trip Markdown, frontmatter inválido, importação externa, conflito de checksum, symlink/traversal, índice reconstruído, XSS |
| UI | tarefa na tela Hoje atualiza projeto e calendário; Pomodoro persiste entre páginas; player não reinicia em navegação |
| Integrações | AccioFeed offline/timeout/retorno inválido; backup ausente/desatualizado/falho, falha parcial local/agentes/cloud |
| Segurança | autenticação, CSRF, acesso indevido a caminhos/arquivos, exposição de segredos, links maliciosos |
| Operação | backup consistente, restauração isolada, falta de rede, reinício com sessão em andamento, duas abas abertas |

## 12. ADRs resumidos

| ADR | Decisão | Justificativa | Revisitar quando |
|---|---|---|---|
| ADR-001 | Rails monolítico + Hotwire | Menos componentes para MVP pessoal | UX exigir frontend rico independente |
| ADR-002 | SQLite transacional | Simples para usuário único/local | Concorrrência/carga exceder perfil previsto |
| ADR-003 | Markdown file-first | Portabilidade/controle do usuário | Requisitos de colaboração simultânea reais |
| ADR-004 | ai-memory desacoplado | Domínios e retenções diferentes | API estável para busca federada |
| ADR-005 | Integrações via adapters | Isolamento de falhas e evolução | Contratos reais precisarem ser estabilizados |
| ADR-006 | Backups somente leitura | Minimizar privilégios e risco operacional | Política de controle remoto explícita futura |
| ADR-007 | Player no navegador, global | Música persistente sem servidor de áudio | Cliente desktop dedicado aparecer |

## 13. Spikes técnicos antes da implementação completa

1. **Rails/SQLite/Solid Queue** no Ubuntu e persistência das bases reais em ambiente de desenvolvimento.
2. **Hotwire + player HTML5 persistente**: verificar navegação Turbo, duas abas, minimização e permissões de áudio.
3. **Vault**: round-trip Markdown, travessia/symlinks, watcher, etags e indexação FTS5 sobre arquivos externos.
4. **Pomodoro**: recarga de página, duas abas simultâneas, suspensão e recuperação de sessão.
5. **AccioFeed**: inspecionar e testar endpoints reais, sem assumir URLs a partir do README.
6. **Telemetria do backup**: desenho de JSON escrito pelos scripts sem afetar confiabilidade dos timers já validados.

**Critério de arquitetura pronta para codificação:** esses spikes produzem evidências, decisões de implementação e testes, não só preferência por tecnologia.
