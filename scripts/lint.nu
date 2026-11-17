# lint.nu
# Finds nu-lint on this host and lints Nushell code with one of the plugin's configs.
# Shared by `/audit-pipeline` (through `nu_exec`) and the post-`nu_exec` lint hook.
#
#   use <plugin root>/scripts/lint.nu
#   lint locate                      where nu-lint is: {via: native|wsl, path: <path>}, or null
#   <code> | lint check strict       lint the piped code with configs/strict.nu-lint.toml
#   <code> | lint check hook         the same with configs/hook.nu-lint.toml
#   lint explain <rule>              nu-lint's explanation of one rule
#
# Search order: `nu-lint` on PATH; the cargo install folders (`~/.cargo/bin`, and on
# Windows also `%USERPROFILE%\.local\share\cargo\bin`); then, on Windows, nu-lint inside
# the default WSL distribution, on its PATH or in its `~/.cargo/bin`.
#
# nu-lint runs without a shell on the host, so the code needs no quoting or escaping.
# Inside WSL it runs through one `sh -c` script whose arguments are passed as positional
# parameters, and the config path is converted with `wslpath` there, so a checkout under
# `C:\…` or `\\wsl.localhost\…` both work and the config always reaches nu-lint.

const CONFIGS = path self ../configs

# Runs inside WSL as `sh -c <this> sh <mode> [arg]`. `wsl.exe --exec` starts no login
# shell, so nu-lint is looked for on the default PATH and then in ~/.cargo/bin.
const WSL_SCRIPT = r#'
p=$(command -v nu-lint 2>/dev/null) || p="$HOME/.cargo/bin/nu-lint"
[ -x "$p" ] || { echo 'nu-lint not found in WSL' >&2; exit 127; }
case "$1" in
  locate) printf '%s\n' "$p" ;;
  check) config=$(wslpath -a -u "$2") || exit 2; exec "$p" --stdin --format compact --config "$config" ;;
  explain) exec "$p" --explain "$2" ;;
  *) echo "unknown mode: $1" >&2; exit 2 ;;
esac
'#

# A diagnostic line of `--format compact`: `<file>:<line>:<col>: <level>(<rule>): …`.
const DIAGNOSTIC = '^[^:]+:\d+:\d+:\s+(warning|error|hint)\('

# The cargo install folders to try when nu-lint is not on PATH.
def cargo-candidates []: nothing -> list<string> {
  let windows = $nu.os-info.name == 'windows'
  let home = if $windows { $env.USERPROFILE? } else { $env.HOME? }
  if $home == null { return [] }
  let exe = if $windows { 'nu-lint.exe' } else { 'nu-lint' }
  let folders = if $windows {
    [['.cargo' bin] ['.local' share cargo bin]]
  } else {
    [['.cargo' bin]]
  }
  $folders | each {|parts| $home | path join ...$parts $exe }
}

# Run the WSL script with `mode` and its arguments; returns `complete`'s record.
def wsl-run [mode: string ...args: string]: any -> record<stdout: string, stderr: string, exit_code: int> {
  $in | ^wsl.exe --exec sh -c $WSL_SCRIPT sh $mode ...$args | complete
}

# Where nu-lint is on this host, or null when it cannot be found.
export def locate []: nothing -> oneof<record<via: string, path: string>, nothing> {
  let found = which nu-lint | where type == external | first
  if $found != null { return {via: native path: $found.path} }
  let cargo = cargo-candidates | where ($it | path exists) | first
  if $cargo != null { return {via: native path: $cargo} }
  if $nu.os-info.name != 'windows' or (which wsl.exe | is-empty) { return null }
  let probe = null | wsl-run locate
  if $probe.exit_code != 0 { return null }
  {via: wsl path: ($probe.stdout | str trim)}
}

# Lint the piped Nushell code with the plugin's `strict` or `hook` config.
# `diagnostics` holds only the finding lines; `output` is nu-lint's whole stdout. A
# `linter` of null means nu-lint was not found (nothing ran).
export def check [
  config: string  # `strict` (explicit audits) or `hook` (the post-nu_exec hook)
]: string -> record<linter: any, exit_code: int, diagnostics: list<string>, output: string, stderr: string> {
  let code: string = $in
  if $config not-in [strict hook] {
    error make --unspanned {msg: $"unknown config '($config)'" help: 'use strict or hook'}
  }
  let config_path = $CONFIGS | path join $"($config).nu-lint.toml"
  let linter = locate
  if $linter == null {
    return {linter: null exit_code: 127 diagnostics: [] output: '' stderr: 'nu-lint not found'}
  }
  let result = if $linter.via == wsl {
    $code | wsl-run check $config_path
  } else {
    $code | ^$linter.path --stdin --format compact --config $config_path | complete
  }
  {
    linter: $linter
    exit_code: $result.exit_code
    diagnostics: ($result.stdout | lines | where $it =~ $DIAGNOSTIC)
    output: ($result.stdout | str trim)
    stderr: ($result.stderr | str trim)
  }
}

# nu-lint's explanation of one rule.
export def explain [
  rule: string  # the rule id, as printed in a diagnostic's parentheses
]: nothing -> string {
  let linter = locate
  if $linter == null { error make --unspanned {msg: 'nu-lint not found'} }
  let result = if $linter.via == wsl {
    null | wsl-run explain $rule
  } else {
    ^$linter.path --explain $rule | complete
  }
  if $result.exit_code != 0 {
    error make --unspanned {msg: $"nu-lint --explain ($rule) failed" help: ($result.stderr | str trim)}
  }
  $result.stdout | str trim
}
