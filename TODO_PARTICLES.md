# Particle Effects Roadmap & To-Do List

This document tracks particle FX implementations and enhancements across the game. As items are completed, update their checkbox to `[x]`.

---

## 📋 Outstanding Tasks

### 1. Loot & Puzzle Interactions
- [x] **1.1 Chest Opening Burst**
  - **Description**: Emit golden sparkling dust and ancient dungeon dust escaping from the chest seams as the lid opens.
  - **Files**: [scripts/rooms/chest_interact.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/chest_interact.gd#L106-L145) (`_open_chest()`, `_spawn_gold()`), [scripts/items/ChestOpenParticleEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/ChestOpenParticleEffect.gd).
  - **Priority**: High

- [x] **1.2 Gold & Key Pickup Sparkles**
  - **Description**: A 3D burst of twinkling golden stars/sparks when picking up coins, gem keys, or skull keys.
  - **Files**: [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1450-L1480) (`pick_up_into_hotbar()`), [scripts/items/gold.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/gold.gd), [scripts/items/PickupSparklesEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/PickupSparklesEffect.gd).
  - **Priority**: Medium

- [x] **1.3 Puzzle Pedestal Socketing (Cursed Energy Pulse)**
  - **Description**: An ethereal cyan or purple rune flash and expanding ring of mist when placing a skull or key into its pedestal or completing an altar.
  - **Files**: [scripts/rooms/skull_puzzle_controller.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/skull_puzzle_controller.gd), [scripts/rooms/candle_puzzle_room.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/candle_puzzle_room.gd), [scripts/items/PedestalSocketEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/PedestalSocketEffect.gd).
  - **Priority**: Medium

---

### 2. Player Movement & Locomotion
- [x] **2.1 Hard Landing, Jump & Sprint Dust**
  - **Description**: Radial ring of stone dust puffing outward at the player's feet upon landing on the floor after a fall or jump, plus backward dust kick-ups while sprinting.
  - **Files**: [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L670-L685) (`_physics_process()`), [scripts/items/LandingDustEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/LandingDustEffect.gd).
  - **Priority**: High

- [ ] **2.2 Exhaustion / Heavy Breathing (Low Stamina)**
  - **Description**: Cold breath / condensation puff in front of the camera and subtle sweat/fatigue indicators when stamina hits 0.
  - **Files**: [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1031-L1045) (`_update_stamina_ui()`).
  - **Priority**: Low

- [ ] **2.3 Torch Embers Trail**
  - **Description**: Small drifting orange embers trailing backward in world space when sprinting while holding a burning torch.
  - **Files**: [scripts/items/torch.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/torch.gd), [assets/room assets/fire_particle.tscn](file:///mnt/Games/Codes/Godot/Treasures-Curse/assets/room%20assets/fire_particle.tscn).
  - **Priority**: Medium

---

### 3. Combat & Weapons
- [ ] **3.1 Melee Weapon Swing Trail**
  - **Description**: A translucent swoosh ribbon / wind slash arc following the blade or bat tip during attacks.
  - **Files**: [scripts/items/MeleeItemSharedComponent.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/MeleeItemSharedComponent.gd), [scripts/items/sword.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/sword.gd), [scripts/items/bat.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/bat.gd), [scripts/items/axe.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/axe.gd), [scripts/items/shovel.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/shovel.gd).
  - **Priority**: High

- [ ] **3.2 Enemy Defeat & Dissolution**
  - **Description**: A burst of dark cursed shadow miasma or dissolving soul embers when an NPC reaches 0 health.
  - **Files**: [scripts/npc/EnemyDeathLingerComponent.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/npc/EnemyDeathLingerComponent.gd), NPC scripts (`charger.gd`, `statue.gd`, `knight.gd`, etc.).
  - **Priority**: High

- [ ] **3.3 Heavy Knockback Shockwave**
  - **Description**: A brief radial shockwave distortion ring at the contact point when landing high-knockback strikes (bat, shovel).
  - **Files**: [scripts/npc/NPCKnockbackComponent.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/npc/NPCKnockbackComponent.gd).
  - **Priority**: Medium

---

### 4. Enemy Behaviors
- [ ] **4.1 Charger Wall Collision**
  - **Description**: Shower of crumbled rock chips and heavy impact dust when the Charger misses and collides with a dungeon wall/pillar.
  - **Files**: [scripts/npc/charger.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/npc/charger.gd).
  - **Priority**: Medium

- [ ] **4.2 Statue Awakening / Movement Crumble**
  - **Description**: Small stone pebbles and dust crumbling off the statue whenever it transitions from frozen stone to active pursuit in the dark.
  - **Files**: [scripts/npc/statue.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/npc/statue.gd).
  - **Priority**: Low

---

### 5. Player Defeat
- [ ] **5.1 Cursed Death Eruption**
  - **Description**: Explosive eruption of dark shadows, curse runes, or soul particles from the player's body upon dying before transitioning to the death/spectator screen.
  - **Files**: [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd#L1595-L1600) (`apply_damage()`).
  - **Priority**: Medium

---

## ✅ Completed Effects
- [x] **Blood Splatter**: 3D crimson sphere particles burst on striking living targets ([scripts/items/BloodSplatterEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/BloodSplatterEffect.gd)).
- [x] **Surface Sparks**: 3D deflected spark particles on hitting solid dungeon walls/surfaces ([scripts/items/SparksEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/SparksEffect.gd)).
- [x] **Torch Fire & Smoke**: Equipped/dropped torch GPUParticles3D emitters ([assets/room assets/fire_particle.tscn](file:///mnt/Games/Codes/Godot/Treasures-Curse/assets/room%20assets/fire_particle.tscn)).
- [x] **Smoke Bomb**: Concentric expanding/dissolving shader spheres on impact ([assets/items/smoke_effect.tscn](file:///mnt/Games/Codes/Godot/Treasures-Curse/assets/items/smoke_effect.tscn)).
- [x] **Healing Green Crosses**: 2D screen-space rising and fading green cross particles on consuming healing potions ([scripts/items/HealParticleEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/HealParticleEffect.gd)).
- [x] **Damage & Heal Screen Tints**: Instant pop and smooth quad ease-out red screen tint on taking damage and green screen tint on healing ([scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd)).
- [x] **Chest Opening Burst**: Ancient dungeon seam dust and golden sparkling dust burst upon opening chests ([scripts/items/ChestOpenParticleEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/ChestOpenParticleEffect.gd), [scripts/rooms/chest_interact.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/chest_interact.gd)).
- [x] **Gold & Key Pickup Sparkles**: 3D burst of twinkling radiant star particles and floating fairy dust sparks themed per item on picking up gold, gem keys, or skull keys ([scripts/items/PickupSparklesEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/PickupSparklesEffect.gd), [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd), [scripts/items/gold.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/gold.gd)).
- [x] **Puzzle Pedestal Socketing & Altar Pulse**: Ethereal cyan and purple arcane rune flashes, expanding horizontal mist rings, and drifting soul embers on socketing skulls/gem keys and completing altar puzzles ([scripts/items/PedestalSocketEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/PedestalSocketEffect.gd), [scripts/rooms/skull_puzzle_controller.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/skull_puzzle_controller.gd), [scripts/rooms/candle_puzzle_room.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/rooms/candle_puzzle_room.gd)).
- [x] **Hard Landing, Jump & Sprint Dust**: Radial expanding ring of dungeon stone dust, central ground puff, and tumbling 3D stone debris chips dynamically scaling between jump takeoff, soft landings, and high-velocity hard landings, plus alternating backward-kicking dust puffs and pebbles while sprinting ([scripts/items/LandingDustEffect.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/items/LandingDustEffect.gd), [scripts/player.gd](file:///mnt/Games/Codes/Godot/Treasures-Curse/scripts/player.gd)).


