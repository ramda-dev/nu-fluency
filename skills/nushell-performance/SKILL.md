---
name: nushell-performance
description: >
  Finds and fixes slow Nushell code: establish heat, profile with
  `probe hot`, count closure-command entries, then apply the first
  pattern that fits. Use when nu code feels slow or is about to be
  optimised, benchmarked or profiled (prompt hooks, Tab completers,
  `export-env` startup, per-element helpers, choosing between `for` and
  `each`/`where`/`reduce`/`any` for speed, `par-each`, `debug profile`,
  `timeit`, `std bench`), or when judging a claimed speed-up.
user-invocable: false
allowed-tools: Bash(nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" nushell-performance *)
compatibility: Requires Nushell 0.117.0 or later.
metadata:
  version: 0.1.1
---

# Nushell Performance

In Nushell the cost of iteration is set by **how many times a closure-taking command is entered**, and by what
each body does. It is not set by mutability. Entering `each`, `where`, `any` or `reduce` costs about twice
what entering a `for`, a `match` or a custom `def` costs (three or more for `record each`, `record where` and
`generate`), whatever the input size; those ratios include the timing harness, and net of it the gap is wider
([cost model](references/cost-model.md)). Per element, a loop body costs a little over half what the same
closure body does, but a loop that builds a list copies it on every step. And in a shell library most wall
time is not nu code at all: it is one external program or one builtin that enumerates the system. So profile
first, count entries second, edit last.

Absolute figures depend on the nu build and the machine, so the measured tables live in
[the cost model reference](references/cost-model.md), labeled with both. Trust the ratios; re-measure the
entry costs with `probe calibrate` after a nu upgrade or on another machine
(`${CLAUDE_PLUGIN_ROOT}/bench/perf/run.nu` re-measures the rest of the 0.117.1 figures; its header lists
what it skips). Figures inline below come from the
same nu 0.117.1-nightly runs, except the library cases, which are mostly from 0.115.2-nightly (the
[case studies](references/case-studies.md) mark each one re-run since).

```nu
use '${CLAUDE_PLUGIN_ROOT}/skills/nushell-performance/scripts/probe.nu'
```

Known bugs for the running nu, if any:

!`nu --no-config-file "${CLAUDE_PLUGIN_ROOT}/scripts/version-notes.nu" nushell-performance 2>/dev/null || echo 'Unavailable: nu was not found or the notes script failed.'`

## Cost model

Three tiers of entry cost:

- **Cheapest, about 3 us**: `for` (and, unmeasured, `while` and `if`), `match`, `try`, `do {}`, a custom `def` call, and most
  closure-free builtins, including `update` / `insert` / `default` / `group-by` / `sort-by` given a value or a
  column name.
- **About two to four times that**: the commands that call a closure for each element (`each`, `where`, `any`,
  `all`, `reduce`, `items`, `take while`, `record each`, `record where`, `generate`), and `update` / `insert`
  / `default` / `group-by` / `sort-by` given a closure. Taking a closure is not the cost by itself: `do {}`
  and `collect {closure}` stay in the cheapest tier.
- **A budget, not a style**: `tee` and `interleave` (about 70 us) and `par-each` (about 0.83 ms).

Per element, a `for` body costs a little over half what the same body costs in `each`, and a closure-free
builtin a fifteenth or less. A body's own cost can dwarf both, so measure it (`probe time` at two sizes, divide
the difference) before assuming it is cheap. Builtins are not uniformly cheap either: `split words` costs about
a hundred times `split row`, and `probe hot` names such a line at once; nothing else will.

What follows:

- One closure command over a large collection is the right default for building a result. A `for` body is
  cheaper per element, but a `for` that collects into a list loses: `$list ++= [x]` copies the list every time,
  so it is quadratic.
- Never build a list or record in `reduce --fold`: every step copies the accumulator, so it is quadratic. Fold
  only to a scalar, and prefer a builtin (`math sum`, `str join`) when one exists. `reduce` is no cheaper than
  `for` with `mut` either; replace state carried between iterations with two stateless passes.
- To build a record from rows, map to `{k v}` rows with `each` and finish with
  `transpose --ignore-titles --header-row --as-record | default --empty {}`, not `insert` in a fold. Without the
  `default`, empty input gives `[]`, not `{}`; a repeated key keeps its first value, where `insert` raises.
- The slow shape is a closure command entered many times: inside another closure, inside a loop, or inside a
  function that itself runs per element, per prompt, per keypress or at shell startup.
- A closure-free builtin beats both styles.
- Piping a large record into a command costs by the record's size; a cell path does not
  (`$env.time?.alarms?`, not `$env | get --optional time.alarms`).
- Total entries predict run time.

## Where it pays, and where it does not

Hot: `export-env` blocks (every shell start), hooks (every prompt), completers (every Tab), and pure-nu helpers
that something else calls per element. A helper's heat is decided by its callers, so search the whole library
for them, not just its own file: a 0.29 ms type-dispatch helper looked cold until its callers turned out to be
another module's `each` and a per-prompt hook condition.

Not worth touching: anything bound by an external program or a system-enumerating builtin (`ps --long`, bare
`which`, `git`, `gh`). The lever there is the external call itself (fewer calls, a narrower query, a cache),
never the nu around it.

Relative gain is not the bar. Multiply the microseconds saved by how often the trigger fires, and set that
against what else runs on the same trigger: a 78% gain worth 46 us on one completer was correctly declined
because a sibling completer spends 30 ms on the same Tab. Correctness risk counts too. More cases, with their
nu version, are in [case studies](references/case-studies.md).

## Workflow

Heat is a gate, and it comes before every number: a function no hot context reaches is left alone however
large its measured gain (a helper that a plain `match` made 96% faster had no caller anywhere, so it stayed).

