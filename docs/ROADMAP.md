# Accio Hub — Roadmap de implementação (ROADMAP)

> **Versão:** 0.4 (encerramento da P0.4 e backlog futuro)<br>
> **Data-base:** 2026-10-11<br>
> **Estado:** P0.3 aprovada visualmente; P0.4 e P1.1 homologadas; P1.0/P1.2A aprovadas; P1.2B homologada; P1.2C aprovada tecnicamente; planejamento P1.2D aprovado; D1 aprovada com ressalvas; D2 aprovada; D3 aprovada tecnicamente<br>
> **Documentos relacionados:** [DESIGN_BASELINE.md](DESIGN_BASELINE.md) · [PRODUCT.md](PRODUCT.md) · [ARCHITECTURE.md](ARCHITECTURE.md)

## 1. Objetivo do roadmap

Entregar um **aplicativo pessoal realmente utilizável** antes de expandir integrações e recursos avançados. O desenvolvimento ocorrerá em ciclos pequenos com demonstração visual, testes, revisão e critérios de aceitação claros.

**Prioridades ordenadas:**
1. Produtividade local confiável e personalização.
2. Conhecimento portável em Markdown, ligado a projetos e tarefas.
3. Foco/Pomodoro com reprodutor de música opcional.
4. Integração segura com AccioFeed e acompanhamento real dos backups.
5. E-mails, calendários externos e busca inteligente.

### 1.1 Releases

| Release | Resultado que precisa entregar | Depende de |
|---|---|---|
| **v0.1 — Core pessoal** | Hoje + tarefas + projetos + calendário + foco + Vault `.md` + player rádio + configuração básica | Fases P0–P6 |
| **v0.2 — Informações reais** | AccioFeed e relatórios de backups, com tratamento de falhas | Fases P7–P8 |
| **v0.3 — Integrações pessoais** | Gmail e, opcionalmente, Google Calendar/GitHub após validação | Fase P9 |
| **v0.4+ — Evolução** | Editor rico, layouts avançados, YouTube/Spotify, busca federada e ai-memory | Fase P10 |

**Nota de escopo:** “v0.1” é a **primeira versão utilizável completa**, não significa que todos os itens sejam desenvolvidos de uma vez. Cada fase libera algo testável.

P0.3/P0.4 são revisões do protótipo dentro de P0; não são releases funcionais
v0.3/v0.4. A aprovação visual da P0.3 não conclui todos os critérios de P0.

## 2. Fases detalhadas

### P0 — Definição e protótipo (antes do código de produção)

**Meta:** validar experiência Dock + Widgets, Conhecimento, Projetos, Tarefas, Planejador e Foco, preservando a baseline visual aprovada.

**Marco confirmado:** P0.3 aprovada visualmente, commit `0018bb4`. Já existem
docks, claro/escuro, fundos, fontes, widgets reordenáveis por arraste/botões,
tamanhos predefinidos, tarefas/notas demonstrativas editáveis, timer e barra
Accio Music global sem áudio. Projetos são fixos; Conhecimento usa lista plana
e texto Markdown no localStorage. Inventário em [PRODUCT.md](PRODUCT.md), §1.3.

**Entregáveis**
- `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md` versionados.
- `docs/DESIGN_BASELINE.md` com referência imutável à P0.3 e limites da aprovação.
- Mapa de rotas, wireframes mobile/desktop e biblioteca mínima de componentes visuais.
- Tokens de design: claro/escuro, cor de destaque, densidade, tipografia, espaços e estados.
- Protótipo navegável com dados **de demonstração claramente identificados**.
- Lista explícita de decisões pendentes do [PRODUCT.md](PRODUCT.md), §9.

**Aceitação**
- [ ] É possível percorrer as telas sem links mortos ou áreas que fingem estar conectadas.
- [ ] Reordenação por arraste/botões, visibilidade e tamanho predefinido continuam funcionando após evoluir as telas.
- [ ] Navegação funciona nos formatos de monitor desktop e celular.
- [ ] Dock compacta e player global não obstruem conteúdo.
- [x] Usuário aprova hierarquia e organização visual da P0.3 **antes de construir as integrações** (baseline `0018bb4`).

**Não inclui:** APIs reais, autenticação de terceiros, parser Markdown definitivo.

