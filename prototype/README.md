# Accio Hub — Studio P0.3 (Docks + Widgets)

Protótipo visual e interativo, com direção de design totalmente reformulada a partir do feedback da P0.2. O conceito aproxima o Accio Hub de um *desktop pessoal*: dock de acesso rápido, quadros com widgets e personalização visual. **Não utiliza os serviços reais do Ubuntu.**

**Baseline visual aprovada:** P0.3, commit `0018bb4`. Referência:
[DESIGN_BASELINE.md](../docs/DESIGN_BASELINE.md). A fase atual é P0.4; somente
a Etapa 1 documental está em execução. Os arquivos HTML/CSS/JavaScript continuam
na P0.3. A aprovação visual não comprova todos os comportamentos ou breakpoints.

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
- Notas Markdown demonstrativas: criar, abrir e editar (somente no `localStorage`; **não** cria arquivos `.md` reais).
- Pomodoro: iniciar, pausar, reiniciar, alternar duração 25/45, contagem por timestamps (sessão não representa trabalho efetivo se navegador/PC ficar inativo).
- Projetos demonstrativos, navegação pelos módulos, busca rápida (Ctrl+K), captura rápida (Ctrl+Shift+N), barra Accio Music apenas visual.
- Relógio local; interface adaptável para telas pequenas.

Projetos são quatro definições fixas: seus atalhos abrem Tarefas, Conhecimento
e Foco gerais, sem filtro/vínculo ao projeto selecionado. Conhecimento possui
lista plana e textarea Markdown, sem árvore de pastas, prévia ou backlinks.
A busca rápida encontra telas e títulos de tarefas/notas, não o corpo das notas.
O Accio Music é global e opcional, com visibilidade e painel expandido; não há
reprodução de áudio. Ocultar aplicativos na dock do board não os remove da dock
lateral nem desativa módulos. Essas descrições refletem o código atual;
validação visual das próximas alterações continua necessária.

## O que NÃO funciona ainda

- AccioFeed real, Gmail, Google Calendar, status real de backups, reprodução de áudio, sincronização casa/trabalho, Vault Markdown real ou autenticação.
- Eventos da agenda e notícias são exemplos ilustrativos, sempre identificados como tais.
- Não altera ou lê scripts systemd, Restic, Docker, ai-memory ou seus arquivos do computador.

## Dados e privacidade

Os dados de tarefas/notas são armazenados no navegador usando a chave `accio-hub-p0.3-studio`. Na primeira visita, a prévia tenta importar apenas tarefas e notas locais da P0/P0.2 (chave `accio-hub-p0-v1`) se estiverem no mesmo domínio/porta. Nada é enviado para um servidor. A P0.3 não altera a chave de dados da P0.2.

Preferências de temas, fundos, widgets e dock também ficam nessa chave.
O localStorage pertence à origem do navegador (protocolo, host e porta);
mudar de origem não transfere os dados. Não há migrações versionadas hoje.
Na evolução da P0.4, mudanças de schema deverão preservar dados e preferências,
com migrações versionadas, não destrutivas e testáveis, e IDs estáveis para
projetos/notas. Não limpar o armazenamento para atualizar o protótipo.

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

Antes de iniciar a Etapa 2, aguardar aprovação do usuário sobre a Etapa 1.

## Verificação das próximas alterações de interface

- Utilizar `verification` e testes automatizados relevantes, além de sintaxe.
- Comparar visualmente com o commit `0018bb4`, usando `agent-browser` quando disponível.
- Verificar desktop/mobile, claro/escuro, teclado, captura, busca e personalização.
- Exercitar recarga, migrações, relações e o fluxo projeto → tarefa → nota → retorno.
- Preservar hierarquia dos widgets, dock e aparência de desktop pessoal aprovada.
- Registrar resultados e limitações; não marcar funcionalidade aprovada sem evidência.
