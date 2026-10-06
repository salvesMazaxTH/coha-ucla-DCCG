extends Control
## Table screen: menu, board rendering, input state machine, AI driver,
## hot-seat pass screen and the full-screen card summary overlay.

const BG := Color("#0f0d16")
const SEL := Color("#ffd23f")
const TARGET := Color("#ff5050")
const OK := Color("#4dff88")

var g: GameState
var vs_ai := true
var viewer := 0 ## whose perspective is drawn
var pending_pass := false

# input state
var picked: Array = [] ## mulligan/discard selection
var attack_sel: Dictionary = {} ## attacker uid -> provoked uid
var provoking := 0 ## attacker currently choosing a provoke target
var block_sel: Dictionary = {} ## attacker uid -> blocker uid
var blocker_pick := 0
var targeting := {} ## {"kind": hand|legendary|ability, "uid": int, "spec": String}

var log_lines: Array = []
var layer: Control
var overlay: Control
var views := {} ## uid -> Control (cards and leader panels) for floats
var ai_timer: Timer

func _ready() -> void:
	ai_timer = Timer.new()
	ai_timer.one_shot = true
	ai_timer.wait_time = 0.55
	ai_timer.timeout.connect(_ai_step)
	add_child(ai_timer)
	_show_menu()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)

# ---------------------------------------------------------------- menu

