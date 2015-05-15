* Discover all deployments (old account):
```bash
rsc cm15 index /api/deployments | \
jq '.[] | .name, [.links[] | select(.rel=="self").href][0]' | \
paste -sd"\t\n" - | sort
```
---

* Discover all publishing groups (old account):

```bash
rsc cm15 index /api/account_groups | \
jq '.[] | .name, [.links[] | select(.rel=="self").href][0]' | \
paste -sd"\t\n" -
```
---

* Extract all ST's from a deployment (old account):

```bash
rsc cm16 show /api/deployments/:id view=full | jq '.instances[].server_template.href' | sort | uniq
```
---

* Publish all ST's (old account):

```bash
# All ST's need to be a comitted version.
rsc cm15 publish /api/server_templates/:id \
account_group_hrefs[]=/api/account_groups/:id \
descriptions[short]="stuff" descriptions[notes]="stuff" \
descriptions[long]="stuff"
```
---

* Import ST's (new account):
```bash
# How do we discover the HREF's to import?
# The HREFs previously published from above don't
# appear to be consistent between accounts.
cm15 import <href> [<params>]
```
---

* Create new deployment (new account):

```bash
rsc cm15 create /api/deployments deployment[description]="stuff" deployment[name]="stuff"
```
---

* Discover all servers in existing deployment (old account):

```bash
rsc cm16 show /api/deployments/:id view=full
```
---

* Discover relevant info about instances that need to be replicated (old account):

```bash
# Note this isn't quite complete or 100% correct yet.
rsc cm16 show /api/deployments/:id view=full | \
jq '.instances[0].links | .name, .cloud, .datacenter,
 .multi_cloud_image, .instance_type, .security_groups'
 ```
 ---
