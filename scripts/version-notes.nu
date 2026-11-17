# version-notes.nu
# Version- and option-dependent notes for the nu-fluency skills, read from
# version-notes.nuon beside this file.
#
#   nu --no-config-file version-notes.nu <skill>         notes that apply to the running nu
#   nu --no-config-file version-notes.nu render          the reference table, as markdown
#   nu --no-config-file version-notes.nu render --write  regenerate the reference file
#   nu --no-config-file version-notes.nu check           fail when the reference file is stale
#
# The per-skill form is injected into SKILL.md bodies, so it stays one short line when
# no note applies and never fails: a failing injected command aborts the whole skill.
# It runs in a fresh process, which sees each experimental option at its default
# whatever the user's own shell sets, so an option note is printed as a condition
# for every nu that has the option, and stated as fact when the option's default
# (its `enabled` value in this fresh process) is the setting it warns about.

const DATA = path self version-notes.nuon
const REFERENCE = path self ../skills/nushell-idioms/references/nushell-diagnostics.md
const SKILLS = path self ../skills
const KEYS = {
  option: [id kind skills option symptom workaround repro]
  diagnostic: [id kind skills since reproduced until symptom workaround repro upstream]
}
const OLDEST_CHECKED = '0.114.1'
const VERSION = '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+.*)?$'

# A version string as a sortable key: 0.117.1-nightly.3 sorts after 0.117.0 and
# before 0.117.1. A prerelease without a number counts as number 0. Build metadata
# (`+…`) does not affect precedence, so it is dropped.
def version-key []: string -> list<int> {
  let parts = split row '+' | first | split row '-'
  let core = $parts | first | split row '.' | each { into int }
  let pre = $parts | skip 1 | str join '-'
  let release = if ($pre | is-empty) { [1 0] } else {
    [0 ($pre | parse --regex '(?<n>\d+)$' | get n.0? | default '0' | into int)]
  }
  $core | append $release
}

# Whether version `a` sorts before version `b`.
def older [a: string b: string]: nothing -> bool {
  let ka = $a | version-key
  let kb = $b | version-key
  let diff = $ka | zip $kb | where $it.0 != $it.1
  if ($diff | is-empty) { false } else { $diff.0.0 < $diff.0.1 }
}

# The notes that apply to the running nu, with the reason for each. An option note
# applies when the running nu has the option; `default` says whether the option's
# default is the setting the note warns about.
def applicable [skill: string]: nothing -> table {
  let running = version | get version
  let options = debug experimental-options | select identifier enabled
  notes | where $skill in $it.skills | each {|note|
    match $note.kind {
      option => {
        let option = $options | where identifier == $note.option.name | get 0?
        if $option != null {
          $note | insert $.stale false | insert $.default ($option.enabled == $note.option.enabled)
        }
      }
      diagnostic => {
        let affected = (not (older $running $note.since)) and ($note.until == null or (older $running $note.until))
        if $affected { $note | insert $.stale (older $note.reproduced $running) }
      }
    }
  } | compact
}

# One markdown bullet for a note.
def bullet [running: string]: record -> string {
  let note = $in
  match $note.kind {
    option => {
      let state = if $note.option.enabled { 'on' } else { 'off' }
      let lead = if $note.default {
        $"`($note.option.name)` is ($state) by default in this nu"
      } else {
        $"If `($note.option.name)` is ($state) in the shell that runs your code \(`debug experimental-options` shows it\)"
      }
      $"- **($lead)**: ($note.symptom). Workaround: ($note.workaround)."
    }
    diagnostic => {
      let unchecked = if $note.stale { $", not yet checked on ($running)" } else { '' }
      $"- **Known Nushell bug \(reproduced on ($note.since) through ($note.reproduced)($unchecked)\)**: ($note.symptom). Workaround: ($note.workaround)."
    }
  }
}