func _show_menu() -> void:
	_clear()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.position = Vector2(600, 260)
	box.custom_minimum_size = Vector2(400, 0)
	layer.add_child(box)
	box.add_child(_label("CSA — Card Game", 44, Color("#e8c25a"), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("alpha 0.1", 16, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	for opt in [["Contra IA  (Fogo × Água)", true, "fogo", "agua"], ["Contra IA  (Água × Fogo)", true, "agua", "fogo"], ["Hot-seat  (2 jogadores)", false, "fogo", "agua"]]:
		var b := _button(opt[0], func(): _start(opt[1], opt[2], opt[3]))
		b.custom_minimum_size = Vector2(400, 54)
		box.add_child(b)

func _start(ai: bool, deck_a: String, deck_b: String) -> void:
	vs_ai = ai
	g = GameState.new(deck_a, deck_b)
	log_lines = ["Partida iniciada. Escolha até 3 cartas para trocar."]
	viewer = 0
	pending_pass = not vs_ai
	_reset_input()
	_render()

func _reset_input() -> void:
	picked.clear()
	attack_sel.clear()
	block_sel.clear()
	provoking = 0
	blocker_pick = 0
	targeting = {}

# ---------------------------------------------------------------- actions

func _do(events: Array) -> void:
	if events.is_empty():
		_log("Ação inválida.")
		return
	_reset_input()
	for e in events:
		_log_event(e)
	var d := g.decider()
	if not vs_ai and d != viewer and g.phase != "over":
		viewer = d
		pending_pass = true
	_render()
	_animate(events)

func _ai_step() -> void:
	if g == null or g.phase == "over" or not _is_ai(g.decider()):
		return
	var ev := SimpleAI.step(g, g.decider())
	if ev.is_empty():
		return
	for e in ev:
		_log_event(e)
	_reset_input()
	_render()
	_animate(ev)

func _is_ai(p: int) -> bool:
	return vs_ai and p == 1

# ---------------------------------------------------------------- render

func _clear() -> void:
	if layer:
		layer.queue_free()
	layer = Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	views.clear()
	queue_redraw()

func _render() -> void:
	_clear()
	if pending_pass:
		_render_pass()
		return
	var me := viewer
	var op := g.opponent(me)
	_render_leader(op, Vector2(20, 20))
	_render_leader(me, Vector2(20, 690))
	_render_command(op, Vector2(250, 20))
	_render_command(me, Vector2(250, 710))
	_render_enemy_hand(op)
	_render_board(op, 175)
	_render_board(me, 470)
	_render_hand(me)
	_render_side()
	if g.phase == "over":
		_render_game_over()
	elif _is_ai(g.decider()):
		ai_timer.start()

func _render_pass() -> void:
	var p := viewer
	var box := VBoxContainer.new()
	box.position = Vector2(550, 330)
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 20)
	layer.add_child(box)
	var who := "Jogador %d — %s" % [p + 1, CardDB.leader(g.players[p]["leader_id"])["name"]]
	box.add_child(_label("Passe o dispositivo", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label(who, 22, Color("#e8c25a"), HORIZONTAL_ALIGNMENT_CENTER))
	var b := _button("Estou pronto", func():
		pending_pass = false
		_render())
	b.custom_minimum_size = Vector2(500, 54)
	box.add_child(b)

func _render_leader(p: int, pos: Vector2) -> void:
	var pl: Dictionary = g.players[p]
	var ld := CardDB.leader(pl["leader_id"])
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(210, 190)
	panel.add_theme_stylebox_override("panel", _box(Color(CardDB.element(ld["elements"][0])["color"]).darkened(0.6), 10))
	layer.add_child(panel)
	var uid: int = GameState.LEADER_UID[p]
	views[uid] = panel
	var tex := CardView.texture(ld["art"])
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(8, 8)
		tr.size = Vector2(80, 80)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tr)
	var nm := _label(ld["name"], 18, Color.WHITE)
	nm.position = Vector2(96, 8)
	panel.add_child(nm)
	var hp := _label("♥ %d / %d" % [pl["leader_hp"], pl["leader_max"]], 22, Color("#ff7a7a"))
	hp.position = Vector2(96, 34)
	panel.add_child(hp)
	var mom := _label("◆ %d / %d" % [pl["momentum"], pl["max_momentum"]], 18, Color("#6fb4ff"))
	mom.position = Vector2(96, 64)
	panel.add_child(mom)
	var info := _label("Deck %d · Cemitério %d" % [pl["deck"].size(), pl["graveyard"].size()], 12, Color(1, 1, 1, 0.6))
	info.position = Vector2(8, 96)
	panel.add_child(info)
	var ab: Dictionary = ld["ability"]
	var ab_btn := _button("%s (%d)" % [ab["name"], ab["cost"]], func(): _on_ability(p))
	ab_btn.position = Vector2(8, 120)
	ab_btn.size = Vector2(194, 30)
	ab_btn.tooltip_text = ab["text"]
	ab_btn.disabled = p != viewer or not g.can_use_ability(p) or _is_ai(p)
	panel.add_child(ab_btn)
	var ab_txt := _label(ab["text"], 10, Color(1, 1, 1, 0.65))
	ab_txt.position = Vector2(8, 152)
	ab_txt.size = Vector2(194, 34)
	ab_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(ab_txt)
	if _is_target(uid):
		panel.add_theme_stylebox_override("panel", _box(Color(CardDB.element(ld["elements"][0])["color"]).darkened(0.6), 10, TARGET))
	panel.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_leader_click(p))

func _render_command(p: int, pos: Vector2) -> void:
	var l: Dictionary = g.players[p]["legendary"]
	var cap := _label("Zona de Comando", 11, Color(1, 1, 1, 0.5))
	cap.position = pos + Vector2(0, -2) if p != viewer else pos + Vector2(0, -18)
	layer.add_child(cap)
	if not l["in_zone"]:
		var empty := _label("(em campo)", 12, Color(1, 1, 1, 0.35))
		empty.position = pos + Vector2(10, 60)
		layer.add_child(empty)
		return
	var v := CardView.new().setup(l["card_id"], {}, 0.8)
	v.position = pos + Vector2(0, 14) if p != viewer else pos
	v.cost_override = g.legendary_cost(p)
	if p == viewer and g.can_cast_legendary(p) and not _is_ai(p):
		v.highlight = OK
	if targeting.get("kind") == "legendary" and p == viewer:
		v.highlight = SEL
	v.left_clicked.connect(func(_v): _on_legendary(p))
	v.right_clicked.connect(_show_overlay)
	layer.add_child(v)

func _render_enemy_hand(p: int) -> void:
	var n: int = g.players[p]["hand"].size()
	for i in n:
		var v := CardView.new().setup("", {}, 0.45)
		v.face_down = true
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.position = Vector2(600 + i * 34, 10)
		layer.add_child(v)

func _render_board(p: int, y: float) -> void:
	var board: Array = g.players[p]["board"]
	var w := 132.0
	var x0 := 830.0 - board.size() * w / 2.0
	for i in board.size():
		var c: Dictionary = board[i]
		var v := CardView.new().setup(c["card_id"], c)
		v.position = Vector2(x0 + i * w, y)
		if c["exhausted"] and g.phase != "blocks":
			v.dim = true
		_decorate_creature(v, c, p)
		v.left_clicked.connect(_on_creature_click)
		v.right_clicked.connect(_show_overlay)
		layer.add_child(v)
		views[c["uid"]] = v
		if attack_sel.has(c["uid"]) or g.attackers.has(c["uid"]):
			v.position.y += -24 if p == viewer else 24
			var prov: int = attack_sel.get(c["uid"], g.attackers.get(c["uid"], 0))
			if prov != 0:
				_tag(v, "provoca", TARGET)
		if block_sel.values().has(c["uid"]):
			_tag(v, "bloqueia", OK)

func _decorate_creature(v: CardView, c: Dictionary, p: int) -> void:
	if _is_target(c["uid"]):
		v.highlight = TARGET
		return
	if g.phase == "main" and p == viewer and g.active == viewer:
		if attack_sel.has(c["uid"]):
			v.highlight = SEL if provoking != c["uid"] else TARGET
		elif not g.players[viewer]["attacked"] and g.can_attack(c) and targeting.is_empty():
			v.highlight = OK
	elif g.phase == "main" and provoking != 0 and p != viewer and not attack_sel.values().has(c["uid"]):
		v.highlight = TARGET
	if g.phase == "blocks" and viewer == g.decider():
		if p == viewer and (c["uid"] == blocker_pick):
			v.highlight = SEL
		elif p == viewer and not block_sel.values().has(c["uid"]) and not g.attackers.values().has(c["uid"]):
			v.highlight = OK
		elif p != viewer and g.attackers.has(c["uid"]):
			v.highlight = TARGET if blocker_pick != 0 and g.can_block(g.find_creature(blocker_pick), c) else SEL
	if provoking != 0 and p != viewer and g.phase == "main":
		v.highlight = TARGET

func _tag(v: Control, t: String, col: Color) -> void:
	var l := _label(t, 12, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.position = Vector2(0, -18)
	l.size = Vector2(v.size.x, 16)
	v.add_child(l)

func _render_hand(p: int) -> void:
	var hand: Array = g.players[p]["hand"]
	var n := hand.size()
	var step: float = min(126.0, 900.0 / max(1, n))
	var x0 := 830.0 - (step * (n - 1) + 120) / 2.0
	for i in n:
		var c: Dictionary = hand[i]
		var v := CardView.new().setup(c["card_id"], c)
		v.position = Vector2(x0 + i * step, 712)
		if picked.has(c["uid"]):
			v.position.y -= 30
			v.highlight = TARGET if g.phase == "discard" else SEL
		elif targeting.get("uid", 0) == c["uid"] and targeting.get("kind") == "hand":
			v.position.y -= 30
			v.highlight = SEL
		elif g.phase == "main" and g.can_play(p, c["uid"]) and not _is_ai(p):
			v.highlight = OK
		v.left_clicked.connect(_on_hand_click)
		v.right_clicked.connect(_show_overlay)
		v.mouse_entered.connect(func(): v.position.y -= 12)
		v.mouse_exited.connect(func(): v.position.y += 12)
		layer.add_child(v)

func _render_side() -> void:
	var x := 1390.0
	var phase_names := {"mulligan": "Mulligan", "main": "Fase Principal", "blocks": "Bloqueios", "discard": "Descarte", "over": "Fim de jogo"}
	var head := _label("Turno %d · %s" % [g.turn, phase_names.get(g.phase, g.phase)], 16, Color("#e8c25a"))
	head.position = Vector2(x, 330)
	layer.add_child(head)
	var whose := _label("Vez de: Jogador %d%s" % [g.decider() + 1, " (IA)" if _is_ai(g.decider()) else ""], 13, Color.WHITE)
	whose.position = Vector2(x, 354)
	layer.add_child(whose)
	var hint := _label(_hint(), 12, Color(1, 1, 1, 0.7))
	hint.position = Vector2(x, 378)
	hint.size = Vector2(200, 60)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(hint)
	var y := 440.0
	if g.decider() == viewer and not _is_ai(viewer):
		for b in _action_buttons():
			b.position = Vector2(x, y)
			b.size = Vector2(195, 40)
			layer.add_child(b)
			y += 48
	var log_box := _label("\n".join(log_lines.slice(max(0, log_lines.size() - 9))), 11, Color(1, 1, 1, 0.55))
	log_box.position = Vector2(x, 20)
	log_box.size = Vector2(200, 290)
	log_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(log_box)
	var menu := _button("Menu", _show_menu)
	menu.position = Vector2(1500, 850)
	menu.size = Vector2(90, 34)
	layer.add_child(menu)

func _hint() -> String:
	if not targeting.is_empty():
		return "Escolha um alvo (botão direito/Esc cancela)."
	match g.phase:
		"mulligan":
			return "Clique em até 3 cartas para trocar."
		"blocks":
			return "Clique numa criatura sua e depois no atacante que ela bloqueia."
		"discard":
			return "Mão acima de 10: escolha %d para descartar." % (g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
		"main":
			if provoking != 0:
				return "Provocar: escolha a criatura inimiga que será obrigada a bloquear."
			return "Jogue cartas. Clique nas suas criaturas para atacar. Botão direito: ver carta."
	return ""

func _action_buttons() -> Array:
	var out: Array = []
	match g.phase:
		"mulligan":
			out.append(_button("Confirmar (%d)" % picked.size(), func(): _do(g.mulligan(viewer, picked.duplicate()))))
		"main":
			if not attack_sel.is_empty():
				out.append(_button("Atacar (%d)" % attack_sel.size(), func(): _do(g.declare_attack(viewer, attack_sel.duplicate()))))
				out.append(_button("Cancelar ataque", func():
					_reset_input()
					_render()))
			out.append(_button("Encerrar turno", func(): _do(g.end_turn(viewer))))
		"blocks":
			out.append(_button("Confirmar bloqueios", func(): _do(g.declare_blocks(viewer, block_sel.duplicate()))))
		"discard":
			var need: int = g.players[viewer]["hand"].size() - GameState.HAND_LIMIT
			var b := _button("Descartar (%d/%d)" % [picked.size(), need], func(): _do(g.discard(viewer, picked.duplicate())))
			b.disabled = picked.size() != need
			out.append(b)
	return out

func _render_game_over() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var txt := "Empate!" if g.winner == 2 else "Jogador %d venceu!" % (g.winner + 1)
	if vs_ai and g.winner < 2:
		txt = "Vitória!" if g.winner == 0 else "Derrota."
	var l := _label(txt, 56, Color("#e8c25a"), HORIZONTAL_ALIGNMENT_CENTER)
	l.position = Vector2(0, 340)
	l.size = Vector2(1600, 80)
	layer.add_child(l)
	var b := _button("Voltar ao menu", _show_menu)
	b.position = Vector2(680, 460)
	b.size = Vector2(240, 50)
	layer.add_child(b)

# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if overlay and e is InputEventMouseButton and e.pressed:
		_close_overlay()
		return
	var cancel: bool = (e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT)
	if cancel and g and (not targeting.is_empty() or provoking != 0 or blocker_pick != 0):
		targeting = {}
		provoking = 0
		blocker_pick = 0
		_render()

func _my_input() -> bool:
	return g.decider() == viewer and not _is_ai(viewer) and not pending_pass

func _on_hand_click(v: CardView) -> void:
	if not _my_input():
		return
	match g.phase:
		"mulligan":
			_toggle_pick(v.uid, GameState.MULLIGAN_MAX)
		"discard":
			_toggle_pick(v.uid, g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
		"main":
			if not g.can_play(viewer, v.uid):
				_log("Não dá para jogar essa carta agora.")
				_render()
				return
			var cd := CardDB.card(v.card_id)
			var spec := g.target_spec(cd["effects"])
			if spec != "" and not g.valid_targets(viewer, spec).is_empty():
				targeting = {"kind": "hand", "uid": v.uid, "spec": spec}
				attack_sel.clear()
				_render()
			else:
				_do(g.play_card(viewer, v.uid, 0))

func _toggle_pick(uid: int, cap: int) -> void:
	if picked.has(uid):
		picked.erase(uid)
	elif picked.size() < cap:
		picked.append(uid)
	_render()

func _on_legendary(p: int) -> void:
	if p != viewer or not _my_input() or not g.can_cast_legendary(p):
		return
	var spec := g.target_spec(CardDB.card(g.players[p]["legendary"]["card_id"])["effects"])
	if spec != "" and not g.valid_targets(p, spec).is_empty():
		targeting = {"kind": "legendary", "uid": 0, "spec": spec}
		_render()
	else:
		_do(g.cast_legendary(p, 0))

func _on_ability(p: int) -> void:
	if not _my_input():
		return
	var spec := g.target_spec(CardDB.leader(g.players[p]["leader_id"])["ability"]["effects"])
	if spec != "":
		targeting = {"kind": "ability", "uid": 0, "spec": spec}
		_render()
	else:
		_do(g.use_ability(p, 0))

func _is_target(uid: int) -> bool:
	return not targeting.is_empty() and g.valid_targets(viewer, targeting["spec"], targeting.get("uid", 0)).has(uid)

func _fire_target(uid: int) -> void:
	match targeting["kind"]:
		"hand":
			_do(g.play_card(viewer, targeting["uid"], uid))
		"legendary":
			_do(g.cast_legendary(viewer, uid))
		"ability":
			_do(g.use_ability(viewer, uid))

func _on_leader_click(p: int) -> void:
	if _my_input() and _is_target(GameState.LEADER_UID[p]):
		_fire_target(GameState.LEADER_UID[p])

func _on_creature_click(v: CardView) -> void:
	if not _my_input():
		return
	var c := g.find_creature(v.uid)
	if c.is_empty():
		return
	if not targeting.is_empty():
		if _is_target(v.uid):
			_fire_target(v.uid)
		return
	match g.phase:
		"main":
			if provoking != 0:
				if c["owner"] != viewer and not attack_sel.values().has(v.uid):
					attack_sel[provoking] = v.uid
					provoking = 0
				_render()
				return
			if c["owner"] != viewer or g.players[viewer]["attacked"] or not g.can_attack(c):
				return
			if attack_sel.has(v.uid):
				attack_sel.erase(v.uid)
			else:
				attack_sel[v.uid] = 0
				if g.has_kw(c, "provocar") and not g.players[g.opponent(viewer)]["board"].is_empty():
					provoking = v.uid
			_render()
		"blocks":
			if c["owner"] == viewer:
				if g.attackers.values().has(v.uid):
					return # already forced to block a provoker
				for a in block_sel.keys():
					if block_sel[a] == v.uid:
						block_sel.erase(a)
				blocker_pick = v.uid if blocker_pick != v.uid else 0
				_render()
			elif blocker_pick != 0 and g.attackers.has(v.uid) and g.attackers[v.uid] == 0:
				if g.can_block(g.find_creature(blocker_pick), c):
					block_sel[v.uid] = blocker_pick
					blocker_pick = 0
				else:
					_log("Essa criatura não pode bloquear esse atacante (Voar/Furtivo).")
				_render()

# ---------------------------------------------------------------- overlay

func _show_overlay(v: CardView) -> void:
	if v.face_down:
		return
	_close_overlay()
	var cd := CardDB.card(v.card_id)
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_overlay())
	add_child(overlay)
	var big := CardView.new().setup(v.card_id, v.inst, 3.0)
	big.cost_override = v.cost_override
	big.position = Vector2(320, 195)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(big)
	var txt := "[font_size=34][color=#e8c25a]%s[/color][/font_size]\n" % cd["name"]
	var rar := {"legendary": "Campeão Lendário", "champion": "Campeão", "common": "Unidade"}
	var typ := {"creature": rar[cd["rarity"]], "spell": "Feitiço", "equipment": "Equipamento"}
	txt += "[color=#aaaaaa]%s · %s · custo %d[/color]\n\n" % [typ[cd["type"]], CardDB.element(cd["element"]).get("name", cd["element"]), cd["cost"]]
	if cd.get("text", "") != "":
		txt += "[font_size=22]%s[/font_size]\n\n" % cd["text"]
	for kw in cd.get("keywords", []):
		var k := CardDB.keyword(kw)
		txt += "[color=#ffe9a8][b]%s[/b][/color] — %s\n" % [k["name"], k["text"]]
	if cd["rarity"] == "legendary":
		txt += "\n[color=#e8c25a]Lendário:[/color] fica na Zona de Comando. Cada nova conjuração custa +%d. Ao morrer, volta para a Zona de Comando.\n" % GameState.COMMANDER_TAX
	if cd.get("flavor", "") != "":
		txt += "\n[i][color=#888888]%s[/color][/i]" % cd["flavor"]
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = txt
	rt.position = Vector2(740, 220)
	rt.size = Vector2(560, 480)
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.add_theme_font_size_override("bold_font_size", 18)
	rt.add_theme_font_size_override("italics_font_size", 16)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(rt)

func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null

# ---------------------------------------------------------------- feedback

func _animate(events: Array) -> void:
	var delay := 0.0
	for e in events:
		var col := Color.TRANSPARENT
		var txt := ""
		match e["type"]:
			"damage":
				txt = "-%d" % e["amount"]
				col = Color("#ff5050")
			"heal":
				txt = "+%d" % e["amount"]
				col = Color("#5dff8a")
			"shield_break":
				txt = "Escudo!"
				col = Color("#9fe3ff")
		if txt == "" or not views.has(e["uid"]):
			continue
		var target: Control = views[e["uid"]]
		var l := _label(txt, 30, col, HORIZONTAL_ALIGNMENT_CENTER)
		l.size = Vector2(target.size.x, 40)
		l.position = target.global_position + Vector2(0, target.size.y * 0.35)
		l.modulate.a = 0
		layer.add_child(l)
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(l, "modulate:a", 1.0, 0.08)
		tw.parallel().tween_property(l, "position:y", l.position.y - 40, 0.7)
		tw.tween_property(l, "modulate:a", 0.0, 0.25)
		tw.tween_callback(l.queue_free)
		delay += 0.08

func _log(t: String) -> void:
	log_lines.append(t)

func _pname(p: int) -> String:
	return "IA" if _is_ai(p) else "J%d" % (p + 1)

func _cname(id: String) -> String:
	return CardDB.card(id)["name"]

func _log_event(e: Dictionary) -> void:
	match e["type"]:
		"play":
			_log("%s jogou %s" % [_pname(e["player"]), _cname(e["card_id"])])
		"ability":
			_log("%s usou %s" % [_pname(e["player"]), CardDB.leader(g.players[e["player"]]["leader_id"])["ability"]["name"]])
		"attack":
			_log("%s atacou com %d" % [_pname(e["player"]), e["attackers"].size()])
		"death":
			pass
		"fatigue":
			_log("%s: fadiga %d" % [_pname(e["player"]), e["amount"]])
		"start_turn":
			_log("— Turno %d: %s —" % [e["turn"], _pname(e["player"])])
		"discard":
			_log("%s descartou uma carta" % _pname(e["player"]))

# ---------------------------------------------------------------- widgets

func _label(t: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b

func _box(col: Color, radius: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	if border.a > 0:
		sb.set_border_width_all(3)
		sb.border_color = border
	return sb
