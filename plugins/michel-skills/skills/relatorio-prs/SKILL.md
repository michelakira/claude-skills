---
name: relatorio-prs
description: Levanta as PRs mergeadas na main (ou outra branch) de um repositório GitHub dentro de um período, lê o código alterado, classifica cada PR (feature, fix, hotfix, refactor, deps...), mede o alcance das mudanças no código, avalia o risco de ter quebrado algo e gera uma página HTML de apresentação com uma visão executiva (para diretoria e gerência) e uma visão técnica. Sem link, usa o repositório do diretório atual. Use quando o usuário pedir o que subiu/foi mergeado num período, changelog, release notes, resumo de PRs, impacto das mudanças, resumo para diretoria/gestão ou se alguma PR pode ter causado problema.
---

# Relatório de PRs mergeadas

Gera um resumo do que entrou na branch principal de um repositório num período: o que é feature, o que é correção, o impacto de cada PR e o risco de ter quebrado algo. A análise lê o código de todas as PRs, e não só os metadados. O resultado final é uma página de apresentação.

## Visão geral

| Etapa | Quem faz | O quê |
|---|---|---|
| 1. Entradas | modelo principal | repositório, período, branch |
| 2. Lista de PRs | modelo principal | metadados, sem diffs |
| 3.1 Triagem | subagentes `haiku` | lê o diff de **todas** as PRs, resume e escala as sensíveis |
| 3.2 Alcance | subagente `haiku` | procura no repositório quem usa o que mudou |
| 3.3 Análise de risco | subagentes `sonnet` | avalia a fundo as PRs escaladas |
| 4. Evidências de quebra | modelo principal | reverts, hotfixes, issues, CI |
| 5. Consolidação | modelo principal | risco final, resumo executivo, pontos de atenção |
| 6–7. Página e resposta | modelo principal | HTML e resumo no chat |

O princípio é: modelos menores fazem extração e busca; o julgamento de risco fica com modelos maiores. Na dúvida, a triagem escala a PR para análise, nunca a marca como risco baixo.

## 1. Entradas

Extraia do pedido:

| Entrada | Obrigatória | Padrão |
|---|---|---|
| Link do repositório (`https://github.com/<owner>/<repo>` ou `owner/repo`) | não | repositório do diretório atual |
| Período (início e fim) | sim | — |
| Branch base | não | branch padrão do repositório (normalmente `main`) |

**Sem link do repositório:** descubra pelo diretório atual.
1. Rode `git remote get-url origin`. Se não houver `origin`, rode `git remote -v` e use o único remote do GitHub; se houver vários, pergunte qual.
2. Extraia `owner/repo` de qualquer um destes formatos, removendo o `.git` final:
   - `https://github.com/owner/repo.git`
   - `git@github.com:owner/repo.git`
   - `ssh://git@github.com/owner/repo.git`
3. Descubra a branch padrão com `git symbolic-ref --short refs/remotes/origin/HEAD` (resultado `origin/main` → `main`). Se falhar, use a branch padrão informada pela API do GitHub, ou `main`.
4. Diga ao usuário qual repositório e branch detectou antes de seguir ("Analisando `owner/repo`, branch `main`").

Se o diretório não for um repositório git, ou o remote não for do GitHub, peça o link.

- Converta períodos relativos para datas absolutas `AAAA-MM-DD` usando a data de hoje: "últimos 15 dias", "setembro", "sprint passada" (pergunte a duração se não souber), "desde 01/09". Datas no formato brasileiro `DD/MM/AAAA` são dia/mês.
- Se faltar o período, pergunte antes de começar. Não invente período.

## 2. Coletar a lista de PRs

Nesta etapa pegue só metadados. Os diffs são lidos pelos subagentes na etapa 3, para não encher o contexto principal.

Use a primeira fonte disponível:

**A. GitHub MCP** (ferramentas `mcp__*Github*`)
1. `search_pull_requests` com
   `query: "repo:<owner>/<repo> is:pr is:merged base:<branch> merged:<inicio>..<fim>"`, `sort: "created"`, `order: "asc"`, `perPage: 100`. Pagine até acabar.
   A busca do GitHub retorna no máximo 1000 resultados: se vier perto disso, quebre o período em meses.
2. Para cada PR, `pull_request_read` com:
   - `method: "get"` → título, corpo, autor, `created_at`, `merged_at`, `head.ref` (nome da branch), labels, `additions`, `deletions`, `changed_files`.
   - `method: "get_reviews"` → quantidade de aprovações.

