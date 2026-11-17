# Fostbraedr

A family addon for **World of Warcraft: Forever**: a shared chronicle and a rivalry tracker. Each brother runs his own copy, and the copies keep their data in sync.

## Install (for players)

1. Open **https://github.com/alxric/fostbraedr/releases/latest** and download `Fostbraedr-x.y.z-forever.zip`.
2. Unpack it into `World of Warcraft\_forever_\Interface\AddOns\`, so you get
   `...\AddOns\Fostbraedr\Fostbraedr_Forever.toc`. Replace the old `Fostbraedr` folder when updating.
3. Restart WoW.

When a brother has a newer version, the addon tells you in game.

**Automatic updates:** install [WowUp](https://wowup.io) (2.24.1 or newer supports Forever), choose
**Get Addons → Install from URL**, paste `https://github.com/alxric/fostbraedr`, and turn on auto-update for
Fostbraedr. WowUp then installs each new release by itself.

## Install (for development)

Clone this repo into your AddOns folder. The folder **must** be named `Fostbraedr`:

```
git clone https://github.com/alxric/fostbraedr.git Fostbraedr
```

Data is stored in `WTF\...\SavedVariables\Fostbraedr.lua` (outside the repo).

## Releasing

Bump `## Version:` in `Fostbraedr_Forever.toc`, commit, then tag that commit with the same version and push
the tag, e.g. `git tag v0.2.0 && git push origin v0.2.0`. GitHub Actions builds the zip (without `tests/`)
and publishes the release. It refuses to release if the tag and the `.toc` version differ.

## Settings

The **Settings** tab in the window has every option: which loot quality to record, pop-up notices and sounds, pokes, the minimap button, and your brother list. The commands below do the same from chat.

## First names on party and raid frames

The **Frames** tab can show only first names ("Thorgrim" instead of "Thorgrim Stormfjord") on Blizzard's
raid-style (compact) party and raid frames and on the classic party frames, for all surnames or only your
family's. It only changes the displayed text; clicking still targets and whispers the full name.

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
- `/fost dump Name[.key]`, `/fost globals text`: diagnostics, show the structure of other addons' data tables
- `/fost version`

## Custom poke sound

Put an `.ogg` file at `Sounds/poke.ogg` in the addon folder and restart WoW; it plays when a brother pokes you.
Without it, the ready-check sound is used.
