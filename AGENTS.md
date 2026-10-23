# Accio Hub — Agent Instructions

## Projeto

Accio Hub é um aplicativo pessoal de produtividade,
conhecimento e informações.

Documentação oficial:
- docs/PRODUCT.md
- docs/ARCHITECTURE.md
- docs/ROADMAP.md
- docs/DESIGN_BASELINE.md

Leia esses documentos antes de implementar funcionalidades.
O design baseline rege a identidade visual; PRODUCT e ARCHITECTURE
mantêm os requisitos funcionais e a arquitetura definitiva planejada.

## Identidade visual aprovada

A versão P0.3 é nossa referência visual, aprovada no commit 0018bb4.
Consulte docs/DESIGN_BASELINE.md ao evoluir a interface.

Direção:
- Interface Dock + Widgets.
- Inspiração no Homarr, sem excesso de elementos.
- Tipografia com personalidade.
- Temas e cores personalizáveis.
- Widgets reorganizáveis e redimensionáveis.
- Navegação compacta.
- Experiência responsiva.

Não substituir por um dashboard convencional.
Não redesenhar a identidade visual sem aprovação.

O diretório prototype/ contém a referência aprovada.
Preservar navegação, temas, fontes, fundos, personalização, widgets
e Accio Music. Personalização é requisito central do produto.
Na P0.3, alterar tamanho significa escolher spans predefinidos;
redimensionamento livre ainda é uma evolução futura.

## Protótipo atual e compatibilidade

- HTML, CSS e JavaScript sem backend, em prototype/.
- Estado persistido no localStorage pela chave accio-hub-p0.3-studio.
- Schema explícito 4, migração com cópia recuperável e proteção de dados incompatíveis.
- Tarefas e notas demonstrativas editáveis; biblioteca de projetos com criação, edição,
  pesquisa, filtros, favoritos e arquivamento reversível; espaços internos com
  tarefas, notas compartilhadas por projectIds, referências e Pomodoro global.
- Projetos, tarefas e notas têm IDs estáveis; relações usam IDs.
- Conhecimento usa pastas por ID, coleções, tags, favoritos, busca, editor Markdown
  com prévia segura/leitura e autosave; sem Vault real.
- Accio Music é global e opcional, com barra visual e painel expandido;
  ainda não reproduz áudio.
- Aprovação visual não equivale a validação funcional de todos os módulos.

Mudanças futuras de dados devem preservar informações e preferências existentes,
com migrações versionadas, não destrutivas e testáveis quando necessárias.
Projetos e notas devem possuir IDs estáveis, independentes de nomes e caminhos,
preparando o futuro Vault Markdown. Evitar refatorações grandes sem necessidade.

## Stack planejada

- Ruby on Rails 8
- Hotwire / Stimulus
- CSS homologado preservado; Tailwind adiado conforme P1.0 aprovada
- SQLite
- PWA

P0.4 homologada, P1.0 arquitetural aprovada e P1.1 encerrada e homologada.
P1.2A/P1.2B/P1.2C aprovadas tecnicamente; planejamento P1.2D aprovado; D1 aprovada tecnicamente com ressalvas e registrada; D2/D3 aprovadas; E1/E2/E3 aprovadas, E3 registrada em35a6671. Plano P1.2F aprovado com ajustes; F1b aprovada com ressalvas e registrada em 7ebfaeb. F1c aprovada com ressalvas e registrada em b262ce6. Exclusivamente F2a autorizada, sem commit da implementação. F2b/F3/F4/F5/P1.3 não autorizadas.
A aprovação visual da P0.3 não autoriza iniciar Rails na P0.4.

## Arquitetura

### Diretriz de portabilidade

O Accio Hub é um aplicativo pessoal local-first, prioritariamente desenvolvido
para Linux, com possibilidade futura de execução no Windows e distribuição para
outras pessoas por instalações independentes. Preservar a separação entre
Rails/SQLite, interface web e possíveis contêineres desktop. Cada instalação
possui seus próprios dados e credenciais, sem compartilhamento implícito.
Não introduzir dependências desnecessárias de caminhos absolutos ou APIs
específicas de um sistema operacional. Esta diretriz não autoriza Electron,
Tauri, PWA, empacotamento ou refatorações preventivas nesta etapa.

