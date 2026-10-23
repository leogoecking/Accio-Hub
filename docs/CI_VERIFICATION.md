> **Atualização de publicação — 23/10/2026:** o usuário autorizou registrar o CI em commit próprio e publicar a branch `p1-persistence`, incluindo o encerramento P1.2. Workflow idêntico aos bytes testados; fontes auditadas preservadas. As referências abaixo a ausência de commit/staging descrevem a entrega inicial. O resultado da execução real no GitHub deverá ser conferido após a publicação; nenhum merge ou tag autorizado.

# Accio Hub — Verificação do CI mínimo

Data: 23/10/2026. Base: `10c661f13869aa2e2855be185a0a5e416b6eb9f2`, branch `p1-persistence`. Workflow e documentação preparados **sem commit e sem staging**, para revisão. **Ainda não houve execução deste workflow no GitHub.**

## Investigação e escopo

Não existia `.github/workflows/` no checkout. A aplicação está em `rails/`; o protótipo aprovado permanece em `prototype/`. Foram examinados AGENTS, contratos de encerramento P1.2, Gemfile/lock, `.ruby-version`, configuração SQLite/test, testes, scripts de verificação e o agregador Rails `config/ci.rb`/`bin/ci`.

Dependências já declaradas: Ruby **3.3.6** (`rails/.ruby-version` contém `ruby-3.3.6`), Rails **8.1.3.1**, Bundler **2.5.22**, sqlite3 gem **2.9.6**, RuboCop/Brakeman e demais versões do `Gemfile.lock`. O lock contém a plataforma `x86_64-linux-gnu`, com binários SQLite/Nokogiri. O runner fornece ferramentas de compilação para gems nativas como bcrypt/bootsnap/nio4r; não foi acrescentada instalação apt ao workflow. Não se usa o executável de sistema `sqlite3`: os testes usam a gem e seu SQLite.

Não há package.json/lock npm necessário aos testes selecionados: **Node.js 24** executa os módulos e as bibliotecas nativas `node:assert`, `node:test`, `node:fs` e `node:vm`. Os três roteiros JavaScript do Pomodoro lançam erro/saída não zero quando uma asserção falha; não requerem DOM real ou navegador.

O `bin/ci` gerado não é invocado: agrega `bin/setup --skip-server` e `bin/importmap audit`, com escopo e dependências remotas adicionais. Os comandos necessários são chamados diretamente, sem editar esse agregador ou desabilitar testes. Nenhuma alteração em produto, dependências, modelos, schema, dados operacionais ou protótipo.

## Arquitetura do workflow

Arquivo: [ci.yml](../.github/workflows/ci.yml). Um único job **`checks`**, nome estável `Rails, SQLite and JavaScript`, em runner **GitHub-hosted `ubuntu-24.04`**, com limite de 20 minutos. Não há services, contêineres, deploy, runners locais ou job privilegiado.

Eventos:

- Push para `main` e `p1-persistence`.
- Pull request destinado a `main`, pelo evento `pull_request` comum.
- Execução manual por `workflow_dispatch`.

Não há filtro de caminhos que oculte alterações relevantes nem gatilho de tag. Execuções anteriores da mesma referência podem ser canceladas pelo grupo de concorrência. Para o disparo manual ficar disponível pelo GitHub, o arquivo também precisa existir na branch padrão; isso depende de aprovação e integração posteriores, não realizadas nesta entrega. [Referência de eventos e sintaxe](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).

As actions estão fixadas em SHA completo, conferido nos repositórios oficiais, evitando mudança implícita das tags:

| Action | SHA | Papel |
|---|---|---|
| actions/checkout v6.1.0 | `d23441a48e516b6c34aea4fa41551a30e30af803` | Checkout, sem persistir credenciais |
| ruby/setup-ruby, referência v1 | `26e5b7d197ebf60545ee9667bcbace0be11ccaec` | Ruby3.3.6, Bundler do lock e instalação/cache somente das gems |
| actions/setup-node v6.5.0 | `249970729cb0ef3589644e2896645e5dc5ba9c38` | Node24, sem cache automático de gerenciador de pacotes |

