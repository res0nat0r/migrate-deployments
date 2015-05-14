* Discover all deployments:
```bash
rsc cm15 index /api/deployments | \
jq '.[] | .name, [.links[] | select(.rel=="self").href][0]' | \
paste -sd"\t\n" - | sort
```
---

* Discover all publishing groups:

```bash
rsc cm15 index /api/account_groups | \
jq '.[] | .name, [.links[] | select(.rel=="self").href][0]' | \
paste -sd"\t\n" -
```
---

* Extract all ST's from a deployment:

```bash
rsc cm16 show /api/deployments/:id view=full | jq '.instances[].server_template.href' | sort | uniq
```
---

* Publish all ST's:
rsc cm15 publish