### P0.4 — Projetos e Conhecimento (protótipo)

**Escopo aprovado:** evoluir com componentes existentes e dados demonstrativos
no navegador. Preservar navegação, temas, fontes, fundos, personalização,
widgets e Accio Music. Sem Rails, APIs externas ou arquivos Markdown reais.
Evitar refatorações grandes sem necessidade.

| Etapa | Entrega | Situação |
|---|---|---|
| 1 — Alinhamento da documentação | Baseline, estado atual, limites e contratos futuros consistentes | Aprovada, commit `1d83387` |
| 2 — Preparação do estado | IDs estáveis para projetos/tarefas/notas, relações e persistência versionada compatível; separação mínima de responsabilidades | Aprovada, commit `cd3589d` |
| 3 — Biblioteca de Projetos | Grade, busca, filtros, favoritos, ordenação, criação/edição com ícone/cor e arquivamento reversível | Homologada após auditoria; commits `6c7a719` e `c759e61` |
| 4 — Espaço do projeto | Visão Geral com widgets, Tarefas, Conhecimento e Referências contextualizados | Aprovada, commit `e88d772`; evidências em P0.4_PROJECT_SPACE_VERIFICATION.md |
| 5 — Conhecimento | Biblioteca/pastas simuladas, propriedades, busca, Markdown, prévia/leitura e vínculos | Homologada após auditoria e correção do BUG-01; commit `8d79186`; evidências em P0.4_KNOWLEDGE_VERIFICATION.md |
| 6 — Verificação e fechamento | Testes de dados/relações e fluxos; comparação visual desktop/mobile com P0.3 | Concluída e homologada, após correções F01–F08 e ajuste visual do Pomodoro; evidências em [P0.4_FINAL_VERIFICATION.md](P0.4_FINAL_VERIFICATION.md) |

Planejamento e Tempo permanecem “em preparação”, sem calendário completo ou
contabilização funcional nesta revisão. A P0.4 foi homologada pelo usuário,
incluindo aprovação visual no Firefox do Pomodoro adaptativo. As limitações e
observações da verificação final permanecem registradas; a homologação não
declara conformidade global de acessibilidade ou validação de fluxos Firefox
que não foram exercitados pelo agente. Marco de encerramento: tag anotada
`p0.4-approved` no commit final. P1 depende de autorização específica.

Modelo, migração, resultados e limitações da Etapa 2 estão registrados em
[P0.4_STATE_VERIFICATION.md](P0.4_STATE_VERIFICATION.md). A aprovação visual
da P0.3 permanece distinta da revisão desta implementação.

**Critérios de evolução:**
- Migrações versionadas, não destrutivas e testáveis preservam dados e
  preferências existentes, inclusive quando reaplicadas ou diante de falha.
- IDs de projetos/notas permanecem estáveis após renomeação; relações não
  dependem da pasta da nota. Arquivar projeto preserva tarefas e notas.
- Conteúdo contextualizado usa os mesmos dados do board, sem cópias divergentes.
- Recarga preserva edições e configurações; falha de salvamento é comunicada.
- Fluxo projeto → tarefa → nota → edição → retorno funciona no navegador.
- Testes automatizados relevantes e `verification` acompanham as alterações;
  `agent-browser`, quando disponível, valida interface e responsividade.
  Sintaxe válida não comprova funcionamento nem aprovação visual.

### P1 — Fundação Rails e migração incremental

O [plano P1.0](P1.0_ARCHITECTURE_PLAN.md) foi aprovado em 2026-10-11 e passa a reger
esta fase. Preservar o CSS homologado; Tailwind adiado. Vault básico e migração
passam a integrar P1.3/P1.4. Os módulos e ampliações das fases posteriores
continuam no backlog, sem autorização implícita.

