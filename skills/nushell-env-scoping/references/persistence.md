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
| items { |k, v| try { $v | to json --raw | ignore; {($k): $v} } catch { null } }
| where $it != null
| into record
| to json --raw
| save --force --raw $path
```

It reuses two patterns from the skill: per-key `for`+`try` on load, and `items`+`where`+`into record` on save.
