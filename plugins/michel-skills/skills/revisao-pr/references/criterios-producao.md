# O que quebra produção

Checklist usado pelo especialista de impacto, pelos verificadores e pelo parecer final. Exemplos em Laravel/PHP com MySQL; para outra stack, procure o equivalente.

O ponto central: **teste verde não garante deploy seguro.** Durante o deploy, coexistem o código antigo e o novo, o schema antigo e o novo, jobs enfileirados pelo código antigo e workers rodando o código novo. Muitas quebras só existem nesse intervalo, ou só com o cache de produção ligado.

## 1. Contratos com quem está fora da PR

- **Método/classe pública:** parâmetro novo obrigatório, parâmetro removido, tipo de retorno diferente, passou a lançar exceção, renomeado ou removido. Conte os chamadores fora da PR que não foram atualizados.
- **Comportamento sem mudar a assinatura:** valor padrão, arredondamento, ordenação, fuso horário, `==` → `===`, filtro novo em scope/query, `null` onde antes vinha array. Passa nos testes existentes e quebra quem depende do comportamento antigo.
- **API HTTP:** rota removida ou renomeada, método HTTP diferente, campo removido ou renomeado em Resource/JSON, campo novo obrigatório no FormRequest, status code diferente, paginação mudou de formato. Consumidores externos (app mobile, front, parceiros) não sobem junto.
- **Nomes de rota:** `route('nome')` em Blade, e-mails, redirects e front.
- **Eventos, filas e webhooks:** payload de evento/broadcast/mensagem com schema alterado; listeners em outros serviços.
- **Blade/Livewire/Inertia:** variável que a view espera e o controller deixou de mandar; props de componente.

## 2. Compatibilidade durante o deploy

- **Migration x código antigo:** coluna removida ou renomeada enquanto o código antigo (outros servidores, workers, cron) ainda a lê. Padrão seguro: expandir → migrar código → contrair em PRs separadas.
- **Coluna `NOT NULL` sem default** em tabela com dados, ou que o código antigo não preenche no `insert`.
- **Jobs já enfileirados:** construtor do Job mudou (propriedade renomeada/removida, tipo diferente, model serializado que mudou). Jobs criados pelo código antigo falham ao desserializar no worker novo. Classe de Job renomeada ou movida também quebra.
- **Workers não reiniciados:** mudança em Job/Listener/Service usado pela fila exige `php artisan queue:restart` ou `horizon:terminate`. Verifique se o deploy faz isso.
- **Cache com formato novo:** mesma chave guardando estrutura diferente (o código novo lê o valor antigo e vice-versa). Model serializado em cache.
- **Sessão:** dados de sessão com formato novo; troca de driver ou cookie.
- **Scheduler:** comando agendado renomeado, frequência mudou, `withoutOverlapping`/`onOneServer` removido.

## 3. Configuração e ambiente

- **`env()` fora de `config/`:** com `config:cache` em produção, retorna `null`. Funciona em dev e quebra em produção.
- **Variável de ambiente nova** sem default no `config/*.php` e sem entrada no `.env.example`. Precisa ser criada em produção antes do deploy.
- **Closure em rota ou config** impede `route:cache`/`config:cache`.
- **Service provider novo** não registrado em `bootstrap/providers.php` / `config/app.php`.
- **Feature flag** nova ligada por padrão.
- **Dependência:** upgrade major em `composer.json`/`package.json`, extensão PHP nova, versão mínima do PHP alterada.

## 4. Banco de dados

- **ALTER em tabela grande:** mudança de tipo, coluna com default em MySQL antigo, índice sem `ALGORITHM=INPLACE`/ferramenta online. Pode travar a tabela por minutos.
- **Update/delete em massa na migration** sem lote.
- **Migration sem `down`**, ou `down` que perde dados.
- **Mudança de enum** ou de formato gravado (JSON, datas, valores em centavos x reais) sem backfill.
- **Unique/foreign key nova** sobre dados que já violam a regra: a migration falha em produção e passa no banco vazio dos testes.

## 5. Áreas críticas

Qualquer mudança aqui sobe o risco de produção para pelo menos `medio`, mesmo sem bug encontrado: pagamento, cobrança, preço, frete, imposto, estoque, autenticação, autorização, sessão, criptografia, dados pessoais, integrações com terceiros (timeouts, retry, credenciais).

## Severidade

| Severidade | Quando |
|---|---|
| `bloqueante` | Quebra provável em produção: chamador não atualizado, contrato quebrado com consumidor real, job em fila que vai falhar, `env()` fora de config, migration que trava tabela grande ou falha com dados reais, falha de segurança explorável, perda de dados. |
| `importante` | Quebra possível em condições específicas, ou exige um passo manual no deploy que, se esquecido, quebra (env nova, `queue:restart`, ordem de deploy). |
| `sugestao` | Melhoria opcional, sem risco de quebra. |

Um passo de deploy obrigatório **não é bug** da PR: é `importante` e entra no checklist de deploy. Vira `bloqueante` só se não houver jeito seguro de fazer o deploy.

## Risco de produção

- **alto:** algum sinal das seções 2 ou 4 confirmado, contrato quebrado com consumidor fora do repositório, ou área crítica com comportamento alterado.
- **medio:** área crítica tocada sem quebra encontrada, passo manual de deploy, código compartilhado com muitos usos (`mapa_impacto` com 10+ usos fora da PR), ou testes não executados numa área com lógica.
- **baixo:** mudança isolada, sem contrato alterado, com testes executados e passando.
