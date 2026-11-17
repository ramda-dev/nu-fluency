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
# Search order: `nu-lint` on PATH; the cargo install folders (`$CARGO_HOME/bin`,
# `~/.cargo/bin`, `~/.local/share/cargo/bin`; `%USERPROFILE%` for `~` on Windows); then,
# on Windows, nu-lint inside the default WSL distribution, on its PATH or in the same
# two cargo folders under its home.
#
# nu-lint runs without a shell on the host, so the code needs no quoting or escaping.
# Inside WSL it runs through one `sh -c` script whose arguments are passed as positional
# parameters, and the config path is converted with `wslpath` there, so a checkout under
# `C:\…` or `\\wsl.localhost\…` both work and the config always reaches nu-lint.

const CONFIGS = path self ../configs

# Runs inside WSL as `sh -c <this> sh <mode> [arg]`. `wsl.exe --exec` starts no login
# shell, so nu-lint is looked for on the default PATH and then in the cargo folders a
# profile would add. Exit 127 means nu-lint was not found.
const WSL_SCRIPT = r#'
p=$(command -v nu-lint 2>/dev/null)
for c in "$HOME/.cargo/bin/nu-lint" "$HOME/.local/share/cargo/bin/nu-lint"; do
  [ -n "$p" ] && break
  [ -x "$c" ] && p=$c
done
[ -n "$p" ] || { echo 'nu-lint not found in WSL' >&2; exit 127; }
case "$1" in
  locate) printf '%s\n' "$p" ;;
  check) config=$(wslpath -a -u "$2") || exit 2; exec "$p" --stdin --format compact --config "$config" ;;
  explain) exec "$p" --explain "$2" ;;
  *) echo "unknown mode: $1" >&2; exit 2 ;;
esac
'#

# A diagnostic line of `--format compact`: `<file>:<line>:<col>: <level>(<rule>): …`.
const DIAGNOSTIC = '^[^:]+:\d+:\d+:\s+(warning|error|hint)\('

# The cargo install folders to try when nu-lint is not on PATH: `$CARGO_HOME/bin`, then
# the default and the XDG-style locations.
def cargo-candidates []: nothing -> list<string> {
  let windows = $nu.os-info.name == windows
  let home = if $windows { $env.USERPROFILE? } else { $env.HOME? }
  let exe = if $windows { 'nu-lint.exe' } else { 'nu-lint' }
  let homes = if $home == null { [] } else {
    [($home | path join .cargo) ($home | path join .local share cargo)]
  }
  $env.CARGO_HOME? | append $homes | compact | each {|dir| $dir | path join bin $exe }
}

# The path of a nu-lint on this host (not inside WSL), or null.
def native []: nothing -> oneof<string, nothing> {
  let found = which nu-lint | where type == external | first
  if $found != null { return $found.path }
  cargo-candidates | where ($it | path exists) | first
}

# Whether nu-lint may be inside WSL: a Windows host with `wsl.exe`.
def wsl-host []: nothing -> bool {
  $nu.os-info.name == windows and (which wsl.exe | is-not-empty)
}

# Run the WSL script with `mode` and its arguments; returns `complete`'s record.
# The script's line endings are normalized, since a Windows checkout may give it CRLF.
def wsl-run [mode: string ...args: string]: oneof<string, nothing> -> record<stdout: string, stderr: string, exit_code: int> {
  let script = $WSL_SCRIPT | str replace --all "\r" ''
  $in | wsl.exe --exec sh -c $script sh $mode ...$args | complete
}

# Where nu-lint is on this host, or null when it cannot be found.
export def locate []: nothing -> oneof<record<via: string, path: string>, nothing> {
  let path = native
  if $path != null { return {via: native path: $path} }
  if not (wsl-host) { return null }
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
  let not_found = {linter: null exit_code: 127 diagnostics: [] output: '' stderr: 'nu-lint not found'}
  let path = native
  # Inside WSL the script finds nu-lint and lints in one `wsl.exe` start, so a cold
  # WSL is started once per check.
  let linter = if $path != null { {via: native path: $path} } else if (wsl-host) { {via: wsl path: null} }
  if $linter == null { return $not_found }
  let result = if $linter.via == wsl {
    $code | wsl-run check $config_path
  } else {
    $code | ^$linter.path --stdin --format compact --config $config_path | complete
  }
  if $linter.via == wsl and $result.exit_code == 127 { return $not_found }
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
  let path = native
  let result = if $path != null {
    ^$path --explain $rule | complete
  } else if (wsl-host) {
    null | wsl-run explain $rule
  } else {
    error make --unspanned {msg: 'nu-lint not found'}
  }
  if $result.exit_code != 0 {
    error make --unspanned {msg: $"nu-lint --explain ($rule) failed" help: ($result.stderr | str trim)}
  }
  $result.stdout | str trim
}