| Etapa | Entrega | Estado |
|---|---|---|
| P1.1 — Fundação Rails | Autenticação local e recuperação de senha por CLI, shell ERB/Turbo, temas, fundos, fontes, Dock, widgets e Music demonstrativo; personalização fundamental | Encerrada e homologada; tag anotada `p1.1-approved` |
| P1.2 — SQLite | Modelos transacionais de projetos, tarefas, referências, preferências e foco global | A/B/C/D aprovadas e registradas; E1 em `0c74250`; E2 aprovada com ressalvas em `a0ab717`; E3 aprovada com ressalvas, encerramento autorizado; somente planejamento F autorizado |
| P1.3 — Vault Markdown | Arquivos reais, índice reconstruível, escrita segura, conflitos e recuperação | Não iniciada; exige autorização |
| P1.4 — Migração | Exportação/importação versionada, simulação, relatório e recuperação | Não iniciada; exige autorização |
| P1.5 — Verificação final | Equivalência, segurança, visual e restauração | Não iniciada; exige autorização |

Objetivos, dependências, riscos, testes e critérios de avanço detalhados no plano.
A P1.1 utiliza apenas modelos de autenticação e fixtures sintéticas de leitura.
As preferências fundamentais são um cookie criptografado deste navegador,
sem modelo de produto ou acesso ao localStorage do protótipo. Persistência
transacional de preferências será tratada na P1.2.

**Aceitação da P1.1:** rotas protegidas, ausência de cadastro público, servidor
loopback, navegação Turbo, personalização por teclado, foco e responsividade
nos cinco tamanhos aprovados. Comparação com P0.4 e limites registrados em
[P1.1_FOUNDATION_VERIFICATION.md](P1.1_FOUNDATION_VERIFICATION.md).

Auditoria independente do Antigravity aprovada e validação manual no Firefox
confirmada pelo usuário no encerramento. Limpeza de sessões expiradas fica para
P1.2; suporte IPv4-mapped IPv6 será avaliado quando houver necessidade de dual-stack.
Essas melhorias não foram implementadas. Limpeza fica na P1.2F.

Divisão aprovada em [P1.2A_SQLITE_PLAN.md](P1.2A_SQLITE_PLAN.md): A planejamento;
B modelos/migrações/integridade; C preferências; D projetos/tarefas/referências;
E foco global; F integração e verificação. A entrega B preserva o fluxo funcional
de cookies e todas as telas demonstrativas da P1.1. Revisão em
[P1.2B_VERIFICATION.md](P1.2B_VERIFICATION.md). Nenhuma etapa seguinte é autorizada
por esse registro.

### P2 — Projetos, Entrada e Tarefas

**Meta:** organizar trabalho e capturar ideias em um só lugar.

**Entregáveis**
- CRUD e arquivamento de projetos; modelos Desenvolvimento, Estudos, Pessoal e Em branco.
- Entrada para captura de itens sem data/projeto obrigatórios.
- Tarefas/subtarefas, prioridades, projeto opcional, prazos, filtros e edição em painel lateral.
- Recorrência simples com ocorrências independentes.
- Resumo de tarefas e projetos para o dashboard.

**Aceitação**
- [ ] Criar tarefa na Entrada, atribuir a projeto, concluir e visualizar a atualização sem recadastrar.
- [ ] Tarefa sem projeto ou prazo funciona.
- [ ] Concluir ocorrência recorrente não conclui automaticamente próximas.
- [ ] Arquivar projeto não elimina tarefas.
- [ ] Há testes contra inconsistências de status e relações.

**Fora da fase:** Kanban e integração GitHub.

### P3 — Accio Knowledge: Vault Markdown

**Meta:** notas reais, portáveis, pesquisáveis e vinculáveis.

**Entregáveis**
- Configuração da pasta Vault e estrutura inicial (Inbox, Diário etc.).
- Criar/editar/renomear/mover/excluir com confirmação arquivos `.md`.
- Editor Markdown com prévia e leitura, captura rápida e templates básicos.
- Frontmatter com ID estável, tags e datas; links `[[Nota]]` e backlinks básicos.
- Indexador SQLite FTS5; reconstrução de índice por varredura completa.
- Sincronização de alterações externas e prevenção de sobrescrita por checksum.
- Relação nota ↔ tarefa/projeto.

**Aceitação**
- [ ] Nota criada na interface existe como `.md` válido fora dela.
- [ ] Nota alterada por VS Code/Obsidian reaparece atualizada no Hub.
- [ ] Duas alterações concorrentes **não** apagam silenciosamente conteúdo.
- [ ] Apagar índice e reconstruí-lo recupera busca/títulos/tags/links dos arquivos.
- [ ] Tentativas de acessar caminho fora do Vault são recusadas.
- [ ] Links continuam íntegros após renomear/mover nota, ou conflitos são explicitamente indicados.

