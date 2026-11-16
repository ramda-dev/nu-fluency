# shape.nu
# The shape of a value for the inspect-shape skill: its detailed type, its length
# when it has one, and the value itself, cut to the first rows of a list or table.
#
#   use '${CLAUDE_PLUGIN_ROOT}/skills/inspect-shape/scripts/shape.nu'
#   <expression> | shape
#
# A closure is run and its result described, so `{|| <expression> } | shape`
# describes what the expression returns.

# Describe the shape of the input value.
export def main [
  --max-rows (-m): int = 3 # rows of a list or table to keep in `value`
]: any -> record {
  let value = $in
  if ($value | describe) == closure {
    return (do --capture-errors $value | main --max-rows $max_rows)
  }
  let detail = $value | describe --detailed
  let shown = if $detail.type == list { $value | first $max_rows } else { $value }
  {type: $detail.detailed_type length: $detail.length? value: $shown}
  | items {|k v| if $v != null { [$k $v] } }
  | compact
  | into record
}
