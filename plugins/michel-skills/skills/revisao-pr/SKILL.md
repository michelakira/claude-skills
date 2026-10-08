---
name: revisao-pr
description: Revisa uma PR como tech lead antes do merge, com foco em saber se ela pode quebrar algo em produção. Divide o diff em lotes pequenos para subagentes especialistas (lógica, segurança, performance, cobertura de testes e impacto fora do diff), executa os testes do projeto (unitários, integração, análise estática, migrations, caches de produção e E2E quando houver) numa worktree isolada, verifica cada achado contra o código e entrega veredito, risco de produção, checklist de deploy, plano de rollback e o que monitorar. Feita para Laravel/PHP com MySQL, mas se adapta a outras stacks. Use quando o usuário pedir para revisar/validar uma PR, perguntar se pode mergear ou subir, se a PR quebra produção, qual o impacto de uma mudança, ou invocar /revisao-pr.
---

# Revisão de PR como tech lead

Responde a uma pergunta: **esta PR pode ir para produção sem quebrar nada?** Para isso, junta três coisas:

1. **Leitura do diff** por especialistas, em lotes pequenos.
2. **Impacto fora do diff:** quem usa o que mudou, contratos, compatibilidade durante o deploy.
3. **Execução real** dos testes e checagens que o projeto tiver.

Requer Claude Code (git, Bash e a ferramenta `Agent`). No claude.ai, avise que só dá para fazer a leitura do diff, sem impacto medido nem testes executados.

## Visão geral

| Etapa | Quem faz | O quê |
|---|---|---|
| 1. Entradas | principal | PR, branch base, repositório |
| 2. Worktree | principal | checkout isolado da PR, sem mexer no diretório do usuário |
| 3. Levantamento | principal | arquivos, tamanho, descrição da PR, ruído descartado |
| 4. Lotes e roteamento | principal | lotes de até 8 arquivos / ~400 linhas |
| 5. Especialistas | subagentes `sonnet` | um por par (especialista, lote), em paralelo |
| 5. Execução de testes | subagente `sonnet` | um para a PR inteira, em paralelo com os especialistas |
| 6. Verificação | subagentes `opus` | confirma cada achado no código, até ~20 achados por subagente |
| 7. Parecer | principal | veredito, risco de produção, deploy, rollback, monitoramento |

**Por que lotes pequenos:** um subagente com 30 arquivos presta atenção no começo e no fim do diff e deixa o meio passar. Com no máximo 8 arquivos, cada um recebe a mesma atenção. O modelo principal nunca lê o diff inteiro: só recebe JSONs.

Os prompts de cada subagente estão em [prompts-subagentes.md](references/prompts-subagentes.md). Os critérios do que quebra produção estão em [criterios-producao.md](references/criterios-producao.md).

## 1. Entradas

| Entrada | Padrão |
|---|---|
| PR (número, link ou branch) | PR aberta da branch atual (`gh pr view --json number`); sem PR, a branch atual contra a base |
| Branch base | `baseRefName` da PR; sem PR, a branch padrão (`git symbolic-ref --short refs/remotes/origin/HEAD`) |
| Repositório | `git remote get-url origin` do diretório atual |

Se o diretório não for o repositório da PR, peça para o usuário abrir o clone. Não clone sozinho.

Diga o que detectou antes de seguir: "Revisando PR #123 (`feature/x` → `main`) em `owner/repo`".

## 2. Worktree isolada

Todos os subagentes leem e executam na versão da PR, sem tocar no diretório de trabalho do usuário:

```bash
git fetch origin <base> "pull/<numero>/head:revisao-pr-<numero>"   # sem PR: use a branch local
WT="${TMPDIR:-/tmp}/revisao-pr-<repo>-<numero>"
git worktree add --force "$WT" revisao-pr-<numero>
BASE_SHA=$(git merge-base origin/<base> revisao-pr-<numero>)
```

Use `$BASE_SHA` como base em todos os `git diff` (`git diff $BASE_SHA..HEAD`). Assim só entra o que a PR mudou, mesmo que a base tenha andado.

No fim (etapa 8), remova a worktree e a branch temporária.

## 3. Levantamento

Na worktree:
- `git diff --numstat $BASE_SHA..HEAD` e `git diff --name-status $BASE_SHA..HEAD`.
- `gh pr view <numero> --json title,body,labels,author,reviews,files,statusCheckRollup`. Sem PR, use `git log --format='%s%n%b' $BASE_SHA..HEAD`.
- Ticket citado no corpo (Jira etc.): anote o código para o parecer.

Descarte da revisão de código (mas conte no parecer): `composer.lock`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `vendor/`, `node_modules/`, `public/build/`, `public/vendor/`, `*.min.js`, `*.map`, snapshots e binários.

**Não descarte** `composer.json` e `package.json`: um upgrade major de dependência é um dos maiores riscos de produção.

Se a PR passar de ~3000 linhas úteis ou ~60 arquivos, avise o usuário que a revisão vai demorar e sugira dividir a PR. Siga mesmo assim, se ele confirmar.

## 4. Lotes e roteamento

**Lotes:** agrupe por feature ou entidade (model + controller + request + migration + teste da mesma coisa ficam juntos), com **no máximo 8 arquivos ou ~400 linhas alteradas** por lote. Arquivo sozinho com mais de 400 linhas vira um lote só dele.

**Roteamento:**