**Gate de segurança:** testes de XSS, YAML inseguro, symlinks, traversal e atomicidade de escrita.

**Fora da fase:** editor visual completo tipo Notion, grafo interativo, embeddings.

### P4 — Planejador e Pomodoro

**Meta:** transformar tarefas em tempo reservado e sessões de foco reais.

**Entregáveis**
- Agenda com dia, semana e mês; eventos e blocos de tempo ligados a tarefas.
- Criar/editar horários via formulário; detecção de sobreposição exibida.
- Pomodoro (25/5/15 configuráveis), pausa/retomada/fim e cronômetro livre.
- Sessão associada a tarefa/projeto ou livre; histórico e totais confirmados.
- Estado de sessão restaurado ao recarregar e indicador global no cabeçalho.

**Aceitação**
- [ ] Tarefa aparece em projeto, Hoje e calendário sem duplicidade.
- [ ] Iniciar um Pomodoro em Projetos e abrir Conhecimento mantém a sessão.
- [ ] Duas abas não produzem duas sessões ativas simultâneas do mesmo usuário.
- [ ] Recarregar/suspender o navegador não contabiliza automaticamente períodos ambíguos como foco realizado.
- [ ] Totais por tarefa/projeto refletem apenas tempo confirmado.

**Fora da fase:** drag-and-drop de calendário, Google Calendar.

### P5 — Accio Music: rádio global + foco

**Meta:** reprodução opcional contínua durante navegação e estudo.

**Entregáveis**
- Barra superior padrão, modo recolhido e painel expandido.
- Estações de web rádio cadastráveis, favoritos, volume e play/pause.
- Preservação do player em navegação Hotwire/Turbo.
- Preferências de iniciar/pausar/atenuar/retomar com Pomodoro (opt-in).
- UI clara para autoplay bloqueado, stream indisponível ou áudio incompatível.

**Aceitação**
- [ ] Navegar de Hoje para Conhecimento não reinicia stream sem necessidade.
- [ ] Áudio só começa por ação autorizada/configurada, respeitando autoplay do navegador.
- [ ] Desabilitar o módulo remove player e não interfere no Pomodoro.
- [ ] Falha de rádio não quebra tarefas/temporizador.
- [ ] Duas abas não criam reprodução duplicada inadvertida sem aviso/controle.

**Spike obrigatório:** testar comportamento real com Turbo, Firefox Ubuntu e navegador Chromium, especialmente permissões de reprodução.

**Fora da fase:** Spotify/YouTube, extração de áudio, streaming central entre dispositivos.

### P6 — Dashboard modular, exportação e hardening v0.1

**Meta:** integrar os módulos locais e validar o primeiro release de ponta a ponta.

**Entregáveis**
- Tela Hoje com widgets Tarefas, Pomodoro, Agenda, Notas e Projetos.
- Visibilidade, ordem e tamanho predefinido persistentes, por usuário.
- Preservar reordenação por arraste/botões, fundos e ordem/visibilidade da dock já presentes na P0.3.
- Estados carregando/vazio/erro/desativado; proteção contra layout inválido.
- Pesquisa inicial local e acessibilidade/atalhos fundamentais.
- Exportação básica de dados essenciais, documentação de backup e **teste de restauração isolada** de SQLite/Vault.
- Revisão visual mobile/desktop e fechamento de bugs impeditivos.

**Aceitação — corte v0.1**
- [ ] Fluxo completo: captura → tarefa → projeto → calendário → foco → nota → conclusão.
- [ ] Alterar preferência e reiniciar mantém layout, tema e cor.
- [ ] O Vault sobrevive a reconstrução do índice.
- [ ] O backup e a restauração de dados do Hub foram **testados**, não apenas configurados.
- [ ] Falta de internet não impede utilizar funções locais no Ubuntu com servidor rodando.
- [ ] Nenhuma tela apresenta dados demonstrativos como dados reais.
- [ ] Usuário consegue utilizar a aplicação como organizador pessoal por um período de piloto local, registrando problemas de UX.

**Saída:** tag **v0.1** somente quando os critérios acima forem comprovados.

### P7 — Integração AccioFeed

