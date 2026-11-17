# EasyMail Lists

EasyMail Lists mails items from your bags to your other characters. You keep a list of items for each recipient. At the mailbox, you see what the addon will send, and then you click **Send**.

EasyMail Lists is a fork of [Plain AutoMail](https://www.curseforge.com/wow/addons/plain-auto-mail) by Pyralis.

## Features

- **Preview before sending.** The **Send** tab shows what goes to whom and which rule matched. Click an item to skip it this time.
- **One list per recipient.** Pick recipients from the characters you have logged in with, or type another name.
- **Rows, text, or bags.** Edit a list as rows with icons, as plain text, or pick items from your bags.
- **Add items in three ways.** Shift-click an item, drag it onto the list, or use **Add from bags**.
- **Rules for each item.** Keep stacks, keep a number of items, or send only above a minimum.
- **Patterns menu.** Add a whole group of items with one line, such as `Flowers` or `Ore`.
- **Unbound gear.** Send unbound weapons and armor to one character, with a minimum quality.
- **Themes.** Use the default game look, EllesmereUI, or a flat modern look.
- **Plain AutoMail import.** The addon imports your lists from Plain AutoMail the first time it runs next to it.

## Install

1. Copy the `EasyMailLists` folder to `World of Warcraft\<version>\Interface\AddOns\`.
2. Start the game, or type `/reload`.

If Plain AutoMail is also enabled, EasyMail Lists pauses to avoid mailing everything twice. Disable Plain AutoMail and type `/reload`.

## Use

1. Type `/easymail` or `/eml` to open the window.
2. On the **Lists** tab, click **New** and choose who gets your items.
3. Add items to the list.
4. Open a mailbox. The window docks next to it.
5. On the **Send** tab, check the preview and click **Send**.

**Auto-send** mails everything when you open the mailbox. By default, it needs Shift held down.

## Rules

Each row has a rule menu. In the text view, you write the rule in front of the item name.

| Text | Rule |
| --- | --- |
| `Runecloth` | Send all. |
| `-1 Silk Cloth` | Keep 1 stack and send the rest. |
| `=20 Rockscale Cod` | Keep 20 items and send the rest. |
| `+20 Runecloth` | Send only when you have 20 or more. |
| `Raw *` | `*` matches any text. |

A rule for one item always wins over a group, and a group wins over a `*` line. The order of the lines doesn't matter. For example, `Flowers` with `-1 Peacebloom` keeps one stack of `Peacebloom` and sends all other herbs.

## Patterns

The **Patterns** menu adds one line that stands for a group of items. Plain lines for items that the group already covers are removed. Lines with a rule stay.

| Group | Profession | Items |
| --- | --- | --- |
| `Flowers` | Herbalism | Every herb. |
| `Herb Seeds` | Herbalism | Greenhouse seeds. |
| `Ore` | Mining | Every ore. |
| `Bars` | Mining | Every metal bar. |
| `Scarce ores` | Mining | Pyrite, bauxite, and pitchblende. |
| `Stone` | Mining | Rough to dense stone. |
| `Gems` | Mining | Every gem. |
| `Smelting` | Mining | Coal and flux. |
| `Leather` | Skinning | Every leather. |
| `Hides` | Skinning | Light to rugged hide. |
| `Scales` | Skinning | Scales and dragonscales. |
| `Cloth` | Tailoring | Linen to runecloth. |
| `Dusts` | Enchanting | Every dust. |
| `Essences` | Enchanting | Lesser and greater essences. |
| `Shards` | Enchanting | Every shard. |
| `Elementals` | Alchemy | Elemental reagents. |
| `Dyes` | Alchemy, leatherworking | Dyes. |
| `Pearls` | Fishing | Pearls. |
| `Cooking` | Cooking | Meat, fish, eggs, and spices. |

The groups use English item names and Classic items plus the new WoW Forever materials. `Flowers` and `Cooking` also take any item of the matching Trade Goods type.

## Test

The tests run with a plain Lua interpreter and a stubbed game API:

```bash
lua test_boe.lua
lua test_ui_smoke.lua
```

## Credits

Plain AutoMail by Pyralis is the base of this addon.