# The data file's rows, or an error naming the first row the per-skill form could not use.
def notes []: nothing -> list<record> {
  let notes = open $DATA
  if ($notes | describe) !~ '^(list|table)' { error make --unspanned {msg: 'version-notes.nuon: not a list'} }
  for n in ($notes | enumerate) {
    if ($n.item | describe) !~ '^record' { error make --unspanned {msg: $"row ($n.index): not a record"} }
    let n = $n.item
    let id = $n.id? | default '(no id)'
    let kind = $n.kind? | default ''
    let keys = if ($kind | describe) == string { $KEYS | get --optional $kind }
    if $keys == null { error make --unspanned {msg: $"($id): kind must be option or diagnostic"} }
    let missing = $keys | where $it not-in ($n | columns)
    if ($missing | is-not-empty) { error make --unspanned {msg: $"($id): missing ($missing | str join ', ')"} }
    let prose = [id symptom workaround repro] | where ($n | get $it | describe) != string
    if ($prose | is-not-empty) { error make --unspanned {msg: $"($id): not a string: ($prose | str join ', ')"} }
    if ($n.skills | describe) !~ '^list<string>' { error make --unspanned {msg: $"($id): skills must be a non-empty list of strings"} }
    if $n.kind == option and (($n.option | describe) !~ '^record' or ($n.option.name? | describe) != string or ($n.option.enabled? | describe) != bool) {
      error make --unspanned {msg: $"($id): option needs a name and a bool enabled"}
    }
    let unknown = $n.skills | where not ($SKILLS | path join $it SKILL.md | path exists)
    if ($unknown | is-not-empty) { error make --unspanned {msg: $"($id): no skill ($unknown | str join ', ')"} }
    if $n.kind == diagnostic {
      let bad = [$n.since $n.reproduced] | where ($it | describe) != string or $it !~ $VERSION
      let bad = if $n.until != null and (($n.until | describe) != string or $n.until !~ $VERSION) { $bad | append [$n.until] } else { $bad }
      if ($bad | is-not-empty) { error make --unspanned {msg: $"($id): not a version string: ($bad | to nuon)"} }
      if (older $n.reproduced $n.since) { error make --unspanned {msg: $"($id): reproduced is older than since"} }
      if $n.until != null and not (older $n.reproduced $n.until) { error make --unspanned {msg: $"($id): until must be newer than reproduced"} }
    }
  }
  let dupes = $notes | get id | uniq --repeated
  if ($dupes | is-not-empty) { error make --unspanned {msg: $"duplicate id: ($dupes | str join ', ')"} }
  $notes
}

def table-cell []: any -> string {
  default '' | into string | str replace --all '|' '\|'
}

# The reference document generated from the data file.
def reference []: nothing -> string {
  let notes = notes
  let diagnostics = $notes | where kind == diagnostic | each {|n|
    [
      $n.id
      $n.symptom
      $'`($n.repro)`'
      $n.workaround
      $n.since
      $n.reproduced
      ($n.until | default open)
      ($n.upstream | default '')
    ] | each { table-cell } | str join ' | ' | $'| ($in) |'
  }
  let options = $notes | where kind == option | each {|n|
    let state = if $n.option.enabled { 'on' } else { 'off' }
    [$'`($n.option.name)` ($state)' $n.symptom $'`($n.repro)`' $n.workaround]
    | each { table-cell } | str join ' | ' | $'| ($in) |'
  }
  [
    '# Nushell diagnostics'
    ''
    '<!-- Generated by scripts/version-notes.nu from scripts/version-notes.nuon; edit the data file, then run `nu --no-config-file scripts/version-notes.nu render --write`. -->'
    ''
    'Nushell bugs that the skills work around. "Since" is the oldest version'
    $"that reproduces the bug \(($OLDEST_CHECKED) was the oldest checked\), \"Reproduced\" the newest,"
    'and "Fixed in" the first version without it. The skills in this plugin print,'
    'when they load, the rows that apply to the running nu.'
    ''
    '| Id | Symptom | Repro | Workaround | Since | Reproduced | Fixed in | Upstream |'
    '|---|---|---|---|---|---|---|---|'
    ...$diagnostics
    ''
    '## Experimental options'
    ''
    'Behavior that depends on an experimental option. The skills print a note as a'
    'condition when the shell that runs the code could have the option set either way'
    '(`debug experimental-options` lists the settings), and as fact when the default'
    'of the option in the running nu is the setting the note warns about.'
    ''
    '| Setting | Symptom | Repro | Workaround |'
    '|---|---|---|---|'
    ...$options
    ''
  ] | str join "\n"
}

# Notes for one skill that apply to the running nu, as markdown bullets.
def main [skill: string]: nothing -> string {
  try {
    if not ($SKILLS | path join $skill SKILL.md | path exists) { error make --unspanned {msg: $"no skill ($skill)"} }
    let running = version | get version
    let bullets = applicable $skill | each { bullet $running }
    let lines = if (older $running $OLDEST_CHECKED) {
      $bullets | append $"Bug notes were checked only on nu ($OLDEST_CHECKED) and newer; bugs affecting nu ($running) may be missing."
    } else { $bullets }
    if ($lines | is-empty) { $"None for nu ($running)." } else { $lines | str join "\n" }
  } catch {|e| $"Unavailable: the notes script failed \(($e.msg)\)." }
}

# Print the reference table, or write it with --write.
def 'main render' [--write]: nothing -> any {
  let doc = reference
  if $write { $doc | save --force $REFERENCE } else { $doc }
}

# Fail when the reference file does not match the data file.
def 'main check' []: nothing -> nothing {
  if (open --raw $REFERENCE | str replace --all "\r\n" "\n") != (reference) {
    error make --unspanned {msg: 'nushell-diagnostics.md is stale; run `render --write`'}
  }
}