**B. GitHub CLI** (`gh` instalado e autenticado)
```bash
gh pr list --repo <owner>/<repo> --state merged --base <branch> \
  --search "merged:<inicio>..<fim>" --limit 1000 \
  --json number,title,body,author,createdAt,mergedAt,headRefName,labels,additions,deletions,changedFiles,reviews,url
```
O diff de cada PR sai com `gh pr diff <numero> --repo <owner>/<repo>`.

**C. Git local** (último recurso, se o repositório estiver clonado e não houver acesso à API)
```bash
git fetch origin
git log origin/<branch> --first-parent --merges --since=<inicio> --until=<fim>T23:59:59 --format="%H|%s|%an|%aI"
git diff <hash>^1 <hash>   # diff de cada merge
```
Nesse caso avise o usuário que a análise é limitada (sem corpo da PR, revisões ou labels).

Se nenhuma fonte funcionar (sem MCP, sem `gh`, repositório privado sem token), pare e diga ao usuário exatamente o que falta.

## 3. Ler o código

Use a ferramenta `Agent` com o parâmetro `model` indicado em cada etapa. Os prompts prontos estão em [prompts-subagentes.md](references/prompts-subagentes.md). Dispare os lotes de uma mesma etapa **em paralelo**, na mesma mensagem.

Diga ao subagente qual ferramenta usar para ler os diffs (a mesma fonte que funcionou na etapa 2).

### 3.1 Triagem (`model: "haiku"`)

- Todas as PRs, em lotes de 8 a 10. Com até 10 PRs, um único subagente.
- Cada subagente lê os diffs ignorando lockfiles e arquivos gerados e devolve, por PR: tipo, resumos, símbolos alterados (funções, endpoints, tabelas, envs), sinais vistos no código e `precisaAnalise`.
- Ao receber, confira: toda PR do lote voltou? Alguma veio com `erro`? Refaça só as que faltaram, uma vez.
- **Rede de segurança:** force `precisaAnalise: true` em toda PR que a triagem deixou como `false` mas que:
  - tem tipo `hotfix` ou `revert`, ou
  - mexe em arquivo cujo caminho contém `migration`, `migrate`, `schema`, `auth`, `payment`, `pagamento`, `billing`, `checkout`, `security`, `.env`, `config/`, `deploy`, `infra`, `terraform`, `k8s`, `helm`, ou
  - tem mais de 500 linhas de código de produção alteradas.

### 3.2 Alcance no código (`model: "haiku"`)

Só roda quando o diretório atual é um clone do repositório analisado (o `owner/repo` do `git remote get-url origin` é o mesmo). Nesse caso:
1. Rode `git fetch origin <branch>` para ter a versão atual.
2. Dispare **um** subagente com os `simbolosAlterados` das PRs com `precisaAnalise: true`. Ele usa `git grep` em `origin/<branch>`, sem checkout e sem mexer no working tree.

Se o diretório não for um clone do repositório, pule esta etapa e registre em `limitacoes` que o alcance não foi medido. Não clone repositórios sem o usuário pedir.

### 3.3 Análise de risco (`model: "sonnet"`)

- Só as PRs com `precisaAnalise: true`, em lotes de 3 a 5.
- Cada subagente recebe a triagem, o alcance (se houver), os metadados (aprovações, tempo entre abrir e mergear, descrição) e o conteúdo de [criterios-risco.md](references/criterios-risco.md), e relê o diff completo.
- Devolve o risco, os motivos separados por fonte (`codigo` ou `metadados`), `breaking`, impacto e como validar em produção.

### PRs que não foram escaladas

Ficam com a triagem. O risco delas é `baixo`, e o motivo vem dos `sinais` da triagem com `fonte: "codigo"` (ex.: "Só altera textos da tela de login"). Se a triagem não trouxe sinal nenhum, use o motivo "Mudança isolada, sem área crítica" com `fonte: "metadados"`.

### Sem a ferramenta `Agent` (claude.ai, ou subagentes indisponíveis)

Faça as mesmas etapas no modelo principal, na mesma ordem:
- Leia o diff de todas as PRs, ignorando os mesmos arquivos de ruído, e anote a triagem de cada uma antes de ir para a próxima.
- Aplique a rede de segurança e aprofunde só nas escaladas.
- Com mais de 40 PRs, leia só a lista de arquivos das PRs de `deps`, `docs`, `test` e `ci` e registre isso em `limitacoes`.

## 4. Procurar evidências de quebra

Classificar risco é estimativa. Evidência de que algo quebrou é outra coisa, e a página separa as duas. Esta etapa usa só metadados e pode rodar enquanto os subagentes da etapa 3 trabalham. Procure:

1. **Reverts**: PRs no período (e até 7 dias depois do fim) com `revert` no título ou branch. Associe à PR original pelo número/título citado.
2. **Hotfix posteriores**: PRs `hotfix`/`fix` que citam outra PR (`#123`, "corrige regressão de ...") ou mexem nos mesmos arquivos logo depois.
3. **Issues de bug**: `search_issues` com `repo:<owner>/<repo> is:issue label:bug created:<inicio>..<fim+7d>` e veja se citam alguma PR do período.
4. **Status/CI**: `pull_request_read` `method: "get_status"` para PRs escaladas; checks falhando no merge contam como sinal.

Resultado por PR em `quebra.status`:
- `confirmado`: revertida, ou hotfix/issue aponta diretamente para ela.
- `suspeita`: hotfix posterior nos mesmos arquivos/área sem citar a PR, ou CI falhando no merge.
- `nao`: nenhuma evidência encontrada. Isso não significa garantia; o risco continua valendo.

## 5. Consolidar

Aqui o modelo principal junta tudo e dá a palavra final:
- **Risco final:** parta da análise do Sonnet. Suba o risco se a etapa 4 achou quebra confirmada ou suspeita. Só baixe o risco dado pelo Sonnet com um motivo concreto, e registre esse motivo.
- **Conflitos:** quando `discordaDaTriagem` vier preenchido, vale a análise do Sonnet para tipo e impacto.
- **Textos da página:** `resumo` vem do `resumoNegocio`, `impacto` da análise (ou da triagem), `corrige` da triagem. Revise para ficarem claros para quem não é da área técnica.
- **Pontos de atenção:** 2 a 6 ações concretas, usando `comoValidar` e o alcance (ex.: "`calcularFrete` mudou e é usada em 7 lugares, incluindo o checkout: acompanhar erros de cotação").
- **Resumo técnico (`resumoExecutivo`):** 3 a 5 frases com o que foi entregue, o que foi corrigido e onde está o risco. Aparece na capa da visão técnica.
- **Visão executiva (`executivo`):** veja a seção 5.1.

### 5.1 Visão executiva

É o que diretoria e gerência veem primeiro. Escreva para quem não conhece o código nem o nome das PRs.

- **Agrupe por tema, não por PR.** Várias PRs da mesma funcionalidade viram uma entrega só. PRs de `deps`, `chore`, `docs`, `test`, `ci` e `refactor` sem efeito visível **não entram** na visão executiva; ficam só na técnica.
- **Linguagem de negócio.** Proibido: nomes de funções, arquivos, tabelas, endpoints, "PR", "merge", "deploy", "refactor", "migration". Troque "altera `calcularJuros`" por "muda a regra de cálculo dos juros". Diga o efeito para cliente, operação ou receita.
- **Nada de inventar números de negócio.** Não cite conversão, receita ou volume que não estejam na PR ou no ticket. Use "tende a", "deve" para efeitos esperados.
- **Campos:**
  - `manchete`: uma frase, de até ~110 caracteres, com o fato mais importante do período.
  - `saude.nivel`: `critico` se houve quebra confirmada ainda não resolvida ou risco alto sem ação; `atencao` se houve quebra já resolvida, revert ou risco alto em acompanhamento; `estavel` nos outros casos. `saude.texto`: 1 a 2 frases justificando.
  - `entregas` (até 6, as mais relevantes primeiro): `tema`, `titulo` (curto, sem prefixo técnico), `descricao`, `beneficio`, `status` (`no-ar`, `parcial` se depende de outra etapa ou flag desligada, `adiado` se foi revertida) e `prs`.
  - `correcoes` (até 6): problemas que o cliente ou a operação sentiam, com `titulo`, `descricao` (o que acontecia e como está agora) e `prs`. Correções internas sem efeito visível não entram.
  - `riscos` (até 4): só riscos `alto` e `medio`, cada um com `descricao` em linguagem de negócio, `acao` concreta e `responsavel` (time ou pessoa citada na PR ou ticket; senão `null`).
  - `proximosPassos` (até 5) e `decisoes` (o que precisa de alguém da gestão decidir; pode ser vazio).

Siga [criterios-risco.md](references/criterios-risco.md) para tipo e risco. Leia o corpo da PR: muitos times descrevem ali o motivo, o link do ticket e o plano de rollback. Use o ticket (Jira etc.) no campo `ticket` quando houver.

Monte um único objeto JSON:

