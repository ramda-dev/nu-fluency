---
name: nushell-idioms
description: >
  Idiomatic Nushell instead of bash translated into nu: structured data,
  pipelines over `let` chains, bash-to-nu equivalents and the common traps.
  Use whenever writing, reading, debugging or running Nushell (`.nu` and
  `.nuon` files, the `nu_exec`/`nu_repl` tools) or converting shell code to
  nu.
allowed-tools: Bash(nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" *)
compatibility: Requires Nushell 0.117.0 or later.
metadata:
  version: 0.2.1
---

# Nushell Idioms

Nushell is a **structural-data-first** shell: parse text into records, lists and tables once, transform them
with pipelines, and render text only at the end. The biggest source of mistakes is reaching for bash patterns,
whose text streams dominate training data and cloud intuition about nu. This skill names the common traps and
their idiomatic replacements.

Known bugs and option-dependent behavior for the running nu, if any:

!`nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" nushell-idioms 2>/dev/null || true`

Native types outside of base primitives (`string`, `int`, etc.) are expansive:

- `record` -> mapping of key-value pairs
- `list` -> sequence of elements
- `table` -> sequence of records with compatible columns (keys)
- `filesize` -> byte-measurement unit (uses suffix; e.g. `3GB`)
- `duration` -> timespan-measurement unit (uses suffix; e.g. `2sec`)
- `datetime` -> temporal-measurement unit (run `date --help` in nu for more info)

## Self-Prompted Reflection

Internalize asking yourself the following question when composing a Nushell pipeline:

> For each `let` assignment, does it carry a state forward or express a transformation?

- state -> keep the `let`
- transformation -> collapse into pipeline

Majority of the time, it's a transformation and does not need assignment.

Two `let` forms exist and behave differently:

- **Statement form** `let name: TYPE = <expr>` is parse-time.
Enforced type annotations (record/string mismatches reject).
- **Pipeline form** `<pipeline> | let name` is runtime.
Its type annotation is checked when the value arrives.

## Bash to Nushell Equivalents

| Bash | Nushell |
|---|---|
| `$( cmd \| jq … )` capture and parse | `cmd \| from json` (nu reads JSON, YAML, CSV, TOML natively) |
| `for x in $(ls); do …; done` | `ls \| each { \|f\| … }` or `for f in (ls) { … }` |
| `grep pattern file` | `open file \| where $it =~ "pattern"` (or `find "pattern"`) |
| `awk '{print $2}'` | `split column " " \| get column1` (columns count from `column0`) |
| `sed 's/a/b/'` | `str replace 'a' 'b'` |
| `cat f \| head -n 5` | `open f \| first 5` |
| `wc -l < file` | `open file \| lines \| length` |
| `arr=(a b c); echo "${arr[1]}"` | `let arr = [a b c]; $arr.1` |
| `[[ -n "$x" ]]` | `($x \| is-not-empty)` |
| `if [[ "$x" == "y" ]]; then …; fi` | `if $x == "y" { … }` |
| `read -r line` | (rare; nu is non-interactive by default in scripts) |
| `printf "%s\n" "${arr[@]}"` | `$arr \| each { print $in }` (rare; most times `$arr` suffices) |
| `cmd 2>/dev/null` | `cmd e>\| ignore` (drop stderr); `cmd \| complete` to capture both for inspection |
| `set -e` | (built-in; pipelines stop on first error unless `try` wraps) |

## Anti-Patterns: Common Mistakes

These show up in nu code written by people fluent in bash. Each has a one-line correction.

### 1. Two sequential `let`s where one pipeline would do

```nu
# anti-pattern
let parsed = ($env.RAW_INPUT | from json)
let result = ($parsed | where active == true | length)
# idiomatic
let result = ($env.RAW_INPUT | from json | where active == true | length)
```

The intermediate name `parsed` is unnecessary.
Substituting the bare expression produces the same result.

### 2. Blocks and closures with `$env` mutations

Parser keywords use blocks
(e.g. `for`, `loop`, `while`, `match`, `if/else`)
and most will propagate environment changes.

- Function definitions require `def --env` to enable `$env` propagation.

Commands use closures
(e.g. `[par-]each`, `items`, `reduce`, `upsert`)
and, by default, do not propagate environment changes.

- `collect` with `--keep-env`/`do` with `--env` will enable `$env` propagation.

```nu
# anti-pattern — `each` runs a closure, not a block
[1 2 3] | each { |n| $env.LAST = $n }
$env.LAST  # error: not set
# idiomatic — `for` runs a block
for n in [1 2 3] { $env.LAST = $n }
$env.LAST  # "3"
```

### 3. `try/catch` swallowing a single cell-path access

```nu
# anti-pattern
let name = (try { $person.name } catch { "unknown" })
# idiomatic — `?` postfix returns null instead of erroring
let name = $person.name? | default "unknown"
```

### 4. `print` chains before a return

```nu
# anti-pattern
print $env.A
print $env.B
print "done"
$env.RESULT

# idiomatic — last expression IS the return
{a: $env.A, b: $env.B, result: $env.RESULT}
```

- If you want all three visible AND the result, return a record.
- If you really need to print mid-pipeline, that's a side effect; do it sparingly.

### 5. Explicit `get N` for list indexing

```nu
# anti-pattern
let third = $planets | get 2
# idiomatic
let third = $planets.2
```

Cell paths work on lists too.

### 6. `alias` standing in for a command

```nu
# anti-pattern — an alias wrapping a closure works, but reads as a typo
alias count-lines = do {|| lines | length }
# idiomatic — a def reads as a function and declares its I/O types
def count-lines []: string -> int { lines | length }
```

### 7. Path string surgery for a sibling

```nu
# anti-pattern — reads as string replacement
$nu.data-dir | path basename --replace my-tool/cache
# idiomatic — says "sibling of data-dir"
$nu.data-dir | path dirname | path join my-tool cache
```

## Anti-Patterns: False Positives

`nu` idioms can look unfamiliar coming from bash. These are all correct and intentional:

1. **Implicit Return**

- The last expression of a closure or pipeline **always** returns a value.
- The `return` keyword has few valid use cases outside of early closure exits.
- The `echo` command has almost 0 valid use cases, as it merely _returns_ the arguments
(which is what bare values already do).

2. **Contextual Strings**

Strings in the starting position of an expression are always _invoked_.

```nu
dirname . # .
/usr/bin/dirname . # .
```

Nushell parses tokens, so pass strings without whitespace as unquoted literals.

Strings with whitespace that require treatment as one argument still require quotes.

- `cd example/path` is valid
- `cd 'example/path/with whitespace/'` is valid

Function signatures can specify an argument's type as `path` or `directory`.

- This streamlines path resolution and operations using the argument in the function.
- The value itself, when piped to `describe`, will still show `string`.
- `directory` is the same as path except completions only include directories.

Function signatures can also specify an argument's type as `glob`.

- Unlike `path`, `glob` values piped to `describe` will return `glob`.
- Conversion to `glob` supported by `into glob`.
- Conversion from `glob` supported by `into string`.
- The built-in `ls` command uses a `glob` argument signature.

Path and glob arguments do not require quotations, unless they contain whitespace.

- `ls foo/bar` is valid and the same as `ls "foo/bar"`
- The same follows for `ls foo/**/*`

Records, tables, and lists treat unparenthesized tokens as strings.

- `{me: whoami} | get me` => `whoami`
- `{me: (whoami)} | get me` => `<username>`

The quotation character used influences the parsing behavior.

- Double-quotes allow backslash-escaping:
  - `"\n"` => `<newline>`
- Single-quotes parse as literal strings:
  - `'\n'` => `\n`
- This behavior also applies to string interpolation.

Interpolation uses parentheses and a distinct convention that differs from bash.

- Syntax uses either double or single quotes prefixed with `$`.
- Only subexpressions produce evaluated values (no bracketed expansion).
  - `$"hello ($env.USER)"` in `nu` = `echo "hello ${USER}"` in `bash`

3. **Environment Mutation**

Environment mutations propagate automatically through direct assignments
on `$env` or with `load-env`, _within_ their enclosing scope.

```nu
$env.x = 'assigned'
load-env {y: loaded}
$env | get x y | str join , # assigned,loaded
```

Construct temporary environments and run a closure via the `with-env` command.

```nu
$env.ABC? # null
with-env {ABC: 123} { $env.ABC } # 123
```

See [`nushell-env-scoping`](../nushell-env-scoping/SKILL.md) for more information.

4. **Implicit Input**

Pipeline input flows into a block without being named, so code that looks
empty or unfinished in bash terms is often deliberate:

- `else { }` or a `match` arm `=> ()` passes the input through unchanged.
- A bare `let x;` (no initializer) binds the block's input; `… | let x | …`
  binds the value and passes it on.
- A cell path's `!` suffix means case-insensitive (`$env.path!`), not negation;
  `!?` is case-insensitive and optional.

See [`nushell-control-flow`](../nushell-control-flow/SKILL.md) for what `$in`
is inside `match` arms and later statements.

## Shape Verification

When uncertain what a value's shape is mid-pipeline, inspect it:

- Read the `[result type: ...]` footer on every `nu_exec` result first.
- `<expr> | describe --detailed` → type, detailed type, and length.
- `<expr> | columns` → field names of a record/table row.
- Default to using safe access methods (e.g. `value.property?`)
when chaining further operations onto a value whose shape was not directly observed.

## Sibling Skills

This skill may not cover the full extent of any inquiry or composition.

Use the mapping below to compound relevant sibling skills:

[`nushell-records`](../nushell-records/SKILL.md)

- Load when working with records or tables.

[`nushell-env-scoping`](../nushell-env-scoping/SKILL.md)

- Load when working with `$env`, persistence, or scope propagation.

[`nushell-strings`](../nushell-strings/SKILL.md)

- Load when working with string parsing, formatting, or interpolation.

[`nushell-control-flow`](../nushell-control-flow/SKILL.md)

- Load when working with iteration, conditionals, and/or error handling.

[`nushell-modules`](../nushell-modules/SKILL.md)

- Load for writing/organizing nu code into reusable units.

## References

[cheat sheet](./references/cheat-sheet.md)

- Syntax-dense quick reference with annotated examples and inline-comment results
for every primitive, plus sections on conversions, records, lists, tables, strings,
filesystem, env and scope, variables, control flow, custom commands, modules,
and cross-cutting flags.
- Each section that has a matching sibling skill links back to it as
the conceptual reference.

[testing](./references/testing.md)

- Framework-free guidance for testing Nushell code: assertions, child
interpreters, sandboxed environments, and why tests are called by literal name.

[diagnostics](./references/nushell-diagnostics.md)

- Known Nushell bugs the skills work around, each with a repro, a workaround
and the versions it was reproduced on, plus behavior that depends on an
experimental option. Read when nu behaves against what a skill says.

[tooling](./references/tooling.md)

- The bundled `nu --lsp` server and the `nu-lint` linter: what each checks and
its entry points. Read when setting up or interpreting diagnostics.

## Constraints

- Refrain from using `print` whenever pipeline result would suffice.
- Debug using Nushell's introspection commands (e.g. `inspect`, `debug`, `describe`).
- Pay attention to both "what" differs from bash and "why" it differs.
  - This will help build an _intuition_ for "thinking-in-nu"
