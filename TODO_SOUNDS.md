# Sound Effects Roadmap & To-Do List

This document tracks sound FX implementations, audio cleanups, and sound design enhancements across the game. As items are completed, update their checkbox to `[x]`.

---

## 📋 Outstanding Tasks

### 1. Core Player Audio & Fixes
- [ ] **1.1 Replace Walking Sound FX (Static Noise Fix)**
  - **Description**: Replace the existing footstep audio files (`step1.mp3` through `step5.mp3`) with clean, static-free dungeon stone footstep sound effects. The current clips have audible background static/hiss when triggered during movement and landings.
  - **Files**:
    - [sounds/player/](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/) (`step1.mp3`, `step2.mp3`, `step3.mp3`, `step4.mp3`, `step5.mp3`)
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L68-L74) (`STEP_SOUND_PATHS`)
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1921-L1954) (`_update_footsteps()`, `_play_random_step()`)
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1977-L1986) (`_play_landing_sound()`)
  - **Priority**: High
  - **Implementation Notes**: Ensure new audio samples have trimmed zero-crossings, consistent normalized volume levels, no white noise floor, and varied pitch/weight for natural footsteps.

---

### 2. Loot & Pickup Audio
- [ ] **2.1 Secondary Chest Opening Sound Effect**
  - **Description**: Add a secondary audio layer when opening dungeon chests. Currently, only the wooden lid creak ([openchest.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/openchest.mp3)) plays. Layer in an additional sound effect such as a magical treasure shimmer, unlocking latch click, or an ancient treasure chime as the lid swings open and gold spawns.
  - **Files**:
    - [scripts/rooms/chest_interact.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/chest_interact.gd#L107-L133) (`_open_chest()`)
    - [sounds/Interactions/](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/)
  - **Priority**: High
  - **Implementation Notes**: Can trigger concurrently or slightly staggered with `openchest.mp3` via `AudioStreamPlayer3D` positioned at the chest center or interior spawn point.

- [ ] **2.2 Gold Pickup Sound Effect**
  - **Description**: Play a distinct, satisfying metallic coin clink / gold jingle when the player picks up gold piles or coins into their hotbar. Currently, only particle sparkles spawn without audio feedback.
  - **Files**:
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1501-L1525) (`_pickup_item_into_hotbar()`)
    - [scripts/items/gold.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/gold.gd)
    - [sounds/Interactions/](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/)
  - **Priority**: High
  - **Implementation Notes**: Add random pitch shifting (e.g. ±5-10% via `AudioStreamRandomizer` or playback pitch offset) so collecting multiple coins in quick succession sounds dynamic and punchy.

- [ ] **2.3 Gem & Key Pickup Sound Effect**
  - **Description**: Play a resonant arcane crystal chime / mystical shimmer sound when picking up gem keys (GemKey 1-4) or skull keys. Differentiates rare key treasures from standard gold pickups.
  - **Files**:
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1483-L1510) (`_pickup_item_into_hotbar()`)
    - [scripts/items/gem_key1.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/gem_key1.gd), `gem_key2.gd`, `gem_key3.gd`, `gem_key4.gd`
    - [scripts/items/skull_key.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/skull_key.gd)
    - [sounds/Interactions/](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/)
  - **Priority**: High
  - **Implementation Notes**: Can share or modulate base crystal chime tones with distinct pitch tints matching the gem color/type.

---

### 3. Puzzles & Dungeon Interactions
- [ ] **3.1 Puzzle Pedestal & Altar Socketing Audio**
  - **Description**: Play a heavy stone click or ethereal arcane hum when placing a skull or gem key into a puzzle pedestal or completing an altar challenge.
  - **Files**:
    - [scripts/rooms/skull_puzzle_controller.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/skull_puzzle_controller.gd)
    - [scripts/rooms/candle_puzzle_room.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/candle_puzzle_room.gd)
  - **Priority**: Medium

- [ ] **3.2 Door & Gate Unlock / Open Audio**
  - **Description**: Heavy dungeon door unlatching, stone grinding, or metal gate sliding audio when unlocking key doors.
  - **Files**:
    - [scripts/rooms/](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/)
  - **Priority**: Medium

---

### 4. Player & Environmental Ambience
- [ ] **4.1 Low Health / Stamina Heartbeat & Breathing**
  - **Description**: Muffled rapid heartbeat and strained breathing sound cues when health falls below 25% or stamina is fully depleted.
  - **Files**:
    - [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1031-L1050)
  - **Priority**: Low

---

## 🔊 Existing Sound FX Reference
- **Chest Open (Base)**: Wooden lid creaking open ([sounds/Interactions/openchest.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/openchest.mp3)).
- **Weapon Swing**: Light whoosh sound on swinging melee weapons ([sounds/player/swing.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/swing.mp3)).
- **Combat Impacts**: Blunt, sharp, and solid impact audio cues ([sounds/Interactions/hit_blunt.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/Interactions/hit_blunt.mp3), `hit_sharp.mp3`, `hit_solid.mp3`).
- **Player Damage & Death**: Death sound cue ([sounds/player/death_sound.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/death_sound.mp3)).
- **Enemy Chases & Screams**: Chase tracks and monster cues ([sounds/player/chase1.mp3](file:///mnt/Games/Codes/Godot/Treasures-Curse/sounds/player/chase1.mp3), `chase3.mp3`, enemy sound folders).
- **Hard Landing**: Step sound triggered with volume boost on fall impact ([scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1977-L1986)).
