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
- Tarefas e notas demonstrativas editáveis; projetos fixos.
- Conhecimento usa lista plana e editor de texto Markdown, sem Vault real.
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
- Tailwind CSS
- SQLite
- PWA

A implementação definitiva começará após a aprovação
do protótipo navegável e autorização para iniciar P1.
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

P0.4 — Evolução do protótipo navegável.

Prioridades:
1. Preservar a interface P0.3.
2. Detalhar e implementar Projetos.
3. Detalhar e implementar Conhecimento.
4. Validar interações e responsividade.

Não iniciar Rails nesta fase.
Não conectar APIs externas nesta fase.
Não implementar armazenamento real em arquivos Markdown nesta fase.

O plano incremental da P0.4 está em docs/ROADMAP.md.
Autorização atual: exclusivamente Etapa 1 — Alinhamento da documentação.
Após verificá-la e apresentar arquivos, mudanças, divergências e pendências,
aguardar aprovação do usuário antes de iniciar a Etapa 2.