Os inputs e a resolução do lock/diretório foram conferidos nas definições oficiais de [setup-ruby](https://github.com/ruby/setup-ruby/blob/26e5b7d197ebf60545ee9667bcbace0be11ccaec/action.yml), [setup-node](https://github.com/actions/setup-node/blob/249970729cb0ef3589644e2896645e5dc5ba9c38/action.yml) e [checkout](https://github.com/actions/checkout/blob/d23441a48e516b6c34aea4fa41551a30e30af803/action.yml). Alterações futuras desses pins devem ser revisadas. Node24 permite variação de patch; o runner Ubuntu também recebe atualizações. Reprodutibilidade aqui significa contratos/versões principais controlados e gems congeladas pelo lock, não identidade binária eterna da VM.

## Jobs e comandos incluídos

Todos os `run` usam `working-directory: rails` e Bash com interrupção em falhas/pipefail, conforme o runner. `RAILS_ENV=test` e `BUNDLE_FROZEN=true`; GitHub fornece `CI=true`, que ativa eager loading no test.rb. Há checagem explícita de Ruby contra `.ruby-version` e do major Node24.

| Etapa | Comando / prova |
|---|---|
| Preparação | Diretório privado novo em RUNNER_TEMP, temporários/evidências e segredo sintético mascarado; cria `rails/tmp` quando ausente |
| Banco | `bin/rails db:schema:load` com `ACCIO_DATABASE_PATH` explícito, depois confere arquivo e modo0600 |
| Rails | `bin/rails test`: suíte completa, incluindo F5-01 e testes de segurança/administração sintéticos |
| Integridade SQLite | `bundle exec ruby script/transversal-sql-check.rb` |
| Estilo | `bin/rubocop` |
| Segurança estática | `bin/brakeman --no-pager --exit-on-warn --exit-on-error` |
| Autoload | `bin/rails zeitwerk:check` |
| JavaScript Pomodoro | `node script/focus-client-check.mjs`, `node script/focus-recovery-check.mjs`, `node script/focus-preset-check.mjs` |
| Protótipo P0.4 | `node --test ../prototype/tests/*.test.mjs` |

O roteiro SQL existente cria **dois bancos novos**, por migrações reais e schema load. Compara nome/SQL dos **25 gatilhos e 36 índices**, FKs compostas equivalentes, pragmas, índices parciais e CHECKs exercitados pelos testes SQL. Exige integrity_check=ok, foreign_key_check vazio, foreign_keys=ON, WAL/FULL e constraints habilitadas. Executa também os testes relacionais/transacionais/identidade/compatibilidade SQL do foco em ambas as preparações.

Esse roteiro tem dependência real do layout `rails/tmp/f2b-sql-*`, verificada no próprio guard. O workflow prepara `rails/tmp`; seus diretórios internos são mkdtemp0700, com caminhos de banco explícitos. As evidências são direcionadas para o diretório privado do runner por `ACCIO_QA_EVIDENCE`, evitando sobrescrever as evidências históricas em docs.

## Segurança e isolamento

- `permissions: contents: read` no workflow; demais permissões não concedidas. Checkout com `persist-credentials: false`; nenhum PAT, SSH ou segredo pessoal.
- Sem `pull_request_target`, self-hosted, publicação, upload-artifact, acesso ao Ubuntu local ou permissão de escrita no repositório.
- Ruby/gems/actions/Node são obtidos de seus distribuidores normais; CI não é offline. Não há download de referências do produto nem conexão a integrações pessoais.
- Segredo Rails novo por execução, gerado por SecureRandom, mascarado antes de ser inserido em GITHUB_ENV. Não é credencial operacional, não é argumento de processo e não é salvo em arquivo versionado.
- Banco principal e TMPDIR em diretório criado com mktemp/umask077, modo0700, fora do checkout; banco principal0600. Não se usa o banco default de storage nem DATABASE_URL pessoal.
- Testes administrativos geram suas próprias fixtures/bancos privados; as guardas F3 e a whitelist não foram alteradas. A suíte pode criar/remover seus próprios arquivos sintéticos no teardown; não chama manutenção ou restauração de uma instalação real.
- Nenhum banco, WAL, dump, cookie, chave, TAR ou evidência é enviado como artefato. O cache de setup-ruby abrange dependências Bundler, não os diretórios de dados/evidências do ensaio. Não há cache npm.
- Sem limpeza por cron, scripts de remoção operacional ou comandos administrativos contra dados existentes. A VM efêmera é descartada pelo provedor.
- Sem `continue-on-error`, skips novos ou mudanças de asserções. Um comando que falhar interrompe o job.

## Compatibilidade encontrada e ajuste do ambiente

A primeira reprodução local colocou **umask077 também na execução dos testes** e falhou em dois casos de permissões. Eles usam `Dir.mkdir(..., 0755)` para comprovar a recusa de diretórios públicos. O umask transformava0755 em0700; assim, o produto corretamente aceitava um diretório que já não era público. Experimento mínimo confirmou0700 sob077 e0755 sob022, sempre dentro de pai0700.

Correção somente no workflow: **umask022 nos passos Rails/SQL**, mantendo a criação explícita dos diretórios de isolamento0700 e banco principal0600. Isso preserva a capacidade dos testes de criar as entradas adversariais necessárias. Não se alterou política de segurança do produto ou teste para aceitar resultados diferentes. O log da tentativa inicial foi mantido localmente em `rails/tmp/ci-verification-attempt-01/`, ignorado pelo Git.

## Resultados locais

Execução dos blocos `run` do YAML com Bash `-e -o pipefail`, `CI=true`, banco novo e segredo sintético; sem executar localmente as actions de instalação/cache. Ambiente local: **Ubuntu26.04.1, Ruby3.3.6, Node24.19.0, Bundler2.5.22, gem sqlite3 2.9.6 / SQLite3.53.2**. Isso não é uma execução em ubuntu-24.04 hospedado.

| Verificação | Resultado local |
|---|---|
| YAML | Psych safe_load, sem aliases; parse aprovado |
| Contratos do workflow | Eventos/branches, um job Ubuntu, timeout, diretório, pins SHA, permissões e ausência de gatilhos privilegiados conferidos |
| Bash | `bash -n` em todos os blocos `run` |
| Rails completo com CI=true | **220 testes / 3.595 asserções**, zero falhas, erros e skips |
| SQL | Duas preparações equivalentes, **25 gatilhos / 36 índices**, integrity/FK/WAL/FULL aprovados; testes SQL em ambos |
| RuboCop | **126 arquivos**, zero infrações |
| Brakeman | Zero erros e avisos |
| Zeitwerk | Aprovado |
| JavaScript Pomodoro | **41 cenários**:11 cliente,15 recuperação e15 preset |
| Protótipo | **66 testes**, zero falhas/skips |
| Isolamento | Caminho explícito fora do checkout, diretórios0700/banco0600 e segredo sintético |
| Git | `git diff --check`; somente workflow/documentação novos, nenhum código funcional modificado |

Além do replay no checkout de trabalho, foi preparada uma cópia privada dos **arquivos versionados** de rails/prototype, sem master.key, credenciais ou configuração Bundler local. Para reproduzir a etapa de dependências localmente, essa cópia reutiliza apenas as gems já instaladas pelo caminho Bundler explícito; não houve instalação. A execução remota de setup-ruby e seu cache continua por validar no GitHub. **Resultado da cópia privada: os dez blocos `run` passaram novamente, incluindo Rails220/3.595, SQL, ferramentas, JS41 e protótipo66.** Sem chaves/credenciais locais; um diretório privado novo foi usado para os bancos. A primeira tentativa dessa cópia não encontrou gems porque a etapa setup-ruby não era executada pelo replay; a substituição local foi somente apontar Bundler para as dependências já instaladas, não instalar ou alterar gems.

Logs e verificações locais ficam em diretórios QA privados/ignorados; não são dados operacionais nem artefatos publicados. Não se acrescentou actionlint ou act ao ambiente: YAML parseado e contratos/shell verificados, mas o validador real do GitHub ainda precisa aceitar o workflow.

## Testes deliberadamente fora deste CI mínimo

| Cobertura não executada pelo workflow | Dependências / razão |
|---|---|
| Roteiros `*-browser-*.mjs`, acessibilidade/axe, comparação visual e F5 integrado | agent-browser/Chromium, servidor loopback, fixtures/credenciais próprias, clocks e portas QA; não declarados como dependências do projeto |
| Roteiros de navegador em prototype/tests | Navegador real/servidor/perfil; o glob `*.test.mjs` seleciona somente os testes Node homologados |
| Firefox e revisão humana/tecnologias assistivas | Não substituídos pelos testes Node/Rack; permanecem pendentes |
| Roteiros completos multiprocesso C/D/E/F3 | Fixtures e sincronização/locks/processos/sinais, alguns gravam em diretórios históricos por padrão; não executados indiscriminadamente em todo push |
| `admin-reset-check.py` | Terminal/PTY e banco sintético próprio; testes Rails de reset/login/revogação continuam incluídos |
| `bin/importmap audit` | Auditoria remota adicional do agregador; não faz parte do gate solicitado |

**Os 220 testes Rails não são testes de navegador.** A suíte inclui os testes F5-01 e de backup/restore/exportação/limpeza sintéticos; isso não substitui o roteiro F5 de17 checkpoints ou a prova multiprocesso integral. Nenhum roteiro existente foi removido/desativado.

Se for necessário automatizar a homologação visual/UI em seguida, recomenda-se **um job separado**, com agent-browser/Chromium fixados, dependências explícitas, fixtures e portas isoladas e resultados redigidos. Sua implantação depende de um escopo próprio; não foi adicionado um job que presumisse funcionar no runner com a configuração do Ubuntu pessoal.

## Critérios de aprovação e limites

1. Revisão deste diff sem alteração funcional, segredo, banco ou permissão de escrita.
2. Após autorização de commit/push, primeira execução **real** no GitHub provisiona Ruby/Node/gems, aceita a sintaxe e passa todos os passos em ubuntu-24.04, sem skips novos.
3. Conferir a execução em push nas branches autorizadas e em PR para main; validar manual quando o workflow estiver disponível na branch padrão.
4. Confirmar os totais e a integridade SQL nos logs remotos; divergências devem ser investigadas, sem flexibilizar fingerprints, testes ou guardas.
5. Não usar um CI verde como nova homologação visual/Firefox, prova de backup operacional ou liberação do nível C.

**Conclusão:** implementação preparada e comandos validados localmente; aprovação no GitHub permanece pendente de execução real. P1.3 não iniciada, nenhum dado pessoal usado e nenhum commit, staging, push, merge ou tag realizado nesta entrega.


## Integridade da entrega

SHA-256 de `.github/workflows/ci.yml`: `3ec5b6d822cc37a8caf7caa845447a8406143bdfc1fa1cc82d3fd53e67a1f570`. Apenas esse arquivo e este documento foram adicionados. HEAD e branch preservados, índice vazio. As asserções e fontes homologadas da P1.2 continuam intactas. Logs do replay final no checkout de trabalho e da cópia privada permanecem somente em áreas QA locais ignoradas, sem upload.
