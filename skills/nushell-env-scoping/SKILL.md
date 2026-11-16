---
name: nushell-env-scoping
description: >
  Explains where Nushell `$env` changes are visible: `for` vs `each`,
  `do --env`, `def --env`, `with-env`, `load-env`, `export-env`, `hide-env`
  and the automatic variables. Use when code sets or reads `$env`, or when
  an env change does not show up where expected.
user-invocable: false
allowed-tools: Bash(nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" *)
compatibility: Requires Nushell 0.117.0 or later.
metadata:
  version: 0.2.1
---

# Nushell Env Scoping

`$env` in nu is a record like any other, but it has **scope semantics that bite hard if you don't know the rules.** Closures isolate env by default. Some constructs propagate; most don't. Some vars can't be set manually at all. This skill names the rules.

Syntax reference: [cheat-sheet → Env and Scope](../nushell-idioms/references/cheat-sheet.md#env-and-scope).

Known bugs for the running nu, if any:

!`nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" nushell-env-scoping 2>/dev/null || true`

## The four propagation rules

1. **Top-level code** mutates the script's env. Always propagates downward to children.
2. **`for n in $list { … }`** — env mutations inside the loop body **propagate to the outer scope**.
3. **`each`, `items`, `reduce`, `where`** — closure invocations. Env mutations inside **do not propagate** to the outer scope.
4. **`do --env { … }`** — propagates closure mutations to caller. **`do { … }`** without `--env` does not.

These four cover blocks and closures; commands (`def --env`), modules (`export-env`) and `with-env` follow below. The biggest trap is writing `each { |x| $env.LAST = $x }` and being surprised that `$env.LAST` is unset after.

## The three scope-affecting constructs

### `do { … }` and `do --env { … }`

Plain `do` runs the closure in an isolated scope — env mutations inside vanish at the closing brace. `do --env` propagates mutations back to the caller; reach for it whenever a closure should write to the outer env (e.g. a later step that needs to see `$env.FOO = …` writes made inside the closure).

### `with-env { … } { … }`

Scoped env, downward-only. Sets the given record into env only for the duration of the closure; env reverts on exit. Mutations made inside the closure do not escape — that is the point. Use it for "run this command with a specific env without polluting the parent."

### `load-env { … }`

Bulk-merges a record into env at the current scope. Subject to the same propagation rules as direct `$env.X = …` assignment: works at top level, blocked inside `each`, propagates with `do --env`.

## Automatic env vars (cannot be set manually)

These three error with `automatic_env_var_set_manually` if you try to `load-env` them:

- `PWD` — set by `cd`
- `FILE_PWD` — directory of the running script
- `CURRENT_FILE` — path of the running script

Because a failed `load-env` loads nothing, the defensive pattern is to **wrap individual `load-env` calls in `try`**:

```nu
for entry in ($record | transpose key value) {
    try { load-env { ($entry.key): $entry.value } } catch {}
}
```

This lets a single auto-var fail in isolation instead of nuking the entire load. `for` is the right iteration construct here because it propagates the successful env mutations.

## Setting env at function boundaries

A `def` is a closure boundary by default — env mutations inside a `def`'d function don't leak out. The `--env` flag opts in to caller-env mutation (`def --env name [...] { ... }`). For modules that need to set env at import time, use `export-env { … }`: the block runs in the caller's scope when `use module.nu` is invoked. Both forms are necessary because the default for functions, like for closures, is isolation.

## Common debugging move

When something env-related isn't working, dump the entries you care about as a record:

```nu
$env | select --optional KEY1 KEY2 KEY3
```

`select --optional` returns null for missing keys instead of erroring — perfect for "did this get set or not." Avoid `print $env.KEY?` chains; assemble the diagnostic as a single record so you can see all the answers together.

## Pitfalls

- **`each` for env is the most common bug**. If you find yourself writing `each { |x| $env.something = … }`, switch to `for` immediately.
- **`do { … }` without `--env`** silently swallows mutations. The default is "isolate"; the opt-in is "propagate."
- **A failed `load-env` is atomic** — if the record contains one bad key (e.g. `PWD`), nothing else loads. Per-key try-load is defensive.
- **`with-env` changes do NOT escape** — that's the design. If you want propagation, use `do --env`.
- **Don't rely on `hide-env` to scrub an environment**: it can silently do nothing after a `--env` call ([known bug](../nushell-idioms/references/nushell-diagnostics.md)). For a child process that needs a clean environment, start it from scratch (`^env -i PATH=$env.PATH HOME=$tmp …` on POSIX); `with-env` only overrides the keys it names and the child still inherits everything else.

## References

- [File-backed env persistence](./references/persistence.md): read when `$env` has to survive between separate nu invocations and no persistent session is available.
