# Accio Hub — Fundação Rails e relacional SQLite

Fundação encerrada e homologada em 2026-10-11, tag anotada `p1.1-approved`.
Auditoria independente aprovada, recuperação local de senha verificada e
validação manual no Firefox confirmada pelo usuário.
P1.2A/B/C aprovadas tecnicamente; B registrada em `ddf6715`, C em `a7f11ab`. Planejamento D aprovado em `7313e6e`;
exclusivamente D1 autorizada, implementada e em revisão sem commit. Firefox C, contraste e retenção dos snapshots
legados (preferencialmente P1.2F) permanecem pendentes.
Referência completa: P0.4 homologada; identidade Dock + Widgets: `0018bb4`.

## Ambiente e instalação local

Ruby 3.3.6, Rails 8.1.3.1, Bundler 2.5.22, sqlite3 2.9.6 (SQLite 3.53.2).
Não instalar gems globais. Dentro de `rails/`:

```sh
bundle config set --local path vendor/bundle
bundle install
bin/rails db:prepare
bin/admin
bin/dev
```

`bin/admin` solicita e-mail e senha sem eco e cria somente a conta única.
Não existe conta/senha padrão, cadastro público ou recuperação por e-mail.
Senhas exigem 12 caracteres; o banco guarda somente o digest bcrypt.
O caminho padrão do ambiente de desenvolvimento é `storage/development.sqlite3`,
ignorado pelo Git. A sessão autenticada expira após 12 horas e é revogada no logout.

### Recuperação local da senha

No terminal administrativo, em `rails/`, executar:

```sh
bin/rails admin:reset
```

Usar o mesmo ambiente Rails e caminho de banco da instalação administrada
(`RAILS_ENV` e `ACCIO_DATABASE_PATH`, quando configurados). O comando exige terminal
interativo, verifica se a conta existe e solicita a nova senha e sua confirmação
sem eco. Não fornecer senha em argumentos ou variáveis de ambiente.

As validações existentes continuam aplicadas, incluindo mínimo de 12 caracteres
e limite de 72 bytes do bcrypt. Entrada vazia, confirmação diferente, cancelamento
ou falha de armazenamento não concluem a redefinição. A troca de senha e a revogação
de todas as sessões são realizadas na mesma transação. Após sucesso, entrar
novamente com a nova senha; não há endpoint HTTP de recuperação.

Limpeza periódica de sessões expiradas fica para P1.2. Compatibilidade com endereços
IPv4-mapped IPv6 será avaliada quando houver necessidade de suporte dual-stack.
Nenhuma dessas duas melhorias foi implementada.

O servidor inicia em `http://127.0.0.1:3000`. `bin/rails server -p 3111` permite
outra porta mantendo loopback. Bindings públicos são rejeitados pelo launcher;
Puma também está configurado para loopback e um middleware confere o par do socket,
sem confiar em headers encaminhados. Nenhum serviço do Ubuntu é configurado.

Para produção local, definir `ACCIO_DATABASE_PATH` fora do checkout e fornecer
`SECRET_KEY_BASE` por ambiente privado fora do Git. O app permanece HTTP loopback;
acesso remoto, proxy e TLS exigem fase e aprovação específicas. Não usar esta
fundação como implantação remota. Credenciais, `.env*`, master key, bancos,
logs, caches e bundles locais são ignorados. Scripts de backup existentes intactos.

## Entrega e limites

Operacionais: autenticação, logout, rotas protegidas, navegação Turbo, busca de
aplicativos/atalhos, temas, quatro fundos, destaque, ordem/visibilidade/tamanho
predefinido dos widgets, Dock, painel de Personalizar e Configurações, Music
visual global expansível e opcional. Arraste tem controles equivalentes por teclado.

Preferências autenticadas são persistidas em SQLite por um agregado versionado.
A primeira inicialização usa POST autenticado/CSRF; migra cookie P1.1 válido e
preserva cópia/digest. Cookie diferente do banco ou inválido exige revisão explícita;
nenhum default sobrescreve registros existentes. O cookie do login guarda somente
tema/fundo/destaque confirmados e nunca é importado. Nenhum localStorage P0.4 é lido.

Conflitos preservam edição local e oferecem reaplicação por campo ou descarte
explícito. Contenção e falhas oferecem retentativa. Alterações pendentes ficam na
memória da aba, com aviso antes de sair; fechar/recarregar forçadamente pode perdê-las.

