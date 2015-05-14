* Discover all deployments:
```bash
rsc cm15 index /api/deployments | \
jq '.[] | .name, [.links[] | select(.rel=="self").href][0]' | \
paste -sd"\t\n" - | sort
```
---

* Extract all ST's from a deployment:

```bash
rsc cm16 show /api/deployments/:id view=full | jq '.instances[].server_template.href' | sort | uniq
```
---