| Caminho | Especialistas |
|---|---|
| `app/`, `routes/`, `config/`, `bootstrap/` | logica, seguranca, performance, testes, impacto |
| `database/migrations/` | logica, performance, impacto |
| `database/seeders/`, `database/factories/` | logica |
| `resources/views/`, componentes Blade/Livewire | logica, seguranca, impacto |
| `resources/js/`, front-end | logica, seguranca, impacto |
| `tests/` | testes |
| `composer.json`, `package.json`, `.env.example`, Docker, CI, deploy | impacto, seguranca |
| outros | todos os cinco |

Arquivos de teste da PR **também** vão como contexto (não para revisão) para o especialista de testes dos lotes que testam.

## 5. Disparo

Numa **única mensagem**, dispare em paralelo com a ferramenta `Agent` (`subagent_type: "general-purpose"`):

- **Um subagente por par (especialista, lote)**, `model: "sonnet"`, com o prompt do especialista. Cada um recebe exatamente: caminho da worktree, `BASE_SHA`, arquivos do lote, lista completa de arquivos da PR (só para contexto), título e descrição da PR.
- **Um executor de testes** para a PR inteira, `model: "sonnet"`, `run_in_background: true`, com o prompt do executor. Ele é o mais demorado; não espere por ele para seguir com a coleta.

Com mais de ~25 pares, dispare em levas de até 25.

### Coleta

- Cada subagente devolve um JSON. Se o JSON vier inválido, ou se `arquivos_revisados` não tiver todos os arquivos do lote, reexecute aquele par **uma única vez**. Se falhar de novo, registre em `limitacoes`.
- **Cobertura:** compare a lista de arquivos da PR (após o descarte) com a união dos `arquivos_revisados`. Arquivo que nenhum especialista revisou vai para `limitacoes` como "sem cobertura".
- Junte o `mapa_impacto` dos especialistas de impacto: ele vai para o parecer.

## 6. Verificação

Junte todos os achados dos especialistas e agrupe por arquivo. Dispare verificadores `model: "opus"` em paralelo, cada um com **até ~20 achados** (arquivos inteiros, sem partir um arquivo entre verificadores). Cada verificador confirma ou descarta, deduplica e calibra a severidade, sem criar achados novos.

Os resultados do executor de testes **não passam pelo verificador**: são fatos executados. O executor já separa falha nova de falha que também existe na base.

Depois dos verificadores, o principal faz uma deduplicação final entre grupos: mesmo arquivo, mesma linha e mesma causa viram um achado, com todos os agentes de origem.

## 7. Parecer

Siga [criterios-producao.md](references/criterios-producao.md) para o veredito e o risco.

**Veredito:**
- `nao_mergear`: algum `bloqueante` confirmado, ou teste que **passava na base e falha na PR**, ou `config:cache`/`route:cache` quebrando.
- `mergear_com_ressalvas`: só `importante` e `sugestao`, ou etapas de teste não executadas em área crítica.
- `pode_mergear`: nada confirmado e os testes executados passaram.

**Risco de produção** (`alto`, `medio`, `baixo`): é diferente do veredito. Uma PR sem bugs pode ter risco alto (migration em tabela grande, mudança em pagamento). Justifique com o que foi visto no código e no `mapa_impacto`.

Apresente no chat, nesta ordem:

1. **Veredito e risco**, em uma linha cada, com o motivo principal.
2. **Resumo** em 2 a 3 frases: o que a PR faz e se faz o que a descrição promete.
3. **Testes executados:** tabela `etapa | comando | resultado` (`passou`, `falhou`, `falha_preexistente`, `nao_executado` + motivo). Falhas novas com o nome do teste e a mensagem em uma linha.
4. **Achados confirmados:** tabela ordenada por severidade (`bloqueante`, `importante`, `sugestao`), com `arquivo:linha` como link, problema e correção. Não reescreva nem amplie o que o verificador confirmou: só formate.
5. **Impacto fora do diff:** o que mudou de contrato e quem usa (do `mapa_impacto`), em lista curta. Só itens com usos fora da PR ou contrato alterado.
6. **Checklist de deploy:** só o que se aplica. Exemplos: ordem migration → código, `.env` novo em produção, `php artisan queue:restart`/Horizon, `config:cache`, flag desligada no primeiro deploy, comunicação com consumidores da API.
7. **Rollback:** dá para reverter só o código? A migration tem `down` e ele preserva dados? O que fazer com dados gravados no formato novo?
8. **Monitorar após o deploy:** 2 a 4 sinais concretos (log, rota, job, métrica) ligados ao que mudou.
9. **Perguntas para o autor:** dúvidas que só ele responde (intenção, volume da tabela, consumidores externos). Pode ser vazio.
10. **Limitações:** lotes que falharam, testes não executados e por quê, PR grande demais, sem acesso à descrição.
11. **Descartados:** só a contagem por motivo (ex.: "7 descartados: 4 tratados em outro lugar, 2 não confirmados, 1 duplicado"). Mostre a lista se o usuário pedir.

### Comentar na PR

Só se o usuário pedir. Mostre o texto antes e peça confirmação, porque o comentário fica visível para o time. Use `gh pr review <numero> --comment --body-file <arquivo>`. Nunca use `--approve` nem `--request-changes` sem o usuário pedir explicitamente.

## 8. Limpeza

```bash
git worktree remove --force "$WT"
git branch -D revisao-pr-<numero>
```

Se o executor subiu containers ou servidores, confirme que ele os parou. Se o usuário quiser rodar algo na worktree depois, pergunte antes de remover.
