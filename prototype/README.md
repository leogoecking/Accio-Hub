# Accio Hub — Studio P0.3 (Docks + Widgets)

Protótipo visual e interativo, com direção de design totalmente reformulada a partir do feedback da P0.2. O conceito aproxima o Accio Hub de um *desktop pessoal*: dock de acesso rápido, quadros com widgets e personalização visual. **Não utiliza os serviços reais do Ubuntu.**

**Baseline visual aprovada:** P0.3, commit `0018bb4`. Referência:
[DESIGN_BASELINE.md](../docs/DESIGN_BASELINE.md). A fase atual é P0.4; Etapa 1
aprovada e commitada (`1d83387`), Etapa 2 aprovada (`cd3589d`) e execução restrita
à Etapa 5 (Accio Knowledge), após aprovação da Etapa 4 (`e88d772`). A identidade continua P0.3. A aprovação visual não comprova todos
os comportamentos ou breakpoints.

## Executar

Na raiz do projeto que contém a pasta `prototype/`:

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory "$PWD/prototype"
```

Abra `http://127.0.0.1:4173/`.

## O que funciona nesta prévia

- Dock lateral com as áreas principais e dock de aplicativos do board.
- **Organizar board**: arrastar widgets e aplicativos da dock para mudar a ordem. No widget, `↔` altera o tamanho. A opção **Aparência** permite ocultar e reordenar ambos também por botões acessíveis.
- **Aparência**: 4 papéis de parede em CSS, cor de destaque, tema claro/escuro, visibilidade e tamanho de widgets.
- Tarefas: marcar como concluída, criar novas.
- Accio Knowledge: pastas/subpastas, coleções, tags, favoritos, busca, editor Markdown com prévia segura/leitura e autosave (somente no `localStorage`; **não** cria arquivos `.md` reais).
- Pomodoro: iniciar, pausar, reiniciar, alternar duração 25/45, contagem por timestamps (sessão não representa trabalho efetivo se navegador/PC ficar inativo).
- Biblioteca de Projetos em grade: pesquisa por nome/descrição, filtros Todos/Ativos/Pausados/Arquivados, favoritos e ordem por nome/atividade.
- Criar/editar projetos com nome, descrição, ícone e cor; pausar/ativar, arquivar e restaurar ao status anterior.
- Navegação pelos módulos, busca rápida (Ctrl+K), captura rápida (Ctrl+Shift+N), barra Accio Music apenas visual.
- Relógio local; interface adaptável para telas pequenas.

Projetos têm IDs estáveis. Quatro exemplos são inseridos somente na primeira
inicialização sem dados. Renomear e arquivar preserva vínculos com tarefas/notas.
O widget reflete os projetos ativos, seus nomes/ícones/cores e contagens por ID.
Favoritos, filtros e ordem são persistidos; pesquisa permanece na sessão.
Atividade recente inclui criação/edição/status e mudanças em tarefas/notas
vinculadas; histórico ausente não é inventado. Cada projeto possui Visão Geral,
Tarefas, Conhecimento e Referências; Pomodoro global único. Accio Knowledge usa
as mesmas notas compartilhadas, com painéis recolhíveis e vínculos por ID.
Não há backlinks/grafo completo. Diário é uma coleção, não um calendário.
A busca rápida encontra telas, tarefas e notas por título, conteúdo e tags.
O Accio Music é global e opcional, com visibilidade e painel expandido; não há
reprodução de áudio. Ocultar aplicativos na dock do board não os remove da dock
lateral nem desativa módulos. Essas descrições refletem o código atual;
validação visual das próximas alterações continua necessária.

## O que NÃO funciona ainda

- AccioFeed real, Gmail, Google Calendar, status real de backups, reprodução de áudio, sincronização casa/trabalho, Vault Markdown real ou autenticação.
- Eventos da agenda e notícias são exemplos ilustrativos, sempre identificados como tais.
- Não altera ou lê scripts systemd, Restic, Docker, ai-memory ou seus arquivos do computador.

## Dados e privacidade

Os dados de projetos/tarefas/notas são armazenados no navegador usando a chave
`accio-hub-p0.3-studio`, com `schemaVersion: 4`. A chave antiga `accio-hub-p0-v1`
continua intacta: quando necessário, suas tarefas/notas preenchem somente
coleções ausentes. Nada é enviado para um servidor. Exemplos iniciais são
inseridos somente quando não existe estado em nenhuma das duas chaves.

Preferências de temas, fundos, widgets e dock também ficam nessa chave.
O localStorage pertence à origem do navegador (protocolo, host e porta);
mudar de origem não transfere os dados. A migração versionada preserva IDs e
conteúdo legados, atribui IDs faltantes e grava uma cópia do JSON anterior em
`accio-hub-p0.3-studio:backup:pre-schema-4` antes de substituir seu formato.
Cópias diferentes recebem sufixo único e nunca são sobrescritas. A migração aceita
P0.3 sem versão e schemas 1, 2 e 3; backups anteriores ficam intactos.

