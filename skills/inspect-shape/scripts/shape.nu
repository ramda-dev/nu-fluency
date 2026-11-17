# shape.nu
# The shape of a value for the inspect-shape skill: its detailed type, its length
# when it has one, and the value itself, cut to the first rows of a list or table.
#
#   use r#'${CLAUDE_PLUGIN_ROOT}/skills/inspect-shape/scripts/shape.nu'#
#   <expression> | shape
#
# A closure is run (with no arguments) and its result described, so a closure
# value cannot be described itself, and the closure's side effects happen. An
# error the closure raises is not caught.

# Describe the shape of the input value.
export def main [
  --max-rows (-m): int = 3 # rows of a list or table to keep in `value` (0 or more)
]: any -> record {
  let value = $in
  if $max_rows < 0 {
    error make {msg: '--max-rows must be 0 or more' label: {text: 'negative' span: (metadata $max_rows).span}}
  }
  if ($value | describe) == closure {
    return (do --capture-errors $value | main --max-rows $max_rows)
  }
  let detail = $value | describe --detailed
  let shown = if $detail.type == list { $value | first $max_rows } else { $value }
  {type: $detail.detailed_type length: $detail.length? value: $shown}
  | record where value != null
}
