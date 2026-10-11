# Accio Hub — P1.1: Fundação Rails

Fundação encerrada e homologada em 2026-10-11, tag anotada `p1.1-approved`.
Auditoria independente aprovada, recuperação local de senha verificada e
validação manual no Firefox confirmada pelo usuário. P1.2 não iniciada.
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

Preferências ficam em cookie criptografado HttpOnly/SameSite Strict deste navegador.
Elas não são modelo de produto e não leem o localStorage da P0.4. O navegador
mantém alterações pendentes em memória diante de falha e oferece retentativa;
recarregar com falha pendente perde somente essas preferências ainda não salvas.

Projetos, tarefas, notas, calendário, foco, Feed, backups e e-mails são fixtures
sintéticas identificadas, de leitura. Controles de criação/foco/captura explicam
a demonstração. Não há timer funcional, áudio, Vault, APIs ou migração pessoal.
Somente `users` e `auth_sessions` são tabelas funcionais. Não iniciar P1.2.

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