JSON inválido, formatos incompatíveis e versões desconhecidas/futuras bloqueiam
gravações. O protótipo abre um estado vazio em memória, com aviso visível, e
mantém o armazenamento intacto. Falhas de gravação também exibem aviso: as
alterações só existem na sessão até uma gravação posterior bem-sucedida.
Não limpar o armazenamento para atualizar o protótipo. Modelo, recuperação e
evidências em [P0.4_STATE_VERIFICATION.md](../docs/P0.4_STATE_VERIFICATION.md).

As fontes **DM Sans, Space Grotesk e JetBrains Mono** são solicitadas ao Google Fonts apenas quando existe internet. O CSS contém fontes fallback para operar offline. A versão final deve preferir fontes distribuídas adequadamente e carregadas localmente, em função da política de privacidade adotada.

## Evolução da P0.4

O trabalho continua neste checkout, preservando a P0.3 no histórico Git.
O fluxo antigo de extrair ZIP sobre a P0.2 não é necessário para este repositório.
Plano incremental e critérios em [ROADMAP.md](../docs/ROADMAP.md).

Projetos e Conhecimento evoluirão com os componentes existentes. Personalização
é central: manter navegação, docks, widgets, temas, fundos, fontes e Accio Music.
Pastas, relações e edição continuarão demonstrativas no navegador; Rails,
APIs externas e armazenamento real em `.md` estão fora da P0.4.
O futuro Vault terá arquivos Markdown como fonte de verdade e índice derivado,
conforme [ARCHITECTURE.md](../docs/ARCHITECTURE.md), §4.

A Etapa 4 foi aprovada e commitada em `e88d772`. A Etapa 5 foi homologada após
auditoria e correção do BUG-01, com registro em commit autorizado.
Não iniciar a Etapa 6 sem nova aprovação. Evidências em
[P0.4_KNOWLEDGE_VERIFICATION.md](../docs/P0.4_KNOWLEDGE_VERIFICATION.md). Evidências da biblioteca
em [P0.4_PROJECTS_VERIFICATION.md](../docs/P0.4_PROJECTS_VERIFICATION.md).

## Testes do estado e da biblioteca

Sem instalar dependências:

```bash
node --test --test-isolation=none prototype/tests/state.test.mjs prototype/tests/projects.test.mjs
```

Para a suíte de navegador, iniciar um servidor na **raiz** do checkout:

```bash
python3 -m http.server 4174 --bind 127.0.0.1
node prototype/tests/browser-check.mjs http://127.0.0.1:4174
node prototype/tests/projects-browser-check.mjs http://127.0.0.1:4174
```

Requer `agent-browser` e Chromium já instalados. No ambiente Ubuntu usado na
verificação, foi necessário executar com `ACCIO_BROWSER_NO_SANDBOX=1`; essa
opção afeta somente o navegador isolado de teste e não é necessária em ambientes
com sandbox Chromium funcional. A suíte usa dados sintéticos e uma sessão própria,
compara com `0018bb4` e produz screenshots/snapshots em `tmp/p04-verification/`
e `tmp/p04-projects-verification/` (ignorados pelo Git). Não manipula dados de sessões pessoais.

## Verificação das próximas alterações de interface

- Utilizar `verification` e testes automatizados relevantes, além de sintaxe.
- Comparar visualmente com o commit `0018bb4`, usando `agent-browser` quando disponível.
- Verificar desktop/mobile, claro/escuro, teclado, captura, busca e personalização.
- Exercitar recarga, migrações, relações e o fluxo projeto → tarefa → nota → retorno.
- Preservar hierarquia dos widgets, dock e aparência de desktop pessoal aprovada.
- Registrar resultados e limitações; não marcar funcionalidade aprovada sem evidência.

## Verificar o Accio Knowledge

```bash
node --test prototype/tests/*.test.mjs
python3 -m http.server 4174 --bind 127.0.0.1
# Em outro terminal, a partir da raiz:
node prototype/tests/knowledge-browser-check.mjs http://127.0.0.1:4174
```

Os cenários usam `agent-browser` instalado, sessões isoladas e dados sintéticos.
Neste Ubuntu, quando Chromium exigir, usar `ACCIO_BROWSER_NO_SANDBOX=1` nos
scripts de navegador. As suítes de regressão `browser-check.mjs`,
`projects-browser-check.mjs` e `project-space-browser-check.mjs` usam a mesma URL.
Evidências ficam em `tmp/p04-knowledge-verification/`.

O autosave tenta gravar após 450 ms sem digitação e também na navegação.
“Salvar agora” e Ctrl+S permitem retentativa. Em falhas, preserve a sessão ou copie
o Markdown antes de recarregar: o rascunho não salvo ainda só existe em memória.
A prévia suporta títulos, listas simples, links HTTP/HTTPS, citações, ênfase e
blocos de código; HTML bruto fica como texto. Sem tabelas, anexos ou paridade
completa com CommonMark. Pastas e notas continuam no localStorage.
