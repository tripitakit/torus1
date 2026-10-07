extends SceneTree

# Bakes the trees' impostor atlases (run once, with a GPU, not headless):
#   ~/Godot_v4.6.1-stable-double_linux.x86_64 --path . -s tools/bake_tree_impostors.gd
# Every TreeModels variant drawn unlit on a transparent background, from the
# side (orthographic, the tree's foot at the cell's bottom middle) and from
# above, each in a CELL-pixel cell of a 5 x 5 atlas:
# assets/trees/impostors_side.png, assets/trees/impostors_top.png.

const TreeModels = preload("res://scripts/tree_models.gd")

func _initialize():
	var variants := TreeModels.variants()
	var cell := TreeModels.IMPOSTOR_CELL
	var grid := TreeModels.IMPOSTOR_GRID
	var view := SubViewport.new()
	view.size = Vector2i(cell, cell)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.own_world_3d = true
	root.add_child(view)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	view.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 20.0
	view.add_child(camera)
	camera.current = true
	var holder := MeshInstance3D.new()
	view.add_child(holder)
	for side in ["side", "top"]:
		var atlas := Image.create_empty(cell * grid, cell * grid, false, Image.FORMAT_RGBA8)
		for k in range(variants.size()):
			holder.mesh = _unlit(variants[k].mesh)
			var size: Vector2 = TreeModels.impostor_frame(variants[k].mesh, side == "top")
			camera.size = size.x
			if side == "side":
				camera.transform = Transform3D(Basis(), Vector3(0.0, size.y, 5.0))
			else:
				camera.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0.0, 5.0, 0.0))
			for f in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			var shot := view.get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(k % grid, k / grid) * cell)
		TreeModels.bleed(atlas, 24)
		var colours := _fill_with_average(atlas, cell, grid)
		if side == "side":
			var file := FileAccess.open(ProjectSettings.globalize_path(TreeModels.IMPOSTOR_COLOURS_PATH), FileAccess.WRITE)
			file.store_string(JSON.stringify(colours))
			print("saved " + TreeModels.IMPOSTOR_COLOURS_PATH)
		var path := "res://assets/trees/impostors_%s.png" % side
		atlas.save_png(ProjectSettings.globalize_path(path))
		print("saved " + path)
	quit()

# The variant with its materials' unlit twins (the impostor lights itself).
func _unlit(mesh: ArrayMesh) -> ArrayMesh:
	var copy := mesh.duplicate() as ArrayMesh
	for s in range(copy.get_surface_count()):
		var source := copy.surface_get_material(s) as ShaderMaterial
		var shader := Shader.new()
		shader.code = source.shader.code.replace("render_mode cull_disabled;", "render_mode cull_disabled, unshaded;")
		var material := ShaderMaterial.new()
		material.shader = shader
		for name in ["albedo_tex", "leaves"]:
			material.set_shader_parameter(name, source.get_shader_parameter(name))
		material.set_shader_parameter("detail_to", 1.0e6)
		material.set_shader_parameter("fade", 0.0)
		copy.surface_set_material(s, material)
	return copy

# Every still-black transparent pixel of a cell coloured with the cell's
# average opaque colour (no black to darken the far mipmaps); those averages,
# [r, g, b] per cell, returned.
func _fill_with_average(atlas: Image, cell: int, grid: int) -> Array:
	var averages := []
	for k in range(grid * grid):
		var corner := Vector2i(k % grid, k / grid) * cell
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for y in range(cell):
			for x in range(cell):
				var c := atlas.get_pixelv(corner + Vector2i(x, y))
				if c.a > 0.5:
					sum += c
					n += 1
		var average := Color(sum.r / maxf(n, 1), sum.g / maxf(n, 1), sum.b / maxf(n, 1), 0.0)
		averages.append([average.r, average.g, average.b])
		for y in range(cell):
			for x in range(cell):
				var c := atlas.get_pixelv(corner + Vector2i(x, y))
				if c.a == 0.0 and c.r + c.g + c.b == 0.0:
					atlas.set_pixelv(corner + Vector2i(x, y), average)
	return averages
