# F4 — Inventário anterior às correções de produto

Base F3c: 11d15fc9957c2b5b78173bf3f3a87e10c3428caa. Antes de qualquer edição CSS/ERB/Stimulus da aplicação. Somente QA novo, bancos e perfis sintéticos. Fontes de referência: DESIGN_BASELINE/P0.4 homologada e plano F, incluindo ressalvas E3. Não é homologação WCAG.

Evidência válida: before-measured/ (64 estados, temas claro/escuro,320/1440,16 superfícies) e palette-before/ (112 estados,4 fundos, verde/lilás/cinza e branco/preto,320/1440). Axe completo, sem filtros/desativação; zero violações nesses cenários, contraste incomplete retido. Os scripts de contraste não transformam incomplete em PASS. Ver também controls-before/ e diagnose-before/.

| Componente | Estados/semântica/teclado observados | Contraste/pequenas telas/Turbo | Prioridade |
|---|---|---|---|
| Dashboard e widgets | Landmarks nomeados, títulos h1/h2/h3; ações com nomes; captura/Music demonstrativos explícitos | Dim fraco; textos de widgets ilustrativos claros insuficientes; matriz320/1440 sem overflow documental | Média |
| Dock e rail | Duas navegações nomeadas; aria-current; links nativos acessíveis | Ícone ativo claro~1,20:1; avatar3,40:1; foco padrão dependente de destaque | Alta |
| Pomodoro | Um controller compartilhado, controles nomeados, diálogo contido e retorno; relógio não aria-live | Círculo170px/lilás preservados; ready examinado; recuperação/erro serão exercitados após esta coleta | Alta, sem defeito de estado confirmado |
| Music | Região nomeada, expandido/recolhido/aria-expanded | Texto auxiliar~3,45–4,21:1; padrão demonstrativo preservado | Média |
| Biblioteca de Projetos | Filtros aria-pressed, regiões/resultados; diálogo com foco inicial, Tab/ShiftTab,Escape/cancelar/X retornam | Kicker verde claro~1,17:1; campos/bordas insuficientes | Alta |
| Espaço de projetos | Tablist/tab/tabpanel; setas/Home/End restauram foco após Turbo; referências reais e espaço vazio | Auxiliares de tarefas3,55–4,42:1; arquivado visível/somente leitura; contratos de dados não alterados | Média |
| Tarefas | Lista global/contextual, labels de checkbox; diálogo acessível nas saídas testadas | Placeholder~3,76:1; após422 e submit pelo teclado foco vai a BODY | Alta |
| Referências | Labels e identificação do diálogo; ciclo/foco/retorno passam | Placeholder~3,87:1; após422 foco vai a BODY | Alta |
| Preferências/painel | Labels, estados pressed/expanded e controles de ordenação nomeados | Auxiliares página3,55–4,39:1; painel possui correção histórica específica; bordas/foco em avaliação dirigida | Alta |
| Busca | Dialog/search/nav identificados; Ctrl+K/foco/resultado | Placeholder~3,61:1; mensagem sem resultados não tem role/status | Média |
| Formulários/erros | Erros role=alert com campos preservados | Desabilitar botão focado durante envio leva a BODY após422 em projetos/tarefas/referências, confirmado após resposta e reabilitação | Alta |
| Avisos/confirmações | Regiões status/alert existentes em C/foco | Estados de erro/transporte, recuperação e motion serão verificados separadamente; sem aprovação por ausência de violações | Pendente |
| Skip link | Diagnóstico com espera de hash/duas frames confirma MAIN com e sem Turbo | Primeiro teste foi cedo demais, não defeito do produto; não alterar implementação | Comportamento esperado |

## Matriz de correções proposta

- F4-01: dim/textos auxiliares/placeholders insuficientes; ajustar tokens/seletores de texto, mantendo fundos/gradientes.
- F4-02: foreground de destaque não garante legibilidade em claro ou destaque escuro; tratar textos/ícones e botões sem alterar cor configurada.
- F4-03: avatar e textos claros fixos em widgets ilustrativos; ajustes locais de foreground, mantendo superfícies.
- F4-04: bordas essenciais de campos~1,27–1,54:1 e focos claros~1,18–1,28:1, controls-before:30 falhas de40 medições; não exigir borda contrastante de todos os botões rotulados. Confirmar semântica/exceções de controles nativos e wrappers na revisão.
- F4-05: perda de foco após erro de submissão nos três formulários; capturar foco anterior e restaurá-lo somente se diálogo ainda aberto e foco estiver em BODY, sem roubar foco de outro controle.
- F4-06: sem resultados da busca sem região status; marcar o feedback existente e indicar busy durante a consulta já existente, sem criar componente.

Medições preliminares before-inventory/before-reviewed/before-stable são preservadas mas substituídas como oráculo: identificador de campo errado no harness, const global redeclarada e metadados capturados antes de rolagem suave estabilizar. before-measured aguarda scrollend/frames e recorta as caixas pelos ancestrais; mínimos artificiais das rodadas preliminares não são defeitos confirmados.

Exceções: logotipos wordmark/brand, pontuação/separadores puramente decorativos e controles inativos não são violações de1.4.3. SVGs decorativos de cartões não recebem exigência de informação essencial. Native-checkbox não modificado e casos sem medição suficiente ficam distintos de PASS. Não há alegação global de leitor de tela, Firefox ou WCAG AA.

Complemento confirmado em login-before/black*: o botão Entrar com destaque preto permitido tem1,17:1. Caso reproduzido por substituição temporária do token de apresentação no perfil sintético sem autenticação; não é alteração de cookie/banco pessoal. Correção local de foreground também na tela de acesso, reaproveitando actionInk existente, sem alterar autenticação. O padrão verde mantém superfície/forma e família tipográfica. Confirmação final por logout/login com preferência sintética real.

Precisão dos controles: controls-before-wrapper/ usa CSS foundation original do HEAD no DOM QA, sem editar produto, e mede o wrapper real de project-search em vez da borda zero do input interno. São34 falhas de40 medições antes, zero de40 em controls-after/, mínimo posterior3,591:1 (bordas) e13,794:1 (foco). A primeira rodada controls-before não é usada para declarar o input sem borda aprovado.