A Biblioteca, os espaços e o widget de Projetos consultam registros reais do SQLite.
Projetos podem ser criados, editados, favoritados, ativados/pausados e arquivados/restaurados.
Arquivados são somente leitura; nenhum projeto é excluído fisicamente. Os filtros
compartilham a versão do agregado de aparência. Tarefas/referências vinculadas são
apenas consulta; Conhecimento indica a futura integração P1.3. Os módulos globais de
tarefas, notas, calendário, foco, Feed, backups e e-mails continuam demonstrativos. Controles de criação/foco/captura explicam
a demonstração. Não há timer funcional, áudio, Vault, APIs ou migração pessoal.
Na P1.2B foram acrescentadas oito tabelas de domínio, ainda sem conexão com essas
telas de produto. Na C, apenas as preferências foram conectadas ao SQLite. Na D1, projetos foram conectados com tokens assinados de intenção e versões de registro. O contrato e a verificação estão em
[P1.2A](../docs/P1.2A_SQLITE_PLAN.md) e [P1.2B](../docs/P1.2B_VERIFICATION.md) e [P1.2C](../docs/P1.2C_VERIFICATION.md) e [P1.2D1](../docs/P1.2D1_VERIFICATION.md).
Não executar `db:prepare` em instalação existente/pessoal para esta revisão;
as verificações desta entrega usam somente bancos temporários sintéticos.

## Estrutura

- `app/views/studio/`: shell e partials ERB; sete fragmentos de widgets.
- `app/javascript/controllers/studio_controller.js`: interações, foco e salvamento.
- `app/presenters/studio.rb`: normalização e composição de demonstrações.
- `app/controllers/concerns/authentication.rb`: sessão local.
- `app/assets/stylesheets/studio.css`: cópia exata do CSS P0.4.
- `app/assets/fonts/`: fontes com três licenças OFL, sem downloads em execução.
- `config/prototype_assets.json`: hashes da origem aprovada.
- `script/reuse_prototype.mjs`: reprodução explícita das fixtures sintéticas/CSS;
  Node é necessário somente para esse script de manutenção e QA, não em produção.

Não executar o script de reaproveitamento após alterar fixtures sem revisar o diff.
Ele lê apenas defaults do código, nunca armazenamento do navegador.

## Verificação

Para verificar a P1.2C e a regressão da P1.2B com bancos privados temporários:

```sh
bundle exec ruby script/preferences-check.rb
```

O script cria os bancos em `tmp/` e verifica a suíte Rails, inicialização/edição
concorrentes, reabertura, os 25 gatilhos e contenção real com HTTP 503.
Não aceita caminho de banco pessoal e grava evidências sintéticas em
`../docs/assets/p1.2c/`. O script B permanece como histórico; não sobrescrever suas
evidências homologadas durante a revisão C. Para outros comandos que
acessam banco, utilizar `RAILS_ENV=test` e `ACCIO_DATABASE_PATH` apontando para
banco sintético isolado. Os comandos da fundação abaixo continuam disponíveis:

```sh
bin/rails test
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --no-pager
bin/rails assets:precompile
bin/rails assets:clobber # depois da conferência em desenvolvimento
python3 script/admin-reset-check.py # terminal real, banco temporário sintético
```

Regressão do protótipo, a partir da raiz: `node --test prototype/tests/*.test.mjs`.
QA de interface com agent-browser: `script/foundation-browser-check.mjs`, conforme
preparação sintética descrita no [relatório](../docs/P1.1_FOUNDATION_VERIFICATION.md).
Esse script utiliza uma sessão própria, exige credenciais sintéticas em arquivo
ignorado e não deve receber uma origem/profile de dados pessoais.

Histórico, evidências, matriz visual e pendências no relatório de verificação.

### Navegador isolado — P1.2C

Com agent-browser disponível, executar de `rails/`:

```sh
bundle exec ruby script/preferences-browser-setup.rb
```

Esse comando cria dois bancos novos e credenciais sintéticas privadas em `tmp/`.
Iniciar cada servidor em um terminal separado, usando o diretório indicado:

```sh
P12C_DIR="$(cat tmp/p12c-workspace)"
RAILS_ENV=development ACCIO_DATABASE_PATH="$P12C_DIR/synthetic.sqlite3" bin/rails server -p 3122 --pid "$P12C_DIR/server.pid"
```

```sh
P12C_DIR="$(cat tmp/p12c-workspace)"
RAILS_ENV=development ACCIO_DATABASE_PATH="$P12C_DIR/empty.sqlite3" bin/rails server -p 3123 --pid "$P12C_DIR/empty-server.pid"
```

Em outro terminal, a partir da raiz do repositório:

```sh
node rails/script/preferences-browser-check.mjs
node rails/script/preferences-browser-recovery-check.mjs
node rails/script/preferences-browser-restart-check.mjs capture
```

Após `capture`, interromper somente o servidor sintético 3122 e reiniciá-lo com
o mesmo comando, banco e diretório. Então executar:

```sh
node rails/script/preferences-browser-restart-check.mjs verify
```

Não repetir o setup entre captura e conferência. Os scripts usam sessões próprias,
recebem a senha por stdin e salvam capturas/resultados sem credenciais em
`docs/assets/p1.2c/`. O cenário de cookie inválido exige que `empty.sqlite3` ainda
não tenha preferências; uma repetição completa requer novo setup e novos servidores.
Encerrar os dois servidores ao terminar. Firefox não foi exercitado por esses scripts.

## Verificação isolada da D1

Em `rails/`, `ruby script/projects-check.rb` cria e remove um banco temporário,
executa toda a suíte e verifica duas requisições concorrentes, contenção HTTP e
reabertura. Não aponta para o banco de desenvolvimento padrão.

`ruby script/projects-browser-setup.rb` prepara somente NOVOS bancos privados em
`rails/tmp/p12d-browser-*` e guarda credenciais sintéticas em arquivo 0600 ignorado.
`tmp/p12d-workspace` identifica o diretório dessa execução. Para os scripts de navegador,
iniciar Rails em loopback/3124 usando `ACCIO_DATABASE_PATH` desse diretório, executar
`node script/projects-browser-check.mjs`, preparar vínculos exclusivamente sintéticos
com `ACCIO_QA_WORKSPACE` e `bin/rails runner script/projects-browser-seed.rb`, e executar
`node script/projects-browser-additional-check.mjs`. A comparação adicional usa um
servidor estático local/3112 para `prototype/`, sem modificar seu conteúdo.

As credenciais são lidas por stdin para preencher o navegador; não copiá-las para
argumentos, documentação ou Git. Nunca usar esses scripts sobre uma instalação pessoal.
A entrega e seus limites estão em `docs/P1.2D1_VERIFICATION.md` na raiz do repositório.

## P1.2D2 — tarefas persistentes em revisão

D1 foi encerrada tecnicamente em `af5e24bab30d90bbb89c19b9798b69b20d1d9185`, com ressalvas mantidas. D2 utiliza o modelo Task existente, sem alterações no schema/gatilhos: `/tasks`, formulários globais/contextuais, prioridade, conclusão/reabertura, mudança de projeto pelo editor global e widgets/contadores compartilhados. Referências, foco e Vault seguem nas etapas próprias.

Verificação exclusivamente sintética:

```bash
cd rails
ruby script/tasks-check.rb
ruby script/tasks-browser-setup.rb
```

O setup imprime um diretório privado novo e grava `tmp/p12d2-workspace`. Inicie Rails com `ACCIO_DATABASE_PATH` apontando para `synthetic.sqlite3` desse diretório, `-b 127.0.0.1 -p 3125` e PID/log dentro dele; nunca use banco pessoal. `node script/tasks-browser-check.mjs` usa agent-browser em sessão própria. Roteiros adicionais, conferência do banco e reinício estão documentados em [P1.2D2_VERIFICATION.md](../docs/P1.2D2_VERIFICATION.md). Credenciais aleatórias ficam somente no diretório privado ignorado. D2 permanece sem commit até revisão.

### Referências do projeto — P1.2D3

Criação/edição em `/projects/:project_uid/references`, com IDs públicos codificados e projeto fixado pela rota autenticada. Tipos Link (URL obrigatória) e Material (URL opcional), sem upload/exclusão. Somente HTTP/HTTPS, host válido e sem credenciais; endereços incompatíveis existentes são exibidos com link desativado. Política local de parsing, sem downloads/preview/DNS. Índices/modelos/gatilhos B intactos.

QA: `bundle exec ruby script/references-check.rb` cria um banco novo sintético temporário, exercita a suíte e processos concorrentes. `ruby script/references-browser-setup.rb` prepara bancos novos privados; somente esses caminhos podem alimentar QA de navegador em loopback 3126. Roteiros `references-browser-check.mjs`, `references-browser-additional-check.mjs`, `references-browser-restart-check.mjs` e `references-browser-state-check.rb` registram evidências em `docs/assets/p1.2d3/`. Não utilizar banco pessoal. Relatório: `docs/P1.2D3_VERIFICATION.md`. D3 aprovada após auditoria independente, conforme confirmação do usuário; encerramento em commit autorizado. Implementação E/F não iniciada.
