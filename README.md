# Fostbraedr

A family addon for **World of Warcraft: Forever**: a shared chronicle and a rivalry tracker. Each brother runs his own copy, and the copies keep their data in sync.

## Install

Clone this repo into your AddOns folder. The folder **must** be named `Fostbraedr`:

```
World of Warcraft\_forever_\Interface\AddOns\Fostbraedr\
```

Data is stored in `WTF\...\SavedVariables\Fostbraedr.lua` (outside the repo).

## Settings

The **Settings** tab in the window has every option: which loot quality to record, pop-up notices and sounds, pokes, the minimap button, and your brother list. The commands below do the same from chat.

## Brothers and alts

Add **one character per brother** (Settings tab, or `/fost brother add`). When his addon says hello it
sends the list of characters on his account, so his alts link to him automatically. Rivalry and Family
then show one entry per brother, combining all his characters. Each person's name is set by that
person (`/fost name`, or Settings), and defaults to the first name of their first character.

## Commands

- `/fost`: toggle the window (also available from the addon compartment button by the minimap)
- `/fost show | hide | reset`
- `/fost name [Name]`: the name your brothers see for you (covers all your characters)
- `/fost brother add [First Last]`: add a brother's character (with no name, adds your target)
- `/fost brother remove First Last`, `/fost brother list`
- `/fost minimap`: show/hide the minimap button
- `/fost ping [First Last]`: check that your brothers' addons answer
- `/fost sync`: exchange missing chronicle entries now
- `/fost peers`: which brothers are online, and when each was last seen
- `/fost debug`: show comm debug output
- `/fost status [text]`: set your status for the family (no text clears it)
- `/fost poke Name [message]`: poke a brother (his first name is enough)
- `/fost toasts`, `/fost pokes`: turn pop-up notices / receiving pokes on or off
- `/fost stats`: your quests, gold and time so far
- `/fost lootquality N`: lowest item quality recorded as notable loot (default 4 = epic; mounts always)
- `/fost loottest`: diagnostic, prints what the game's Loot History lets addons read
- `/fost version`

## Custom poke sound

Put an `.ogg` file at `Sounds/poke.ogg` in the addon folder and restart WoW; it plays when a brother pokes you.
Without it, the ready-check sound is used.
