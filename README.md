# claude-skills

Coleção pessoal de skills para o Claude.

## Instalar no Claude Code

```
/plugin marketplace add michelakira/claude-skills
/plugin install michel-skills@michelakira-skills
```

Para puxar atualizações depois: `/plugin marketplace update michelakira-skills`.

## Usar no claude.ai / Claude Desktop

1. Rode `./scripts/package-skills.sh` (gera um `.zip` por skill em `dist/`).
2. No claude.ai, vá em **Settings > Capabilities > Skills** e faça upload do `.zip`.

## Adicionar uma nova skill

1. Crie `plugins/michel-skills/skills/<nome-da-skill>/SKILL.md`:

   ```markdown
   ---
   name: nome-da-skill
   description: O que ela faz e QUANDO o Claude deve usá-la.
   ---

   Instruções da skill...
   ```

2. Arquivos de apoio (scripts, templates, referências) podem ficar na mesma pasta e ser citados no `SKILL.md`.
3. Suba a versão em `plugin.json`, faça commit e push.

A `description` é o que o Claude usa para decidir quando ativar a skill, então seja específico.

## Estrutura

```
.claude-plugin/marketplace.json      # catálogo do marketplace
plugins/michel-skills/
  .claude-plugin/plugin.json         # manifesto do plugin
  skills/<skill>/SKILL.md            # uma pasta por skill
scripts/package-skills.sh            # empacota skills para o claude.ai
```
