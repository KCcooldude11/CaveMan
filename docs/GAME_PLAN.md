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
- First-person controller, grey-box shop + village + dungeon gate
- 3 crafting stations, 14 recipes, 10 materials, 5 dungeons, 4 classes, 6 upgrades, all in JSON
- Timing minigame decides item quality
- Adventurer NPCs walk in, queue, haggle, walk off to the dungeon
- Overnight dungeon simulation with leveling, loot, gear breakage, death
- Renown tiers, day/night clock, save/load, HUD with goal hints
- Automated logic tests + a 30-day economy simulation

### Phase 1: Make the loop *feel* good (2–4 weeks)
**Goal: you want to play "one more day" with grey boxes.**
- Playtest 10+ in-game days yourself. Write down every moment you were bored or confused.
- Tune numbers in `data/*.json` (prices, power, difficulty) and the constants listed in section 6.
- Add **sound** (biggest bang for buck): hammer clangs on each strike, coin jingle on sale, door bell, night-report fanfare. Free sources: Kenney audio packs, freesound.org, Sonniss GDC bundles.
- Juice: screen shake on a perfect strike, item pops out of the forge, gold counter ticks up.
- Display shelves: crafted items appear physically on racks in the shop.

### Phase 2: Art pass (1–3 weeks, see section 4)
- Pick ONE asset family and replace grey boxes via `assets/models/<key>.glb`.
- Add animations: adventurers walking/idling, your hands hammering.
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

## 4. Getting 3D art without modeling it yourself

Schedule 1 is low-poly and stylized, and that style is very achievable with ready-made packs. The most important rule:
**pick ONE art family and stick to it.** Mixed styles look worse than grey boxes.

### Recommended: free, high quality, commercial-use OK (CC0)
| Source | What to grab | Why |
|---|---|---|
| **KayKit** (Kay Lousberg, kaylousberg.itch.io) | *Adventurers* character pack, *Dungeon Remastered*, *Furniture Bits*, *Medieval Hexagon* | Rigged & **animated** adventurers (knight, barbarian, mage, rogue). It's almost exactly this game's cast. Ships as .glb/.gltf that drop straight into Godot. **Best starting point.** |
| **Quaternius** (quaternius.com) | *Ultimate RPG Pack*, *Medieval Village MegaKit*, *Ultimate Animated Character Pack* | Huge, consistent, animated |
| **Kenney** (kenney.nl) | *Fantasy Town Kit*, *Furniture Kit*, *Survival Kit*, UI and audio packs | Very clean, very consistent |
| **Poly Pizza** (poly.pizza) | Search engine across thousands of CC0/CC-BY low-poly models | Good for filling one-off gaps |

### Paid (if you outgrow the free packs)
- **Synty POLYGON** packs (*Fantasy Kingdom*, *Dungeon*, *Fantasy Characters*): the most "commercial indie" look. Read the license for non-Unity engines before buying.

### Animations
- **Mixamo** (free, Adobe account): upload any humanoid model, auto-rig it, download walk/idle/hammering animations.
- KayKit and Quaternius characters already include animation sets.

### AI 3D generation (for props)
- **Meshy**, **Tripo**, **Hyper3D Rodin** turn text or images into 3D models. They work well for **props** (a specific sword, an anvil, a gem) and less well for animated characters. Check each tool's commercial license for your plan tier. Run outputs through Blender's *Decimate* modifier to cut the polygon count, and match the colors to your main pack.

### Hiring
- For a few "hero" assets later (your shop building, a signature anvil): Fiverr, ArtStation, r/gameDevClassifieds. Roughly $30–$300 per prop depending on complexity.

### How art plugs into this project (no code changes)
Drop a `.glb` named after its key into `assets/models/` and it replaces the grey box automatically:

| Key | Replaces |
|---|---|
| `forge`, `workbench`, `jeweler` | crafting stations |
| `counter`, `bed`, `lectern`, `supply_board`, `ledger_board` | furniture |
| `adventurer_warrior`, `adventurer_ranger`, `adventurer_mage`, `adventurer_rogue` | NPC bodies (one per class) |
| `house`, `dungeon_gate` | village props |

(Models should face **-Z**, have their origin at the **bottom center**, and be about real-world size: 1 unit = 1 meter.)

---

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
| `data/dungeons.json` | `difficulty`, `gold`, `loot`, `renown` | How hard / rewarding each dungeon is |
| `data/renown_tiers.json` | `min`, `visitors`, `max_level` | Pace of fame, daily customers, hero levels |
| `data/upgrades.json` | `costs`, `renown` | Upgrade prices and gates |
| `time_manager.gd` | `minutes_per_second`, `PAUSE_IN_MENUS` | Day length; whether menus freeze time |
| `adventurer_manager.gd` | `RENOWN_PER_WIN`, `FIRST_CLEAR_BONUS`, death/break chances in `_run()` | Progression speed and risk |
| `forge_minigame.gd` | `configure()` | Minigame difficulty |
| `game_state.gd` | `START_GOLD`, starting materials in `reset()` | Opening minutes |

`tests/test_runner.gd` runs a 30-day bot simulation and prints gold and renown every 5 days. Re-run it after balance changes to see the progression curve.
Current curve: ~10 renown by day 5, ~30 by day 15, ~50–100 by day 30.
