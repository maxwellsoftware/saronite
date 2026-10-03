# Export string format, version 1

The contract between the Saronite addon and the gear bot. Any
incompatible change bumps the version in **both** the prefix and the `SAR`
line, and the bot keeps decoding older versions until addons are updated.

## Envelope

```
!SAR:1!<payload>
```

- `<payload>` = `LibDeflate:EncodeForPrint(LibDeflate:CompressZlib(body))`.
- Alphabet `a-z A-Z 0-9 ( )`; 6-bit groups, least significant bits first
  (3 bytes → 4 characters, a partial tail is padded with zero bits).
- zlib (RFC 1950) carries an Adler-32 checksum, so a string damaged by
  copy-paste fails to decode instead of producing garbage.
- The bot strips whitespace and line breaks before decoding (Telegram may
  wrap or split long messages).

## Body

UTF-8 text, one record per line, fields separated by `|`. Field values never
contain `|` or line breaks. Empty field = unknown. Readers ignore unknown
record types and unknown keys (forward compatibility within a version).

| Record | Fields | Notes |
|---|---|---|
| `SAR` | version | Always the first line |
| `H` | key, values… | Header, see below |
| `T` | group, tab, points, ranks | Talent ranks as digits ordered by (tier, column) — the order used by talent calculators. `group` is the dual-spec index (1–2), `tab` is the tree index (1–3) in the client's order |
| `G` | group, ids | Six glyph spell ids, comma separated, `0` = empty socket |
| `P` | key, rank, max | Profession: `ALCHEMY BLACKSMITHING ENCHANTING ENGINEERING HERBALISM INSCRIPTION JEWELCRAFTING LEATHERWORKING MINING SKINNING TAILORING` |
| `S` | key, value | Character sheet snapshot (see below) |
| `I` | 22 fields | Item (see below) |
| `J` | gem id, stats | Stats of a gem item used in the exported items (`STR=16`) |

### Header keys

| Key | Values |
|---|---|
| `addon` | addon version |
| `client` | client version, build, locale (`ruRU`, `enUS`…) |
| `realm`, `name` | realm and character name |
| `class` | class token: `WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK DRUID` |
| `race` | race token: `Human Dwarf NightElf Gnome Draenei Orc Scourge Tauren Troll BloodElf` |
| `sex` | 1 unknown, 2 male, 3 female |
| `level` | character level |
| `time` | unix time of the export |
| `group` | active talent group (1 or 2) |
| `bank` | unix time of the cached bank scan, `0` if the bank was never opened |

### Stats (`S`)

Character sheet values at export time. **They include active buffs** — `buffs`
is the number of buffs so the bot can warn about a buffed snapshot.

Ratings and their percent bonus (`<key>` raw rating, `<key>Pct` percent):
`hitMelee hitRanged hitSpell critMelee critRanged critSpell hasteMelee
hasteRanged hasteSpell expertise arp defense`.

Other keys: `hitMod` and `spellHitMod` (hit % from talents and auras —
**absent on 3.3.5 clients**, which lack `GetHitModifier`; the bot derives hit
from talents itself), `expMH` `expOH`
(expertise skill incl. talents), `ap` `rap` `sp` `heal`, `str agi sta int spi`
(effective), `armor hp mana dodge parry block buffs`, `spellHaste` (total
spell haste % from `UnitSpellHaste`, since addon 0.8.1; absent in older
strings — readers must treat it as optional).

### Items (`I`)

```
I|loc|slot|id|enchant|j1|j2|j3|j4|suffix|unique|g1|g2|g3|g4|count|quality|ilvl|sockets|stats|type|usable|bonus
```

| Field | Meaning |
|---|---|
| `loc` | `E` equipped, `B` bags, `K` bank (cached scan) |
| `slot` | `E`: inventory slot id (1 head … 18 ranged; 4 shirt and 19 tabard are never exported). `B`/`K`: `bag:slot`, bank main container is `-1` |
| `id` | item id |
| `enchant` | enchant id (SpellItemEnchantment) |
| `j1`–`j4` | gem **enchant** ids exactly as in the item link |
| `suffix` | random property / suffix id; negative = random suffix |
| `unique` | link unique id, only for negative `suffix` (carries the suffix factor), otherwise `0` |
| `g1`–`g4` | gem **item** ids resolved by `GetItemGem`, `0` = empty |
| `count` | stack size |
| `quality` | 0 poor … 4 epic, 5 legendary; `-1` unknown |
| `ilvl` | item level from the client cache |
| `sockets` | base sockets of the item: letters `M` meta, `R` red, `Y` yellow, `B` blue, `P` prismatic. Extra sockets (belt buckle, blacksmith) are **not** listed — a gem in `g*` beyond these letters means an extra socket |
| `stats` | `CODE=value` pairs from `GetItemStats`, comma separated, sorted. May be empty for bag/bank items when trimmed |
| `type` | equip location without the `INVTYPE_` prefix: `HEAD NECK SHOULDER CHEST ROBE WAIST LEGS FEET WRIST HAND FINGER TRINKET CLOAK WEAPON SHIELD 2HWEAPON WEAPONMAINHAND WEAPONOFFHAND HOLDABLE RANGED RANGEDRIGHT THROWN RELIC`; empty for gems |
| `usable` | `1` the player can equip it, `0` the tooltip shows a red requirement (armor type, class, level). Empty in older exports = usable |
| `bonus` | socket bonus as the client shows it without the "Socket Bonus:" prefix, localized (`+6 Strength`, `+6 к силе`) |

Stat codes: `STR AGI STA INT SPI HIT CRIT HASTE EXP ARP AP RAP FAP SP SPEN
MP5 HP5 DEF DODGE PARRY BLOCK BLOCKV RESIL ARMOR DPS`. Unknown keys are sent
as the API key without the `ITEM_MOD_` prefix and `_SHORT` suffix.

Stats come from the client's item cache, i.e. what the server sent for this
item id. They let the bot learn custom Frostmourne items it has no data for.

## Size limits

The addon aims at 4000 characters (one Telegram message is 4096). When the
full export is longer it drops, in order: stats of bag/bank items, bank items,
bag items. If it is still too long the player is told to send it anyway; the
bot reassembles a message that Telegram split into parts.
