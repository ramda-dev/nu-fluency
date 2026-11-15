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

In Nushell the cost of iteration is set by **how many times a closure-taking command is entered**. It is not
set by mutability, and not by loop-versus-pipeline style. Entering `each`, `where`, `any` or `reduce` costs
about ten times what entering a `for`, an `if` or a custom `def` costs, whatever the input size; per element,
a closure body and a loop body cost the same. And in a shell library most wall time is not nu code at all: it
is one external program or one builtin that enumerates the system. So profile first, count entries second,
edit last.

Every number here was measured with the kit in [`scripts/probe.nu`](scripts/probe.nu) on nu 0.115.2-nightly, one WSL2 laptop,
September 2026. Trust the ratios; re-measure the absolutes with `probe calibrate` after a nu upgrade or on
another machine.

```nu
use ${CLAUDE_PLUGIN_ROOT}/skills/nushell-performance/scripts/probe.nu
```

## Cost model

Microseconds to enter a form once, on a quiet machine with no config (about 1.3x under a login config):

| about 5 us | about 40-45 us | about 1100 us |
|---|---|---|
| `for`, `while`, `if`, `match`, `try`, `do {}`, a custom `def` call, `with-env`, most closure-free builtins (`str replace`, `get`, `in`, `split row`: 5-10), and `update` / `insert` / `default` / `group-by` / `sort-by` given a **value or a column name**. Also `insert col {closure}` and `collect {closure}` (7) | `each`, `where` (row condition or closure), `any`, `all`, `reduce`, `items`, `take while`, `skip while`, and `update` / `upsert` / `default` / `group-by` / `sort-by` given a **closure** | `par-each` |

Microseconds per element (slope between 200 and 2000 elements, so entry cost is cancelled):

| body | us |
|---|---|
| closure-free builtin: `get n \| math sum` | 0.05 |
| `each {\|x\| $x + 1 }` / the same body in a `for` | 0.66 / 0.64 |
| `each` reading a record field / the same in a `for` | 1.81 / 1.82 |
| `where tag == a` (row condition) / `where {\|r\| $r.tag == a }` | 1.08 / 1.87 |
| a formatter closure: `match` on `describe`, then `format number` or `to nuon` | 9-15 |

The per-element figure is the body's own cost, so measure it (`probe time` at two sizes, divide the
difference) before assuming a body is cheap.

Builtins are not uniformly cheap. `split words` costs about 400 us a call (Unicode segmentation) against 10 for
`str replace --regex` and 9 for `split row`: the idiom `describe | split words | first` was 97% of a path helper
that three completers call on every Tab. `probe hot` names such a line at once; nothing else will.

