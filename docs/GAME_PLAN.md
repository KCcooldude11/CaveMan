# Forge & Fortune: Game Plan

*Working title. You're the village crafter. The "heroes" are NPCs, and you're the one who equips them.*

---

## 1. The pitch in one paragraph

Adventurers come to your village to dive into dungeons. You don't fight. You **forge their swords, stitch their armor, and set their gems**. Every piece you sell goes into the dungeon with them. When they win, *your* name spreads. When they die wearing your chainmail, people talk about that too. They come back richer and stronger, carrying rare monster materials only they can get. You buy those, craft better gear, and sell it to them again. Over time you go from an **Unknown Tinkerer** in a shack to the **Legendary Craftsman** every hero in the realm wants to buy from.

---

## 2. Why Schedule 1 is addictive (and how we copy the *structure*, not the theme)

| Schedule 1 hook | Why it works | Our version |
|---|---|---|
| **Tight produce → sell → reinvest loop** | Every action pays off within minutes | Craft (minigame) → haggle at the counter → buy upgrades/materials |
| **Product quality matters** | Skill and investment both show up as numbers | Crude / Common / Fine / Masterwork from the forging minigame + station upgrades |
| **Named customers with needs & budgets** | You build relationships and learn who pays well | Adventurers have names, classes, preferred gear tags, purses that grow |
| **Customers' demand scales with you** | Bigger numbers keep coming | Adventurers level up in dungeons, earn more gold and want better gear |
| **Constant unlocks** | There's always a "next thing" within reach | Renown tiers unlock recipes, stations, more visitors, harder dungeons |
| **Employees / automation** | Turns grind into management; you feel like a boss | Apprentices craft overnight (more hires later: smelter, salesclerk) |
| **The day cycle and "one more day"** | Natural session breaks that make you *want* to keep going | The **Night Report**: you sleep, then read what your heroes did with your gear |
| **Risk** | Stakes make wins feel earned | Heroes can die. Your gear can break. Renown can drop. |

**Our unique twist** is a *co-dependency loop*: you need adventurers' **dungeon loot** (troll hide, ember crystals, mithril) to craft top-tier gear, and they need your top-tier gear to survive the dungeons that drop it. Equipping a promising Lv 2 rogue and watching them become a Lv 12 legend wearing your Masterwork blade is the emotional core. Lean into it: named heroes, memorials for the fallen, heroes who return to thank you.

### The core loop (what's built now)

```
   ┌──────────── buy materials (Supply Board) ◄────────────┐
   │                                                       │
   ▼                                                       │
 CRAFT at Forge / Workbench / Jeweler  ── minigame → quality│
   │                                                       │
   ▼                                                       │
 SELL at the counter (haggle with named adventurers)        │
   │                                                       │
   ▼                                                       │
 SLEEP → NIGHT REPORT: heroes delve, level up, die,         │
         loot, gear breaks, YOU gain renown                 │
   │                                                       │
   ▼                                                       │
 REINVEST: upgrades, new recipes (renown), loot materials ──┘
```

---

## 3. Development roadmap

Work in **small vertical slices**. Each phase ends with something playable. Don't touch art until the loop is fun with grey boxes. That's how most successful indie games (Schedule 1 included) get made.

### Phase 0: Framework ✅ *(this commit)*
- Third-person controller with 2D pixel sprites in a 3D world (EthrA / HD-2D style), pixel-textured shop + village + dungeon gate
- 3 crafting stations, 14 recipes, 10 materials, 5 dungeons, 4 classes, 6 upgrades, all in JSON
- Timing minigame decides item quality
- Adventurer NPCs walk in, queue, haggle, walk off to the dungeon
- Overnight dungeon simulation with leveling, loot, gear breakage, death
- Renown tiers, day/night clock, save/load, HUD with goal hints
- Automated logic tests + a 30-day economy simulation

