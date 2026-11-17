# Cases for hooks/scripts/lint-pipeline.nu and scripts/lint.nu, with a stub nu-lint.
# Run from the repository root: nu --no-config-file hooks/tests/lint-pipeline.nu
#
# The stub stands in for nu-lint, on PATH or (with `--cargo`) only in `$CARGO_HOME/bin`;
# HOME points at an empty folder, so no real install is found. It echoes its arguments
# as one finding when the code holds `FLAG`, and reports a clean pass otherwise. The
# WSL branch needs a Windows host and is not covered here.

use std/assert

const HOOK = path self ../scripts/lint-pipeline.nu
const LINT = path self ../../scripts/lint.nu
const CONFIGS = path self ../../configs

# Run `code` with a stub nu-lint first on PATH, only in `$CARGO_HOME/bin` (`--cargo`), or
# nowhere (`--stub=false`).
def with-stub [code: closure --stub = true --cargo]: nothing -> any {
  let dir = mktemp --directory
  let home = $dir | path join home
  let cargo_home = $dir | path join cargo
  let bin = if $cargo { $cargo_home | path join bin } else { $dir | path join bin }
  mkdir $home $bin
  if $stub {
    let nu_lint = $bin | path join nu-lint
    [
      '#!/bin/sh'
      # builtins only: the folders that hold a real nu-lint (often /usr/bin) are left off PATH
      r#'input=$(while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "$l"; done)'#
      'case "$input" in *FLAG*) echo "<stdin>:1:1: warning(stub_rule): args $*" ;; *) echo "No violations found!" ;; esac'
    ] | str join "\n" | save $nu_lint
    chmod +x $nu_lint
  }
  let others = $env.PATH | where ($it | path join nu-lint | path exists) == false
  let path = if $cargo { $others } else { $others | prepend $bin }
  let result = with-env {PATH: $path HOME: $home CARGO_HOME: $cargo_home} $code
  rm --recursive $dir
  $result
}

# Run the hook on a payload; return its parsed JSON output.
def hook [payload: record]: nothing -> record {
  $payload | to json | ^$nu.current-exe --no-config-file --stdin $HOOK | from json
}

def main [] {
  if $nu.os-info.name == windows { print 'lint-pipeline: skipped on Windows (the stub is a sh script)'; return }

  # the runner: finds the stub, passes the right config, keeps only finding lines
  let found = with-stub {|| ^$nu.current-exe --no-config-file -c $"use '($LINT)'; 'FLAG' | lint check hook | to nuon" | from nuon }
  assert equal $found.linter.via native
  assert equal ($found.diagnostics | length) 1
  assert str contains $found.diagnostics.0 ($CONFIGS | path join hook.nu-lint.toml)
  let in_cargo = with-stub --cargo {|| ^$nu.current-exe --no-config-file -c $"use '($LINT)'; 'FLAG' | lint check hook | to nuon" | from nuon }
  assert ($in_cargo.linter.path | str ends-with (['cargo' 'bin' 'nu-lint'] | path join))
  assert equal ($in_cargo.diagnostics | length) 1
  let clean = with-stub {|| ^$nu.current-exe --no-config-file -c $"use '($LINT)'; 'ls' | lint check strict | to nuon" | from nuon }
  assert equal $clean.diagnostics []
  assert equal $clean.exit_code 0
  let missing = with-stub --stub=false {|| ^$nu.current-exe --no-config-file -c $"use '($LINT)'; 'FLAG' | lint check strict | to nuon" | from nuon }
  assert equal $missing.linter null

  # the hook: blocks only on findings, from nu_exec's pipeline or nu_repl_write's input
  let blocked = with-stub {|| hook {tool_input: {pipeline: 'FLAG | where x'}} }
  assert equal $blocked.decision block
  assert str contains $blocked.reason 'stub_rule'
  assert equal (with-stub {|| hook {tool_input: {input: 'FLAG'}} } | get decision) block
  assert equal (with-stub {|| hook {tool_input: {pipeline: 'ls'}} }) {}
  assert equal (with-stub --stub=false {|| hook {tool_input: {pipeline: 'FLAG'}} }) {}
  assert equal (with-stub {|| 'not json' | ^$nu.current-exe --no-config-file --stdin $HOOK | from json }) {}

  print 'lint-pipeline: all cases pass'
}