```json
{
  "repo": "owner/repo",
  "repoUrl": "https://github.com/owner/repo",
  "base": "main",
  "periodo": { "inicio": "2026-09-01", "fim": "2026-09-15" },
  "geradoEm": "2026-09-28",
  "fonte": "GitHub MCP",
  "analise": { "triagem": "haiku", "risco": "sonnet", "alcance": true },
  "limitacoes": ["Frases curtas sobre o que não foi possível analisar."],
  "executivo": {
    "manchete": "Parcelamento em 12x entrou no ar; o cupom de primeira compra foi adiado após falha.",
    "saude": { "nivel": "atencao", "texto": "..." },
    "entregas": [{ "tema": "Checkout", "titulo": "Parcelamento em até 12x", "descricao": "...", "beneficio": "...", "status": "no-ar", "prs": [482] }],
    "correcoes": [{ "titulo": "Frete errado para o interior de SP", "descricao": "...", "prs": [480] }],
    "riscos": [{ "titulo": "Valor cobrado no parcelamento", "descricao": "...", "nivel": "alto", "acao": "...", "responsavel": "Time de Pagamentos", "prs": [482] }],
    "proximosPassos": ["..."],
    "decisoes": ["..."]
  },
  "resumoExecutivo": "...",
  "pontosDeAtencao": ["..."],
  "prs": [
    {
      "numero": 482,
      "titulo": "feat(checkout): parcelamento em até 12x",
      "url": "https://github.com/owner/repo/pull/482",
      "autor": "login",
      "mergedAt": "2026-09-03T14:22:00Z",
      "tipo": "feat",
      "escopo": "checkout",
      "resumo": "...",
      "impacto": "...",
      "corrige": null,
      "risco": "alto",
      "motivosRisco": [
        { "texto": "calcularJuros passa a arredondar por parcela em PaymentService", "fonte": "codigo" },
        { "texto": "Sem testes novos", "fonte": "metadados" }
      ],
      "comoValidar": "Comparar o total cobrado com o exibido no checkout nas primeiras compras parceladas.",
      "breaking": false,
      "quebra": { "status": "nao", "evidencia": null, "relacionadas": [] },
      "alcance": [
        { "simbolo": "calcularJuros", "usos": 4, "exemplos": ["src/checkout/total.ts:42"], "areasAfetadas": ["checkout"] }
      ],
      "analise": "aprofundada",
      "adicoes": 640, "remocoes": 85, "arquivos": 14,
      "revisoes": 1, "testes": false,
      "areas": ["pagamentos", "api"],
      "ticket": null
    }
  ]
}
```

- Datas de período em `AAAA-MM-DD`; `mergedAt` em ISO 8601 como vem da API.
- `revisoes` é o número de aprovações; `testes` indica se a PR alterou ou adicionou testes.
- `analise` por PR: `aprofundada` (passou pela 3.3) ou `triagem`.
- `alcance` só para símbolos não genéricos; lista vazia quando não houver.
- `analise.alcance` no topo: `true` se a etapa 3.2 rodou.

## 6. Gerar a página

1. Copie [assets/template.html](assets/template.html) e troque **todo** o conteúdo entre `<script id="dados" type="application/json">` e `</script>` pelo JSON da seção 5. O template vem com dados de exemplo; nada deles pode sobrar.
   - Escape `</` como `<\/` dentro do JSON para não fechar a tag antes da hora.
2. Troque o `<title>` por `<repo> · <período>` (ex.: `loja-api · Setembro 2026`).
3. Entregue:
   - **Se a ferramenta `Artifact` existir:** publique o arquivo como artifact (ícone `chart`, descrição de uma frase com repo e período) e mande o link. O template já segue o contrato de página do Artifact.
   - **Senão:** salve como `relatorio-prs-<repo>-<inicio>_<fim>.html` no diretório atual, adicionando no topo `<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">`, e informe o caminho.

A página tem duas visões, trocadas no seletor **Executivo / Técnico** do topo:
- **Executivo** (abre por padrão): manchete, saúde do período, quatro números, entregas por tema, correções, riscos com ação e responsável, próximos passos e decisões.
- **Técnico**: capa com números, pontos de atenção, panorama por tipo/risco/dia, features, correções, demais mudanças e tabela completa com filtros. Cada PR mostra os motivos do risco marcados como "código" ou "metadados", o alcance no código e como validar.

O botão **Apresentar** mostra um slide por seção da visão escolhida, navegável com as setas do teclado. Para mandar o link já na visão técnica, acrescente `#tecnico` ao final.

Se o usuário pedir só a visão executiva ou só a técnica, gere a página completa do mesmo jeito e diga qual visão abrir.

## 7. Resposta no chat

Depois de gerar a página, responda de forma curta:
- A manchete e a saúde do período (da visão executiva).
- Total de PRs e divisão por tipo.
- Quantas PRs foram só triadas e quantas tiveram análise aprofundada.
- PRs de risco alto e quebras confirmadas/suspeitas, com número e motivo em uma linha cada.
- O link ou caminho da página.
- As `limitacoes`, se houver (fonte limitada, alcance não medido, diffs parciais, PRs com erro de leitura).