- Aplicativo modular.
- Notas Markdown reais como fonte da verdade.
- SQLite para tarefas, projetos e metadados.
- AccioFeed permanece independente.
- ai-memory permanece independente.
- Monitoramento de backups somente de leitura.
- Accio Music como player global opcional.

## Segurança

- Nunca incluir credenciais no repositório.
- Nunca modificar backups reais sem autorização.
- Não executar comandos administrativos desnecessários.
- Não expor serviços locais publicamente.
- Não modificar configurações globais do Ubuntu sem autorização.

## Desenvolvimento

- Implementar em etapas pequenas.
- Preservar funcionalidades existentes.
- Evitar dependências desnecessárias.
- Executar testes após alterações.
- Validar visualmente interfaces no navegador.
- Investigar causas antes de corrigir bugs.

## Skills

Utilizar quando apropriado:
- codebase-map
- verification
- bug-hunt
- diagnose
- agent-browser

## Fluxo de trabalho

1. Ler a documentação.
2. Inspecionar o código existente.
3. Apresentar plano.
4. Implementar após aprovação.
5. Executar testes.
6. Verificar regressões.
7. Resumir mudanças e pendências.

## Fase atual

P1.2C — Encerramento técnico aprovado em 2026-10-12 após auditoria independente do Antigravity.
P1.2D1 encerrada tecnicamente em af5e24bab30d90bbb89c19b9798b69b20d1d9185 após aprovação independente com ressalvas.
P1.2D2 — Tarefas Persistentes aprovada após auditoria independente sem bloqueadores, registrada em cf9546122255f5aeba5b56f5625d4b01cbf260af.
P1.2D3 — Referências Persistentes e Integração aprovada após auditoria independente sem bloqueadores; registrada em 0e5323c5b823e2d2d531ad8c41c35a05a7ab2045.

- Aplicação em `rails/`; preservar integralmente `prototype/`.
- Rails 8, Hotwire/Turbo/Stimulus, SQLite, ERB, Importmap e CSS aprovado.
- Autenticação local por sessão, um administrador, sem cadastro público.
- Execução somente em loopback; credenciais fora do Git.
- Modelos de projetos, tarefas, referências, preferências, Dock, widgets, foco e recibos técnicos; integridade SQL e versões.
- Preferências autenticadas, Dock e widgets persistem no SQLite; bootstrap autenticado/CSRF e controle de versão do agregado.
- Cookie legado é somente candidato de importação; cookie mínimo do login deriva de dados confirmados e nunca inicializa o banco.
- Biblioteca e espaço de projetos utilizam SQLite; tarefas persistentes globais/contextuais aprovadas na D2; referências reais do projeto com criação/edição, versões e URLs seguras aprovadas na D3. Conhecimento aguarda Vault na P1.3; interface compartilhada do foco integrada na E2 para revisão; demais módulos não conectados continuam demonstrativos.
- Formulários/comandos de projetos e tarefas conectados; sem exclusão física, nota em SQLite, Vault, API externa ou importação pessoal. Motor de foco E1 homologado; interface E2 em revisão.
- Migrações e testes somente em bancos novos, temporários e sintéticos nesta entrega.
- P1.2B registrada em `ddf671585a7f1908b40a63d89417cb378454e218`; nenhuma tag/merge.
- P1.2C registrada em `a7f11ab`; planejamento D aprovado registrado em `7313e6e`. D1 registrada em `af5e24b`; D2 registrada em `cf95461`; D3 registrada em `0e5323c`; plano E aprovado com ajustes; exclusivamente motor E1 autorizado, sem commit da implementação, tag, push ou merge.
- Pendências C: Firefox manual, contraste inconclusivo e retenção/descarte de legacy_cookie_backup (preferencialmente P1.2F).
- D3 aprovada. Plano E aprovado com ajustes; exclusivamente E1 autorizada, E2/E3/F dependem de revisão e autorização; nenhum schema/modelo/gatilho alterado nesta entrega.