### Minigame design notes
- **Forge / Workbench: timing bar.** Three hammer strikes, each scored on how close it lands to the gold zone's center.
- **Jeweler: gem-setting dial**, inspired by the *Starcatcher* Minecraft fishing mod. A needle sweeps around a ring. Hit the glowing slots to raise a progress bar that slowly drains, and misses cost progress. Each slot jumps elsewhere when hit. Slot types:
  - *thin*: worth more
  - *flip*: reverses the needle
  - *fading*: vanishes unless hit in time
  - *drifting*: slides around the ring
  - *treasure*: fills a "Flawless" meter worth +1 quality

  Harder recipes get faster needles and nastier slots, and bench upgrades widen the slots. Everything is tunable in `data/dial_minigame.json`.
- Idea for later: give each station its own minigame (e.g. a bellows rhythm game for the forge), and let rare materials add their own special slots, the way Starcatcher gives each fish its own.

### Phase 0.5: Village & forecast ✅
- **Dungeon forecast** (notice board): each day 1–2 events (*swarm*: double loot plus a bounty; *invasion*: a different enemy moves in; *vein*: extra rare material). You can see 3 days ahead, or 6 with tavern rumors.
- **Enemies with weaknesses and resistances** (`data/enemies.json`). Gear that exploits a weakness gets +30% power, and a resisted weapon gets -30%. Heroes plan their dungeon each morning, tell you at the counter, and pay more for the right counter.
- **Commissions** from villagers, often asking for counters to an upcoming threat.
- **Points of interest**: the tavern (rumors, where heroes are heading), Zara's wagon (rare materials every 3rd day), the old mine and the woodcutter's grove (free daily gathering).

This turns "craft whatever is cheapest" into planning a few days ahead: *"Skeletons swarm the crypt in two days, so I'll forge maces now and buy the bone dust they bring back to make Bone Wards."*

### Phase 1: Make the loop *feel* good (2–4 weeks)
**Goal: you want to play "one more day" with grey boxes.**
- Playtest 10+ in-game days yourself. Write down every moment you were bored or confused.
- Tune numbers in `data/*.json` (prices, power, difficulty) and the constants listed in section 6.
- Add **sound** (biggest bang for buck): hammer clangs on each strike, coin jingle on sale, door bell, night-report fanfare. Free sources: Kenney audio packs, freesound.org, Sonniss GDC bundles.
- Juice: screen shake on a perfect strike, item pops out of the forge, gold counter ticks up.
- Display shelves: crafted items appear physically on racks in the shop.

### Phase 2: Art pass (1–3 weeks, see section 4)
- Lock a palette and replace the generated sprites with real pixel art (pack, artist or Aseprite).
- Add sprite animations: hammering at the forge, adventurers cheering or showing off new gear.
- Pixel-textured furniture and buildings, plus extra billboard props (barrels, banners, item racks showing your stock).
- Lighting pass: warm forge glow, lanterns at night.

