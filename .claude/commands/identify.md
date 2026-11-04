---
description: Identifies the connected Android phone precisely
---

Identify the connected phone. Run `sh identify.sh --kv` and tell me in plain words which
phone it is (marketing name, model number, Android and skin version, chip, region) and how
sure you are. If the confidence isn't "high" or "confirmed", ask me to read you the name and
model number from Settings > About phone and save it with `sh identify.sh --confirm "<name>"`.
Don't change anything on the phone.