1. Establish heat: name the trigger (shell start, prompt, Tab, per element of what) and find the callers
   across the whole library. No hot caller: record it as cold and stop.
2. `probe hot {|| <call> }`: self time per source line, plus calls and inclusive time per callee. An external
   or a heavy builtin shows up here at once, which usually ends the investigation. When the function owns
   only a few percent of its trigger, stop: halving 5% of a Tab is 2.5% of the Tab.
3. `probe entries {|| <call> }`: exact closure-command entries of one run, by command. Entries times about
   3 us (6 us for `record each` / `record where`, 8 for `generate`) is the most that rewriting them as loops can
   remove; a `tee`, `interleave` or `par-each` entry is a budget item, so subtract those (listed in `by`)
   from `total` first. `total` counts only commands that always take a closure: `update`, `insert`,
   `default`, `group-by`, `sort-by`, `collect`, `zip` and `str replace` are tallied in `closure-or-value`
   whether given a closure or a value, so check the source before counting them.
   Entries made per element usually matter more than their count suggests, because each one also pays its
   body. The count cannot show one entry getting cheaper: `par-each` to `each` reads 1 and 1 while the run
   drops by most of a millisecond.
4. Build the workload from literal data shaped like the real input, never from live user data. When the real
   input is empty or tiny, that is the workload: measure the guard path and stop, rather than tuning for a
   size nobody has. When input size varies, measure several sizes: a `for` with `++=` rewrite of a completion
   formatter won below about 120 items and lost badly above. When the common case is dominated by something
   else (a glob, an external), quote the case where the change shows, say which real case it is, and report
   the common one too.
5. Apply the first pattern below that fits.
6. `probe compare {|| <old> } {|| <new> }`. It refuses to time unless both closures return equal values, then
   times them old-new-new-old and reports `gain_pct` and `noise_pct`. Never compare two separate
   `probe time` runs: drift between them is larger than most gains. Near the 10% bar, also run
   `probe compare {|| <old> } {|| <old> }` as a control.
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
  run the old tree and the new tree in two processes, check that the old output is not empty, and diff their
  `to nuon` output. A variant that turns
  the empty case from `[]` into an error is not equal. `par-each` without `--keep-order` can return a different
  order on any run (13 distinct orders in 30 runs over nine elements), so compare it sorted, and say in the
  commit that `each` made the order deterministic.

If the two variants disagree, stop timing: one of them is wrong, and it is as likely to be the original. Settle
which, and treat it as a defect with its own failing test, separate from the optimisation.

## Patterns

Try 1 to 5 in that order. 6 and 7 apply wherever `probe hot` points at them.

1. **A builtin that takes no closure.** `in` / `not-in`, `math sum`, `str join`, `get <col>`, `select`,
   `reject`, `uniq`, `compact --empty`, `is-empty`, `group-by <col>`, `sort-by <col>`, `update <col> <value>`,
   `transpose --ignore-titles --header-row --as-record`, `format pattern` over a table, string commands fed a whole
   list, `join --anti` to drop rows with a match, `get ...$paths` for several cell paths, and
   `find --only-matching --regex` to extract matches. A builtin is not automatically the fastest form, so time
   it: `uniq-by g --keep-last` lost to `group-by g --to-table | each {|grp| $grp.items | last }` for the same
   result ([figures](references/cost-model.md#builtins-worth-knowing)).
2. **Enter once.** `flatten` first, then one `where` or `each` over the flat list, instead of a closure per
   row. Replace state carried between iterations with two stateless passes before reaching for `reduce` or
   `mut`.
3. **Guard the scan that is usually empty**: `if ($xs | is-not-empty) and (...)`.
4. **A small scan entered many times** becomes a `for` with `break`, or a private `def` with an early
   `return`.
5. **`default {closure}` becomes `default <value>`** only when the value is cheap and has no side effect: the
   closure form is lazy, the value form is not.
6. **`par-each` is a budget, not a style.** It costs about 0.83 ms to enter, so it pays only when the serial
   work it spreads is well above that: external or IO work per element, or a heavy pure body over many
   elements (a formatter at 3.7-6.1 us per element crossed over near 170 elements with `--keep-order`). Over a
   few cheap pure rows it is the whole cost. Time `--keep-order` as well as the unordered form: the known-bug
   notes at the top of this skill say whether the unordered form is slower on this nu. When real callers sit
   on both sides of the crossover, keep `par-each`: a size gate would bake a load-dependent constant into the
   code ([figures](references/cost-model.md#par-each)).
7. **A cheaper builtin for the same job**, when `probe hot` puts the time on one closure-free line:
   `describe | str replace --regex '<.*' ''` for `describe | split words | first` (0.36 ms to 0.005 ms), a builtin
   `match` for a closure-taking dispatch helper. `probe entries` reads 0 to 0 for such a change: only the
   self-time view finds it. Check the arms first: the `str replace` form differs from `split words` on
   `cell-path` and on a stream whose description has no `<` (`byte stream`, `table (stream)`), and the
   [case studies](references/case-studies.md#a-cheaper-builtin) give the exact drop-in.

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

## References

- [Cost model](references/cost-model.md): the measured entry and per-element tables, loop shapes, record
  transforms and `par-each` figures. Read when a number decides a change.
- [Case studies](references/case-studies.md): one library's optimisations, kept and declined. Read when judging
  whether a gain is worth keeping.
- [Reading `debug profile` directly](references/debug-profile.md): read when `probe hot` and `probe entries` are
  not enough.
- Don't time with `std bench`: under `nu -l` it reported 962 us for one `each` that a plain timing loop put at
  55 us (nu 0.115.2-nightly). Use `probe time`.