**Meta:** apresentar notícias reais das fontes já configuradas no projeto existente.

**Entregáveis**
- `codebase-map` do AccioFeed e inventário de endpoints reais.
- Adapter Rails com cliente HTTP, cache/TTL, limites, erros e testes com respostas simuladas.
- Widget Notícias da tela Hoje e página de acesso ao AccioFeed.
- Ação criar tarefa vinculada ao título/URL do artigo.
- Decisão explícita sobre favoritos/ler depois após confirmar contratos e autorização.

**Aceitação**
- [ ] Artigos apresentados possuem fonte e atualização verificáveis.
- [ ] AccioFeed offline exibe estado claro, sem bloquear Hub.
- [ ] Nenhum artigo é duplicado desnecessariamente no banco do Hub.
- [ ] Contrato de API testado; não depender de endpoint imaginado a partir do README.

### P8 — Monitor de backups e alertas

**Meta:** estado real e confiável do backup ai-memory local/agentes/cloud, mais verificação de manutenção.

**Entregáveis**
- Adaptar scripts versionados de backup para produzir **relatórios mínimos por etapa**, sem incorporar segredos.
- Collector de leitura + normalização, com status e limites de freshness.
- Widgets de estado e tela de detalhes por etapa.
- Avisos de falha, atraso e ausência de execução com timestamps.
- Testes que simulem backup local OK + agentes FAIL + nuvem FAIL, e timer que não rodou.

**Aceitação**
- [ ] Success de etapa local **não** mascara falha do cloud.
- [ ] `ExecStartPost=-` não mascara falha do backup de agentes.
- [ ] Ausência de relatório no prazo é tratada como atrasado/desconhecido, nunca OK automático.
- [ ] Painel mostra último sucesso e última tentativa distintos.
- [ ] Aplicação não lê senha Restic, config rclone, socket Docker e não executa ações administrativas.
- [ ] Backups existentes continuam passando nos testes após instrumentação.

**Saída:** tag **v0.2** após integração AccioFeed + Backups validada ponta a ponta.

### P9 — Integrações pessoais (posterior)

**Potenciais entregas independentes:**
- Gmail OAuth somente leitura: mensagens importantes, filtros e converter em tarefa.
- Google Calendar: leitura de eventos inicialmente; escrita/sync só após política anti-conflito aprovada.
- GitHub: atividades e referências de projeto, sem substituir tarefas da HUB.
- Acesso remoto privado via Tailscale, com autenticação e testes de origem/sessão.

**Gate:** nenhuma integração exige permissões maiores que o necessário; tokens não ficam expostos; revogação e erros tratados.

### P10 — Funcionalidades avançadas (backlog, sem compromisso de release)

- Editor visual rico Markdown com teste de preservação de conteúdo.
- Gráfico de notas e backlinks avançados.
- Busca semântica e pesquisa federada com ai-memory, opt-in e referências de origem.
- Música YouTube/Spotify nos players oficiais, conforme requisitos das plataformas.
- Redimensionamento livre de widgets e múltiplos layouts (casa/trabalho); reordenação por arraste/botões já pertence à baseline P0.3.
- Recursos offline em clientes remotos com sincronização e resolução de conflitos.
- Mais templates, Kanban, métricas e notificações externas.

#### Personalização avançada do Pomodoro — módulo futuro

**Situação:** backlog futuro, sem implementação e fora do escopo concluído da
P0.4. A adaptação visual ao tema já homologada não constitui este módulo.
Detalhamento, priorização e implementação dependem de autorização posterior;
este registro não inicia P1 ou qualquer outra fase.

- **Duração configurável:** tempos personalizados de foco, pausas curtas e
  longas, além das opções predefinidas.
- **Ciclos:** configuração da sequência de foco/pausas, quantidade de sessões
  e intervalo até a pausa longa.
- **Notificações:** avisos visuais e sonoros opcionais para transições e fim de
  sessão, respeitando preferências e permissões do navegador.
- **Temas do temporizador:** aparência personalizável, preservando o formato
  circular, acessibilidade e consistência com os temas do Hub.
- **Perfis de foco:** conjuntos reutilizáveis de duração, ciclos, aparência e
  preferências, por exemplo para estudos ou desenvolvimento.
