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
P1.2A/P1.2B/P1.2C aprovadas tecnicamente; planejamento P1.2D aprovado; D1 aprovada tecnicamente com ressalvas e registrada; D2/D3 aprovadas; planejamento P1.2E aprovado com ajustes; exclusivamente E1 autorizada.
A aprovação visual da P0.3 não autoriza iniciar Rails na P0.4.

## Arquitetura

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
- Biblioteca e espaço de projetos utilizam SQLite; tarefas persistentes globais/contextuais aprovadas na D2; referências reais do projeto com criação/edição, versões e URLs seguras aprovadas na D3. Conhecimento aguarda Vault na P1.3; foco e os demais módulos continuam demonstrativos.
- Formulários/comandos de projetos e tarefas conectados; sem exclusão física, timer funcional, nota em SQLite, Vault, API externa ou importação pessoal.
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
