# File-backed env persistence

How to carry `$env` across separate nu invocations through a file. Prefer a persistent session (e.g. a REPL) when one is available. If a file is the only option, the load/save loop is:

```nu
# Load
let __persisted = try {
    open --raw $path | from json | reject --optional PWD FILE_PWD CURRENT_FILE
} catch { {} }
for entry in ($__persisted | transpose key value) {
    try { load-env { ($entry.key): $entry.value } } catch {}
}

# User code runs here (inside `do --env { … }` if a closure boundary intervenes)

# Save
$env
| reject --optional ENV_CONVERSIONS config FILE_PWD CURRENT_FILE
| record each {|k v| try { $v | to json --raw | ignore; [$k $v] } catch { null } }
| to json --raw
| save --force --raw $path
```

Load is a per-key `for`+`try`, so one bad value does not stop the rest; save drops every value JSON cannot hold with `record each` (a `null` result drops the field; see [`nushell-records`](../../nushell-records/SKILL.md)).
