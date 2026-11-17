---
name: nushell-control-flow
description: >
  Chooses the right Nushell iteration, conditional or error-handling form:
  `for` vs `each`, `where`/`any`/`all`/`take while` row conditions,
  `reduce`, `if`/`match`, what `$in` is, `try`/`catch` vs the `?` postfix.
  Use when writing loops, filters, maps, folds, branches or error paths in
  nu.
user-invocable: false
allowed-tools: Bash(nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" *)
compatibility: Requires Nushell 0.117.0 or later.
metadata:
  version: 0.2.1
---

# Nushell Control Flow

The single biggest decision in nu iteration is **`for` vs `each`** — they look similar, but they have completely different scope semantics. The single biggest decision in nu error handling is **`?` postfix vs `try/catch`** — they look unrelated, but they solve overlapping problems and `?` is almost always the right reach.

Syntax reference: [cheat-sheet → Control Flow](../nushell-idioms/references/cheat-sheet.md#control-flow) and [Lists → Operations and Accessing](../nushell-idioms/references/cheat-sheet.md#lists).

Known bugs and option-dependent behavior for the running nu, if any:

!`nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" nushell-control-flow 2>/dev/null || true`

## Iteration: pick the right tool

| Construct | Returns | Env propagates? | Use when |
|---|---|---|---|
| `each { \|x\| … }` | List of closure results | **No** | Pure map; you want the transformed list |
| `for x in $list { … }` | Nothing (side-effecting) | **Yes** | You're mutating state per iteration |
| `where <row condition>` | Filtered list/table | **No** | Predicate filter (`where size > 1kb`, `where $it > 2`) |
| `reduce -f INIT { \|x, acc\| … }` | Single accumulated value | **No** | Folding into one value |
| `any { \|x\| … }` | Bool | **No** | "Is there any element matching?" |
| `all { \|x\| … }` | Bool | **No** | "Do all elements match?" |
| `take while { \|x\| … }` | Prefix of list | **No** | Slice up to first failing |
| `skip while { \|x\| … }` | Suffix of list | **No** | Slice from first failing |
| `enumerate` | List of `{index, item}` | **No** | When you need the index |
| `items { \|k, v\| … }` (on records) | List of closure results | **No** | Iterating record entries |

**Rule**: if the loop body mutates `$env`, use `for`. Otherwise use the highest-level transform that fits: `each`/`where`/`reduce`/`any`/`all`/`take while`/`skip while`.

Predicates are row conditions, not closures: `where name =~ $re`, `take until name == $x`, `any name == $n`, `all $it in $expected`. A column is named bare on the left of an operator; use `$it` for a scalar element or inside parentheses. A closure (`where {|r| … }`) is only for a predicate that needs more than one expression, or for the two cases a row condition misreads:

- **A quoted string on the left of an operator is read as a column name**: `where bad and '.' not-in $it.at` fails with "Cannot find column '.'".
- **A bare word on the right is a string**: `where old != new` compares the column `old` with the text "new", not with the column `new`. Write `where {|r| $r.old != $r.new }`.

### Cost

`reduce --fold` that builds a list or record is quadratic, and `par-each` costs about a millisecond to enter, so it suits slow per-item work only; [`nushell-performance`](../nushell-performance/SKILL.md) has the cost model. Never `par-each` writes to shared state (files, SQLite, `$env`). Use `each --flatten` when each iteration yields a list (same cost as `each | flatten`, reads better).

## `reduce` parameter order

Nu's `reduce` closure is `{ |elt, acc| … }` — **element first, accumulator second**. Opposite of JavaScript's `reduce((acc, elt) => …)`. Easy bug source:

```nu
[1 2 3 4] | reduce -f 0 { |elt, acc| $acc + $elt }   # ✓ → 10
[1 2 3 4] | reduce -f 0 { |acc, elt| $acc + $elt }   # name confusion but same result
```

The names you write don't matter — positional binding does. First param is the element. Second is the accumulator.

The `--fold INIT` form is the long version; `-f INIT` is the short flag.

## Conditionals

`if` is an expression — it returns the chosen branch's value. No need for assignment inside; just use the whole expression as the value (`let result = (if ... { ... } else { ... })`).

`match` patterns can match literals, ranges, records, and lists. The fallback wildcard is `_`. Arms can destructure with `$`-prefixed bindings — `{type: "click", x: $x}` matches a record-shaped value and binds `$x` from the inner field. Use match for branching on shape, not just value.

## What `$in` is

Pipeline input flows implicitly, and a bash reader's instincts about "nothing" are wrong here:

- **An empty block or `()` passes the input through.** `5 | if false { 1 } else { }` is `5`, and a `match` arm `=> ()` returns the match's input. An empty `else` is an identity, not "produce nothing"; to discard, write `null` or pipe to `ignore`.
- **Inside a `match` arm, `$in` is the match's pipeline input, not the subject.** In `$p | match ($in | path type) { dir => (glob $"($in)/**") }` the arm's `$in` is the path. When both appear, bind the value first (`let p = …; match ($p | path type) { … }`).
- **Only a block's first statement receives its input implicitly.** Later statements reach it through `$in`, but an `if` or `match` there can see the input in its condition and an empty `$in` in its body ([known bug](../nushell-idioms/references/nushell-diagnostics.md)). Bind the input in the first statement (`let xs;` with no initializer binds it) or write `$in | if …`.
- **`each` doubles as "apply if present"**: piped a scalar or record it runs the closure once and returns the bare result; piped `null` it skips the closure. Use it that way only where the value can never be a list.

## Bare words in arms

In expression position a bare word is a command call. `match $x { null => written, _ => kept }` tries to run commands named `written` and `kept`; inside a list or record the same words are strings. Quote arm values: `null => 'written'`.

## Error handling

### The `?` postfix — first reach

For "this might be missing, default if so". Use `?` **inline on the cell path itself**, not as a wrapper around the access — `$record.deeply.nested.field?` returns null at the first missing link rather than erroring, and `$list.10?` is the list-index equivalent. Compose with `default` to substitute a value: `$record.name? | default "anonymous"`.

### `try/catch` — when something else might throw

```nu
try { 
    risky-operation 
} catch { |e| 
    print -e $"failed: ($e.msg)"
    "default value"
}
```

The catch closure receives an error record with `msg`, `debug`, `raw`, etc. The closure's return value becomes the expression's value if it threw.

**Use `try/catch` when**:

- Something other than a missing field could go wrong (file I/O, parse errors, external commands).
- You need to inspect the error (e.g., log `$e.msg`).
- The retry logic isn't expressible as a default.

**Don't use `try/catch` to**:

- Guard against null/missing fields → use `?` instead.
- Suppress all errors silently → at minimum log to stderr; better, fix the root cause.

### Expression-form `try`

`try` is an expression — you can use it on the right-hand side of a `let`: `let parsed = (try { open --raw $path | from json } catch { {} })`. This is the right idiom for "load if possible, default if not." The catch returns the default value, `let` binds the result. Avoids splitting load into multiple statements.

## A note on iteration shortcuts

For sum/product/min/max/avg, prefer `math sum` / `math product` / `math min` over a hand-rolled `reduce` — they read better and need no init value. `[] | math sum` raises an error rather than returning 0, so append a zero of the element type when the list can be empty: `append 0 | math sum` for numbers, `append 0ns` for durations, `append 0b` for filesizes (an `int` zero added to a duration or filesize is a type error). The `$it` implicit-element name works inside one-arg closures (`where $it > 2`), useful for short predicates that don't earn a named parameter. Use `enumerate` to pair each element with its index before mapping.

## Pitfalls

- **`each` for env mutation** is the most common iteration bug. If the loop body touches `$env`, use `for` ([`nushell-env-scoping`](../nushell-env-scoping/SKILL.md) owns the rules).
- **A command whose body ends in `try`/`catch` can stop catching when its output is piped to `ignore`** ([known bug](../nushell-idioms/references/nushell-diagnostics.md)). Bind the result instead (`let _ = f`).
- **`break` and `continue`** exist in `for`, `while` and `loop`. To transform a stream, prefer `take while` / `skip while` / `first N`; for a small scan that exits early and runs many times, a `for` with `break` is cheaper than `any` (see [`nushell-performance`](../nushell-performance/SKILL.md), pattern 4).
