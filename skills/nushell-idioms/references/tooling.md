# Nushell LSP and nu-lint

The bundled LSP uses the native `nu --lsp` server,
which provides realtime diagnostics when working on Nushell files.

When available, the `nu-lint` command provides much richer diagnostics,
and is what the plugin's post-`nu_exec`/`nu_repl_write` hook calls when checking that code.

It's a deterministic, community-maintained linter. Its most notable rule groups,
`replace-external-tools` (swap `grep`, `sed`, `jq` and the like for built-ins) and
`translate-bash-syntax` (bash operators and variables pasted into nu), cover a large
subset of bash → nu translation traps.

Useful entry points:

- `nu-lint <path>` — lint files in a directory (default `.`)
- `nu-lint --stdin --format=compact` — lint a snippet from stdin, one line per finding
- `nu-lint rules explain <rule>` — full rationale for a specific rule
- `nu-lint rules list` — every available rule with its configured level
- `nu-lint rules groups` — the rule groups and their rules
- `nu-lint fix <path>` — apply auto-fixes (most rules support this)

The [`audit-pipeline`](../../audit-pipeline/SKILL.md) skill runs `nu-lint` on a snippet, with an agent fallback
when it is not installed.
