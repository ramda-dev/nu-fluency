---
max_turns: 3
allowed_tools: [Skill]
tags: [triggers]
---

Lint this Nushell pipeline and tell me what is wrong with it: `ls | each {|f| $f.name } | str join ','`
