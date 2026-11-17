# Cost model: measured figures

Measured with the kit in [`scripts/probe.nu`](../scripts/probe.nu) on nu 0.117.1-nightly, one WSL2 laptop with
22 CPUs, November 2026. Trust the ratios; re-measure the absolutes with `probe calibrate` after a nu upgrade or
on another machine. Library case studies measured on an older nu are in [case studies](case-studies.md).

## Entry cost

Microseconds to enter a form once, on a quiet machine with no config (about 1.3x under a login config):

| about 3 us | about 5-9 us | about 70 us | about 830 us |
|---|---|---|---|
| `for`, `while`, `if`, `match`, `try`, `do {}`, a custom `def` call, `with-env` (5), `collect {closure}`, most closure-free builtins (`str replace`, `get`, `in`, `split row`: 3-4), `zip <list>`, and `update` / `insert` / `default` / `group-by` / `sort-by` given a **value or a column name** | `each`, `where` (row condition or closure), `any`, `all`, `reduce`, `items`, `take while` / `until`, `skip while` / `until`, `each while`, `chunk-by`, `update cells`, `zip {closure}`, `record walk`, `record apply` (5-6); `record each`, `record where`, `str replace {closure}` (9); `generate` (11); and `update` / `insert` / `default` / `group-by` / `sort-by` given a **closure** (5-7) | `tee`, `interleave`: both run their closures in parallel | `par-each` |

The timing loop itself accounts for about 2 us of every figure, so the gap between the first two columns is
larger than it looks: about 1 us of work against 3 to 7.

## Per-element cost

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

## Builtins and cell paths

- `split words` costs about 350 us a call (Unicode segmentation) against 4 for `str replace --regex` and 4 for
  `split row`.
- Piping a large record into a command costs by the record's size; a cell path does not. `$env | get --optional
  time.alarms` took 0.076 ms in a bare 126-variable environment and 0.118 ms with 90 more variables, against a
  flat 0.002 ms for `$env.time?.alarms?`.

## Loop shapes

- Each nested entry of a closure command costs about 3 us per outer element in either style, four to seven
  times the outer body.
- A closure-free builtin costs a half to a third of the entry cost of a closure command as timed (less once
  the timing harness is subtracted) and a fifteenth or less per element.
- `$list ++= [x]` inside a loop: mapping 1000 elements, `each` 0.6 ms, `for` with `++=` 4.7 ms, `for` with
  `append` 21 ms. The two tie up to about 10 elements; from 20 on `each` wins, by 2.7x at 200.
- `reduce --fold [] { … append … }` at 5,000 items took about a second against 3.9 ms for `each --flatten`.
- State carried across 1200 items (a section-tracking workload): `reduce` 36 ms, `for` with `mut` 33 ms.
- Building a 1000-key record with `insert` in a fold costs 24-27 ms in either style; `each` to `{k v}` rows then
  `transpose --ignore-titles --header-row --as-record` costs 2.5 ms.
- Finding an element 10% into a 1000-element list: `$x in $xs` 2 us, `for` with `break` 51 us, `any {}` 72 us.
- 400 rows with 5 inner items each: a closure per row 2.6 ms, `flatten` then one `where` 1.4 ms, nested `for`
  1.9 ms.

## Record transforms

Measured on 5,000 fields: `record each` 5.0 ms against 28 ms for `items … | into record` and 51 ms through
`transpose`; `record where` 3.1 ms with a closure and 4.2 ms with a row condition, against 12.5 ms for
`items … | compact | into record`. Building the record with `reduce --fold {} { … upsert … }` took 555 ms
against 27 ms for the `items` form.

## Builtins worth knowing

- `join --anti` to drop rows with a match: 0.25 ms against 2.0 for `where k not-in`, 1000 rows by 500.
- `get ...$paths` for several cell paths: 6 us against 30 for `each` over 20 paths.
- `find --only-matching --regex` to extract matches: 78 us against 107 for `parse --regex`.
- Keeping the last row of each of 100 groups in 2000 rows: `uniq-by g --keep-last` took 0.97 ms against 0.37
  for `group-by g --to-table | each {|grp| $grp.items | last }`, with the same result.

## `par-each`

- It costs about 0.83 ms to enter.
- External or IO work per element (two globs): `each` measured 62% slower.
- A formatter at 3.7-6.1 us per element: `each` wins by 97% at 4 elements and by 25% at 130, and loses by 78%
  at 1741, crossover near 170.
- Over a few cheap pure rows it is the whole cost (3 rows: 0.87 ms, against 0.007 ms with `each`).
- At 1741 elements the unordered form took 26-29 ms in every round, slower than `each` (8-9 ms), while
  `--keep-order` took 2.1-2.3 ms; `--threads 4` did not cure it (see the
  [diagnostics table](../../nushell-idioms/references/nushell-diagnostics.md)).
- Without `--keep-order` it returns a different order on each run (13 distinct orders in 30 runs over nine
  elements).
