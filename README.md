# nu-fluency

A plugin that helps Claude write [Nushell](https://github.com/nushell/nushell) (`nu`) code idiomatically.

## Installation

```nu
# 1. Ensure your Nushell version is compatible
version | get version # >= 0.117.0
# 2. Add the plugin marketplace
claude plugin marketplace add zaynram/code-marketplace
# 3. Install the `nu-fluency` plugin
claude plugin install nu-fluency@ramda-code-marketplace
```

## Background

When first introducing Claude to `nu`, we both agreed that it seemed like an
LLM's optimal shell; it's natural language semantics and first-class support
for structured data bridges the gap between human and machine readable data.

This insight led to the construction of my
[`nushell-mcp`](https://github.com/zaynram/nushell-mcp).

After testing out the MCP with Claude, he would often treat it as "`bash` with
weird syntax", which we hypothesize is the result of POSIX convention being
over-represented in his training distribution.

This highlighted a need to teach Claude about Nushell and its
built-in primitives, as the default behavior of reaching for `bash` patterns
bottlenecked the advantages of `nu` semantics and structured-data support.

This plugin counteracts that bias by combining authoritative tooling (`nu-lint`)
with educational scaffolding.

## MCP Server

This plugin uses the `nushell-mcp` server, automatically installed
from its [NPM package listing](<https://www.npmjs.com/package/nushell-mcp>).

It provides a curated set of `nu` utilities to Claude including but not limited
to: `nu_exec` (one-shot `nu` pipeline execution) and `nu_repl` (persistent `nu`
REPL sessions piggybacking off of Nushell's built-in `nu --mcp`).

## Peer Dependency: Nu-Lint

The commands packaged in this plugin prefer to delegate diagnostics to [`nu-lint`](https://codeberg.org/wvhulle/nu-lint).

`nu-lint` is a deterministic community linter for Nushell whose rules are grouped into
`idioms`, `posix`-replacement, `parsing`, `dead-code`, `runtime-errors`, and more.

Most rules have auto-fixes, and the rules themselves respect the nuance of diverging
from the status quo in the age of LLM.

### Installation

```sh
# `--git <url>` - Build from latest source code
# `--locked` - Pins the lockfile's dependency versions.
cargo install --git https://codeberg.org/wvhulle/nu-lint --locked
```

On Windows with nu-lint installed inside WSL, `/audit-pipeline` looks for it on the
distribution's default `PATH` only, which does not include `~/.cargo/bin`. Link it
there (`sudo ln -s ~/.cargo/bin/nu-lint /usr/local/bin/nu-lint`), or the skill falls
back to the agent.

The hook system is inert by default, and will not warn or error when `nu-lint` is
unavailable. The only downside is losing out on deterministic diagnostics.

## Native LSP Integration

The plugin declares an LSP configuration with Nushell's built-in language server.

```jsonc
// .claude-plugin/plugin.json
{
    // ...
    "lspServers": {
        "nushell": {
            "command": "nu",
            "args": [
                "--lsp"
            ],
            "extensionToLanguage": {
                ".nu": "nu",
                ".nuon": "nu"
            },
            "restartOnCrash": true,
            "maxRestarts": 3
        }
    }
}
```

After plugin installation and the language server connects, Claude sees inline diagnostics,
hover info, and auto-fixes any time it edits a Nushell file.

## Components

| Type | Count | Purpose |
|---|---|---|
| Skills | 11 | `/nushell-idioms`, `/env-snapshot`, `/audit-pipeline`, `/command-help`; model-only: `inspect-shape`, `nushell-{records,env-scoping,strings,control-flow,modules,performance}` |
| Agents | 1 | Fallback review agent for `/audit-pipeline` when `nu-lint` isn't installed (**experimental**) |
| Hooks | 2 | Pre-`Bash` nudge toward nu equivalents; post-`nu_exec`/`nu_repl_write` hook that runs `nu-lint` on the executed code |
| LSP | 1 | `nu --lsp` via `lspServers` in `.claude-plugin/plugin.json` |
| Configs | 2 | `configs/hook.nu-lint.toml`, `configs/strict.nu-lint.toml` |

### Skills

#### User-Invocable

- **`/nushell-idioms`**
— (entry point) deep syntax lookup reference
([`cheat-sheet.md`](skills/nushell-idioms/references/cheat-sheet.md)),
`bash` → `nu` equivalents, pointers to nu-lint.
- **`/env-snapshot [keys...]`**
— `$env | select --optional <keys>` with sensible defaults.
- **`/audit-pipeline [<snippet or .nu path>] [--read-only]`**
— runs nu-lint on the snippet (or on the code Claude last wrote) and applies fixes;
`--read-only` only reports, with `nu-lint --explain` per rule. Falls back to the
experimental agent if nu-lint isn't installed.
- **`/command-help <name>`**
— inline help lookup via `nu_doc_help`.

#### Model-Only

- **`inspect-shape`**
— runs an expression through `nu_exec` and returns its detailed type, length
and first rows. Structural intuition.
- **`nushell-records`**
— records, tables, cell paths, `record each` / `record where`.
- **`nushell-env-scoping`**
— `$env`, `do --env`, `with-env`, `for` vs `each` propagation, automatic env vars.
- **`nushell-strings`**
— `parse` templates, `str` namespace, interpolation, `from <format>`.
- **`nushell-control-flow`**
— `for`/`each`/`reduce`/`any`/`all`/`take while`, conditionals, `try/catch` vs `?`.
- **`nushell-modules`**
— `module`/`use`/`export def`/`export-env`/`main`.
- **`nushell-performance`**
— closure-entry cost model, profile-first workflow, `probe` kit (`scripts/probe.nu`).

### Version notes

[`scripts/version-notes.nuon`](scripts/version-notes.nuon) lists known Nushell bugs
and behavior that depends on an experimental option. The idioms, control-flow,
env-scoping and performance skills run `scripts/version-notes.nu` when they load
and show only the notes that apply to the installed `nu`; the full table is
[`nushell-diagnostics.md`](skills/nushell-idioms/references/nushell-diagnostics.md).
After editing the data, run
`nu --no-config-file scripts/version-notes.nu render --write` (`check` fails
when the table is stale).

### Hooks

Pre-tool-use hook on `Bash` calls.
When the command does text processing that nu does structurally
(`jq`, `sed`, `awk`, `cut`, `xargs`, `find`, read loops, or `grep`/`wc`/`sort`/`uniq`
in a pipeline), it adds a short note naming the nu equivalents.
It never blocks or changes the permission decision; the command runs either way.
Cases live in `hooks/tests/nu-over-bash.nu`
(`nu --no-config-file hooks/tests/nu-over-bash.nu`).

Post-tool-use hook on MCP `nu_exec` and `nu_repl_write` calls.
Reads the tool's `pipeline` (or `input`) argument from stdin (JSON),
pipes it through `nu-lint --stdin --format compact` using the narrow
`configs/hook.nu-lint.toml`, and surfaces findings as a block reason iff
there are diagnostics surfaced.

The hook config is intentionally conservative
— `posix`, `idioms`, `parsing` as warnings and `dead-code` as hints
— so it fires on bash-translation patterns and skips stylistic noise.

For broader analysis, use `/audit-pipeline`
(which uses the `strict.nu-lint.toml` config).

## Conventions

The hook + nu-lint catches most of these mechanically,
but for completeness they are also enumerated here.

1. When a `let` chain forms, ask whether each step is
*carrying state* or *expressing a transform*.
Transforms collapse into pipeline stages.
2. Records are nu's primary data structure.
3. Env mutations propagate through keyword blocks
(e.g. `for`/`while`/`loop`, `match`, `if`/`else if`/`else`),
and certain commands with flags (`do --env`, and `def --env` for commands;
`collect --keep-env` does not, despite its help text).
The closures used in `each`/`items`/`reduce` and bare `do`/`collect` do not propagate
environment mutations.
4. Optional access (`<cell-path>?`) postfix on cell paths returns `null`.
Prefer it over `try/catch` for safe property/nested property access without errors.
5. NUON string quoting is context-dependent.
Assert via in-`nu` equality checks, not raw NUON comparison.
6. The last expression in a closure or pipeline is its return value, akin to `rust`.
Don't `print` what you're returning.

## License

MIT.
