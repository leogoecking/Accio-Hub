# Accio Hub — Design Baseline

## Versão aprovada

P0.3 — Docks + Widgets

Status: APROVADA VISUALMENTE

Commit de referência: `0018bb4` (`0018bb4b3c7a7760f9905c5d5dc163dea7e0919c`).

Documentos relacionados: [PRODUCT.md](PRODUCT.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [ROADMAP.md](ROADMAP.md).

Este documento rege a identidade visual. A aprovação não certifica todos os
comportamentos, acessibilidade ou responsividade do protótipo, nem conclui P0
ou autoriza iniciar a implementação definitiva.

## Conceito

O Accio Hub deve transmitir a sensação de um
desktop pessoal, e não de um dashboard corporativo.

Referências:
- Homarr: docks, widgets e personalização.
- Super Productivity: organização e produtividade.
- Obsidian/Notion: experiência de conhecimento.

## Identidade

- Dock de aplicativos como elemento principal.
- Widgets interativos e personalizáveis.
- Fundos e temas configuráveis.
- Tipografia expressiva.
- Boa hierarquia visual.
- Animações funcionais e discretas.
- Evitar excesso de cards uniformes.
- Evitar banners grandes sem utilidade.
- Evitar aparência genérica de dashboards.

## Personalização

Requisito central do produto.

O usuário deve poder:
- Reorganizar widgets.
- Alterar tamanhos.
- Ocultar módulos.
- Personalizar cores e fundos.
- Reorganizar aplicativos da dock.

Na P0.3, widgets e aplicativos podem ser reordenados por arraste ou botões.
Os tamanhos dos widgets são predefinidos na grade de 12 colunas.
Ocultar widgets e aplicativos da dock do board já é possível; a dock lateral
continua disponível. Ocultar um atalho não desativa o módulo.
Redimensionamento livre e layouts por contexto são evoluções futuras.

## Referência de implementação

Diretório: prototype/

Qualquer mudança visual significativa deve ser
comparada com a P0.3 aprovada.

Elementos a preservar na comparação:

- Dock lateral compacta e dock de aplicativos do board.
- Grade com hierarquia e diferentes tamanhos de widgets.
- Temas claro/escuro, cor de destaque e quatro fundos em CSS.
- Fontes DM Sans, Space Grotesk e JetBrains Mono, com fallbacks.
- Cabeçalho, busca, captura e drawer de personalização.
- Accio Music global e opcional: barra superior, expansão e visibilidade.

A implementação atual do Accio Music é demonstrativa, sem reprodução de áudio.
Suas regras funcionais futuras permanecem em [PRODUCT.md](PRODUCT.md), §4.7.

## Fase atual

P0.4 encerrada e homologada, tag anotada `p0.4-approved`. A referência de
identidade permanece P0.3, commit `0018bb4`; a referência completa incorpora
as correções de acessibilidade e o Pomodoro adaptativo aprovados na P0.4,
incluindo validação visual manual no Firefox.

P1.0 arquitetural aprovada; P1.1 encerrada e homologada em 2026-10-11,
tag anotada `p1.1-approved`. O usuário confirmou validação manual no Firefox
da aplicação Rails; evidência informada, separada da automação Chromium.
Reproduzir o shell em `rails/`, preservando classes, geometria, tokens,
responsividade, fontes, temas e backgrounds. O CSS aprovado será preservado,
sem conversão para Tailwind. `prototype/` continua intacto como referência.

Os módulos de produto da fundação são demonstrativos de leitura; autenticação,
navegação e personalização fundamental devem funcionar. Nenhum redesenho ou
mudança de identidade foi autorizado. Verificação e diferenças em
[P1.1_FOUNDATION_VERIFICATION.md](P1.1_FOUNDATION_VERIFICATION.md).
