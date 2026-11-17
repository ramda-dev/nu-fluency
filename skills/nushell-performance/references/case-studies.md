# Case studies

Optimisations tried on one Nushell library's real code: its validator, completers, hooks and helpers. Unless
an item says otherwise, it was measured on nu 0.115.2-nightly in September 2026 and not re-run; closure entry
cost roughly seven times as much then, so the gains would be smaller today. The figures show how the heat rule
and the keep rule decide, not what a rewrite will gain now.

## Heat

- A 0.29 ms type-dispatch helper looked cold until its callers turned out to be another module's `each` and a
  per-prompt hook condition. Rewritten with pattern 4 (a `for` with `break`, or a `def` with an early
  `return`): 0.048 ms, 83%.
- A helper that a plain `match` made 96% faster had no caller anywhere, so it stayed.
- Bound by externals and system-enumerating builtins: `ps --long` 108 ms per call, bare `which` (2275 rows)
  27.7 ms per Tab, `git`, `gh`, `wslpath`, `powershell.exe`. A 6 us closure entry is 0.02% of the cheapest of
  these.

## Declined gains

- A 78% gain worth 46 us on one completer was declined because a sibling completer spends 30 ms on the same
  Tab.
- A 7% gain worth 30 us per shell start was declined because it replaced a branch that cannot miss a case with
  two regexes that must stay exact complements of each other.
- Two rewrites worth 58% and 77% in isolation were 3% and 5% of their completers, whose time went to
  `commandline complete` and `plugin list`.
- A `for` with `++=` rewrite of a completion formatter won below about 120 items and lost badly above.

## Entries predict time

One 36-rule validator written three ways: 13 entries 3.8 ms, 55 entries 5.8 ms, 141 entries 10.7 ms. Exact
entry counts from `debug profile` read 13 / 141 / 55 where matching command names in source text read
35 / 160 / 65.

## Restructured state

One library's section-tracking pass (state carried across 1200 items), restructured as two stateless passes,
took 4 ms against 117 ms for the loop.

## Patterns 3 and 4 together

A check that runs once per rule of a validator went from 5.5 ms to 3.5 ms on sparse input (the code is in the
skill, under Patterns).

## A cheaper builtin

- `describe | split words | first` was 97% of a path helper that three completers call on every Tab.
- A builtin `match` for a closure-taking dispatch helper: 9.4 ms to 2.4 ms across one completer.
- Re-measured on nu 0.117.1-nightly: `describe | str replace --regex '<.*' ''` for
  `describe | split words | first` is 0.36 ms to 0.005 ms. Over 19 value shapes the two forms differ on one,
  `cell-path`, which `split words` reads as `cell` and the `str replace` does not. Where an arm matches or
  prints the name, the exact drop-in is `describe | parse --regex '^(?<type>\w*)' | get 0.type` (0.014 ms
  against 0.005 for the `str replace` and 0.36 for `split words`).

## Equality

- A vectorised regex rewrite of a PATH partition matched on every ordinary input and silently dropped an empty
  PATH element.
- A harness that failed to parse wrote two empty files, and `cmp` called them identical.

## Timing

- An old-versus-old control read +4%. Drift between two separate `probe time` runs is larger than most gains;
  other benchmarks on the machine swing a result by 10 points or more.
- `std bench` under `nu -l` reported 962 us for one `each` that a plain timing loop put at 55 us.
