# F5-01 — Verificação prévia da correção condicionada

Data: 2026-10-23. Branch `p1-persistence`. HEAD **`7c1cea40cc180a3c03f5521d83219690294cdb1b`**. **Correção não aplicada: condição de interrupção acionada na reprodução dos quatro schemas.** Nenhum staging, commit, push, merge ou tag. F5 permanece bloqueada; P1.3 não iniciada.

## 1. Autorização e referência efetiva

F5-01 foi confirmado pela auditoria independente do Antigravity em `P1.2F5_01_AUDIT.md`. O usuário esclareceu que o contrato versionado no HEAD é a fonte de verdade, autorizando adicionar exclusivamente `b42e0bb5…` somente após reproduzir os quatro casos e confirmar o fingerprint/estrutura. Determinou interromper sem modificar o contrato se algum hash observado fosse diferente ou houvesse divergência estrutural adicional.

O contrato atual e seus campos continuam byte a byte iguais ao HEAD. SHA-256 do arquivo: **`31fcfafc5fd0deaedeef454a4380c9365882a9bdedd186c2fa657b291df3f367`**. Diff de produção: **vazio**.

## 2. Errata documental, sem editar a auditoria original

A seção4 do relatório do Antigravity transcreve `format=accio-sqlite-backup-contract`, apenas um fingerprint e `migrations_sha256=24a35ea6…`. O checkout efetivo contém:

- `format`: `accio-sqlite-schema-contract`;
- `version`:1;
- fingerprints originais, na ordem:
  1. `621ee16d32be40ae482a50c92cc8a3fc55fc92d5aa27186e34506e1b77f529e8`;
  2. `c8752c5aabda1b9064750d8982648e89eaacfb4d68d117f36c3ad1e77ca542f7`;
- `migrations_sha256`: `07cf9e1c10867429a2242b9d683b8554bc185f4de1030605e1aeebe9a94e7993`;
- cinco migrações, demais propriedades e ordem dos campos preservados.

O JSON bruto da auditoria já confirma o digest de migrações `07cf9e1c…`, em desacordo com aquela transcrição. Sua alegação de paridade literal entre migrate/schema load também **não foi reproduzida** neste ensaio independente. Não se atribui causa ao ensaio do auditor sem evidência adicional. O relatório e os artefatos originais não foram modificados.

## 3. Reprodução anterior a qualquer edição

Novo roteiro QA: `rails/script/backup-schema-contract-check.rb`. Quatro bancos/fixtures sintéticos novos, em diretórios privados fora do checkout, criados por cruzamento de ambiente e tarefa. Conta/dados pessoais não usados. A criação usa test/development; cada comando administrativo usa **RAILS_ENV=test**, banco explícito e fixture privada existente. Arquivos SQLite0600 e diretórios0700.

`db:migrate` recebe `SCHEMA` apontando para arquivo privado de saída, impedindo alteração de `rails/db/schema.rb`. `db:schema:load` lê o schema versionado. Uma primeira execução de QA passou incorretamente o caminho de saída também como entrada do schema load e foi recusada; seu log foi preservado. O roteiro foi corrigido somente nesse parâmetro de QA e a matriz foi refeita com quatro bancos novos. Nenhum arquivo de produção foi alterado em qualquer tentativa.

Comando, executado em `rails/`:

```sh
ACCIO_QA_PHASE=before ACCIO_QA_EVIDENCE=<pasta-de-evidencias-nova> \
  bundle exec ruby script/backup-schema-contract-check.rb
```

## 4. Fingerprints realmente observados

| Ambiente de criação | Preparação | Fingerprint observado | Whitelist atual / backup |
|---|---|---|---|
| test | db:migrate | `621ee16d32be40ae482a50c92cc8a3fc55fc92d5aa27186e34506e1b77f529e8` | listado / aceito, TAR verificado |
| test | db:schema:load | `c8752c5aabda1b9064750d8982648e89eaacfb4d68d117f36c3ad1e77ca542f7` | listado / aceito, TAR verificado |
| **development** | **db:migrate** | **`edc335eb6c71b2062b5a65c4563fcbe0fe341deaa5ca55ac7383f8dd92ec5751`** | **não listado / recusado** |
| development | db:schema:load | `b42e0bb59d064152d690856959275801ae4f1e034e291765d56bbc1874986470` | candidato autorizado / ainda não listado, recusado |

Portanto, `b42e0bb5…` é produzido legitimamente por **development/schema load**, mas não pelo caso development/migrate. Aplicá-lo sozinho não faria a matriz positiva de quatro cenários passar. `edc335eb…` não está autorizado para inclusão.

