---
name: nushell-performance
description: >
  This skill should be used when Nushell code feels slow or is about to be
  optimised, benchmarked or profiled: a laggy prompt hook, Tab completer,
  `export-env` startup block or per-element helper; choosing between
  `for`/`mut` and `each`/`where`/`reduce`/`any` for speed; reaching for
  `par-each`; reading `debug profile` output; timing with `std bench`; or
  judging a claimed speed-up in a `.nu` file. Trigger phrases: "slow",
  "optimise", "optimize", "speed up", "performance", "profile", "benchmark",
  "debug profile", "timeit", "std bench", "par-each", "laggy prompt",
  "slow completer", "startup time".
version: 0.1.0
user-invocable: false
---

# Nushell Performance

In Nushell the cost of iteration is set by **how many times a closure-taking command is entered**, and by
what each body does. It is not set by mutability. Entering `each`, `where`, `any` or `reduce` costs about
twice what entering a `for`, an `if` or a custom `def` costs, whatever the input size; per element, a loop
body costs a little over half what the same closure body does, but a loop that builds a list copies it on
every step. And in a shell library most wall time is not nu code at all: it is one external program or one
builtin that enumerates the system. So profile first, count entries second, edit last.

The tables and worked figures were measured with the kit in [`scripts/probe.nu`](scripts/probe.nu) on
nu 0.117.1-nightly, one WSL2 laptop with 22 CPUs, November 2026. Cases taken from one library's real code
(the validator, the completers, the hooks and helpers named below) were measured on nu 0.115.2-nightly in
September 2026 and not re-run; closure entry cost roughly seven times as much then, so their gains would be
smaller today. Trust the ratios; re-measure the absolutes with `probe calibrate` after a nu upgrade or on
another machine.

```nu
use ${CLAUDE_PLUGIN_ROOT}/skills/nushell-performance/scripts/probe.nu
```

## Cost model

Microseconds to enter a form once, on a quiet machine with no config (about 1.3x under a login config):

| about 3 us | about 5-9 us | about 70 us | about 830 us |
|---|---|---|---|
| `for`, `while`, `if`, `match`, `try`, `do {}`, a custom `def` call, `with-env` (5), `collect {closure}`, most closure-free builtins (`str replace`, `get`, `in`, `split row`: 3-4), `zip <list>`, and `update` / `insert` / `default` / `group-by` / `sort-by` given a **value or a column name** | `each`, `where` (row condition or closure), `any`, `all`, `reduce`, `items`, `take while` / `until`, `skip while` / `until`, `each while`, `chunk-by`, `update cells`, `zip {closure}`, `record walk`, `record apply` (5-6); `record each`, `record where`, `str replace {closure}` (9); `generate` (11); and `update` / `insert` / `default` / `group-by` / `sort-by` given a **closure** (5-7) | `tee`, `interleave`: both run their closures in parallel | `par-each` |

The timing loop itself accounts for about 2 us of every figure, so the gap between the first two columns is
larger than it looks: about 1 us of work against 3 to 7.

Microseconds per element (slope between 200 and 2000 elements, so entry cost is cancelled):

| body | us |
|---|---|
| closure-free builtin: `get n \| math sum` | 0.05 |
| `each {\|x\| $x + 1 }` / the same body in a `for` | 0.75 / 0.41 |
| `each` reading a record field / the same in a `for` | 0.82 / 0.45 |
| `where tag == a` (row condition) / `where {\|r\| $r.tag == a }` | 0.87 / 1.02 |
| `take while` or `all`, row condition or closure | 0.52-0.59 |
| a formatter closure: `match` on `describe`, then `format number` or `to nuon` | 3.7-6.1 |
| a closure command inside each element (`[$x] \| where $it > 0`), in `each` / in a `for` | 3.7 / 3.2 |
| `each {\|r\| $r \| update n {closure} }` / one `update n {closure}` over the table | 3.8 / 0.91 |

The per-element figure is the body's own cost, so measure it (`probe time` at two sizes, divide the
difference) before assuming a body is cheap.

