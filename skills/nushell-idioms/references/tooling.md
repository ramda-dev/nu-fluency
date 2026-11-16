# Nushell LSP and nu-lint

The bundled LSP uses the native `nu --lsp` server,
which provides realtime diagnostics when working on Nushell files.

When available, the `nu-lint` command provides much richer diagnostics,
and is what the plugin's post-`nu_exec` hook calls when checking a pipeline.

It's a deterministic, community-maintained linter. Its most notable rule group,
`posix`, aims to "replace common bash/posix patterns", which covers a large
subset of bash → nu translation traps.

Useful entry points:

- `nu-lint <path>` — lint files in a directory (default `.`)
- `nu-lint --stdin --format=compact` — lint a snippet from stdin, one line per finding
- `nu-lint --explain <rule>` — full rationale for a specific rule
- `nu-lint --list` — every available rule, by group
- `nu-lint --fix <path>` — apply auto-fixes (most rules support this)

The [`audit-pipeline`](../../audit-pipeline/SKILL.md) skill runs `nu-lint` on a snippet, with an agent fallback
when it is not installed.
