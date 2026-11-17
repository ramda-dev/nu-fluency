---
name: audit-pipeline
description: Lints a Nushell snippet with `nu-lint` (or an agent fallback when it is not installed or cannot be found) and applies or reports the fixes. Use after writing or before running Nushell code (including `nu_exec`/`nu_repl` calls), when debugging it, or when asked for Nushell diagnostics or a nu-lint run.
argument-hint: "[<nushell snippet or .nu path>] [--read-only]"
allowed-tools: ["mcp__plugin_nu-fluency_nushell__nu_exec", "Agent(nu-fluency:generate-diagnostics)", "Read(*)"]
compatibility: Requires Nushell 0.117.0 or later.
metadata:
  version: 0.2.0
---

# Audit Pipeline

The argument substitution in the [snippet](#snippet) happens once, at
invocation, like a slash command's preprocessing; this is not a recurring hook.

## Snippet

The snippet to lint is everything passed to the skill, without a `--read-only`
flag at its start or end:

```text
$ARGUMENTS
```

Claude Code (2.1.326) escapes `!` when it substitutes the arguments: a `!` at
the start of a word or line arrives as `` \! `` (so `!=` arrives as `\!=`), and a
space is put between a backtick and an adjacent `!`, after which a `!` that
starts a word gets the backslash too (`` `a b`! `` arrives as `` `a b` \! ``,
and a word-initial `!` before a backtick as `` \! ``, a space and the backtick).
Undo both wherever you use the snippet (the `nu_exec` input or the fallback
agent's prompt). A space that was already next to the `!` (before it, or
between it and a backtick) cannot be told apart from an inserted one, so keep
it only where the code needs it.

Two more changes cannot be undone: Claude Code expands its own `${CLAUDE_…}`
placeholders in the arguments (the plugin root, project directory, plugin data,
skill directory, session id and effort, each written in that dollar-brace form),
and a `` \! `` the code already had after a space arrives unchanged, so it reads like
an escaped `!`. When the snippet may hold either, lint the file or the code as
you wrote it instead.

If the snippet is empty (no arguments, only `--read-only`, or the block above
still shows the placeholder), lint the Nushell code you most recently wrote or
ran. If the block holds only the path of a `.nu` file, lint that file: pass the
path as `input` and read it in the pipeline, as shown in the
[procedure](#procedure).

## Procedure

The plugin's [`scripts/lint.nu`](../../scripts/lint.nu) finds nu-lint (on
`PATH`, in the cargo install folders, or on Windows inside WSL) and runs it on
code it reads from stdin, so the snippet never passes through a shell and needs
no quoting or escaping, whatever quotes or braces it holds.

1. Call `nu_exec` with `structured: false`, this pipeline, and as `input` the
   snippet's raw text with the escaping undone. Pass the text itself: the tool
   describes `input` as NUON or JSON, but here it must not be quoted or
   encoded, or nu-lint lints a single string literal and reports it clean.

   ```nu
   use r#'${CLAUDE_PLUGIN_ROOT}/scripts/lint.nu'#; $in | lint check strict | to json
   ```

   For a `.nu` file, pass its absolute path as `input` instead, as plain text,
   and read the file (a relative path resolves against the MCP server's
   directory, not the project's):

   ```nu
   use r#'${CLAUDE_PLUGIN_ROOT}/scripts/lint.nu'#; open --raw ($in | str trim) | lint check strict | to json
   ```

2. Read the JSON result:
   - `linter` is null: nu-lint was not found or could not be started (`stderr`
     says why). Follow the [fallback](#fallback).
   - `diagnostics` is not empty: render the findings directly, one per line,
     with their line/column references.
   - `diagnostics` is empty and `exit_code` is 0: the snippet is clean.
   - Otherwise nu-lint ran and failed: report its `stderr` and `output` and
     stop; do not fall back.

   If the `nu_exec` call itself fails, check the cause first: an `open` error
   for a file that was not found means the `.nu` path was wrong (make it absolute and retry). Otherwise
   (the tool is unavailable, or `nu` cannot load the script) say so and follow
   the [fallback](#fallback).

## Fallback

1. Invoke the `nu-fluency:generate-diagnostics` subagent
   ([definition](../../agents/generate-diagnostics.md)). Pass it the code to
   lint, un-escaped: the snippet, the code you most recently wrote or ran when
   the snippet is empty, or for a `.nu` path that path with an instruction to
   Read the file and review its contents. Name the fix that applies, so the
   agent adds it to its recommendation: when nu-lint was not found, "install
   nu-lint (`cargo install --git https://codeberg.org/wvhulle/nu-lint --locked`);
   it is found on `PATH`, in `$CARGO_HOME/bin`, `~/.cargo/bin` or
   `~/.local/share/cargo/bin`, or on Windows also inside WSL", followed by the
   result's `stderr` when it names another cause; when `nu_exec` failed, what
   failed.
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
for each diagnostic, surface nu-lint's explanation of its rule: call `nu_exec`
with `structured: false` and the pipeline
`use r#'${CLAUDE_PLUGIN_ROOT}/scripts/lint.nu'#; lint explain <rule>` (on the
fallback path, name the related rule instead).
