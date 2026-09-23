extends Node

const WorldRebase = preload("res://scripts/world_rebase.gd")

@export var tracked_node: NodePath
@export var rebasing_node: NodePath
@export var rebase_threshold: float = 5000.0

func _physics_process(_delta: float) -> void:
	_check_and_rebase()

func _check_and_rebase() -> void:
	var tracked := get_node_or_null(tracked_node) as Node3D
	var rebasing := get_node_or_null(rebasing_node) as Node3D
	if tracked == null or rebasing == null:
		return
	if not WorldRebase.should_rebase(tracked.position, rebase_threshold):
		return
	var offset := WorldRebase.compute_rebase_offset(tracked.position)
	tracked.position -= offset
	rebasing.position -= offset