P1.1 homologada em 2026-10-11, tag `p1.1-approved`, com auditoria independente,
recuperação local via `bin/rails admin:reset` e validação manual no Firefox.
Esse histórico não constitui validação de interface das fases posteriores.

O plano aprovado está em [docs/P1.0_ARCHITECTURE_PLAN.md](docs/P1.0_ARCHITECTURE_PLAN.md).
A P1.2A aprovada está em [docs/P1.2A_SQLITE_PLAN.md](docs/P1.2A_SQLITE_PLAN.md).
Verificações: [P1.1](docs/P1.1_FOUNDATION_VERIFICATION.md) [P1.2B](docs/P1.2B_VERIFICATION.md) e [P1.2C](docs/P1.2C_VERIFICATION.md).

P0.4 encerrada e homologada: tag anotada `p0.4-approved`, incluindo validação
visual manual no Firefox e Pomodoro adaptativo. A identidade P0.3 permanece
referenciada por `0018bb4`. Histórico e evidências em
[docs/P0.4_FINAL_VERIFICATION.md](docs/P0.4_FINAL_VERIFICATION.md).

Planejamento E aprovado com ajustes em 2026-10-17: [docs/P1.2E_PLAN.md](docs/P1.2E_PLAN.md). Somente o motor E1 está autorizado; manter sua implementação sem commit e a interface demonstrativa até aprovação da E2.


P1.2E1 — Motor implementado para revisão em 2026-10-17, sem commit da implementação. Plano aprovado com ajustes registrado em `573e739d23b50dcd0111fe891687e7ca37e378c6`. Serviços FocusCommands/FocusTime e endpoints JSON usam os modelos/25 gatilhos B intactos; recuperação parcial em paused e recibos imutáveis por ID/versão. Nenhuma interface de foco conectada. E2/E3/F dependem de aprovação. Evidências: [docs/P1.2E1_VERIFICATION.md](docs/P1.2E1_VERIFICATION.md).


### Encerramento E1 e autorização E2 — 2026-10-21

E1 aprovada após auditoria independente do Antigravity, sem bloqueadores identificados; relatório existente em docs/P1.2E1_AUDIT.md. Encerramento em commit autorizado após nova verificação de 127 testes/1.714 asserções, processos, 25 gatilhos e segurança. Exclusivamente a interface compartilhada E2 está autorizada e deverá permanecer sem commit para revisão. E3/F, tag, push e merge não autorizados. Limitações anteriores preservadas.


### P1.2E2 — Interface compartilhada para revisão — 2026-10-21

E1 aprovada pela auditoria independente, sem bloqueadores identificados, e registrada em `0c742503fa7c1df59523b4cdabf047b5e80c19c5` após 127 testes/1.714 asserções e verificações de encerramento. Commit documental `573e739` preservado. E2 conecta exclusivamente a interface ERB/Stimulus aos endpoints homologados: Dashboard, Foco e projetos usam a mesma sessão SQLite; relógio visual monotônico, polling visível 15s, versões, intenções e recibos, recuperação explícita e preset versionado. Sem estado do timer em cookies/localStorage ou gravação por segundo. Alterações E2 permanecem **sem commit**, aguardando revisão. Modelos/schema/migrações/25 gatilhos, backend E1, protótipo e DTO de aparência intactos. Relatório: [docs/P1.2E2_VERIFICATION.md](docs/P1.2E2_VERIFICATION.md). E3/F não iniciadas. Sem tag/push/merge/importação pessoal. Firefox C/D/E2, contraste inconclusivo, retenção de cookies, SafeReferenceUrl, rascunhos e backup/restauração operacional continuam pendentes.

### Encerramento E2 e autorização E3 — 2026-10-21

