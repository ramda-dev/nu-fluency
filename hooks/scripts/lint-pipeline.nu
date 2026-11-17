# nu-fluency: lint the code of an MCP nu_exec or nu_repl_write call
# (`pipeline` and `input` respectively).
#
# Reads tool-input JSON from stdin (Claude Code's hook protocol), lints the
# code with `scripts/lint.nu` and the narrow `configs/hook.nu-lint.toml`, and
# emits a non-empty response only when nu-lint actually flags something.
# Silent on clean code, silent when nu-lint isn't installed or fails.
#
# Invoked by hooks.json as `nu --stdin <this-script>`; no shebang needed.
# `scripts/lint.nu` finds nu-lint on PATH, in the cargo install folders, or
# (on Windows) inside WSL, where the config path is converted with `wslpath`.

use ../../scripts/lint.nu

# Extract the user code from the JSON payload Claude Code piped in:
# nu_exec's `pipeline` or nu_repl_write's `input`.
# Returns the empty string if neither field is present.
def extract-pipeline []: record -> string {
    let payload = $in
    $payload.tool_input?.pipeline?
    | default $payload.tool_input?.input?
    | default $payload.arguments?.pipeline?
    | default ''
    | into string
}

# Build the block-reason text shown when nu-lint flags issues.
def format-reason []: list<string> -> string {
    let diagnostics = $in
    let count = $diagnostics | length
    let header = $"nu-lint flagged ($count) issue\(s\) in the just-executed nu code."
    let footer = 'Run `nu-lint --fix <file>` to auto-fix where possible, or `/audit-pipeline` for guidance. To silence specific rules edit `configs/hook.nu-lint.toml`.'
    [$header '' ...$diagnostics '' $footer] | str join "\n"
}

# Hook entry point. `main` is required because we read `$in` here;
# nu-lint flags `$in` used outside `main` as a runtime-error risk.
def main []: string -> nothing {
    # Defensive parse: if input isn't a JSON object for any reason, exit silent
    # (`from json` returns some non-JSON text as a plain string rather than failing).
    let parsed = try { $in | from json } catch { null }
    let payload = if ($parsed | describe | str starts-with record) { $parsed } else { {} }
    let pipeline = $payload | extract-pipeline

    # Nothing to lint → silent pass-through.
    if ($pipeline | str trim | is-empty) {
        print '{}'
        return
    }

    # Only finding lines count: nu-lint prints "No violations found!" on a
    # clean pass, and a missing linter or a failed run (a config conflict,
    # a crash) yields none, so our tooling never blocks the call.
    let diagnostics = try { $pipeline | lint check hook | get diagnostics } catch { [] }
    if ($diagnostics | is-empty) {
        print '{}'
        return
    }

    {decision: block, reason: ($diagnostics | format-reason)} | to json --raw | print
}
