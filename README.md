Requirements
---

* (Required) Download the prebuilt Go based [RSC tool](https://github.com/rightscale/rsc) to query the [RightScale API](http://reference.rightscale.com/)
* (Optional) Download the [jq](http://stedolan.github.io/jq/) tool to parse JSON output.

---
Discover the deployment ID you wish to migrate:

```bash
rsc -a <source account ID> cm15 index /api/deployments \
| jq '.[] | .name, [.links[] | select(.rel=="self").href][0]' \
| paste -sd"\t\n" - | sort
```
---

Discover deployment group to publish to:

```bash
rsc cm15 index /api/account_groups | \
jq '.[] | .name, [.links[] | select(.rel=="self").href][0]' | \
paste -sd"\t\n" -
```
---

```bash
Usage: ./copy-deployment.rb [options]
-s, --src <id>                   Source account ID
-d, --dst <id>                   Destination account ID
-e, --deployment <id>            Source deployment ID to be migrated
-g, --group <id>                 Export ServerTemplates to Publishing Group ID
```
