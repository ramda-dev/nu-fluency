# Re-measures the figures in skills/nushell-performance/SKILL.md and prints them as one NUON record.
# Run from the repository root: nu --no-config-file bench/perf/run.nu
# Progress goes to stderr; stdout carries only the record. Nothing is written to disk.

use ../../skills/nushell-performance/scripts/probe.nu

# ——— helpers ——————————————————————————————————————————————————————————————————

# Median milliseconds of one run (probe time with tunable rounds).
def t [code: closure --rounds: int = 20]: nothing -> float {
  probe time $code --rounds $rounds --passes 5
}

# Microseconds for one call, the same harness as `probe calibrate`.
def us [code: closure --rounds: int = 3000]: nothing -> int {
  do $code | ignore
  let start = date now
  for _ in 1..$rounds { do $code | ignore }
  ((date now) - $start) / $rounds / 1us | math round
}

# Per-element microseconds: slope between 200 and 2000 elements, so entry cost cancels.
def slope [make: closure body: closure]: nothing -> float {
  let small = do $make 200
  let large = do $make 2000
  let t_small = probe time {|| $small | do $body } --rounds 60 --passes 7
  let t_large = probe time {|| $large | do $body } --rounds 60 --passes 7
  ($t_large - $t_small) / 1800 * 1000 | math round --precision 2
}

# Run one section, reporting progress on stderr; a failure is recorded instead of aborting the run.
def section [name: string code: closure]: nothing -> any {
  print --stderr $'running ($name)'
  try { do $code } catch {|e| {error: $e.msg} }
}

# ——— fixtures —————————————————————————————————————————————————————————————————

const FORMATTER_SIZES: list<int> = [4 130 1741]
const CROSSOVER_SIZES: list<int> = [5 10 20 50 100 200]

let ints = {|n| 1..$n | each {|i| $i } }
let recs = {|n| 1..$n | each {|i| {n: $i tag: (if $i mod 2 == 0 { 'a' } else { 'b' })} } }
let fmt = {|x| match ($x | describe) { 'int' => ($x | format number | get display) _ => ($x | to nuon) } }
let xs = do $ints 1000

# ——— measurements —————————————————————————————————————————————————————————————

let meta = {
  nu: (version | get version)
  os: $nu.os-info.name
  kernel: $nu.os-info.kernel_version
  cpus: (sys cpu | length)
  date: (date now | format date '%Y-%m-%d')
  env_vars: ($env | columns | length)
}

let entry_us = section entry_us {
  let cal = probe calibrate | transpose --ignore-titles --header-row --as-record
  let r = {a: 1}
  $cal | merge {
    'harness floor (empty closure)': (us {|| null })
    'get': (us {|| $r | get a })
    'in': (us {|| 2 in [1 2 3] })
    'split row': (us {|| 'a.b.c' | split row . })
    'str replace --regex': (us {|| 'list<int>' | str replace --regex '<.*' '' })
  }
}

let per_element_us = section per_element_us {
  {
    'get n | math sum': (slope $recs {|| get n | math sum })
    'each {|x| $x + 1 }': (slope $ints {|| each {|x| $x + 1 } | ignore })
    'for, $x + 1': (slope $ints {|| let items = $in; for x in $items { $x + 1 } })
    'each reading a field': (slope $recs {|| each {|r| $r.n } | ignore })
    'for reading a field': (slope $recs {|| let items = $in; for r in $items { $r.n } })
    'where tag == a': (slope $recs {|| where tag == a })
    'where {|r| $r.tag == a }': (slope $recs {|| where {|r| $r.tag == 'a' } })
    'formatter, format number arm': (slope $ints {|| each {|x| do $fmt $x } | ignore })
    'formatter, to nuon arm': (slope {|n| 1..$n | each {|i| $'s($i)' } } {|| each {|x| do $fmt $x } | ignore })
  }
}

let builtins = section builtins {
  {
    'describe | split words | first (us)': (us {|| [1 2] | describe | split words | first } --rounds 500)
    'describe | str replace --regex (us)': (us {|| [1 2] | describe | str replace --regex '<.*' '' })
    'describe | parse --regex (us)': (us {|| [1 2] | describe | parse --regex '^(?<type>\w*)' | get 0.type })
    'env get --optional (ms)': (t {|| $env | get --optional time.alarms } --rounds 2000)
    'env cell path (ms)': (t {|| $env.time?.alarms? } --rounds 2000)
  }
}

