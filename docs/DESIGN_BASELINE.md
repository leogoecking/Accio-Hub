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

P0.4 — Projetos e Conhecimento.

A identidade da P0.3 deve ser preservada enquanto
as novas telas são desenvolvidas.

Projetos e Conhecimento evoluirão com componentes existentes, dados no
localStorage, IDs estáveis e migrações compatíveis. Rails, APIs externas e
Vault com arquivos reais estão fora desta fase.

A Etapa 1 documental foi aprovada e registrada no commit `1d83387`.
A Etapa 2 foi aprovada e registrada em `cd3589d`. Está autorizada exclusivamente
a Etapa 3 — Biblioteca de Projetos. Cards com ícones e cores personalizados
reutilizam os tokens existentes; o shell e o board permanecem a referência P0.3.
O espaço interno dos projetos (Etapa 4) depende de nova aprovação, conforme
[ROADMAP.md](ROADMAP.md).