E2 aprovada pelo Antigravity como APROVADO COM RESSALVAS, sem bloqueadores confirmados; relatório existente em docs/P1.2E2_AUDIT.md. Encerramento autorizado após nova verificação de 127 testes/1.728 asserções, 11 testes JS, processos, rollback, contenção, 25 gatilhos e segurança. Preservar Firefox pendente, contraste inconclusivo e assimetria de retentativa do preset (409 após resposta perdida pós-commit), além das limitações anteriores. Exclusivamente E3 investigativa/integrada autorizada, com bancos/perfis sintéticos; relatório e eventuais correções sem commit para revisão. F/P1.3, tag, push e merge não autorizados. As seções anteriores são registros históricos e não ampliam o escopo atual.

### E3 integrada para revisão — 2026-10-21

E2 encerrada em `a0ab717f9497d6e3bf5209f7a26b16a8c2091053`; diretriz de portabilidade registrada separadamente em `d2dc047d63c6eade280e2a27abbe80e415c652e4`. [Verificação E3](docs/P1.2E3_VERIFICATION.md): 93 cenários de navegador, E1 específico 24 testes/689 asserções, 11 JS, 25 gatilhos idênticos e integridade SQLite. Suíte completa reexecutada no gate E2 desta sessão: 127/1.728; nenhuma alteração funcional depois. Recuperação após 20 minutos sintéticos preserva checkpoint e exige três ações para aceitar/retomar; registrar atrito cotidiano, sem mudar limiares15/60/5. Firefox pendente e contraste inconclusivo mantidos, além das demais ressalvas. Somente QA/documentação/evidências E3 alterados, **sem commit**; aguardar revisão, sem iniciar F/P1.3, tag, push ou merge.

### Encerramento E3 e planejamento F — 2026-10-21

E3 revisada e APROVADA COM RESSALVAS, conforme parecer informado pelo usuário; sem bloqueadores funcionais ou de integridade nos cenários documentados. Commit de encerramento autorizado, preservando testes e evidências. Exclusivamente planejamento F1–F5 autorizado, sem alterar aplicação/modelos/schema/gatilhos, limites15/60/5 ou contratos E1; documento F sem commit para revisão. Firefox passa a ser complementar e não bloqueante para a F, mantendo resultado histórico não testado. Auditoria independente continua obrigatória antes do encerramento final da P1.2. Sem implementação F/P1.3, dados pessoais, descarte de cookies/backups, tag, push, merge ou distribuição.

### Plano F aprovado com ajustes — autorização F1b

E3 encerrada em `35a66711b57e5afe2c11fc2ca5bd9716128d9383`. [Plano F](docs/P1.2F_PLAN.md) aprovado com ajustes: exclusivamente F1b alternativa B autorizada, resolve/resume separados e idempotentes, duas transações aceitas, confirmação da própria resolução e versão fixa antes de retomar. C/D e F1c/F2/F3/F4/F5 não autorizados. Descarte real de legacy_cookie_backup proibido; prazo30dias ainda não aprovado. Firefox complementar; backups/restauração somente sintéticos até autorização específica, sem iniciar F3. Registrar plano em commit documental; implementação F1b sem commit para revisão/auditoria. Sem alterações de backend E1/modelos/schema/gatilhos/limites15/60/5, push, merge, tag ou dados pessoais.

### F1b entregue para revisão — 2026-10-21

Plano aprovado registrado no commit exclusivamente documental `30c69750ccb1a9f884b53cc3f7d0bd17ad97fa22`. Exclusivamente F1b alternativa B implementada, **sem commit**: conferir intervalo e aceitar estimativa/continuar em duas ações humanas. Coordenador de interface exige recibo próprio de resolve antes de resume, com envelopes/versões fixos e retentativas explícitas; duas transações, sem continuação após reload. Candidato integral exige revisão explícita da conclusão. Backend E1, modelos, schema, migrações, 25 gatilhos, CSS e protótipo intactos. [Relatório F1b](docs/P1.2F1B_VERIFICATION.md): 127 testes Rails/1.728 asserções, 26 cenários JS e 77 cenários de navegador aprovados em dados sintéticos. Contraste inconclusivo e Firefox não executado permanecem separados de aprovação. Aguardar revisão/auditoria independente; F1c/F2/F3/F4/F5, descarte real de snapshots, push, tag, merge e dados pessoais não autorizados.


