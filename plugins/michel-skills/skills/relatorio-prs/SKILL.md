---
name: relatorio-prs
description: Levanta as PRs mergeadas na main (ou outra branch) de um repositório GitHub dentro de um período, classifica cada uma (feature, fix, hotfix, refactor, deps...), avalia o impacto e o risco de ter quebrado algo e gera uma página HTML de apresentação com o resumo. Use quando o usuário passar um link de repositório e pedir o que subiu/foi mergeado num período, changelog, release notes, resumo de PRs, impacto das mudanças ou se alguma PR pode ter causado problema.
---

# Relatório de PRs mergeadas

Gera um resumo do que entrou na branch principal de um repositório num período: o que é feature, o que é correção, o impacto de cada PR e o risco de ter quebrado algo. O resultado final é uma página de apresentação.

## 1. Entradas

Extraia do pedido:

| Entrada | Obrigatória | Padrão |
|---|---|---|
| Link do repositório (`https://github.com/<owner>/<repo>` ou `owner/repo`) | sim | — |
| Período (início e fim) | sim | — |
| Branch base | não | `main` |

- Converta períodos relativos para datas absolutas `AAAA-MM-DD` usando a data de hoje: "últimos 15 dias", "setembro", "sprint passada" (pergunte a duração se não souber), "desde 01/09". Datas no formato brasileiro `DD/MM/AAAA` são dia/mês.
- Se faltar o repositório ou o período, pergunte antes de começar. Não invente período.
- Se o repositório usar `master` ou `develop` como principal e o usuário não especificou, confira a branch padrão antes.

## 2. Coletar as PRs

Use a primeira fonte disponível:

**A. GitHub MCP** (ferramentas `mcp__*Github*`)
1. `search_pull_requests` com
   `query: "repo:<owner>/<repo> is:pr is:merged base:<branch> merged:<inicio>..<fim>"`, `sort: "created"`, `order: "asc"`, `perPage: 100`. Pagine até acabar.
   A busca do GitHub retorna no máximo 1000 resultados: se vier perto disso, quebre o período em meses.
2. Para cada PR, `pull_request_read` com:
   - `method: "get"` → título, corpo, autor, `merged_at`, `head.ref` (nome da branch), labels, `additions`, `deletions`, `changed_files`.
   - `method: "get_files"` → lista de arquivos alterados (é a base da análise de risco).
   - `method: "get_reviews"` → quantidade de aprovações.
   - `method: "get_diff"` → só para PRs que já parecem de risco médio/alto, ou pequenas o bastante para ler rápido. Não baixe o diff de PRs gigantes de lockfile/deps.

**B. GitHub CLI** (`gh` instalado e autenticado)
```bash
gh pr list --repo <owner>/<repo> --state merged --base <branch> \
  --search "merged:<inicio>..<fim>" --limit 1000 \
  --json number,title,body,author,mergedAt,headRefName,labels,additions,deletions,changedFiles,files,reviews,url
gh pr diff <numero> --repo <owner>/<repo>
```

**C. Git local** (último recurso, se o repositório estiver clonado e não houver acesso à API)
```bash
git log origin/<branch> --first-parent --merges --since=<inicio> --until=<fim>T23:59:59 --format="%H|%s|%an|%aI"
```
Nesse caso avise o usuário que a análise é limitada (sem corpo da PR, revisões ou labels).

Se nenhuma fonte funcionar (sem MCP, sem `gh`, repositório privado sem token), pare e diga ao usuário exatamente o que falta.

**Volume grande:** acima de ~30 PRs, se a ferramenta `Agent` estiver disponível, divida em lotes de ~10 PRs e peça a subagentes que devolvam, para cada PR, o objeto JSON da seção 5. Passe a eles o conteúdo de [criterios-risco.md](references/criterios-risco.md).

## 3. Procurar evidências de quebra

Classificar risco é estimativa. Evidência de que algo quebrou é outra coisa, e a página separa as duas. Procure:

