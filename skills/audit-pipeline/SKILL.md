---
name: audit-pipeline
description: Lints a Nushell snippet with `nu-lint` (or an agent fallback when it is not installed) and applies or reports the fixes. Use after writing or before running Nushell code (including `nu_exec`/`nu_repl` calls), when debugging it, or when asked for Nushell diagnostics or a nu-lint run.
argument-hint: "<nushell snippet> [--read-only]"
allowed-tools: ["Bash(nu --version *)", "Bash(which nu-lint *)", "Bash(wsl.exe --exec which nu-lint *)", "Bash(nu-lint *)", "Bash(wsl.exe --exec nu-lint *)", "Task(*)", "Read(*)"]
shell: bash
---

# Audit Pipeline

The `!`-executed probes and the `$ARGUMENTS` substitution below run once at
invocation, like a slash command's preprocessing — this is not a recurring
hook.

## Snippet

The snippet to lint is everything passed to the skill, without a `--read-only`
flag at its start or end:

```text
$ARGUMENTS
```

## Environment

- Nushell version: !`nu --version 2>/dev/null || echo 'not found'`
- Nu-Lint native installation path: !`which nu-lint 2>/dev/null || echo 'not found'`
- Nu-Lint WSL installation path: !`wsl.exe --exec which nu-lint 2>/dev/null || echo 'not found'`

If the native Nu-Lint installation path is a path (not `not found`), follow the standard [procedure](#procedure).

Else, if the WSL installation path is a path, then
follow the standard [procedure](#procedure) with the entire command call wrapped
with `wsl.exe` to ensure the binary is on PATH.

Else, follow the [fallback](#fallback) instructions.

## Procedure

1. Run the linter on the snippet. Call it by name, `nu-lint`, as written
   below rather than by the path found above, so the skill's permission rule
   covers it.

   ```bash
   # quoted heredoc (<<'PIPELINE') stops bash from expanding the snippet as shell syntax
   nu-lint --stdin --format compact --config "${CLAUDE_PLUGIN_ROOT}/configs/strict.nu-lint.toml" <<'PIPELINE'
   <the snippet, verbatim>
   PIPELINE
   ```

2. Render the diagnostics directly, one per line, with line/column references.

## Fallback

1. Invoke the [`generate-diagnostics`](../../agents/generate-diagnostics.md) Task agent.
2. Prepend a one-line caveat to your output indicating the diminished integrity.
3. Present the diagnostics in a table with each row containing a message and a
line/column reference

## Constraints

If diagnostics return with no warnings or errors, say so explicitly.

If `$ARGUMENTS` does not contain the flag `--read-only`, apply sensible fixes
automatically and await confirmation for further edits.

Else, present the diagnostics to the user without making any changes, and
for each diagnostic, surface `nu-lint --explain <rule>` output.