### Encerramento F1b e autorização F1c

F1b aprovada após auditoria independente em docs/P1.2F1B_AUDIT.md: **APROVADO COM RESSALVAS, SEM BLOQUEADORES**. Encerramento autorizado após revisão e reexecução sintética de Rails 127/1.728, JS 26, processos, 25 gatilhos e segurança; preservadas duas transações, contraste inconclusivo e Firefox complementar. Reexecuções da auditoria arquivadas separadamente, sem substituir evidências históricas. Exclusivamente F1c autorizada: feedback/reconciliação do PATCH preset, preservando CAS do agregado C, sem novos recibos/tabelas/endpoints ou alteração E1. Implementação F1c sem commit para revisão/auditoria. F2/F3/F4/F5 não autorizadas; sem tag/push/merge/dados pessoais.


### F1c entregue para revisão e auditoria independente

F1b encerrada em `7ebfaebe16027b9338ed63bf89d11d570779a7f8`, após parecer independente APROVADO COM RESSALVAS, SEM BLOQUEADORES. Exclusivamente F1c implementada **sem commit**: PATCH preset conserva CAS C; diferencia sucesso HTTP, operação incerta, 409 e valor atual igual/diferente sem atribuir autoria; GET indisponível conserva envelope para gesto explícito. Sem novos recibos/tabelas/endpoints ou mudança E1. Versão/rascunho de aparência protegidos. Corrigidos acesso a controlador desconectado após Turbo e foco perdido após retry reconciliado. [Verificação F1c](docs/P1.2F1C_VERIFICATION.md): Rails 127/1.728, JS 41, navegador 94; 25 gatilhos, backend, CSS, protótipo e focus_recovery.js intactos. Contraste inconclusivo e Firefox complementar não executado preservados. Aguardar revisão/auditoria; F2/F3/F4/F5 não autorizadas; sem tag/push/merge/importação/descarte pessoal.


### Encerramento F1c e autorização exclusiva F2a — 2026-10-22

F1c aprovada pela auditoria independente em docs/P1.2F1C_AUDIT.md: **APROVADO COM RESSALVAS, SEM BLOQUEADORES**. Encerramento autorizado após hashes de nove fontes/QA coincidentes e nova verificação sintética Rails 127/1.728, JS 41, processos, 25 gatilhos e segurança. Preservar ressalvas de CAS/autoria, contraste e Firefox complementar. Exclusivamente F2a autorizada: hardening local de SafeReferenceUrl, contratos D3 e apresentação segura de legados, sem DNS/HTTP para destinos. Não alterar modelos/schema/migrações/gatilhos. Implementação F2a sem commit para revisão/auditoria; F2b/F3/F4/F5, tag/push/merge, dados pessoais e serviços Ubuntu não autorizados.


### F2a entregue para revisão e auditoria independente — 2026-10-22

F1c encerrada em `b262ce6813d78a21d9454bb25e4e8a30b6f09ab8`, após parecer independente APROVADO COM RESSALVAS, SEM BLOQUEADORES. Exclusivamente F2a implementada **sem commit**: SafeReferenceUrl rejeita endereços numéricos ambíguos e autoridade incompatível; preserva DNS legítimo, IPv4 canônico, IPv6, portas e string original. Legado incompatível continua consultável como texto escapado, sem href, com correção explícita. Sem DNS/HTTP para destinos ou normalização automática. [Verificação F2a](docs/P1.2F2A_VERIFICATION.md): Rails 133/2.555, matriz Ruby/Chromium 114 URLs, browser 43, JS foco 41; 25 gatilhos, 36 índices e FKs preservados. Modelos/schema/migrações, E1/F1b/F1c/C, CSS e protótipo intactos. Contraste inconclusivo e Firefox complementar não executado mantidos. Aguardar revisão/auditoria; F2b/F3/F4/F5, tag/push/merge/importação/descarte pessoal não autorizados.