Builtins are not uniformly cheap. `split words` costs about 350 us a call (Unicode segmentation) against 4 for
`str replace --regex` and 4 for `split row`: the idiom `describe | split words | first` was 97% of a path helper
that three completers call on every Tab. `probe hot` names such a line at once; nothing else will.

Piping a large record into a command costs by the record's size; a cell path does not. `$env | get --optional
time.alarms` took 0.076 ms in a bare 126-variable environment and 0.118 ms with 90 more variables, against a
flat 0.002 ms for `$env.time?.alarms?`.

What follows from the tables:

- One closure command over a large collection is the right default for building a result. A `for` body is
  cheaper per element, but a `for` that collects into a list loses (see `++=` below).
- The slow shape is a closure command entered many times: inside another closure, inside a loop, or inside a
  function that itself runs per element, per prompt, per keypress or at shell startup. Each nested entry
  costs about 3 us per outer element in either style, four to seven times the outer body.
- A closure-free builtin beats both styles: half the entry cost of a closure command and a fifteenth or less
  per element.
- `$list ++= [x]` inside a loop copies the list every time, so it is quadratic. Mapping 1000 elements: `each`
  0.6 ms, `for` with `++=` 4.7 ms, `for` with `append` 21 ms. The two tie up to about 10 elements; from 20 on
  `each` wins, by 2.7x at 200.
- `reduce` is no cheaper than `for` with `mut`. State carried across 1200 items (a section-tracking
  workload): `reduce` 36 ms, `for` with `mut` 33 ms. In the library case the same result restructured as two
  stateless passes took 4 ms against 117 for the loop (0.115.2-nightly).
- Building a 1000-key record with `insert` in a fold costs 24-27 ms in either style; `each` to `{k v}` rows
  then `transpose --header-row --as-record` costs 2.5 ms.
- Finding an element 10% into a 1000-element list: `$x in $xs` 2 us, `for` with `break` 51 us, `any {}` 72 us.
- 400 rows with 5 inner items each: a closure per row 2.6 ms, `flatten` then one `where` 1.4 ms, nested
  `for` 1.9 ms.
- Total entries predict run time. One 36-rule validator written three ways (0.115.2-nightly): 13 entries
  3.8 ms, 55 entries 5.8 ms, 141 entries 10.7 ms.

## Where it pays, and where it does not

Hot: `export-env` blocks (every shell start), hooks (every prompt), completers (every Tab), and pure-nu helpers
that something else calls per element. A helper's heat is decided by its callers, so search the whole library
for them, not just its own file: a 0.29 ms type-dispatch helper looked cold until its callers turned out to be
another module's `each` and a per-prompt hook condition (rewritten with pattern 4 below: 0.048 ms, 83%).

Not worth touching: anything bound by an external program or a system-enumerating builtin. Measured in one
library: `ps --long` 108 ms per call, bare `which` (2275 rows) 27.7 ms per Tab, `git`, `gh`, `wslpath`,
`powershell.exe`. A 6 us closure entry is 0.02% of the cheapest of these. The lever there is the external call itself
(fewer calls, a narrower query, a cache), never the nu around it.

Relative gain is not the bar. Multiply the microseconds saved by how often the trigger fires, and set that
against what else runs on the same trigger. A 78% gain worth 46 us on one completer was correctly declined
because a sibling completer spends 30 ms on the same Tab. Correctness risk counts too: a 7% gain worth 30 us
per shell start was declined because it replaced a branch that cannot miss a case with two regexes that must
stay exact complements of each other.

## Workflow

Heat is a gate, and it comes before every number: a function no hot context reaches is left alone however
large its measured gain (a helper that a plain `match` made 96% faster had no caller anywhere, so it stayed).

1. Establish heat: name the trigger (shell start, prompt, Tab, per element of what) and find the callers
   across the whole library. No hot caller: record it as cold and stop.
2. `probe hot {|| <call> }`: self time per source line, plus calls and inclusive time per callee. An external
   or a heavy builtin shows up here at once, which usually ends the investigation. When the function owns
   only a few percent of its trigger, stop: halving 5% of a Tab is 2.5% of the Tab.
3. `probe entries {|| <call> }`: exact closure-command entries of one run, by command. Entries times about 3 us is
   the most that rewriting them as loops can remove; entries made per element usually matter more than
   their count suggests, because each one also pays its body. The count cannot show one entry getting
   cheaper: `par-each` to `each` reads 1 and 1 while the run drops by most of a millisecond.
4. Build the workload from literal data shaped like the real input, never from live user data. When the real
   input is empty or tiny, that is the workload: measure the guard path and stop, rather than tuning for a
   size nobody has. When input size varies, measure several sizes: a `for` with `++=` rewrite of a completion
   formatter won below about 120 items and lost badly above. When the common case is dominated by something
   else (a glob, an external), quote the case where the change shows, say which real case it is, and report
   the common one too.
5. Apply the first pattern below that fits.
6. `probe compare {|| <old> } {|| <new> }`. It refuses to time unless both closures return equal values, then
   times them old-new-new-old and reports `gain_pct` and `noise_pct`.
7. Run the repository's gates. `nu-lint` caps nesting at depth 4, which is why pattern 4 extracts a `def`.

Keep a change only when all four hold:

- the function is hot (step 1) and owns a real share of its trigger (step 2);
- `gain_pct` is at least 10 and at least three times `noise_pct`, measured end to end on the hot entry point
  (the completer, the hook, the `export-env` block), not on the fragment you extracted: two rewrites worth
  58% and 77% in isolation were 3% and 5% of their completers, whose time went to `commandline complete` and
  `plugin list`;
- it is still so on a second run in a fresh process (quote the smaller of the two);
- old and new are equal on an edge-case matrix, not just the workload: empty input, `null`, an element that
  is itself empty, a string with an embedded newline, keys that collide. For a change that spans a module,
  run the old tree and the new tree in two processes and diff their `to nuon` output. A variant that turns
  the empty case from `[]` into an error is not equal. `par-each` without `--keep-order` returns a different
  order on each run (13 distinct orders in 30 runs over nine elements), so compare it sorted, and say in the
  commit that `each` made the order deterministic.

If the two variants disagree, stop timing: one of them is wrong, and it is as likely to be the original. Settle
which, and treat it as a defect with its own failing test, separate from the optimisation.

## Patterns

Try 1 to 5 in that order. 6 and 7 apply wherever `probe hot` points at them.

1. **A builtin that takes no closure.** `in` / `not-in`, `math sum`, `str join`, `get <col>`, `select`,
   `reject`, `uniq`, `compact --empty`, `is-empty`, `group-by <col>`, `sort-by <col>`, `update <col> <value>`,
   `transpose --header-row --as-record`, `format pattern` over a table, string commands fed a whole list.
   Among the newer ones: `join --anti` to drop rows with a match (0.25 ms against 2.0 for `where k not-in`,
   1000 rows by 500), `get ...$paths` for several cell paths (6 us against 30 for `each` over 20 paths), and
   `find --only-matching --regex` to extract matches (78 us against 107 for `parse --regex`). A builtin is not
   automatically the fastest form, so time it: keeping the last row of each of 100 groups in 2000 rows,
   `uniq-by g --keep-last` took 0.97 ms against 0.37 for `group-by g --to-table | each {|grp| $grp.items | last }`,
   with the same result.
2. **Enter once.** `flatten` first, then one `where` or `each` over the flat list, instead of a closure per
   row. Replace state carried between iterations with two stateless passes before reaching for `reduce` or
   `mut`.
3. **Guard the scan that is usually empty**: `if ($xs | is-not-empty) and (...)`.
4. **A small scan entered many times** becomes a `for` with `break`, or a private `def` with an early
   `return`.
5. **`default {closure}` becomes `default <value>`** only when the value is cheap and has no side effect: the
   closure form is lazy, the value form is not.
6. **`par-each` is a budget, not a style.** It costs about 0.83 ms to enter, so it pays only when the serial
   work it spreads is well above that: external or IO work per element (two globs: `each` measured 62%
   slower), or a heavy pure body over many elements (a formatter at 3.7-6.1 us per element: `each` wins by
   97% at 4 elements and by 25% at 130, and loses by 78% at 1741, crossover near 170). Over a few cheap pure
   rows it is the whole cost (3 rows: 0.87 ms, against 0.007 ms with `each`). Time `--keep-order` as well
   as the unordered form: on the 22-CPU machine above, the unordered form took 26-29 ms at 1741 elements in
   every round, slower than `each` (8-9 ms), while `--keep-order` took 2.1-2.3 ms; `--threads 4` did not cure
   it. When real callers sit on both sides of the crossover, keep `par-each`: a size gate would bake a
   load-dependent constant into the code.
7. **A cheaper builtin for the same job**, when `probe hot` puts the time on one closure-free line:
   `describe | str replace --regex '<.*' ''` for `describe | split words | first` (0.36 ms to 0.005 ms), a builtin
   `match` for a closure-taking dispatch helper (9.4 ms to 2.4 ms across one completer). `probe entries` reads
   0 to 0 for such a change: only the self-time view finds it. Check the arms first: over 19 value shapes the
   forms differ on one, `cell-path`, which `split words` reads as `cell` and the `str replace` does not. Where
   an arm matches or prints the name, the exact drop-in is `describe | parse --regex '^(?<type>\w*)' | get 0.type`
   (0.014 ms against 0.005 for the `str replace` and 0.36 for `split words`).

Patterns 3 and 4 together, on a check that runs once per rule of a validator (sparse input 5.5 ms to 3.5 ms):

```nu
# before, once per rule:   $dead | any {|d| $at == $d or ($at starts-with $"($d).") }
# A `for`, not `any`: entering a closure command costs about twice what the loop does, once per rule.
def under [at: string ...dead: string]: nothing -> bool {
  for d in $dead { if $at == $d or ($at starts-with $"($d).") { return true } }
  false
}
# call site: `$dead` is empty for every valid document, so the guard skips even the `def` call
if ($dead | is-not-empty) and (under $r.at ...$dead) { continue }
```

## Reading `debug profile` directly

`debug profile --max-depth 30 --lines --duration-values {|| <call> }` returns one row per IR instruction with
columns `depth id parent_id file line source pc instruction duration`. Other flags: `--spans`,
`--expand-source`, `--values`. There is no `--instructions` flag; the column is always present.

- **Exact entry counts**: keep rows where `instruction =~ '^call'` and parse the callee with
  `decl \d+ "(?<name>[^"]+)"`. Matching command names in `source` text double-counts (it read 35 / 160 / 65
  where the exact counts were 13 / 141 / 55).