Em todos os quatro: `integrity_check=ok`, foreign_key_check sem violações,25 gatilhos,36 índices, histórico de migrações com hash `07cf9e1c…` e origem logicamente idêntica após a tentativa. Nos dois aceitos, a tarefa verify conferiu o pacote TAR e seu resultado coincidiu com o recibo de criação. Nenhum TAR/SQLite/segredo foi incluído no Git.

## 5. Comparação estrutural dirigida

Cada schema development foi comparado ao seu correspondente test **do mesmo método de preparação**:

- nomes, tipos e ordem dos objetos iguais;
- FKs compostas idênticas;
- exatamente34 diferenças, todas em índices explícitos;
- cada SQL development diferente corresponde exatamente ao SQL test acrescido de ` /*application='AccioHub'*/`;
- todos os demais objetos, incluindo tabelas/CHECKs e25 gatilhos, idênticos.

Essa prova foi feita por comparação de strings e estruturas, sem remover comentários, sem normalizar DDL e sem escrever SQL no banco para obter um hash aceito. A aplicação e os contratos permaneceram intocados.

A comparação entre test/migrate e test/schema load produz dois fingerprints distintos já previstos no contrato original. Assim, os dois schemas homologados geram também dois candidatos development diferentes. Não se afirma que `edc335eb…` está homologado: sua inclusão exige avaliação/autorização própria.

## 6. Resultado e condição de parada

O roteiro registrou os quatro resultados e a comparação completa, depois retornou erro deliberado `Unexpected legitimate fingerprint` ao validar development/migrate contra o único novo hash autorizado. Isso é **reprodução de uma condição bloqueante**, não aprovação da matriz. A configuração não foi editada.

Evidências:

- [before-matrix.json](assets/p1.2f/f5/f5-01-correction/before-matrix.json);
- [before-matrix.log](assets/p1.2f/f5/f5-01-correction/before-matrix.log);
- [before-matrix-attempt-01.log](assets/p1.2f/f5/f5-01-correction/before-matrix-attempt-01.log), falha inicial do parâmetro SCHEMA no QA;
- [stop-condition.json](assets/p1.2f/f5/f5-01-correction/stop-condition.json).

Testes Rails de pós-correção foram esboçados durante a espera da matriz, mas não incorporados à descoberta da suíte: o rascunho foi preservado apenas na área privada ignorada após a parada. Nenhum teste existente foi removido, alterado ou enfraquecido. O novo roteiro de matriz permanece disponível como reprodução do bloqueio.

## 7. Verificações não executadas após a parada

Não foram executadas matriz pós-correção, nova bateria negativa, regressões gerais ou retomada do fluxo integrado F5: a condição prévia obrigatória não foi satisfeita e nenhuma correção foi aplicada. Não se reutilizam resultados históricos como se comprovassem uma implementação nova.

A referência anterior continua203 testes Rails/3.452 asserções, mas **não é resultado de execução desta sessão**. F3b/F3a/F3c/C/D/E/F2 e os resultados anteriores da F5 permanecem preservados nos relatórios correspondentes. Não há comprovação nova de restauração do dataset da interface neste corte interrompido.

## 8. Restritividade e próximos passos

O contrato continua com exatamente os dois fingerprints originais e todas as demais propriedades preservadas. Os schemas test conhecidos foram aceitos; os dois development não listados foram recusados, sem alteração de dados. Isso confirma a manutenção da whitelist atual, mas **não substitui os11 testes negativos solicitados**, ainda pendentes após uma futura correção autorizada.

Solicitar revisão independente dos fingerprints da matriz atual e autorização explícita para tratar também development/migrate. Uma eventual whitelist de quatro fingerprints exigiria preservar os dois originais e homologar separadamente `b42e0bb5…` e `edc335eb…`; não foi aplicada nem presumida autorizada. Não se propõe normalização ou redução da comparação integral.

## 9. Níveis A/B/C e Git

- **A — Implementação técnica:** correção F5-01 não aplicada; bloqueio de compatibilidade persiste.
- **B — Homologação integrada sintética:** não concluída; fluxo F5 não retomado nesta sessão por determinação de parada.
- **C — Dados pessoais importantes:** não liberado. Permanecem recuperação sem origem, proteção/redundância de backups, chaves/configuração, operação por pessoa, acessibilidade/Firefox e retenção definitiva.

Branch/HEAD inalterados. Aplicação, serviços, configurações, modelos, migrações/schema/gatilhos/índices, frontend e protótipo sem diff. Apenas QA/documentação/evidências novos, além das alterações F5 preexistentes; index vazio. Sem commit/staging/push/merge/tag, P1.3 ou alterações Ubuntu. Aguardar revisão da nova divergência antes de qualquer edição do contrato.