### Encerramento F2a e autorização exclusiva F2b — 2026-10-22

F2a aprovada pelo Antigravity: APROVADO COM RESSALVAS, SEM BLOQUEADORES. Sete hashes da entrega conferidos; esclarecimento documental de IPv4 na verificação F2a sem alterar o relatório independente original. Gate sintético Rails 133/2.555, JS41, processos/contenção/rollback e ferramentas aprovado. Exclusivamente investigação transversal F2b autorizada, sem correções automáticas, aplicação/modelos/schema/migrações/gatilhos novos. Novos testes/docs/evidências F2b sem commit. Preservar ressalvas, sem F3/F4/F5, dados pessoais, tag/push/merge ou serviços Ubuntu.


### F2b — investigação transversal para revisão — 2026-10-22

F2a encerrada em `07bb2cff06169224a1e07b584e6ececc5f88b357`, após aprovação independente com ressalvas e esclarecimento documental de compatibilidade IPv4, sem editar auditoria original. F2b somente QA/documentação, **sem commit**: Rails final146/2.940, com um erro de reprodução confirmado F2B-01 (intenção de projeto como objeto gera500); não corrigido por falta de autorização específica. SQL em migrações/schema load:25 gatilhos/36 índices idênticos e FKs equivalentes;21 testes/243 asserções em cada banco;24 disputas multiprocesso e5 contenções reais503; JS41; browser F1b14, F1c18 e transversal9 (um é reprodução de defeito). Roteiro legado D3 interrompido em duas tentativas, cobertura inconclusiva F2B-COV-01, sem mascarar como aprovação. [Relatório F2b](docs/P1.2F2B_VERIFICATION.md). Aplicação/modelos/schema/migrações/gatilhos/protótipo intactos. Aguardar revisão/auditoria e autorização de correções; sem F3/F4/F5, descarte/importação pessoal, tag/push/merge ou serviços Ubuntu.


### Correções direcionadas F2b para revisão — 2026-10-22

Autorizadas exclusivamente F2B-01 e recuperação de cobertura F2B-COV-01. ProjectCommands agora recusa tipos não String pela rejeição InvalidIntent existente (422), sem alterar assinatura/CSRF/transações. Clique contextual D3 corrigido somente no roteiro: remoção da rolagem redundante antes do clique nativo, após trilha comprovar ponteiro fora do link. Aplicação visual intacta;33/33 D3,7 F2a e9 transversais aprovados; Rails148/3.050, JS41,25 gatilhos/36 índices preservados. [Relatório de correções](docs/P1.2F2B_CORRECTIONS_VERIFICATION.md). Relatórios/evidências anteriores preservados; F2b inteira **sem commit e sem staging**. Aguardar revisão/auditoria; sem F3/F4/F5, tag/push/merge ou dados pessoais.

### Encerramento F2b e autorização exclusiva F3a — 2026-10-22

F2b aprovada pelo Antigravity como **APROVADO COM RESSALVAS, SEM BLOQUEADORES** em docs/P1.2F2B_AUDIT.md. Oito fontes auditadas idênticas; gate Rails148/3.050, JS41 e ferramentas revalidado, preservando reproduções anteriores e cobertura D3. Encerramento específico autorizado. Exclusivamente F3a: inventário/exportação privada/verificação e round-trip de legacy_cookie_backup, somente sintético com banco explícito, sem descarte/TTL ou alteração do bootstrap/modelos/schema/gatilhos. Implementação F3a sem commit e sem staging para auditoria. F3b/F3c/F4/F5/P1.3, dados pessoais, tag/push/merge e backups/serviços Ubuntu não autorizados. Ressalvas anteriores preservadas.

### F3a — inventário/exportação sintética para revisão — 2026-10-22

