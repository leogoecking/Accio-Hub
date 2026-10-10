# Accio Hub — Agent Instructions

## Projeto

Accio Hub é um aplicativo pessoal de produtividade,
conhecimento e informações.

Documentação oficial:
- docs/PRODUCT.md
- docs/ARCHITECTURE.md
- docs/ROADMAP.md

Leia esses documentos antes de implementar funcionalidades.

## Identidade visual aprovada

A versão P0.3 é nossa referência visual.

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

## Stack planejada

- Ruby on Rails 8
- Hotwire / Stimulus
- Tailwind CSS
- SQLite
- PWA

A implementação definitiva começará após a aprovação
do protótipo navegável.

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
