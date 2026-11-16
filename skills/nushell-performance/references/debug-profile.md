# Reading `debug profile` directly

Read this when `probe hot` and `probe entries` are not enough and you need the raw profile. Figures are from
nu 0.117.1-nightly unless marked.

`debug profile --max-depth 30 --lines --duration-values {|| <call> }` returns one row per IR instruction with
columns `depth id parent_id file line source pc instruction duration`. Other flags: `--spans`,
`--expand-source`, `--values`. There is no `--instructions` flag; the column is always present.

- **Exact entry counts**: keep rows where `instruction =~ '^call'` and parse the callee with
  `decl \d+ "(?<name>[^"]+)"`. Matching command names in `source` text double-counts (it read 35 / 160 / 65
  where the exact counts were 13 / 141 / 55, on nu 0.115.2-nightly).
- **It distorts time.** A 2.6 ms run produced 13,610 rows; the durations it recorded summed to 2.8 ms on one
  run and 8.0 ms on another, and the profiled call itself took 85-143 ms. Rank with it; never quote a
  duration from it.
- **Lazy streams move the blame.** `each` and `where` return streams, so the closure body's rows appear after
  the producing function has returned, charged to whatever consumes the stream (often depth 1, parent 0).
  Inclusive time per callee therefore misleads. Self time per source line (a row's duration minus its
  children's, joined on `parent_id`) is the view to trust; `probe hot` computes both.
