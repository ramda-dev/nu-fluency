#!/usr/bin/env nu
# Regenerate tests/triggers/ from tests/triggers.nuon: one `claude plugin eval`
# case per row, with a deterministic Skill grader. Positive cases pass when the
# skill is invoked; negative cases pass when it is not (`arm: both` keeps that
# grader in the score in two-arm runs, as the eval docs require).

const PLUGIN = 'nu-fluency'

def case-prompt [prompt: string]: nothing -> string {
    [
        '---'
        'max_turns: 3'
        'allowed_tools: [Skill]'
        'tags: [triggers]'
        '---'
        ''
        $prompt
        ''
    ] | str join "\n"
}

def case-grader [skill: string kind: string]: nothing -> string {
    let match = $"'\"skill\"\\s*:\\s*\"($PLUGIN):($skill)\"'"
    let bounds = if $kind == negative { ['min: 0' 'max: 0' 'arm: both'] } else { [] }
    [
        '---'
        'type: tool_used'
        'tool: Skill'
        $"input_match: ($match)"
        ...$bounds
        '---'
        ''
        (if $kind == negative { $"The ($skill) skill is not invoked." } else { $"The ($skill) skill is invoked." })
        ''
    ] | str join "\n"
}

def main []: nothing -> nothing {
    let root = $env.FILE_PWD
    let out = $root | path join triggers
    let cases = open ($root | path join triggers.nuon)
    let kinds = $cases | get kind | uniq
    if ($kinds | any $it not-in [positive negative]) {
        error make --unspanned $"unknown kind in triggers.nuon: ($kinds)"
    }
    rm --recursive --force $out
    $cases | each {|case|
        let dir = $out | path join $"($case.skill)-($case.kind)"
        mkdir ($dir | path join graders)
        case-prompt $case.prompt | save ($dir | path join prompt.md)
        case-grader $case.skill $case.kind | save ($dir | path join graders skill.md)
    } | ignore
    print $"wrote ($cases | length) cases to ($out)"
}
