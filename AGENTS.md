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
P1.2 depende de nova autorização, conforme docs/P1.0_ARCHITECTURE_PLAN.md.
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

P1.1 — Fundação Rails, encerrada e homologada em 2026-10-11, tag anotada `p1.1-approved`.

- Aplicação em `rails/`; preservar integralmente `prototype/`.
- Rails 8, Hotwire/Turbo/Stimulus, SQLite, ERB, Importmap e CSS aprovado.
- Autenticação local por sessão, um administrador, sem cadastro público.
- Execução somente em loopback; credenciais fora do Git.
- Shell Dock + Widgets, temas, fontes, fundos, Music demonstrativo e personalização fundamental.
- Somente modelos de autenticação. Projetos, tarefas, notas, foco e integrações são demonstrações identificadas e somente de leitura.
- Nenhuma migração de dados pessoais, Vault real, API externa ou P1.2 nesta entrega.
- Auditoria independente do Antigravity aprovada; recuperação local via `bin/rails admin:reset` verificada.
- Validação manual no Firefox confirmada pelo usuário, separada dos testes automatizados.
- Encerramento autorizado em commit; P1.2 não iniciada e exige nova autorização.

O plano aprovado está em [docs/P1.0_ARCHITECTURE_PLAN.md](docs/P1.0_ARCHITECTURE_PLAN.md).
A verificação está em [docs/P1.1_FOUNDATION_VERIFICATION.md](docs/P1.1_FOUNDATION_VERIFICATION.md).

P0.4 encerrada e homologada: tag anotada `p0.4-approved`, incluindo validação
visual manual no Firefox e Pomodoro adaptativo. A identidade P0.3 permanece
referenciada por `0018bb4`. Histórico e evidências em
[docs/P0.4_FINAL_VERIFICATION.md](docs/P0.4_FINAL_VERIFICATION.md).