- **Integração com Accio Music:** iniciar, pausar, atenuar ou retomar o player
  global durante sessões, mediante configuração opcional.
- **Estatísticas:** histórico, totais e evolução de sessões por perfil,
  tarefa/projeto, considerando apenas tempo confirmado.

O módulo reutilizará o Pomodoro global, sem temporizadores independentes por
projeto. Depende do núcleo de sessões planejado em P4 e do player funcional
planejado em P5; não altera os entregáveis já aprovados da P0.4 nem promete
uma data de release.

## 3. Dependências críticas e ordem recomendada

```text
P0 Protótipo (P0.3 visual aprovada → P0.4 homologada)
  │
  ▼
P1 Fundação Rails
  │
  ├──▶ P2 Tarefas e projetos ──┬──▶ P4 Calendário + Foco
  │                            │           │
  └──▶ P3 Vault + Conhecimento ┘           ▼
  │                                      P5 Music
  └────────────────────────────────────────┴──▶ P6 Dashboard/hardening
                                               │
                                               ▼
                                              v0.1
                                               │
                        ┌──────────────────────┴────────────┐
                        ▼                                   ▼
                   P7 AccioFeed                       P8 Backups
                        └──────────────────────┬────────────┘
                                               ▼
                                              v0.2
                                               │
                                       P9/P10 futuros
```

P2 e P3 podem ter desenvolvimento parcialmente paralelo **após** estabilizar IDs, banco, Vault e regras de relacionamento; caso contrário, a aparente velocidade criará retrabalho.

## 4. Critérios de qualidade aplicáveis a toda fase

Toda fase deve terminar com evidência mínima:

1. **Escopo:** critérios previstos atendidos, excluídos documentados.
2. **Testes:** automáticos relevantes + validação manual pelo navegador real quando houver UX.
3. **Segurança:** sem segredo em commit/log/UI; testes de permissões e entradas malformadas nas superfícies afetadas.
4. **Regressão:** módulos existentes continuam funcionando; deploy/desenvolvimento reproduzível.
5. **Documentação:** alterações em PRODUCT/ARCHITECTURE/ROADMAP, se uma decisão mudar.
6. **Operação:** banco/Vault/integrações têm estados claros e erro recuperável.
7. **Evidências:** comandos de teste, resultado, limitações e riscos conhecidos resumidos em PR/commit ou relatório da fase.

**Bloqueadores de release:** perda/corrupção silenciosa de Markdown; vazamento de dados/segredos; contagem incorreta persistente de foco; sessão não autorizada; alteração/destruição de backups; indisponibilidade de integração travando núcleo local.

## 5. Fluxo de trabalho com Codex, Antigravity e skills

Seguir as ferramentas já utilizadas pelo usuário, sem tornar a execução dependente de um agente específico.

| Momento | Skill/ferramenta | Objetivo |
|---|---|---|
| Início / integração com projeto existente | `codebase-map` | Mapear fluxo e contratos reais, especialmente AccioFeed e scripts de backups |
| Implementação de cada fase | Testes locais e commit pequeno | Entregar comportamento verificável, sem misturar vários módulos |
| Antes do fechamento da fase | `verification` | Executar testes previstos, verificar critérios e relatar evidências |
| Após funcionalidades com UI ou risco importante | `bug-hunt` | Buscar falhas de borda, regressões e estados inconsistentes |
| Diante de falha real/reprodução ruim | `diagnose` | Encontrar causa raiz **antes** de corrigir |
| Fluxos navegador e responsividade | `agent-browser` (quando disponível) | Validar comportamento real, não apenas asserts unitários |
| Retomada entre agentes | ai-memory (já configurado) | Reaproveitar contexto de desenvolvimento; manter documentação no Git |

**Padrão de ciclos:** mapear → implementar teste/funcionalidade pequena → verificar → corrigir/diagnosticar → bug-hunt direcionado → registrar decisão → avançar.

Não é necessário rodar `agent-browser` em **todo commit**; priorizar mudanças de UI, navegação, formulários, player, Vault e fluxos críticos.

## 6. Registro de riscos

