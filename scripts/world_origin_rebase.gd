extends Node

const WorldRebase = preload("res://scripts/world_rebase.gd")

@export var tracked_node: NodePath
@export var rebase_threshold: float = 5000.0

func _physics_process(_delta: float) -> void:
	_check_and_rebase()

func _check_and_rebase() -> void:
	var tracked := get_node_or_null(tracked_node) as Node3D
	if tracked == null:
		return
	if not WorldRebase.should_rebase(tracked.position, rebase_threshold):
		return
	var offset := WorldRebase.compute_rebase_offset(tracked.position)
	var parent := tracked.get_parent()
	if parent != null:
		for child in parent.get_children():
			if child == tracked:
				continue
			if child is Node3D:
				(child as Node3D).position -= offset
	tracked.position -= offset
