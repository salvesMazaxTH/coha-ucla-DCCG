extends SceneTree
## Headless UI smoke test: builds the table and renders several states.

func _init() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m._start(false, "fogo", "agua")
	m.pending_pass = false
	m._render()
	m._do(m.g.mulligan(0, []))
	m.pending_pass = false
	m._do(m.g.mulligan(1, []))
	m.pending_pass = false
	for i in 30:
		if m.g.phase == "over":
			break
		var ev = SimpleAI.step(m.g, m.g.decider())
		m.viewer = m.g.decider()
		m._do(ev)
		m.pending_pass = false
		m._render()
		var v = null
		for c in m.layer.get_children():
			if c is CardView and not c.face_down:
				v = c
		if v:
			m._show_overlay(v)
			m._close_overlay()
		await process_frame
	print("smoke ok, turn ", m.g.turn)
	quit()
