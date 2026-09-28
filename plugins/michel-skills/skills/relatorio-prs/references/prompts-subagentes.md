# Prompts dos subagentes

Modelos de prompt para as etapas da seção 3 do SKILL.md. Troque o que está entre `<...>`. Cada subagente busca os próprios diffs, para o diff não passar pelo contexto principal, e responde **somente** com o JSON pedido, sem texto em volta.

Todos recebem estas regras comuns:

```
Regras:
- Responda somente com JSON válido no formato pedido, sem markdown nem comentários.
- Escreva os textos em português.
- Cite arquivos e símbolos reais do diff. Não invente nada que você não viu.
- Se não conseguir ler o diff de uma PR, devolva a PR com "erro": "<motivo>" e o resto do que conseguiu.
```

---

## Triagem (modelo `haiku`, lotes de 8 a 10 PRs)

```
Você faz a triagem de PRs mergeadas no repositório <owner>/<repo>, branch <branch>.

PRs do lote (número, título, branch, labels, +/-, arquivos):
<lista resumida das PRs do lote>

Para cada PR:
1. Leia os arquivos alterados e o diff com <ferramenta: pull_request_read method "get_files" e "get_diff" | gh pr diff <n> --repo <owner>/<repo>>.
2. Ignore no diff os arquivos de ruído: lockfiles (package-lock.json, yarn.lock, pnpm-lock.yaml, poetry.lock, Gemfile.lock, go.sum, composer.lock, Cargo.lock), pastas dist/, build/, vendor/, node_modules/, arquivos *.min.js, *.map, snapshots (__snapshots__, *.snap) e arquivos marcados como gerados. Conte-os em "arquivosIgnorados".
3. Se o diff útil passar de ~1500 linhas, leia os arquivos de código de produção primeiro e marque "diffParcial": true.
4. Preencha o JSON abaixo.

Regra de escalonamento: "precisaAnalise" é true quando a PR:
- toca qualquer área crítica: pagamento, preço, frete, imposto, estoque, autenticação, autorização, sessão, criptografia, migração de banco, schema, contrato de API ou de evento, config de produção, variáveis de ambiente, feature flags, jobs agendados, filas;
- muda assinatura de função/método exportado ou usado em outros módulos;
- muda regra de negócio, validação, tratamento de erro, retry, timeout ou concorrência;
- é hotfix ou revert;
- atualiza dependência em versão major;
- ou você não tem certeza. Na dúvida, true.
Você NÃO decide o risco final. Só diga se precisa de análise e por quê.

Formato:
{"prs": [{
  "numero": 0,
  "tipo": "feat|fix|hotfix|revert|refactor|perf|deps|chore|docs|test|ci",
  "escopo": "área curta, ex.: checkout",
  "resumoTecnico": "o que o código passou a fazer, 1 a 2 frases",
  "resumoNegocio": "o efeito para quem usa o sistema, 1 frase",
  "corrige": "problema resolvido, ou null",
  "simbolosAlterados": [{"nome": "calcularFrete", "tipo": "funcao|classe|metodo|endpoint|tabela|coluna|evento|config|env", "mudanca": "assinatura|comportamento|removido|novo|renomeado", "arquivo": "src/frete/calculo.ts"}],
  "sinais": ["frases curtas do que você viu no código, ex.: 'remove coluna legacy_id em orders'"],
  "testes": true,
  "areas": ["frete"],
  "arquivosIgnorados": 0,
  "diffParcial": false,
  "precisaAnalise": true,
  "motivoEscalonamento": "por que precisa de análise, ou null"
}]}
```

---

## Alcance no código (modelo `haiku`, uma chamada para todos os símbolos)

Só roda quando o diretório atual é um clone de `<owner>/<repo>` (ver SKILL.md, seção 3.2).

```
Você mede o alcance de mudanças no repositório local em <caminho>, na referência origin/<branch>.

Símbolos alterados (nome, tipo, arquivo onde foi definido, PR):
<lista de simbolosAlterados das PRs com precisaAnalise = true>

Para cada símbolo:
1. Procure os usos com: git grep -n -w "<nome>" origin/<branch> -- . ':!*.lock' ':!*lock.json' ':!dist' ':!build' ':!vendor'
   - Para endpoints, procure também o caminho da rota (ex.: "/v1/orders").
   - Para tabelas e colunas, procure também em arquivos .sql e em models/ORM.
   - Para variáveis de ambiente, procure também em .env.example, docker-compose, arquivos de deploy e CI.
2. Descarte a própria definição e os testes. Conte os testes à parte.
3. Nomes muito genéricos (ex.: "get", "data", "id") com mais de 100 resultados: marque "generico": true e não liste exemplos.
4. Não altere nem faça checkout de nada. Use só leitura.

Formato:
{"simbolos": [{
  "nome": "calcularFrete",
  "pr": 0,
  "usos": 7,
  "usosEmTestes": 3,
  "arquivos": 5,
  "exemplos": ["src/checkout/total.ts:42", "src/api/cotacao.ts:18"],
  "areasAfetadas": ["checkout", "api"],
  "generico": false
}]}
```

Liste no máximo 5 exemplos por símbolo, priorizando código de produção de áreas diferentes.

---

## Análise de risco (modelo `sonnet`, lotes de 3 a 5 PRs)

Só para PRs com `precisaAnalise: true`.

```
Você avalia o risco de PRs já mergeadas no repositório <owner>/<repo>, branch <branch>, de terem quebrado algo ou poderem quebrar.

Critérios de risco (siga à risca):
<conteúdo de references/criterios-risco.md>

Para cada PR abaixo você recebe a triagem e, quando houver, o alcance no código:
<JSON da triagem de cada PR do lote>
<JSON do alcance dos símbolos dessas PRs, ou "alcance não disponível">
<metadados: aprovações, tempo entre abrir e mergear, descrição da PR>

Para cada PR:
1. Leia o diff completo com <ferramenta>. Não confie só na triagem: ela foi feita por um modelo menor e pode ter deixado passar algo.
2. Responda: o comportamento mudou para quem já usava esse código? Algum chamador listado no alcance passa a receber algo diferente, precisa de um parâmetro novo ou deixa de funcionar? Há caminho de erro novo sem tratamento? A migração é reversível? O que acontece com dados já existentes?
3. Separe o que você VIU no código (fonte "codigo") do que deduziu por metadados como tamanho, falta de testes ou revisão (fonte "metadados").

Formato:
{"prs": [{
  "numero": 0,
  "risco": "alto|medio|baixo",
  "motivosRisco": [{"texto": "calcularFrete passa a exigir o parâmetro uf; 2 dos 7 chamadores não passam", "fonte": "codigo"}],
  "breaking": false,
  "impacto": "quem sente a mudança e como, 1 a 2 frases",
  "comoValidar": "o que olhar em produção para saber se quebrou, 1 frase, ou null",
  "discordaDaTriagem": "o que a triagem errou, ou null"
}]}
```
