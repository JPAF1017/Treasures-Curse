# Sound Effects Roadmap & To-Do List

This document tracks sound FX implementations, audio cleanups, and sound design enhancements across the game. As items are completed, update their checkbox to `[x]`.

---

## 📋 Outstanding Tasks

### 1. Core Player Audio & Fixes
- [x] **1.1 Walking Sound FX Static Noise Fix**
  - **Description**: Walking footstep audio static/hiss has been fixed and no longer requires replacing footstep audio assets.
  - **Files**:
    - [sounds/player/](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/) (`step1.mp3`, `step2.mp3`, `step3.mp3`, `step4.mp3`, `step5.mp3`)
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L68-L74) (`STEP_SOUND_PATHS`)
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1921-L1954) (`_update_footsteps()`, `_play_random_step()`)
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1977-L1986) (`_play_landing_sound()`)
  - **Status**: Completed (noise fixed, replacement no longer needed).

---

### 2. Loot & Pickup Audio
- [x] **2.1 Secondary Chest Opening Sound Effect**
  - **Description**: Added secondary audio layer (`openchest2.mp3`) playing concurrently with the primary lid opening sound (`openchest.mp3`) when the chest is opened.
  - **Files**:
    - [scripts/rooms/chest_interact.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/chest_interact.gd#L107-L135) (`_open_chest()`)
    - [sounds/Interactions/openchest2.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/openchest2.mp3)
  - **Status**: Completed (plays both `openchest.mp3` and `openchest2.mp3` simultaneously via 3D audio players).

- [x] **2.2 Gold Pickup Sound Effect**
  - **Description**: Play a distinct metallic coin clink / gold jingle ([sounds/Interactions/pickupgold.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupgold.mp3)) with pitch randomization when gold is picked up.
  - **Files**:
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1530-L1540) (`_pickup_item_into_hotbar()`, `_play_pickup_sound_for_item()`, `_sync_item_removed()`)
    - [scripts/items/gold.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/gold.gd#L90-L105) (`play_pickup_sound()`)
    - [sounds/Interactions/pickupgold.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupgold.mp3)
  - **Status**: Completed (plays `pickupgold.mp3` with random pitch variation ±8% upon pickup and peer sync).

- [x] **2.3 Gem & Key Pickup Sound Effect**
  - **Description**: Play resonant crystal chime ([sounds/Interactions/pickupgem.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupgem.mp3)) when picking up Gem Keys (1-4) with pitch tints per gem, and skull pickup audio ([sounds/Interactions/pickupskull.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupskull.mp3)) when picking up the Skull Key.
  - **Files**:
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1422-L1445) (`_play_pickup_sound_for_item()`)
    - [scripts/items/gem_key1.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/gem_key1.gd), `gem_key2.gd`, `gem_key3.gd`, `gem_key4.gd` (`play_pickup_sound()`)
    - [scripts/items/skull_key.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/skull_key.gd#L70-L88) (`play_pickup_sound()`)
    - [sounds/Interactions/pickupgem.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupgem.mp3)
    - [sounds/Interactions/pickupskull.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupskull.mp3)
  - **Status**: Completed (plays `pickupgem.mp3` with distinct color pitch shifts for Gem Keys and `pickupskull.mp3` for Skull Key upon pickup and peer sync).

---

### 3. Puzzles & Dungeon Interactions
- [x] **3.1 Puzzle Pedestal & Altar Socketing Audio**
  - **Description**: Play heavy stone placement / key socketing sound ([sounds/Interactions/placekey.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/placekey.mp3)) when placing a skull key or gem key onto a puzzle pedestal.
  - **Files**:
    - [scripts/rooms/skull_puzzle_controller.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/skull_puzzle_controller.gd#L295-L345) (`_play_place_key_sound()`)
    - [scripts/rooms/candle_puzzle_room.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/candle_puzzle_room.gd#L330-L460) (`_play_place_key_sound()`)
    - [sounds/Interactions/placekey.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/placekey.mp3)
  - **Status**: Completed (plays `placekey.mp3` with pitch variation on placing skull and gem keys).

- [x] **3.2 Door & Gate Unlock / Open Audio**
  - **Description**: Door interaction audio ([sounds/Interactions/interact.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/interact.mp3)), dungeon door unlatching, and stone sliding audio ([sounds/Interactions/opening.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/opening.mp3) and [sounds/Interactions/concrete.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/concrete.mp3)) when interacting with or unlocking key doors.
  - **Files**:
    - [scripts/rooms/skull_puzzle_controller.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/skull_puzzle_controller.gd#L370-L435) (`_play_door_interact_sound()`, `_play_door_sound()`, `_play_concrete_sound()`)
    - [scripts/rooms/candle_puzzle_room.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/candle_puzzle_room.gd#L410-L480) (`_play_door_interact_sound()`, `_play_door_sound()`, `_play_concrete_sound()`)
    - [sounds/Interactions/interact.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/interact.mp3)
    - [sounds/Interactions/opening.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/opening.mp3)
    - [sounds/Interactions/concrete.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/concrete.mp3)
  - **Status**: Completed (plays `interact.mp3` upon interacting with doors; door open/unlatch audio already implemented).

---

### 4. Player & Environmental Ambience
- [ ] **4.1 Low Health / Stamina Heartbeat & Breathing**
  - **Description**: Muffled rapid heartbeat and strained breathing sound cues when health falls below 25% or stamina is fully depleted.
  - **Files**:
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1031-L1050)
  - **Priority**: Low

---

## 🔊 Existing Sound FX Reference
- **Chest Open**: Wooden lid creaking open ([sounds/Interactions/openchest.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/openchest.mp3)) layered with secondary open audio ([sounds/Interactions/openchest2.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/openchest2.mp3)).
- **Gold Pickup**: Dynamic metallic coin clink with pitch modulation ([sounds/Interactions/pickupgold.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupgold.mp3)).
- **Gem Key Pickup**: Resonant arcane crystal chime with pitch tints per gem ([sounds/Interactions/pickupgem.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupgem.mp3)).
- **Skull Key Pickup**: Arcane skull pickup sound ([sounds/Interactions/pickupskull.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/pickupskull.mp3)).
- **Key & Skull Pedestal Socketing**: Stone click and key socketing audio ([sounds/Interactions/placekey.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/placekey.mp3)) when placing gem or skull keys onto puzzle pedestals.
- **Door & Gate Interaction & Opening**: Door interaction audio ([sounds/Interactions/interact.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/interact.mp3)), dungeon door unlatching, and stone sliding audio ([sounds/Interactions/opening.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/opening.mp3) and [sounds/Interactions/concrete.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/concrete.mp3)).
- **Weapon Swing**: Light whoosh sound on swinging melee weapons ([sounds/player/swing.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/swing.mp3)).
- **Combat Impacts**: Blunt, sharp, and solid impact audio cues ([sounds/Interactions/hit_blunt.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/hit_blunt.mp3), `hit_sharp.mp3`, `hit_solid.mp3`).
- **Player Damage & Death**: Death sound cue ([sounds/player/death_sound.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/death_sound.mp3)).
- **Enemy Chases & Screams**: Chase tracks and monster cues ([sounds/player/chase1.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/chase1.mp3), `chase3.mp3`, enemy sound folders).
- **Hard Landing**: Step sound triggered with volume boost on fall impact ([scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1977-L1986)).
