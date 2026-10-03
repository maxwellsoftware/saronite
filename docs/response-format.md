# Bot answer format, version 1

The bot answers an export with the optimized setup. The player pastes it
into the addon (`/sar import`), which renders it.

## Envelope

```
!SARP:1!<payload>
```

Same encoding as the export: `EncodeForPrint(CompressZlib(body))`.

## Body

Lines of `|`-separated fields.

| Record | Fields | Notes |
|---|---|---|
| `SARP` | version | First line |
| `H` | `char`, name, realm | |
| `H` | `spec`, label | Localized spec label, e.g. `Сила зверя (ДД)` |
| `H` | `phase`, phase | `T7` |
| `C` | `hit` or `exp`, before, after, cap | Hit in %, expertise in skill points |
| `I` | slot, item, loc, bag:slot, enchant source, enchant id, g1, g2, g3, g4, sockets, flags | One per inventory slot of the setup |
| `N` | text | Localized note |

Item fields:

- `slot` — inventory slot (1 head … 18 ranged).
- `item`, `loc`, `bag:slot` — the owned item to equip and where it is (`E` equipped, `B` bags, `K` bank).
- `enchant source` — `s<spell id>` or `i<item id>` of the enchant to apply (empty: none); the addon shows its localized name. `enchant id` is the SpellItemEnchantment id.
- `g1`–`g4` — gem item ids per socket; `0` for sockets beyond `sockets`.
- `sockets` — socket colors `M R Y B P`; `P` also marks an extra socket (belt buckle, blacksmith).
- `flags` — `I` item changes, `E` enchant changes, `G` gems change, `B` the belt needs an Eternal Belt Buckle.
