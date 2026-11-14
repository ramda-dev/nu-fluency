# Tests

## Trigger round-trip cases

`tests/triggers/` holds one `claude plugin eval` case per row of
`tests/triggers.nuon`. Every skill has two cases:

- `<skill>-positive`: a prompt that must make Claude invoke the skill.
- `<skill>-negative`: a nearby prompt that must not invoke it.

Each case allows only the `Skill` tool and is graded by a deterministic
`tool_used` grader, so a run costs model calls but no judge calls. The manifest
points the eval runner at this folder (`experimental.evals` in
`.claude-plugin/plugin.json`).

Run the whole set once:

```sh
claude plugin eval . --tag triggers --ablation none --runs 1
```

`--ablation none` skips the no-plugin baseline arm, which can never invoke a
plugin skill. Drop `--runs 1` for the default three runs per case; add
`--case '<glob>'` to run a subset. Results land in `tests/results/`, which git
ignores.

To add or change a case, edit `tests/triggers.nuon` and regenerate:

```sh
nu tests/gen-triggers.nu
```

The generator rewrites `tests/triggers/` from scratch, so edit the table rather
than the generated files.