- **It distorts time.** A 2.6 ms run produced 13,610 rows; the durations it recorded summed to 2.8 ms on one
  run and 8.0 ms on another, and the profiled call itself took 85-143 ms. Rank with it; never quote a
  duration from it.
- **Lazy streams move the blame.** `each` and `where` return streams, so the closure body's rows appear after
  the producing function has returned, charged to whatever consumes the stream (often depth 1, parent 0).
  Inclusive time per callee therefore misleads. Self time per source line (a row's duration minus its
  children's, joined on `parent_id`) is the view to trust; `probe hot` computes both.

## Pitfalls

| Pitfall | Fact |
|---|---|
| `std bench` under `nu -l` | Reported 962 us for one `each` that a plain timing loop put at 55 us, and it prints OSC progress codes to stdout. Use `probe time`. |
| Timing old, then new | An old-versus-old control read +4%. `probe compare` balances the order; near the bar, run the control too. |
| Two separate `probe time` runs | Drift between them is larger than most gains. Other benchmarks on the machine swing a result by 10 points or more. |
| Quoted string on the left in a row condition | `where bad and '.' not-in $it.at` fails with "Cannot find column '.'": the string is read as a column name. Use the closure form. |
| Bare word on the right in a row condition | `where old != new` compares the column `old` with the string "new", so an equality check reports every row as different. Use `where {\|r\| $r.old != $r.new }`. |
| `[] \| math sum` | Raises "Unsupported input". Write `append 0 \| math sum`. |
| Equality checked on the happy path only | A vectorised regex rewrite of a PATH partition matched on every ordinary input and silently dropped an empty PATH element. |
| Diffing two saved outputs | A harness that fails to parse writes two empty files, and `cmp` calls them identical. Assert the old output is non-empty (`test -s`) before comparing. |
| `mut` blamed for slowness | Mutability measured as free. Count entries instead. |