| Risco | Impacto | Estratégia |
|---|---|---|
| Escopo crescer antes do primeiro uso | MVP nunca pronto | Releases v0.1/v0.2 e gates com corte real |
| Editor visual corromper Markdown | Perda de conhecimento | Markdown puro primeiro; round-trip test antes de editor rico |
| Alterações externas em notas | Sobrescrita acidental | Etag/checksum, watcher, reconciliação e conflito explícito |
| Rails e SQLite com fila/background jobs | Concorrência/backup inconsistente | Spike e testes de sessão e snapshot consistentes |
| Áudio reiniciar na navegação | UX ruim | Testes reais de Turbo + player persistente |
| Autoplay bloqueado | Player parece quebrado | Interação explícita e instrução visível |
| AccioFeed API incompatível | Retrabalho | Mapear endpoints antes do cliente e versionar contrato |
| Backup parcial dar falso positivo | Confiança indevida | Estado de cada etapa + timestamps + simulações de falha |
| Exposição fora do localhost | Vazamento de notas/tarefas | Tailscale + autenticação + proxy/origins controlados |
| Dependência excessiva de LLM | Custo, privacidade e falha | Núcleo sem LLM; IA opcional e sujeita a aprovação |

## 7. Checklist de preparação para a primeira implementação

- [x] Checkout Git existente em `~/Projects/Accio-HUB`.
- [x] Documentos PRODUCT/ARCHITECTURE/ROADMAP/DESIGN_BASELINE versionados na baseline `0018bb4`.
- [x] Sistema visual Dock + Widgets aprovado na P0.3.
- [x] Protótipo navegável P0.3 existente; guia de execução em `prototype/README.md`.
- [x] Revisar o alinhamento documental da P0.4 e autorizar Etapa 2.
- [x] Concluir e validar Projetos/Conhecimento e os critérios do protótipo P0.4, conforme verificação final e homologação do usuário.
- [ ] Confirmar configuração privada do remoto e preparar README operacional para Rails em P1.
- [ ] Registrar questões abertas e resultados de prototipagem.
- [x] Compatibilidade Rails 8 + Hotwire + adapter SQLite/FTS5 conferida na P1.1. Solid Queue adiado até necessidade de indexação.
- [x] P1.0 aprovada e P1.1 autorizada explicitamente em 2026-10-11.

## 8. Próximo passo imediato

**P0.4 encerrada e homologada.** Etapas 1–6 aprovadas; Etapa 5 registrada em
`8d79186`; correções finais e Pomodoro adaptativo aprovados, com validação visual
manual no Firefox informada pelo usuário. O relatório
[P0.4_FINAL_VERIFICATION.md](P0.4_FINAL_VERIFICATION.md) conserva testes,
evidências, limites e pendências futuras. O commit final é identificado pela
tag anotada `p0.4-approved`.

P1.2C registrada em `a7f11ab`; [plano D aprovado](P1.2D_PLAN.md) em `7313e6e`; D1 em `af5e24b`, D2 em `cf95461` e D3 em `0e5323c`. Motor E1 homologado em `0c74250`; E2 aprovada com ressalvas e registrada em `a0ab717`. E3 integrada entregue para revisão, sem commit; F permanece não autorizada.
Firefox C e contraste permanecem pendentes; retenção/descarte de snapshots legados fica preferencialmente na P1.2F.
A personalização avançada do Pomodoro permanece no backlog futuro de P10.

As próximas entregas serão comparadas com a P0.3 no monitor de 27” e em tela móvel. Banco de dados, Vault real e integrações seguem nas fases definitivas, após autorização. O bootstrap de recuperação do Ubuntu foi **explicitamente adiado** e não faz parte do roadmap do Accio Hub.

### Situação D3 — 2026-10-13

P1.2D2 aprovada tecnicamente após auditoria independente e registrada em `cf95461`. P1.2D3 implementa referências persistentes e verifica a integração Projetos → Tarefas → Referências → Dashboard; entrega aprovada pelo Antigravity, conforme confirmação do usuário, sem bloqueadores confirmados; encerramento em commit autorizado. Implementação P1.2E/F não autorizada. Mantidas pendências de Firefox manual C/D, contraste inconclusivo, retenção/descarte legacy_cookie_backup (preferencialmente F) e rascunhos em memória.


### Planejamento E — 2026-10-13

