# EasyMail Lists: user-experience plan

The goal: a new user understands the addon in one minute, and nobody is surprised by
what it mails.

## Problems today

These come from using the addon in this project, not from guesses.

| Problem | Example |
| --- | --- |
| Rules are a hidden syntax. | `+20` reads like "keep 20" but means "mail all when I own 20". |
| You can't see what the addon will mail before it mails it. | "It sent everything." |
| Sending is triggered by holding Shift while you open the mailbox. | Easy to forget, easy to trigger by accident. |
| The list is free text. | Typos fail silently. Nothing shows that a line matches no item. |
| Recipients are typed by hand, with a faction icon to toggle. | A typo in a name mails items to a stranger. |
| BoE mailing is a blunt rule. | It mails gear that you carry to equip later. |
| Help is one long tooltip. | You must already know that the **?** button exists. |

## Design principles

- **Show before you send.** Nothing leaves your bags without a visible list first.
- **Plain words, no syntax.** You choose a rule from a menu.
- **Pick, don't type.** Items and recipients come from clicks.
- **Old lists keep working.** Every existing line and prefix still loads.

## Phase 1: understand what happens

This phase removes the surprises. It's the most valuable phase.

1. **Preview at the mailbox.** The docked window opens on a **Send** tab that lists
   what goes to whom, for example "Luttman Bank: 40 Mithril Ore, 12 Raw Sagefish".
   Each row shows the rule that matched it.
2. **A Send button.** One click sends what the preview shows. The Shift shortcut stays
   as an option for people who like it, and it's off for new users.
3. **Skip one item this time.** Click a row in the preview to leave that item out of
   this send.
4. **A summary afterwards.** One chat line per recipient, plus a line for what the
   addon kept and why, for example "Kept 15 Rockscale Cod: fewer than 20".
5. **A guard for risky rules.** A line that is only `*` asks for confirmation.

## Phase 2: easy to add items and rules

1. **Rows instead of text.** Each item is a row with its icon, its name, its rule, and
   a remove button. Rows that match nothing in the game are marked.
2. **Rules in plain words.** Each row has a menu:
   - Send all
   - Keep N items, send the rest
   - Keep N stacks, send the rest
   - Send only when I have N or more
3. **Keep N items.** This rule is new. It needs stack splitting, so it's the largest
   single piece of work in the plan.
4. **Three ways to add.** Shift-click and drag-and-drop stay. A new **Add from bags**
   button shows your bag items as icons. Click one to add it.
5. **Text mode stays available.** A button switches to the old text box, for pasting
   and bulk edits. The `+`, `-`, and `*` syntax still works there.

## Phase 3: recipients and gear

1. **Pick recipients from your characters.** The addon remembers every character that
   you log in with, including faction and realm. **New** shows that list. Typing a name
   stays possible for other people.
2. **No faction toggle.** The addon knows the faction of your own characters. The icon
   stays only for typed names.
3. **Clearer gear rule.** "Mail BoE gear" becomes "Send unbound gear to this
   character", with a minimum quality menu (green, blue, epic). The preview from phase 1
   shows every piece before it's sent.
4. **Item groups.** Menu entries such as "All cloth" or "All raw fish" add a wildcard
   line for you.

## Phase 4: polish

1. **First-run guide.** An empty window shows three steps: add a recipient, add items,
   open a mailbox.
2. **Help where you need it.** A short hint under each control replaces the long
   tooltip.
3. **Flat checkboxes and menu.** They match the rest of the window.
4. **Match by item ID.** Rows store the item ID, so matching doesn't depend on the
   exact name or the game language.

## Phase 5: themes

The window gets three looks that share one layout. VendorProfit does the same in
`ProfessionWindow.lua`, and this phase follows its approach.

| Theme | Setting value | Look |
| --- | --- | --- |
| Default | `game` | The game's own window frame, buttons, checkboxes, and fonts, with gold titles. |
| EllesmereUI | `ellesmere` | Flat and dark, with EllesmereUI's accent color and font. |
| Modern | `modern` | Flat, with the blue-grey palette. This is the look without EllesmereUI today. |

1. **One setting.** `EasyMailListsSave.theme` holds `game`, `ellesmere`, or `modern`.
   When it's not set, the addon uses `ellesmere` if EllesmereUI is loaded and `game`
   otherwise. `ellesmere` without EllesmereUI falls back to `modern`.
2. **One place decides the look.** `ApplySkin` picks the colors and fonts. The helpers
   `Button`, `Check`, `Label`, the window frame, and the panels read the theme, so the
   layout code stays the same for all three.
3. **A theme button.** A **Theme** button in the title bar opens a menu with the three
   themes. The current one is marked.
4. **Apply on reload.** The look is read once when the window is built. Picking a theme
   saves it and asks to reload the interface.
5. **Tests.** The smoke test builds and exercises the window once per theme.

## Out of scope

- Mailing gold.
- Collecting or opening received mail.
- Syncing lists between accounts.

## Suggested order

Phase 1 first, because it fixes the "it sent everything" class of problems without
changing how lists are stored. Phase 2 changes the storage format, so it comes with a
converter for existing lists. Phases 3 and 4 are independent of each other.