1. **Reverts**: PRs no período (e até 7 dias depois do fim) com `revert` no título ou branch. Associe à PR original pelo número/título citado.
2. **Hotfix posteriores**: PRs `hotfix`/`fix` que citam outra PR (`#123`, "corrige regressão de ...") ou mexem nos mesmos arquivos logo depois.
3. **Issues de bug**: `search_issues` com `repo:<owner>/<repo> is:issue label:bug created:<inicio>..<fim+7d>` e veja se citam alguma PR do período.
4. **Status/CI**: `pull_request_read` `method: "get_status"` para PRs de risco alto; checks falhando no merge contam como sinal.

Resultado por PR em `quebra.status`:
- `confirmado`: revertida, ou hotfix/issue aponta diretamente para ela.
- `suspeita`: hotfix posterior nos mesmos arquivos/área sem citar a PR, ou CI falhando no merge.
- `nao`: nenhuma evidência encontrada. Isso não significa garantia; o risco continua valendo.

## 4. Classificar e avaliar

Para cada PR, siga [criterios-risco.md](references/criterios-risco.md):
- **tipo**: `feat`, `fix`, `hotfix`, `revert`, `refactor`, `perf`, `deps`, `chore`, `docs`, `test`, `ci`.
- **resumo**: 1 a 2 frases em português, em linguagem de negócio ("Clientes passam a poder parcelar em 12x"), não repetindo o título.
- **impacto**: quem ou o que é afetado (usuário final, API pública, time interno, infraestrutura) e como.
- **corrige**: para `fix`/`hotfix`, qual problema foi resolvido.
- **risco**: `alto`, `medio` ou `baixo`, com `motivosRisco` concretos (cite arquivos ou mudanças). Nunca deixe risco sem motivo.

Leia o corpo da PR: muitos times descrevem ali o motivo, o link do ticket e o plano de rollback. Use o link do ticket (Jira etc.) no campo `ticket` quando houver.

## 5. Montar os dados

Monte um único objeto JSON:

```json
{
  "repo": "owner/repo",
  "repoUrl": "https://github.com/owner/repo",
  "base": "main",
  "periodo": { "inicio": "2026-09-01", "fim": "2026-09-15" },
  "geradoEm": "2026-09-28",
  "fonte": "GitHub MCP",
  "resumoExecutivo": "3 a 5 frases: o que foi entregue, o que foi corrigido e onde está o risco.",
  "pontosDeAtencao": ["Ações concretas: monitorar X, validar Y em produção, falar com time Z."],
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
      "motivosRisco": ["Altera cálculo de juros em PaymentService", "Sem testes novos"],
      "breaking": false,
      "quebra": { "status": "nao", "evidencia": null, "relacionadas": [] },
      "adicoes": 640, "remocoes": 85, "arquivos": 14,
      "revisoes": 1, "testes": false,
      "areas": ["pagamentos", "api"],
      "ticket": null
    }
  ]
}
```

Datas de período em `AAAA-MM-DD`; `mergedAt` em ISO 8601 como vem da API. `revisoes` é o número de aprovações; `testes` indica se a PR alterou ou adicionou testes.

## 6. Gerar a página

1. Copie [assets/template.html](assets/template.html) e troque **todo** o conteúdo entre `<script id="dados" type="application/json">` e `</script>` pelo JSON da seção 5. O template vem com dados de exemplo; nada deles pode sobrar.
   - Escape `</` como `<\/` dentro do JSON para não fechar a tag antes da hora.
2. Troque o `<title>` por `<repo> · <período>` (ex.: `loja-api · Setembro 2026`).
3. Entregue:
   - **Se a ferramenta `Artifact` existir:** publique o arquivo como artifact (ícone `chart`, descrição de uma frase com repo e período) e mande o link. O template já segue o contrato de página do Artifact.
   - **Senão:** salve como `relatorio-prs-<repo>-<inicio>_<fim>.html` no diretório atual, adicionando no topo `<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">`, e informe o caminho.

A página tem: capa com números principais, pontos de atenção (risco alto e quebras), panorama por tipo/risco/dia, features, correções, demais mudanças e tabela completa com filtros. O botão **Apresentar** ativa um slide por seção, navegável com as setas do teclado.

## 7. Resposta no chat

Depois de gerar a página, responda de forma curta:
- Total de PRs e divisão por tipo.
- PRs de risco alto e quebras confirmadas/suspeitas, com número e motivo em uma linha cada.
- O link ou caminho da página.
- Limitações da análise, se houver (fonte limitada, PRs sem descrição, diffs não lidos por tamanho).