D3 encerrada em `0e5323c5b823e2d2d531ad8c41c35a05a7ab2045`. [P1.2E_PLAN.md](P1.2E_PLAN.md) propõe Pomodoro global sobre FocusSession/FocusCommand existentes, checkpoints e recuperação conservadora, preservando presets 25/45 e identidade P0.4. Somente planejamento autorizado; nenhum modelo, migração, gatilho ou temporizador funcional alterado. Permanecem abertas validação Firefox C/D1/D2/D3, contraste, retenção de legacy_cookie_backup, hardening de hosts numéricos em SafeReferenceUrl e verificação operacional de backup/restauração.


### Autorização E1 — 2026-10-17

[Plano E](P1.2E_PLAN.md) aprovado com ajustes de contrato. Exclusivamente E1 autorizada: máquina de estados, persistência, comandos e recuperação de tempo; implementação sem commit até revisão. E2 (interface), E3 e F dependem de autorização própria. Sem novos modelos/migrações/gatilhos ou alterações no Ubuntu.


### Entrega E1 para revisão — 2026-10-17

Plano aprovado com ajustes registrado em `573e739`. Motor global, comandos e recuperação E1 implementados e verificados, sem commit: [relatório](P1.2E1_VERIFICATION.md). Suíte Rails: 127 testes/1.714 asserções; corridas entre processos, rollback, contenção 503 e reabertura. Os 25 gatilhos e os módulos C/D permanecem preservados. A interface continua demonstrativa; E2/E3/F aguardam autorização. Pendências anteriores não foram encerradas por testes de backend.


### Encerramento E1 e autorização E2 — 2026-10-21

E1 aprovada após auditoria independente do Antigravity, sem bloqueadores identificados; relatório existente em docs/P1.2E1_AUDIT.md. Encerramento em commit autorizado após nova verificação de 127 testes/1.714 asserções, processos, 25 gatilhos e segurança. Exclusivamente a interface compartilhada E2 está autorizada e deverá permanecer sem commit para revisão. E3/F, tag, push e merge não autorizados. Limitações anteriores preservadas.


### Entrega E2 para revisão — 2026-10-21

E1 encerrada em `0c742503fa7c1df59523b4cdabf047b5e80c19c5`, com auditoria independente aprovada. Exclusivamente E2 autorizada e implementada: Pomodoro compartilhado no Dashboard, Foco e projetos, ações de tarefas, presets, recuperação e concorrência pela API E1. Relatório [P1.2E2_VERIFICATION.md](P1.2E2_VERIFICATION.md), evidências em assets/p1.2e2/. Implementação **sem commit**, aguardando revisão. Nenhuma alteração de modelo/schema/gatilho, protótipo, Vault, backup ou serviço real. Não iniciar E3/F. Pendências anteriores, inclusive Firefox C/D/E2 e contraste inconclusivo, preservadas.

### Encerramento E2 e entrega E3 para revisão — 2026-10-21

E2 aprovada com ressalvas pelo Antigravity, sem bloqueadores confirmados, e encerrada em `a0ab717f9497d6e3bf5209f7a26b16a8c2091053`; diretriz de portabilidade em `d2dc047`, sem empacotamento. Verificação E3 exclusivamente investigativa/integrada concluída nos cenários executados: [relatório](P1.2E3_VERIFICATION.md), 93 cenários de navegador, 25 gatilhos idênticos, suíte completa127/1.728 no gate desta sessão e E1 específico24/689. Recuperação após20min mensurou três ações para aceitar/retomar; limiares intactos. Sem nova funcionalidade. Firefox, contraste, retenção de cookies, SafeReferenceUrl, rascunhos e backup/restauração operacional mantidos. E3 sem commit para revisão. Recomendada revisão para eventual autorização de F; F/P1.3 não iniciadas.

### Encerramento E3 e autorização de planejamento F — 2026-10-21

Usuário aprovou E3 com ressalvas, sem bloqueadores funcionais/de integridade documentados, e autorizou seu commit e exclusivamente planejamento F1–F5. Não há autorização de correções F. Preservar recuperação/PATCH de preset como ressalvas, contraste inconclusivo e pendências operacionais. Firefox complementar, não bloqueante para a F, sem declarar teste inexistente. Encerramento final P1.2 exige evidências e auditoria independente; P1.3, importação pessoal, tags, push, merge e distribuição dependem de autorização própria.
