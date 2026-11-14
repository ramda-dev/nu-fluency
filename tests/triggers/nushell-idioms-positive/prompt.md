---
max_turns: 3
allowed_tools: [Skill]
tags: [triggers]
---

Convert this to Nushell: `cat data.json | jq '.items[] | .name' | sort | uniq`