Piping a large record into a command costs by the record's size; a cell path does not. `$env | get --optional
time.alarms` took 0.155 ms in a login-sized environment (0.090 bare, 0.176 with 90 more variables) against a
flat 0.012 ms for `$env.time?.alarms?`.

What follows from the tables:

- One closure command over a large collection is the right default. A loop does not beat it per element.
- The slow shape is a closure command entered many times: inside another closure, inside a loop, or inside a
  function that itself runs per element, per prompt, per keypress or at shell startup.
- A closure-free builtin beats both styles: a tenth of the entry cost and a fifteenth or less per element.
- `$list ++= [x]` inside a loop copies the list every time, so it is quadratic. Mapping 1000 elements: `each`
  0.7 ms, `for` with `++=` 4.8 ms, `for` with `append` 22 ms. The loop only wins below about 100 elements.
- `reduce` is no cheaper than `for` with `mut`. State carried across 1200 items: `reduce` 137 ms, `for` with
  `mut` 117 ms, the same result restructured as two stateless passes 4 ms.
- Building a 1000-key record with `insert` in a fold costs 27 ms in either style; `each` to `{k v}` rows then
  `transpose --header-row --as-record` costs 2.7 ms.
- Finding an element 10% into a 1000-element list: `$x in $xs` 6 us, `for` with `break` 58 us, `any {}` 117 us.
- 400 rows with 5 inner items each: a closure per row 22.7 ms, `flatten` then one `where` 4.5 ms, nested
  `for` 4.6 ms.
- Total entries predict run time. One 36-rule validator written three ways: 13 entries 3.8 ms, 55 entries
  5.8 ms, 141 entries 10.7 ms.

## Where it pays, and where it does not

Hot: `export-env` blocks (every shell start), hooks (every prompt), completers (every Tab), and pure-nu helpers
that something else calls per element. A helper's heat is decided by its callers, so search the whole library
for them, not just its own file: a 0.29 ms type-dispatch helper looked cold until its callers turned out to be
another module's `each` and a per-prompt hook condition (rewritten with pattern 4 below: 0.048 ms, 83%).

Not worth touching: anything bound by an external program or a system-enumerating builtin. Measured in one
library: `ps --long` 108 ms per call, bare `which` (2275 rows) 27.7 ms per Tab, `git`, `gh`, `wslpath`,
`powershell.exe`. A 40 us closure entry is 0.04% of such a call. The lever there is the external call itself
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
3. `probe entries {|| <call> }`: exact closure-command entries of one run, by command. Entries times 40 us is
   the share of the run that restructuring can remove. The count cannot show one entry getting cheaper:
   `par-each` to `each` reads 1 and 1 while the run drops by a millisecond.
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
  order on each run (17 orders in 30 runs of a nine-element completer), so compare it sorted, and say in the
  commit that `each` made the order deterministic.

If the two variants disagree, stop timing: one of them is wrong, and it is as likely to be the original. Settle
which, and treat it as a defect with its own failing test, separate from the optimisation.

## Patterns

Try 1 to 5 in that order. 6 and 7 apply wherever `probe hot` points at them.

1. **A builtin that takes no closure.** `in` / `not-in`, `math sum`, `str join`, `get <col>`, `select`,
   `reject`, `uniq`, `compact --empty`, `is-empty`, `group-by <col>`, `sort-by <col>`, `update <col> <value>`,
   `transpose --header-row --as-record`, `format pattern` over a table, string commands fed a whole list.
2. **Enter once.** `flatten` first, then one `where` or `each` over the flat list, instead of a closure per
   row. Replace state carried between iterations with two stateless passes before reaching for `reduce` or
   `mut`.
3. **Guard the scan that is usually empty**: `if ($xs | is-not-empty) and (...)`.
4. **A small scan entered many times** becomes a `for` with `break`, or a private `def` with an early
   `return`.
5. **`default {closure}` becomes `default <value>`** only when the value is cheap and has no side effect: the
   closure form is lazy, the value form is not.
6. **`par-each` is a budget, not a style.** It costs about 1.1 ms to enter, so it pays only when the serial
   work it spreads is well above that: external or IO work per element (two globs: `each` measured 62%
   slower), or a heavy pure body over many elements (a formatter at 9-15 us per element: `each` wins by 82%
   at 4 elements and loses by 66% at 1741, crossover near 130). Over a few cheap pure rows it is the whole
   cost (3 rows: 3.2 ms, against 0.57 ms with `each`). When real callers sit on both sides of the crossover,
   keep `par-each`: a size gate would bake a load-dependent constant into the code.
7. **A cheaper builtin for the same job**, when `probe hot` puts the time on one closure-free line:
   `describe | str replace --regex '<.*' ''` for `describe | split words | first` (0.41 ms to 0.03 ms), a builtin
   `match` for a closure-taking dispatch helper (9.4 ms to 2.4 ms across one completer). `probe entries` reads
   0 to 0 for such a change: only the self-time view finds it. Check the arms first: over 19 value shapes the
   forms differ on one, `cell-path`, which `split words` reads as `cell` and the `str replace` does not. Where
   an arm matches or prints the name, the exact drop-in is `describe | parse --regex '^(?<type>\w*)' | get 0.type`
   (0.017 ms against 0.008 for the `str replace` and 0.40 for `split words`).

Patterns 3 and 4 together, on a check that runs once per rule of a validator (sparse input 5.5 ms to 3.5 ms):

```nu
# before, once per rule:   $dead | any {|d| $at == $d or ($at starts-with $"($d).") }
# A `for`, not `any`: entering a closure command costs about ten times what the loop does.
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
- **It inflates run time about 4x** (17,595 rows for a 3.85 ms run, profiled at 14.25 ms). Rank with it;
  never quote a duration from it.
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
| `[] \| math sum` | Raises "Empty input". Write `append 0 \| math sum`. |
| Equality checked on the happy path only | A vectorised regex rewrite of a PATH partition matched on every ordinary input and silently dropped an empty PATH element. |
| Diffing two saved outputs | A harness that fails to parse writes two empty files, and `cmp` calls them identical. Assert the old output is non-empty (`test -s`) before comparing. |
| `mut` blamed for slowness | Mutability measured as free. Count entries instead. |
