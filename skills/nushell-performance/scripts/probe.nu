# probe.nu
# Probe kit for nushell performance work. `use ${CLAUDE_PLUGIN_ROOT}/skills/nushell-performance/scripts/probe.nu`
#
#   probe hot {|| <call> }               where the time goes (start here)
#   probe entries {|| <call> }           exact closure-command entries of one run
#   probe time {|| <call> }              median ms
#   probe compare {|| <old> } {|| <new> } equality gate, then a balanced timing with a noise estimate
#   probe calibrate                      the entry-cost table for the running nu (re-run after an upgrade)

const ALWAYS: list<string> = [
  each
  par-each
  where
  any
  all
  reduce
  items
  'take while'
  'take until'
  'skip while'
  'skip until'
  'each while'
  'chunk-by'
  generate
  'record each'
  'record where'
  'record walk'
  'record apply'
  'update cells'
  tee
  interleave
]
const MAYBE: list<string> = [default update upsert insert collect zip 'str replace' group-by sort-by]

# Exact number of closure-command entries one run of `code` makes, by command.
export def entries [code: closure]: nothing -> record<total: int, by: record, closure-or-value: record> {
  let calls: list<string> = debug profile --max-depth 30 $code
    | where instruction =~ '^call'
    | get instruction
    | parse --regex 'decl \d+ "(?<name>[^"]+)"'
    | get name
  let tally = {|names| $calls | where $it in $names | uniq --count | reduce --fold {} {|r acc| $acc | insert $r.value $r.count } }
  let by: record = do $tally $ALWAYS
  {total: ($by | values | append 0 | math sum) by: $by closure-or-value: (do $tally $MAYBE)}
}

# Median milliseconds of one run of `code`. Each run's result is bound (`let _ =`), not piped to `ignore`, so a
# closure that ends in `try` keeps its catch (try-escapes-under-ignore); a streamed result is therefore collected,
# which adds 0.1 to 0.2 us per element (nu 0.117.0). `compare` and `calibrate` time the same way.
export def time [code: closure --rounds: int = 100 --passes: int = 5]: nothing -> float {
  let _ = do $code
  1..$passes | each {
    let t = date now
    for _ in 1..$rounds { let _ = do $code }
    ((date now) - $t) / $rounds / 1ms
  } | math median | math round --precision 3
}