### Phase 3: Content & depth (ongoing)
- **Commission board**: heroes post specific requests ("Fine axe, 150g, by Day 12") for bonus renown.
- **Enchanting / gem socketing** with dungeon materials.
- **Hero relationships**: loyalty meter. Loyal heroes give discounts on loot and tell others about you.
- **Parties**: heroes team up. A party geared fully by you earns bonus renown.
- **Events**: festivals, a dragon attack (everyone needs fire-resistant armor *now*), a rival smith opening across the road.
- **More stations**: Alchemy table (potions, a consumable that's always in demand), Tannery, Smelter (turn ore into ingots).

### Phase 4: Management layer (the Schedule 1 "employees" moment)
- Hire **apprentices** per station (already stubbed), a **shopkeeper** who sells while you craft, a **courier** who restocks materials.
- Expand the building: buy the lot next door, build a second forge.
- Decorations that raise prices (Schedule 1's property upgrades).

### Phase 5: Polish & ship
- Main menu, save slots, settings (sensitivity, volume, keybinds)
- Proper tutorial (the goal hint system is a start)
- **Put up a Steam page early** (even in Phase 2) to collect wishlists
- Steam Next Fest demo

---

## 4. Art direction: 2D pixel art in a 3D world (EthrA / HD-2D style)

The game uses **2D pixel-art sprites standing in a simple 3D world**, the approach of *EthrA*, *Octopath Traveler* ("HD-2D"), *Paper Mario* and *Don't Starve*. It's much cheaper to produce than full 3D: no modeling, rigging or 3D animation. Characters are flipbooks of small PNGs, and buildings are just boxes with pixel textures.

### How it works in the engine
| Piece | Technique | Code |
|---|---|---|
| **Characters** (you, adventurers, later monsters & pets) | `AnimatedSprite3D`. A flat sprite that always turns to face the camera (Y-axis billboard), with nearest-neighbour filtering for crisp pixels. It casts real shadows. | `scripts/world/pixel_character.gd` |
| **Facing** | Each sheet has *front / back / side* rows. The game picks the row from the direction the character moves **relative to the camera**, and mirrors the side row for left. | `PixelCharacter.face()` |
| **Foliage & small props** | `Sprite3D` billboards (trees, bushes, later crates, banners, item drops) | `Visuals.billboard()` |
| **Buildings, floors, furniture** | Simple 3D boxes with 32×32 pixel textures, mapped in world space | `Visuals.tex_mat()` |
| **One consistent pixel size** | Everything uses **16 pixels per meter**, sprites and textures alike. This is the single most important rule, because mismatched pixel sizes ("mixels") are what makes 2D+3D look cheap. | `PIXELS_PER_METER`, `TILE_METERS` |
| **Camera** | Third-person and slightly top-down (35°), with a narrow 38° FOV for the miniature-diorama feel. Mouse orbits, wheel zooms. | `scripts/world/player.gd` |
| **Seeing inside** | Walls between the camera and you hide automatically, and the shop roof disappears when you walk in | `player._update_cutaways()` |
| **HD-2D polish** | Bloom, background depth-of-field blur, warm point lights | `main._build_environment()` |
| **Optional retro filter** | **F2** snaps the 3D view to chunky 2×/3×/4× pixels (the UI stays sharp) | `scripts/world/pixel_filter.gd` |

### Sprite sheet format (what an artist delivers)
`assets/sprites/<name>.png`, with **32×40 px frames**:

| | col 0 | col 1 | col 2 | col 3 | col 4 | col 5 |
|---|---|---|---|---|---|---|
| **row 0: front** | idle | idle | walk | walk | walk | walk |
| **row 1: back**  | idle | idle | walk | walk | walk | walk |
| **row 2: side (facing right)** | idle | idle | walk | walk | walk | walk |

The feet sit on the bottom row of each frame, and a character is about 28–32 px tall. Adventurer sheets are named after their class (`warrior.png`, `mage.png`...). Your character is `smith.png`. Overwrite a PNG and the game uses it; no code changes. Later we can add rows for *attack/hammering* and *carry* animations.

The current sprites and textures are **programmer art** generated by `tools/gen_pixel_assets.py`. They're consistent enough to build the game on, and meant to be replaced.

### Where to get the art
1. **Pixel-art asset packs (cheapest, fastest).** itch.io has thousands of 2D RPG character and tileset packs (search "top-down RPG characters 4 directions", "fantasy tileset 32x32"). Good creators to look at: *Seliel the Shaper* (Mana Seed), *Pixel Frog*, *Cup Nooble* (Sprout Lands), *LimeZu*, *Szadi art*. Many cost $5–$30 and allow commercial use. Check each license. You may need to re-arrange frames into the sheet layout above (or adapt `pixel_character.gd` to the pack's layout).
2. **Make or edit it yourself in Aseprite** (~$20, the standard pixel-art editor). Pixel art at 32×40 is far more approachable than 3D modeling. Editing a pack's base character into your own smith or a new class is a realistic skill to learn.
3. **Hire a pixel artist.** A full 4-direction walk/idle sheet typically runs ~$40–$200 per character on Fiverr, r/gameDevClassifieds or itch.io's "pixel art commissions" community. Order one character first to lock the style, then order the rest from the same artist.
4. **AI pixel-art tools** (e.g. PixelLab, Retro Diffusion) can draft characters and directional views quickly. Expect to clean up the output in Aseprite, and check the tool's commercial-use terms.
5. **3D environment pieces.** Keep them simple: boxes and slopes with pixel textures. *Crocotile 3D* (~$25) is built for exactly this, letting you "paint" pixel tiles onto low-poly 3D shapes, and it exports .glb/.obj that drop into `assets/models/`. Free CC0 tilesets from Kenney work as textures too.

**Style tip:** decide your palette early (Lospec.com has curated palettes) and use it for every sprite and texture. A shared palette is what makes assets from different sources look like one game.

### How art plugs into this project (no code changes)
- **Sprites:** `assets/sprites/<name>.png` (the sheet layout above)
- **Textures:** `assets/textures/<name>.png`, 32×32 tiles covering 2 m: `wood_floor`, `plaster`, `stone`, `grass`, `dirt`, `roof`, `dark_wood`, `iron`
- **3D models** (optional, e.g. from Crocotile 3D): drop a `.glb` named after its key into `assets/models/` and it replaces the matching grey box:

| Key | Replaces |
|---|---|
| `forge`, `workbench`, `jeweler` | crafting stations |
| `counter`, `bed`, `lectern`, `supply_board`, `ledger_board` | furniture |
| `house`, `dungeon_gate` | village props |

(Models should face **-Z**, have their origin at the **bottom center**, and use 1 unit = 1 meter.)

## 5. Learning path (no prior game dev needed)

1. **Godot basics (1 weekend):** official docs → *Getting Started → Your first 3D game*. Brackeys' Godot tutorials on YouTube. GDQuest's free *Learn GDScript From Zero* app.
2. **Read this project's code** in this order: `data/*.json` → `game_state.gd` → `adventurer_manager.gd` → `main.gd` → `ui/craft_menu.gd`. Every file has a header comment explaining its job.
3. **Change one number, play, observe.** Then add one recipe to `recipes.json`. Then add one dungeon. You'll be surprised how far data editing goes.
4. When you want a feature, ask Claude in small steps: *"add a potion table station that works like the jeweler"* is much better than *"add alchemy"*.

---

## 6. Tuning knobs (start here when balancing)

| Where | Knob | Effect |
|---|---|---|
| `data/recipes.json` | `power`, `value`, `renown`, `inputs` | Item strength, price, unlock point, cost |
| `data/dungeons.json` | `difficulty`, `gold`, `enemy`, `renown` | How hard / rewarding each dungeon is |
| `data/enemies.json` | `weak`, `resist`, `loot` | Which gear counters what, and what heroes bring back |
| `data/village.json` | forecast kinds/weights, commissions, merchant, tavern, gathering | Village activities and how often things happen |
| `data/renown_tiers.json` | `min`, `visitors`, `max_level` | Pace of fame, daily customers, hero levels |
| `data/upgrades.json` | `costs`, `renown` | Upgrade prices and gates |
| `time_manager.gd` | `minutes_per_second`, `PAUSE_IN_MENUS` | Day length; whether menus freeze time |
| `adventurer_manager.gd` | `RENOWN_PER_WIN`, `FIRST_CLEAR_BONUS`, death/break chances in `_run()` | Progression speed and risk |
| `forge_minigame.gd` | `configure()` | Forge/Workbench timing-bar difficulty |
| `data/dial_minigame.json` | `difficulties` (hp, speed, penalty, decay, slots), `spot_types` | Jeweler's gem-setting dial (Starcatcher-style) |
| `craft_menu.gd` | `STATION_MINIGAMES` | Which minigame each station uses |
| `game_state.gd` | `START_GOLD`, starting materials in `reset()` | Opening minutes |

`tests/test_runner.gd` runs a 30-day bot simulation and prints gold and renown every 5 days. Re-run it after balance changes to see the progression curve.
Current curve for a bot that ignores the forecast and commissions: ~10 renown by day 5, ~25 by day 15, ~50–80 by day 30. A player who uses counters and commissions should land higher.
