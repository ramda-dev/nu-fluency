---
name: nushell-strings
description: >
  Parses and builds strings the Nushell way: `parse '{a} {b}'` into tables,
  the `str` commands, `from`/`to` json, csv, yaml and toml, `$"…"`
  interpolation, splitting, joining and regex. Use for any string work that
  bash would do with sed, awk, grep, cut or printf.
user-invocable: false
compatibility: Requires Nushell 0.117.0 or later.
metadata:
  version: 0.1.1
---

# Nushell Strings

In bash, string manipulation is a parade of `sed`, `awk`, `grep`, `cut`, `tr`, `printf`. In nu, there are three primary tools — `parse`, the `str` namespace, and the `from <format>` family — plus interpolation. The shift to internalize: **nu wants you to parse strings into structured data and then operate on the data**, not chain text transformations.

Syntax reference: [cheat-sheet → Strings](../nushell-idioms/references/cheat-sheet.md#strings).

## The four primary tools

### 1. `parse '{name} {pattern}'` — typed extraction

The strongest single tool. Takes a template with named captures and returns a **table**. Whenever the bash instinct is a regex with named groups, or a line whose whole shape is known, `parse` is the right tool — chain `get` or `select` to extract from the returned table. Applied to a list of lines (`lines | parse …`), its last capture takes the rest of each line and lines that do not match are dropped; on one multi-line string it takes the rest of the string. For `awk -F: '{print $(2)}'` use `lines | split column ':' | get column1?`, and for whitespace-separated fields `lines | str trim | split column --regex '\s+'`. For full regex, `parse --regex '<pattern>'` accepts standard syntax with named captures `(?<name>…)`. To split filenames, use `ls | get name | path parse` (`parse '{stem}.{ext}'` splits at the first dot).

### 2. The `str` namespace

Covers ~95% of single-string manipulation — case conversion (`uppercase`, `lowercase`, `capitalize`, `camel-case`, `snake-case`, etc.), inspection (`length`, `contains`, `starts-with`, `ends-with`, `index-of`, `distance`), slicing (`substring`), replacement (`replace`, `replace --all`, `replace --regex`), trimming (`trim`, `trim --char`), and reshaping (`reverse`, `expand`). Run `help str` to discover the full set. `str upcase` and `str downcase` are deprecated; write `str uppercase` and `str lowercase`.

### 3. The `from <format>` family

`from json`, `from csv`, `from yaml`, `from toml`, `from nuon` each read a string and return structured data. `from nuon` is a JSON-superset parser — it accepts both nu's native form and plain JSON. The pair `from json` and `to json` round-trip. `to nuon --serialize` writes a closure as its source text, which `from nuon` reads back as a string, not a closure.

### 4. Interpolation: `$"…"` and `$'…'`

The `$` prefix turns either quote form into an interpolation. Inside `(…)`, full nu expressions are evaluated — `$"sum: ([1 2 3] | math sum)"` works. Double-quoted interpolation `$"…"` interprets backslash escapes; single-quoted interpolation `$'…'` preserves backslashes verbatim. Plain `"…"` and `'…'` (no `$`) are non-interpolating strings with the same escape distinction.

## Splitting and joining

`lines` is the preferred line-splitter — it handles `\r\n` correctly across platforms. `split row` returns a list of strings; `split column` returns a single-row table with auto-named columns (`column0`, `column1`, …). Pick by what the next stage expects.

## Encoding conversion

`encode utf-8` and `decode utf-8` convert between strings and binary; `encode base64` / `decode base64` handle base64 (`encode base64` returns a string and `decode base64` returns binary, so chain `decode utf-8` after `decode base64` to recover text).

## Regex

When `parse` doesn't fit, full regex is available via `str replace --regex` (substitute) and `find --regex` (filter list elements). For extraction with captures, `parse --regex '(?<name>pattern)'` reads more cleanly than `find --regex` followed by post-processing.

## When bash's text-stream model leaks in

Coming from bash, the instinct is "transform text → transform text → final text." In nu, the better instinct is "parse text into structured data once, transform structurally, render to text at the very end." If a pipeline has three `str replace` calls in a row, it's almost always a sign you should be parsing into a record first and using `update` instead.

## Pitfalls

- **`echo`** in nu prints a list of values, not a string. Use `print` for stdout-side-effect, `$"…"` for interpolation.
- **`'…'` (plain single-quoted) is literal** — no escapes interpreted. For interpolation that still preserves backslashes, use the `$` prefix: `$'…'`. Plain double-quoted `"…"` interprets escapes; `$"…"` adds interpolation on top.
- **`parse` returns a table**, not a record. Use `parse … | first | …` if you expect one match.
