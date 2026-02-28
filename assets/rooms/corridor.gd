@tool
extends DungeonRoom3D

# Chance for torches to appear (0.0 = never, 1.0 = always)
@export var torch_spawn_chance: float = 0.5

func _ready():
	super._ready()
	dungeon_done_generating.connect(remove_unused_doors_and_walls)
	randomize_torches()

func remove_unused_doors_and_walls():
	var models = $Models

	var directions = {
		"F": "F_WALL",
		"R": "R_WALL",
		"B": "B_WALL",
		"L": "L_WALL"
	}

	for dir in directions.keys():
		var door_node_path = "CSGBox3D/DOOR?_" + dir + "_CUT"
		var wall_name = directions[dir]

		if has_node(door_node_path):
			var door = get_door_by_node(get_node(door_node_path))
			if door and door.get_room_leads_to() != null:
				# Remove the wall if a door leads to another room
				if models.has_node(wall_name):
					models.get_node(wall_name).queue_free()
			else:
				# Otherwise make sure the wall is visible
				if models.has_node(wall_name):
					models.get_node(wall_name).visible = true

	# Remove doors that don't lead anywhere
	for door in get_doors():
		if door.get_room_leads_to() == null:
			door.door_node.queue_free()

func randomize_torches():
	var models = $Models
	var walls = ["F_WALL", "B_WALL", "L_WALL", "R_WALL"]
	
	for wall_name in walls:
		if models.has_node(wall_name):
			var wall = models.get_node(wall_name)
			if wall.has_node("Torch"):
				var torch = wall.get_node("Torch")
				# Random chance to show/hide the torch
				torch.visible = randf() < torch_spawn_chance