let worked_ms = section worked_ms {
  let keys = 1..1000 | each {|i| $'k($i)' }
  let rows = 1..400 | each {|i| {id: $i items: [1 2 3 4 5]} }
  let lines = 1..1200 | each {|i| if $i mod 20 == 1 { {h: true v: $'sec($i)'} } else { {h: false v: $'l($i)'} } }
  let target = 100
  {
    'map 1000: each': (t {|| $xs | each {|x| $x * 2 } })
    'map 1000: for ++=': (t {|| mut acc = []; for x in $xs { $acc ++= [($x * 2)] }; $acc })
    'map 1000: for append': (t {|| mut acc = []; for x in $xs { $acc = ($acc | append ($x * 2)) }; $acc } --rounds 5)
    'map crossover: each vs for ++=': ($CROSSOVER_SIZES | each {|n|
      let s = $xs | first $n
      {
        n: $n
        each: (t {|| $s | each {|x| $x * 2 } } --rounds 200)
        for_append_assign: (t {|| mut acc = []; for x in $s { $acc ++= [($x * 2)] }; $acc } --rounds 200)
      }
    })
    'state 1200 (reconstructed workload): reduce': (t {||
      $lines
      | reduce --fold {cur: '' out: []} {|l a| if $l.h { $a | update cur $l.v } else { $a | update out ($a.out | append {sec: $a.cur v: $l.v}) } }
      | get out
    } --rounds 3)
    'state 1200 (reconstructed workload): for mut': (t {||
      mut cur = ''
      mut out = []
      for l in $lines { if $l.h { $cur = $l.v } else { $out = ($out | append {sec: $cur v: $l.v}) } }
      $out
    } --rounds 3)
    'record 1000: reduce insert': (t {|| $keys | reduce --fold {} {|k acc| $acc | insert $k 1 } } --rounds 5)
    'record 1000: for mut insert': (t {|| mut acc = {}; for k in $keys { $acc = ($acc | insert $k 1) }; $acc } --rounds 5)
    'record 1000: each + transpose': (t {|| $keys | each {|k| {k: $k v: 1} } | transpose --ignore-titles --header-row --as-record })
    'find 10% in (us): in': ((t {|| $target in $xs } --rounds 500) * 1000)
    'find 10% in (us): for break': ((t {|| mut hit = false; for x in $xs { if $x == $target { $hit = true; break } }; $hit } --rounds 500) * 1000)
    'find 10% in (us): any': ((t {|| $xs | any {|x| $x == $target } } --rounds 500) * 1000)
    '400x5: closure per row': (t {|| $rows | each {|r| $r.items | where $it == 3 } | flatten } --rounds 10)
    '400x5: flatten + where': (t {|| $rows | get items | flatten | where $it == 3 } --rounds 10)
    '400x5: nested for': (t {|| mut out = []; for r in $rows { for i in $r.items { if $i == 3 { $out ++= [$i] } } }; $out } --rounds 10)
  }
}

let par_each = section par_each {
  let three = [1 2 3]
  let nine = 1..9 | each {|i| $i }
  {
    'formatter (ms)': ($FORMATTER_SIZES | each {|n|
      let s = do $ints $n
      let r = if $n > 500 { 5 } else { 30 }
      {
        n: $n
        each: (t {|| $s | each {|x| do $fmt $x } } --rounds $r)
        par_each_keep_order: (t {|| $s | par-each --keep-order {|x| do $fmt $x } } --rounds $r)
        par_each: (t {|| $s | par-each {|x| do $fmt $x } } --rounds $r)
      }
    })
    '3 cheap rows: par-each (ms)': (t {|| $three | par-each {|x| $x } } --rounds 200)
    '3 cheap rows: each (ms)': (t {|| $three | each {|x| $x } } --rounds 200)
    '9 elements: distinct orders in 30 runs': (1..30 | each { $nine | par-each {|x| $x } | to nuon } | uniq | length)
  }
}

let profiler = section profiler {
  let rows = 1..400 | each {|i| {id: $i items: [1 2 3 4 5]} }
  let work = {|| $rows | each {|r| $r.items | where $it == 3 } | flatten }
  let profiled = debug profile --max-depth 30 --lines --duration-values $work
  {
    'plain run (ms)': (t $work)
    'profiled call, wall (ms)': (probe time {|| debug profile --max-depth 30 --lines --duration-values $work } --rounds 3 --passes 3)
    'profiled durations, depth 1 sum (ms)': ($profiled | where depth == 1 | get duration | math sum | $in / 1ms | math round --precision 3)
    'rows': ($profiled | length)
    'entries': (probe entries $work).total
  }
}

let pitfalls = section pitfalls {
  let table = [{bad: true at: 'a.b'} {bad: true at: 'ab'}]
  let pairs = [{old: 1 new: 1} {old: 1 new: 2}]
  let shapes = [
    1 1.5 'a' true null 1kb 1sec 2026-01-01 [1] [[a]; [1]] {a: 1} {|| 1 } $.a.b 0x[01] (1..2)
    [{a: 1} {b: 2}] [1 'a'] ('*.nu' | into glob) ([] | wrap a)
  ]
  {
    '[] | math sum': (try { [] | math sum } catch {|e| $e.msg })
    'quoted string left in row condition': (try { $table | where bad and '.' not-in $it.at | length } catch {|e| $e.msg })
    'bare word right: rows reported different (of 2, 1 truly)': ($pairs | where old != new | length)
    'describe shapes where split words differs from str replace': (
      $shapes | each {|v| $v | describe } | where ($it | split words | first) != ($it | str replace --regex '<.*' '')
    )
    'describe shapes tested': ($shapes | length)
  }
}

# Last, because it changes this script's environment.
let env_plus_90 = section env_plus_90 {
  let pad = 1..40 | each { 'y' } | str join
  load-env (1..90 | each {|i| [$'BENCH_EXTRA_($i)' $pad] } | into record)
  {
    env_vars: ($env | columns | length)
    'env get --optional (ms)': (t {|| $env | get --optional time.alarms } --rounds 2000)
    'env cell path (ms)': (t {|| $env.time?.alarms? } --rounds 2000)
  }
}

{
  meta: $meta
  entry_us: $entry_us
  per_element_us: $per_element_us
  builtins: $builtins
  worked_ms: $worked_ms
  par_each: $par_each
  profiler: $profiler
  pitfalls: $pitfalls
  env_plus_90: $env_plus_90
} | to nuon --indent 2 | print
