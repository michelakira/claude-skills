# Critérios de classificação e risco

## Tipo da PR

Decida nesta ordem e pare no primeiro que resolver:

1. **Prefixo Conventional Commits no título**: `feat:`, `fix(api):`, `chore(deps):`, `refactor!:` etc. O `!` indica breaking change.
2. **Labels**: `bug` → fix, `enhancement`/`feature` → feat, `dependencies` → deps, `hotfix` → hotfix.
3. **Nome da branch** (`head.ref`): `feature/`, `feat/` → feat; `fix/`, `bugfix/` → fix; `hotfix/` → hotfix; `release/` → veja o conteúdo; `dependabot/`, `renovate/` → deps.
4. **Conteúdo do diff e da descrição**, quando nada acima resolve.

| Tipo | Quando |
|---|---|
| `feat` | Comportamento novo visível para usuário ou consumidor da API |
| `fix` | Corrige comportamento errado, sem urgência de produção |
| `hotfix` | Correção urgente de produção (branch `hotfix/`, label, ou descrição falando em incidente) |
| `revert` | Desfaz outra PR. Sempre ligue à PR revertida |
| `refactor` | Muda estrutura sem mudar comportamento esperado |
| `perf` | Otimização de desempenho |
| `deps` | Atualização de dependências |
| `chore` | Build, configuração, scripts, limpeza |
| `docs` | Só documentação |
| `test` | Só testes |
| `ci` | Pipelines, workflows, deploy |

Se o título diz uma coisa e o diff mostra outra (ex.: "refactor" que muda regra de negócio), classifique pelo diff e cite isso em `motivosRisco`.

## Risco

Some os sinais. Um único sinal crítico já basta para **alto**.

### Sinais críticos (→ alto)
- Migração de banco que remove/renomeia coluna ou tabela, muda tipo, ou roda sobre tabela grande sem estratégia.
- Mudança de contrato público: endpoint removido/renomeado, campo obrigatório novo, resposta com formato diferente, evento/mensagem com schema alterado.
- Autenticação, autorização, permissões, criptografia, sessões, tokens.
- Pagamentos, cobrança, cálculo de preço/frete/imposto, estoque.
- Breaking change declarado (`!`, "BREAKING CHANGE" no corpo).
- Atualização *major* de dependência central (framework, ORM, driver de banco, SDK de pagamento).
- Mudança de infraestrutura que afeta produção: variáveis de ambiente novas/obrigatórias, filas, cache, feature flag ligada por padrão, config de deploy.
- Revert (algo já deu errado) ou hotfix (produção estava com problema).

### Sinais de atenção (2 ou mais → médio; 1 → baixo a médio conforme a área)
- PR grande: mais de ~500 linhas alteradas ou ~20 arquivos, excluindo lockfiles e arquivos gerados.
- Nenhum teste adicionado ou alterado numa PR que muda lógica.
- Zero aprovações, ou merge em poucos minutos após abrir.
- Mexe em código compartilhado (utils, middlewares, componentes base, clientes HTTP).
- Tratamento de erro, retries, timeouts, concorrência, jobs agendados.
- Muitas áreas diferentes na mesma PR.
- Descrição vazia numa PR não trivial.

### Sinais que só aparecem no diff

Leia o código procurando estes padrões. Cada um vale como sinal de atenção, ou crítico se estiver numa área crítica ou tiver alcance grande.

- **Assinatura mudou:** parâmetro novo obrigatório, parâmetro removido, tipo de retorno diferente, função que passou a lançar exceção. Cruze com o alcance: quantos chamadores existem e se foram todos atualizados na mesma PR.
- **Comportamento mudou sem a assinatura mudar:** valor padrão diferente, arredondamento, ordenação, fuso horário, comparação `==` virando `===`, filtro novo numa query, condição invertida. É o tipo de quebra que passa nos testes existentes.
- **Tratamento de erro:** `catch` que engole exceção, erro que passou a ser propagado, fallback removido, timeout ou retry alterado.
- **Dados existentes:** migração sem valor padrão para coluna nova `NOT NULL`, mudança de enum ou de formato gravado, backfill ausente, migração sem `down`.
- **Consultas:** query nova sem índice em tabela grande, N+1 dentro de loop, `SELECT *` virando junção pesada, remoção de `LIMIT`.
- **Concorrência e estado:** cache com chave ou TTL novo, variável global, lock removido, operação que deixou de ser idempotente, job que pode rodar em duplicidade.
- **Contrato:** campo renomeado ou removido em resposta de API, DTO, evento de fila ou webhook; status HTTP diferente; validação mais restritiva na entrada.
- **Configuração:** leitura de variável de ambiente nova sem valor padrão, feature flag ligada por padrão, URL ou credencial trocada.
- **Código morto que não está morto:** remoção de função ou rota que o alcance mostra ainda ter usos.

### Alcance

Quando houver medição de alcance (quantos lugares usam o que mudou):
- Mudança de assinatura ou de comportamento com usos em **3 ou mais áreas diferentes**: suba um nível de risco.
- Usos em área crítica (pagamento, checkout, autenticação...) de uma função alterada fora dela: trate como se a PR tocasse a área crítica.
- Poucos usos, todos atualizados na própria PR e com testes: pode baixar a preocupação, dizendo isso no motivo.

### Baixo
- Só docs, testes, textos, estilos isolados, dependências *patch*/*minor* de dev, ou mudança pequena, testada e revisada numa área não crítica.

## Como escrever

- `motivosRisco`: frases curtas e concretas, citando o arquivo ou a mudança. Bom: "Remove coluna `legacy_id` em `orders` (migração 2026_09_03)". Ruim: "Mudança sensível".
- Marque a `fonte` de cada motivo: `codigo` quando você viu no diff ou no alcance; `metadados` quando vem de tamanho, falta de testes, revisão, tempo de merge ou nome de arquivo. Um risco alto precisa de pelo menos um motivo com fonte `codigo`, a não ser que o diff não tenha sido lido (e então diga isso).
- `impacto`: diga quem sente a mudança. "Clientes do app veem o novo parcelamento no checkout", "Integrações que usam `GET /v1/orders` passam a receber `status` como enum".
- Para baixo risco, um motivo basta ("Só documentação").
- Não trate falta de evidência de quebra como prova de que está tudo bem: o campo `quebra` fica `nao`, mas o risco continua o que os sinais indicam.

## Pontos de atenção

Gere de 2 a 6 itens acionáveis para o time a partir das PRs de risco alto/médio e das quebras. Exemplos:
- "Acompanhar taxa de erro do checkout após #482 (parcelamento), que entrou sem testes."
- "Confirmar com o time de integrações a mudança de contrato em #490 antes do próximo release mobile."
- "#495 reverteu #488: a funcionalidade de cupom ainda não está em produção."