# Refuse to time two variants unless they return the same value; then time them old-new-new-old inside every pass,
# so neither drift nor running second favours a side (timed old-then-new, an old-vs-old control read +4%).
# `noise_pct` is the median distance of one pass's gain from the median gain, in points: a `gain_pct` that is
# not several times clear of it is not a gain.
export def compare [old: closure new: closure --rounds: int = 100 --passes: int = 5]: nothing -> record {
  let a = do $old
  let b = do $new
  if $a != $b { error make --unspanned {msg: 'the variants return different values; nothing timed' help: $"old: ($a | to nuon | str substring 0..300)\nnew: ($b | to nuon | str substring 0..300)"} }
  let _ = do $old; let _ = do $new
  let half: int = [($rounds // 2) 1] | math max
  let runs = 1..$passes | each {
      let t0 = date now
      for _ in 1..$half { let _ = do $old }
      let t1 = date now
      for _ in 1..$half { let _ = do $new }
      for _ in 1..$half { let _ = do $new }
      let t2 = date now
      for _ in 1..$half { let _ = do $old }
      let t3 = date now
      let first: float = ($t1 - $t0) / $half / 1ms
      let last: float = ($t3 - $t2) / $half / 1ms
      let old: float = ($first + $last) / 2
      let new: float = ($t2 - $t1) / $half / 2 / 1ms
      {old: $old new: $new gain: ((1 - $new / $old) * 100)}
    }
  let o: float = $runs.old | math median
  let n: float = $runs.new | math median
  let g: float = $runs.gain | math median
  let noise: float = $runs.gain | each {|x| $x - $g | math abs } | math median
  {identical: true old_ms: ($o | math round --precision 3) new_ms: ($n | math round --precision 3) gain_pct: ($g | math round --precision 1) noise_pct: ($noise | math round --precision 1) old_entries: (entries $old).total new_entries: (entries $new).total}
}

# Where one run of `code` spends its time, from `debug profile`. Two views:
#   lines   - SELF time per source line (a row's duration minus its children's), the robust one
#   callees - calls and INCLUSIVE time per command or def
# The profiler multiplies run time several times over (one row per instruction), so use this to RANK, never to
# quote a duration; quote `probe time` / `probe compare`. `each`, `where` and friends return lazy streams: their
# closure body runs when the stream is consumed, so its rows are charged to the consumer, not to the `each` call.
export def hot [code: closure --top: int = 12]: nothing -> record<total: duration, lines: table, callees: table> {
  let rows: table = debug profile --max-depth 30 --lines --duration-values $code
  let kids: record = $rows | group-by parent_id | items {|id items| {id: $id kids: ($items.duration | math sum)} } | transpose --header-row --as-record
  let total: duration = $rows | where depth == 1 | get duration | append 0ns | math sum
  let self: table = $rows | where depth > 0 | insert self {|r| [($r.duration - ($kids | get --optional ($r.id | into string) | default 0ns)) 0ns] | math max }
  {
    total: $total
    lines: (
      $self | group-by {|r| $"($r.file | default inline):($r.line)" } --to-table
      | each {|g| let at = $g.items | first; {line: $"($at.file | default inline | path basename):($at.line)" self: ($g.items.self | math sum) rows: ($g.items | length) sample: ($g.items | sort-by self --reverse | first | get source | str trim | str substring 0..60)} }
      | sort-by self --reverse | first $top | insert share {|r| $"($r.self / $total * 100 | math round)%" }
    )
    callees: (
      $rows | where instruction =~ '^call' | insert callee {|r| $r.instruction | parse --regex 'decl \d+ "(?<n>[^"]+)"' | get 0?.n? }
      | group-by callee --to-table | each {|g| {callee: $g.callee calls: ($g.items | length) inclusive: ($g.items.duration | math sum)} }
      | sort-by inclusive --reverse | first $top
    )
  }
}

# Microseconds to enter each iteration form once, on a one-element input. The skill's cost model is this table as
# measured on one machine and one nu version: re-run it before trusting the numbers anywhere else.
export def calibrate [--rounds: int = 3000]: nothing -> table<form: string, us: int> {
  let cost = {|code: closure|
    let _ = do $code
    let t = date now
    for _ in 1..$rounds { let _ = do $code }
    ((date now) - $t) / $rounds / 1us | math round
  }
  def f [x: int]: nothing -> int { $x }
  let xs = [1]
  let r = {a: 1}
  let t = [{a: 1}]
  [
    [form code];
    ['for' {|| for x in $xs { $x } }]
    ['do { }' {|| do { 1 } }]
    ['custom def call' {|| f 1 }]
    ['match' {|| match 1 { 1 => 2 _ => 3 } }]
    ['try / catch' {|| try { 1 } catch { 2 } }]
    ['with-env' {|| with-env {A: 1} { 1 } }]
    ['str replace (most closure-free builtins)' {|| 'a.b' | str replace . - }]
    ['split words (an expensive builtin)' {|| 'list<int>' | split words }]
    ['each' {|| $xs | each {|x| $x } }]
    ['par-each' {|| $xs | par-each {|x| $x } }]
    ['where (row condition)' {|| $xs | where $it == 1 }]
    ['where {closure}' {|| $xs | where {|x| $x == 1 } }]
    ['any' {|| $xs | any {|x| $x == 1 } }]
    ['reduce' {|| $xs | reduce --fold 0 {|x a| $a + $x } }]
    ['items' {|| $r | items {|k v| $v } }]
    ['take while' {|| $xs | take while {|x| $x == 1 } }]
    ['take while (row condition)' {|| $xs | take while $it == 1 }]
    ['all' {|| $xs | all {|x| $x == 1 } }]
    ['chunk-by' {|| $xs | chunk-by {|x| $x } }]
    ['generate (one step)' {|| generate {|i| if $i < 1 { {out: $i next: ($i + 1)} } } 0 }]
    ['record each' {|| $r | record each {|k v| {$k: $v} } }]
    ['record where (row condition)' {|| $r | record where value == 1 }]
    ['record where {closure}' {|| $r | record where {|k v| $v == 1 } }]
    ['update cells' {|| $t | update cells {|v| $v } }]
    ['collect {closure}' {|| $xs | collect {|v| $v } }]
    ['update col {closure}' {|| $r | update a {|row| $row.a + 1 } }]
    ['update col value' {|| $r | update a 2 }]
    ['insert col {closure}' {|| $r | insert b {|row| $row.a } }]
    ['insert col value' {|| $r | insert b 2 }]
    ['default {closure}' {|| null | default { 1 } }]
    ['default value' {|| null | default 1 }]
    ['group-by {closure}' {|| $t | group-by {|row| $row.a } }]
    ['group-by column' {|| $t | group-by a }]
    ['sort-by {closure}' {|| $t | sort-by {|row| $row.a } }]
    ['sort-by column' {|| $t | sort-by a }]
  ] | each {|row| {form: $row.form us: (do $cost $row.code)} } | sort-by us
}