F2b encerrada em `dcef7015b5171068283ef82ada96e6c0252c4146`, após auditoria independente APROVADO COM RESSALVAS, SEM BLOQUEADORES e gate148/3.050. Exclusivamente F3a implementada sem commit e sem staging: tarefas locais de inventário/exportação/verificação, gate de fixture/banco sintético explícitos fora do checkout, leitura READONLY em SELECT único, JSON original/candidatos/unknown fields preservados, arquivo privado versionado e publicação sem overwrite. Recuperação demonstrada apenas em outro perfil sintético vazio, com revalidação C; opacos não aplicados. [Relatório F3a](docs/P1.2F3A_VERIFICATION.md). Bootstrap C, modelos/schema/migrações/gatilhos/frontend intactos. Sem descarte/TTL, backup SQLite inteiro, restore operacional, endpoints, jobs ou serviços. Aguardar revisão/auditoria; F3b/F3c/F4/F5/P1.3 e dados pessoais/tag/push/merge não autorizados.

### Encerramento F3a e autorização exclusiva F3b — 2026-10-22

F3a aprovada pelo Antigravity como APROVADO COM RESSALVAS, SEM BLOQUEADORES, conforme docs/P1.2F3A_AUDIT.md. Sete hashes da entrega coincidem; gate Rails167/3.208, CLI/quatro concorrências, JS41 e ferramentas reexecutado. Encerramento específico autorizado. Exclusivamente F3b: backup consistente do SQLite inteiro e restauração em banco/processo sintéticos novos, guardas equivalentes à F3a, sem overwrite, invalidação de AuthSessions somente na cópia antes de HTTP, sem secrets reais, alteração de modelos/schema/gatilhos, backups/serviços Ubuntu ou dados pessoais. Implementação F3b sem commit e sem staging. F3c/F4/F5/P1.3, tag/push/merge não autorizados; ressalvas anteriores preservadas.

### F3b — backup e restauração sintética para revisão — 2026-10-22

F3a encerrada em `c3c96d15279ce262fec868609e55d133fb58bd33`, após auditoria APROVADO COM RESSALVAS, SEM BLOQUEADORES e gate167/3.208. Exclusivamente F3b implementada sem commit e sem staging: Online Backup API, origem READONLY em transação fixada, pacote TAR privado/verificado, restauração em novo SQLite/processo sintético, fidelidade conferida antes de revogar AuthSessions somente na cópia. Chave de runtime nova fora do pacote e launcher QA guardado impedem reaproveitamento de cookies antigos no procedimento; fonte/senha/histórico preservados. [Relatório F3b](docs/P1.2F3B_VERIFICATION.md): Rails187/3.348, vinte testes novos/140 asserções, 25 gatilhos/36 índices, concorrência real e reinício HTTP. Sem modelos/schema/migrações/gatilhos alterados, backend C/E1/frontend intactos, sem dados pessoais/backups/serviços Ubuntu. Aguardar revisão/auditoria; F3c/F4/F5/P1.3, limpeza/TTL, backup automático, tag/push/merge não autorizados.

### Encerramento F3b e autorização exclusiva F3c — 2026-10-22

F3b aprovada pelo Antigravity como **APROVADO COM RESSALVAS, SEM BLOQUEADORES**, onze hashes coincidentes e gate187/3.348 reexecutado. Restore permanece sintético e dependente de fixture/banco de origem preexistentes; recuperação operacional sem origem continua pendente, sem autorização de implementação. Exclusivamente F3c autorizada: CLI administrativa para inventário/limpeza confirmada de AuthSessions expiradas, somente test com fixture e banco sintéticos explícitos; sem mudar política, modelos/schema/gatilhos ou F3b. Implementação F3c sem commit e sem staging. F4/F5/P1.3, dados pessoais, tag/push/merge e serviços/backups Ubuntu não autorizados.

### F3c — limpeza administrativa sintética para revisão — 2026-10-22

