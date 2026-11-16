# Import cost and modules with `nu_exec`

## Measuring an import

`$nu.startup-time` covers the whole boot but does not register config
evaluation in every mode (`--config … -e`), so measure an import as process
wall time: `timeit { ^nu --no-config-file -c 'use mymod; null' }`, minus a bare
`^nu --no-config-file -c null`.

Import cost is parse cost: it cannot be deferred to a background job, only runtime
work in an `export-env` can (see the skill's parse-time keywords section).

## Modules with `nu_exec`

In its default structured mode, the nushell-mcp `nu_exec` tool wraps the
pipeline in `do { … }`, writes it to a temporary script and runs that script, so
scope introspection is limited and a relative `use` resolves against the
temporary script's directory instead of `cwd`. Ways around it:

1. Pass `structured: false`. Raw mode runs the code as plain `nu --commands`, so
a relative `use` resolves against `cwd`; the result comes back as text rather
than NUON.
2. Use the `nu_repl_*` tools instead of `nu_exec`. A REPL bucket keeps its state
between calls and is not subject to this.
3. Pass `includeDirs` with the parent directories of the modules: the tool puts
them on `NU_LIB_DIRS`, so `use <name>` resolves in either mode. Setting
`const NU_LIB_DIRS = [...]` at the start of the pipeline does the same by hand.
4. Use absolute paths in any `use` calls, so resolution doesn't depend on the
script's location.
