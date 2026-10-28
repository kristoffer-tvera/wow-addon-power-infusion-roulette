# Power Infusion Roulette

WoW Retail addon for interfaces **120100 / 120105**, version **12.1.5**. No libraries or other addons required.

## Use

1. Enable the addon in WoW's AddOns list and reload the UI if needed.
2. On a Priest who has learned Power Infusion, join a party or raid and type `/pir` or `/powerinfusion`.
3. Group members enter by typing `big` in group chat, in any letter case. Each character gets one entry. Other players do not need the addon.
4. Click the X beside a player to remove and block them for the current round. Their exclusion is announced in group chat.
5. After 30 seconds, or when you click **Start roulette**, signups close and the wheel spins for six seconds. Numbers on the wheel correspond to the player list; hovering a number shows the full name.
6. The winner is announced as `<playername> won this round!` in group chat. Power Infusion is **not** automatically cast or targeted.

The host sees the window and animation. Everyone in the group sees the announcements. Party, raid, and instance groups use their corresponding chat channels. Whisper, say, guild, and unrelated channel messages do not enter the round. Realm-qualified names distinguish characters from different realms.

## Commands

| Command                    | Action                                                |
| -------------------------- | ----------------------------------------------------- |
| `/pir` or `/powerinfusion` | Start a new round, or reopen the active one           |
| `/pir show`                | Reopen the window without starting a round            |
| `/pir timeout 45`          | Save a 5-300 second signup duration for future rounds |
| `/pir cancel`              | Cancel the active round                               |
| `/pir help`                | Print command help                                    |

The window also has a signup-duration field; press Enter or click Apply to save it. Drag the window to move it. Escape or the close button hides it without interrupting the round; the timeout and winner announcement still run.

**Allow healers to enter** and **Allow tanks to enter** are independent checkboxes above the duration settings. Both default to off and are saved between sessions. Changes apply to the next round. Eligibility uses WoW's assigned group role, not class: DPS are always eligible, healers and tanks require their respective option, and players without an assigned role cannot enter. Assign group roles before opening signups.

Exclusions reset each round. Players who leave or change to an ineligible role during signup are removed; roles are checked again before the draw. Leaving or switching group chat type cancels the round. If the selected winner leaves or becomes ineligible during the animation, the round is cancelled instead of declaring them the winner. Reloading the UI discards the active round but preserves the timeout and role settings.

## Verification

From the addon folder, run `lua tests/run.lua`, or use `npx --yes --package fengari-node-cli fengari tests/run.lua` when Lua is not installed. These tests mock WoW APIs and do not require a game client.

In-game smoke test: use a Priest with Power Infusion and one group member; test mixed-case signup, duplicate signup, exclusion and blocked reentry, early start, automatic timeout, the winner announcement, and hiding/reopening the window during a round. Check a full raid, cross-realm names, and instance chat as well.

The live WoW renderer and protected/secret chat behavior require in-game verification. Rounds cannot start while the client reports chat restrictions, and active rounds cancel if chat becomes restricted. Secret chat values, when supplied by the client, are ignored rather than inspected. This addon reads only group chat and roster information; it does not inspect combat logs or cast spells.
