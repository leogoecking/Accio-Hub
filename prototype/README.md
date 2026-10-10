# Accio Hub — Studio P0.3 (Docks + Widgets)

Protótipo visual e interativo, com direção de design totalmente reformulada a partir do feedback da P0.2. O conceito aproxima o Accio Hub de um *desktop pessoal*: dock de acesso rápido, quadros com widgets e personalização visual. **Não utiliza os serviços reais do Ubuntu.**

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

## O que NÃO funciona ainda

- AccioFeed real, Gmail, Google Calendar, status real de backups, reprodução de áudio, sincronização casa/trabalho, Vault Markdown real ou autenticação.
- Eventos da agenda e notícias são exemplos ilustrativos, sempre identificados como tais.
- Não altera ou lê scripts systemd, Restic, Docker, ai-memory ou seus arquivos do computador.

## Dados e privacidade

Os dados de tarefas/notas são armazenados no navegador usando a chave `accio-hub-p0.3-studio`. Na primeira visita, a prévia tenta importar apenas tarefas e notas locais da P0/P0.2 (chave `accio-hub-p0-v1`) se estiverem no mesmo domínio/porta. Nada é enviado para um servidor. A P0.3 não altera a chave de dados da P0.2.

As fontes **DM Sans, Space Grotesk e JetBrains Mono** são solicitadas ao Google Fonts apenas quando existe internet. O CSS contém fontes fallback para operar offline. A versão final deve preferir fontes distribuídas adequadamente e carregadas localmente, em função da política de privacidade adotada.

## Atualizar a P0.2 sem perder rollback

Se o protótipo estiver em `~/Projects/Accio-HUB/accio-hub-p0-prototipo`, faça uma cópia de segurança antes de extrair o novo ZIP:

```bash
cd ~/Projects/Accio-HUB/accio-hub-p0-prototipo
cp -a prototype prototype-p0.2-backup
unzip -o ~/Downloads/accio-hub-p0.3-docks-widgets.zip -d .
```

Se o servidor local ainda estiver rodando, basta atualizar com `Ctrl+Shift+R`. A porta de acesso permanece 4173.

## Próxima validação

- A dock deve fazer sentido para iniciar o dia.
- A grade deve ser útil sem parecer um painel genérico de métricas.
- Os diferentes tamanhos de widget devem comunicar hierarquia.
- O layout deve parecer um aplicativo pessoal e não um dashboard administrativo.
