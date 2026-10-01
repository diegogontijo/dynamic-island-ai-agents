# Agent Island

Clique no notch do MacBook para ver quanto resta das janelas de 5 horas (e semanais) do **Claude Code** e do **Codex**.

## Instalar

```bash
./scripts/build.sh --install
```

Gera `build/AgentIsland.app`, copia para `/Applications` e abre. O app não aparece no Dock. Fica um ícone na barra de menus com: resumo, atualizar (⌘R), abrir ao iniciar sessão e sair.

## Como funciona

- **Claude Code:** lê o token OAuth que o Claude Code guarda no Keychain (`Claude Code-credentials`) e consulta `api.anthropic.com/api/oauth/usage`, a mesma fonte do `/usage`.
- **Codex:** lê `~/.codex/auth.json` e consulta `chatgpt.com/backend-api/wham/usage`, a mesma fonte do `/status`.
- Os tokens são só lidos, nunca renovados, então o login dos CLIs não é afetado. Se um token expirar, o painel pede para abrir o CLI correspondente, que renova o token sozinho.
- Atualiza a cada 3 minutos e também ao abrir o painel (se os dados tiverem mais de 30 s).
