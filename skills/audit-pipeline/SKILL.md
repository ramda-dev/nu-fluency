---
name: audit-pipeline
description: Lints a Nushell snippet with `nu-lint` (or an agent fallback when it is not installed) and applies or reports the fixes. Use after writing or before running Nushell code (including `nu_exec`/`nu_repl` calls), when debugging it, or when asked for Nushell diagnostics or a nu-lint run.
argument-hint: "[<nushell snippet or .nu path>] [--read-only]"
allowed-tools: ["Bash(nu --version *)", "Bash(which nu-lint *)", "Bash(wsl.exe --exec which nu-lint *)", "Bash(nu-lint *)", "Bash(wsl.exe --exec nu-lint *)", "Bash(wsl.exe --exec wslpath *)", "Agent(nu-fluency:generate-diagnostics)", "Read(*)"]
shell: bash
---

# Audit Pipeline

The `!`-executed probes and the argument substitution in the
[snippet](#snippet) run once at invocation, like a slash command's
preprocessing; this is not a recurring hook.

## Snippet

The snippet to lint is everything passed to the skill, without a `--read-only`
flag at its start or end:

```text
$ARGUMENTS
```

Claude Code (2.1.326) escapes `!` when it substitutes the arguments: a `!` at
the start of a word or line arrives as `\!` (so `!=` arrives as `\!=`), and a
space is put between a backtick and an adjacent `!`, after which a `!` that
starts a word gets the backslash too (`` `a b`! `` arrives as `` `a b` \! ``,
and a word-initial `!` before a backtick as `\!`, a space and the backtick).
Undo both wherever you use the snippet (the heredoc or the fallback agent's
prompt). A space that was already before the `!` cannot be
told apart from an inserted one, so keep it only where the code needs it.

If the snippet is empty (no arguments, only `--read-only`, or the block above
still shows the placeholder), lint the Nushell code you most recently wrote or
ran. If the block holds only the path of a `.nu` file, lint that file: give its
path to `nu-lint` in place of `--stdin` and the heredoc (inside WSL, convert it
first with `wsl.exe --exec wslpath -a -u '<path>'` and pass the result with an
extra leading `/`, as for the config path below).

## Environment

- Nushell version: !`nu --version 2>/dev/null || echo 'not found'`
- Nu-Lint native installation path: !`which nu-lint 2>/dev/null || echo 'not found'`
- Nu-Lint WSL installation path: !`wsl.exe --exec which nu-lint 2>/dev/null || echo 'not found'`
- Strict config path inside WSL: !`wsl.exe --exec wslpath -u '${CLAUDE_PLUGIN_ROOT}/configs/strict.nu-lint.toml' 2>/dev/null || echo 'not found'`

If the native Nu-Lint installation path is an absolute path (not
`not found`), follow the standard [procedure](#procedure).

Else, if the WSL installation path is an absolute path and the strict config
path inside WSL is not `not found`, follow the standard
[procedure](#procedure), but run the linter inside WSL with this command, the
strict config path inside WSL found above in place of the placeholder:

```bash
wsl.exe --exec nu-lint --stdin --format compact --config "/<strict config path inside WSL>" <<'PIPELINE'
<the snippet, verbatim>
PIPELINE
```

Write `wsl.exe --exec` exactly, so the skill's permission rule covers it. The
extra leading `/` stops Git Bash from rewriting the path into a Windows one;
Linux reads `//work/…` as `/work/…`.
Choose the heredoc delimiter as in the [procedure](#procedure).

`wsl.exe --exec` runs its program without a shell, so neither probe nor
command reads a shell profile: `nu-lint` is found only on the distribution's
default `PATH`, not in a directory a profile adds (such as `~/.cargo/bin`).

Else, follow the [fallback](#fallback) instructions.

## Procedure

1. Run the linter on the snippet. Call it by name, `nu-lint`, as written
   below rather than by the path found above, so the skill's permission rule
   covers it.

   The quoted heredoc (`<<'PIPELINE'`) stops bash from expanding the snippet
   as shell syntax. A snippet line that is exactly the delimiter would end the
   heredoc early and run the lines after it as bash, so when any line of the
   snippet is `PIPELINE`, pick a word that no line equals (`PIPELINE_END`,
   `NU_SNIPPET_1`, …) and use it in both the opener and the closer.

   ```bash
   nu-lint --stdin --format compact --config "${CLAUDE_PLUGIN_ROOT}/configs/strict.nu-lint.toml" <<'PIPELINE'
   <the snippet, verbatim>
   PIPELINE
   ```

2. Render the diagnostics directly, one per line, with line/column references.

## Fallback

1. Invoke the `nu-fluency:generate-diagnostics` subagent
   ([definition](../../agents/generate-diagnostics.md)). Pass it the code to
   lint, un-escaped: the snippet, the code you most recently wrote or ran when
   the snippet is empty, or for a `.nu` path that path with an instruction to
   Read the file and review its contents. If the WSL installation path was an
   absolute path but the strict config path inside WSL was `not found`, say
   so, so the agent recommends a config fix instead of an install. On a
   Windows host, also tell it that nu-lint installed inside WSL only in
   `~/.cargo/bin` is not found, so it mentions the README's symlink step.
2. Prepend a one-line caveat to your output indicating the diminished integrity.
3. Present the agent's findings as it returns them (quoted snippet, why, the
   alternative), with its uncertainty note and install recommendation. Its
   alternatives are suggestions: on this path apply no fix automatically, even
   without `--read-only`, and wait for confirmation.

## Constraints

If diagnostics return with no warnings or errors, say so explicitly.

If the arguments do not start or end with the flag `--read-only`, apply
sensible fixes automatically and await confirmation for further edits.

Else, present the diagnostics to the user without making any changes, and
for each diagnostic, surface the output of `nu-lint --explain <rule>`
(`wsl.exe --exec nu-lint --explain <rule>` when the linter runs inside WSL;
on the fallback path, name the related rule instead).
