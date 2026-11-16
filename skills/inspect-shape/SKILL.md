---
name: inspect-shape
description: Inspects the structure of a `nu` expression and return it's described type, length (if applicable), and the value itself. Use when you are uncertain about a pipeline result's data type, debugging Nushell code, testing that a Nushell expression produces an expected shape, or when the user mentions "typecheck", "unknown data types", "inspect the shape", or "what kind of data".
user-invocable: false
allowed-tools: ["mcp__nushell__nu_exec"]
compatibility: { nu: '>=0.117.0' }
version: 0.1.1
---

# Inspect Shape

## Procedure

Call `nu_exec` with `pipeline` set to:

```nu
use '${CLAUDE_PLUGIN_ROOT}/skills/inspect-shape/scripts/shape.nu'
<expression> | shape
```

The result is a record. `type` is the detailed type (`list<int>`,
`table<a: int>`), `length` the number of items or bytes when the value has one,
and `value` the value itself, cut to the first three rows of a list or table
(`shape --max-rows <n>` keeps more). A `nothing` result has `type` only.

To describe what an expression returns when it may fail, pass it as a closure:
`{|| <expression> } | shape` runs it, so a failure shows as its error rather
than as an empty result.