F3b encerrada em `4cb6fc5f39abe79914bfc6843ca2219fe4978eb9`, após auditoria APROVADO COM RESSALVAS, SEM BLOQUEADORES e gate187/3.348. Exclusivamente F3c implementada **sem commit e sem staging**: CLI com inventário/dry-run padrão e confirmação explícita; guarda test/fixture/banco privados, cutoff único, somente expires_at classificável, transação atômica e anomalias preservadas. [Verificação F3c](docs/P1.2F3C_VERIFICATION.md): Rails203/3.452, específicos16/104, concorrência real/rollback/SIGKILL,25 gatilhos/36 índices e autenticação preservados; F3a/F3b revalidadas sem alteração. Não é manutenção pessoal/agendada. Restore F3b continua sintético e dependente da origem, sem homologação de recuperação operacional. Modelos/schema/migrações/UI/C/E1/protótipo intactos. Aguardar revisão/auditoria; F4/F5/P1.3, expurgo/TTL, dados pessoais, tag/push/merge e serviços/backups Ubuntu não autorizados.

### Encerramento F3c e autorização exclusiva F4 — 2026-10-22

F3c aprovada pelo Antigravity como APROVADO COM RESSALVAS, SEM BLOQUEADORES; oito hashes idênticos, gate203/3.452 e QA administrativo reexecutados. Esclarecimentos JSON F3a/TAR F3b e confirmação ausente versus inválida registrados sem editar auditoria/código. Exclusivamente F4 autorizada: inventário e medição de acessibilidade, correções CSS/ERB/Stimulus localizadas de defeitos confirmados, sem redesign, mudança de domínio/modelos/schema/gatilhos ou mecanismos F2/F3. F4 sem commit e sem staging para revisão/auditoria. F5/P1.3, dados pessoais, tag/push/merge e serviços/backups Ubuntu não autorizados.

### Encerramento F3c e entrega F4 para revisão — 2026-10-22

F3c aprovada pelo Antigravity como **APROVADO COM RESSALVAS, SEM BLOQUEADORES**, oito hashes coincidentes e gate203/3.452 revalidado; encerrada em `11d15fc9957c2b5b78173bf3f3a87e10c3428caa`. Relatório original preservado; esclarecido que F3a exporta JSON, F3b TAR, e confirmação F3c ausente significa dry-run, enquanto valor explicitamente inválido é recusado. Exclusivamente F4 autorizada e entregue **sem commit e sem staging**: foreground/bordas/foco, restauração de foco após erros e feedback sem resultados, com identidade/layout P0.4 preservados. [Verificação F4](docs/P1.2F4_VERIFICATION.md): Rails203/3.452, JS41, protótipo66, navegador E2 37/F1b14/F1c18/D3 33, teclado16 e335 auditorias axe sem violações; contraste incomplete permanece separado de medições dirigidas/exceções. Quarenta medições de bordas/foco aprovadas e comparação P0.4/5larguras/2temas. Modelos/schema/migrações/25gatilhos/36índices, C/E1/F1/F2/F3 e protótipo intactos. Firefox complementar não executado, leitor de tela/revisão humana e limites de contraste permanecem; sem alegação WCAG AA global. Restore F3b segue sintético dependente da origem; retenção/descarte ainda pendentes. Aguardar auditoria independente; não iniciar F5/P1.3, tag/push/merge ou operações pessoais.

### Encerramento F4 autorizado e preparação F5 — 2026-10-23

F4 aprovada pelo Antigravity com ressalvas, sem bloqueadores;22 hashes idênticos. Reconciliação documental:154 fail nas três primeiras matrizes,167 incluindo hover;56 logotipos/109 pontos/2 separadores pertencem ao universo completo. Acervo integral preservado em arquivo privado persistente fora do Git, com manifesto/hash e seleção curada rastreável; auditoria original/código aprovados intactos. Encerramento F4 em commit autorizado após gates. Somente após esse commit, F5 investigativa/sintética G1–G10 autorizada, sem correções automáticas nem ampliação funcional. Distinguir implementação técnica, homologação sintética e liberação pessoal; recuperação operacional sem origem e custódia/chaves continuam pendentes, sem implementação autorizada. F5 sem commit/staging para revisão e auditoria; não iniciar P1.3, dados pessoais, tag/push/merge ou operações Ubuntu.
