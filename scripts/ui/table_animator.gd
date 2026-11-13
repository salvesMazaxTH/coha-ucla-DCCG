class_name TableAnimator
extends RefCounted
## Plays a batch of game events on the table: cards flying, attacks, hits, deaths, banners.
## Main (`host`) owns the table; the drawing tools come from FxLibrary, FxShots and FxCasts.

const FxLibraryScript = preload("res://scripts/ui/fx_library.gd")
const ICE := FxLibraryScript.ICE

var host
var fx_library: FxLibrary
var fx_shots: FxShots
var fx_casts: FxCasts

## Read-only mirrors of Main's state, so the code below reads as it did inside Main.
var g:
	get:
		return host.g
var viewer: int:
	get:
		return host.viewer
var online: bool:
	get:
		return host.online
var vs_ai: bool:
	get:
		return host.vs_ai
var pending_pass: bool:
	get:
		return host.pending_pass
var fx: Control:
	get:
		return host.fx
var stage_w: float:
	get:
		return host.stage_w
var lane_cx: float:
	get:
		return host.lane_cx
var views: Dictionary:
	get:
		return host.views
var hand_uids: Dictionary:
	get:
		return host.hand_uids


func _init(host_node, library: FxLibrary, shots: FxShots, casts: FxCasts) -> void:
	host = host_node
	fx_library = library
	fx_shots = shots
	fx_casts = casts


## How long a revealed spell/ability stays frozen mid-screen: long enough for the
## opponent to read it, short for your own plays (you already know what you cast).
## Hot-seat shares one screen between both players, so it gets a middle value.
const REVEAL_HOLD := 2.78
const REVEAL_HOLD_OWN := 0.8
const REVEAL_HOLD_HOTSEAT := 1.5
const REVEAL_W := 280.0 ## on-screen width of a revealed spell
const FATIGUE_W := 240.0


func _reveal_hold(p: int) -> float:
	if not online and not vs_ai:
		return REVEAL_HOLD_HOTSEAT
	return REVEAL_HOLD_OWN if p == viewer else REVEAL_HOLD


## A Leader ability has no card to show: a banner with its name and text instead.
func _ability_banner(p: int, t: float, hold: float, passive := false) -> void:
	var ab: Dictionary = CardDB.leader(g.players[p]["leader_id"])["ability"]
	var w := 440.0
	var box := PanelContainer.new()
	var sb := UITheme.box(Color(0.03, 0.03, 0.05, 0.94), 18, Color(UITheme.GOLD, 0.85), 2, 16)
	sb.set_content_margin_all(16)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(w, 0)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	col.add_child(
		host._label(
			"%s · %s do Líder" % [host._pname(p), "Passiva" if passive else "Habilidade"],
			15,
			Color(UITheme.TEXT, 0.6),
			HORIZONTAL_ALIGNMENT_CENTER,
			"body",
		)
	)
	col.add_child(host._label(String(ab["name"]), 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "bold", 4))
	var tx: Label = host._label(String(ab.get("text", "")), 18, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "body")
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size = Vector2(w - 32, 0)
	col.add_child(tx)
	box.z_index = 30
	box.modulate.a = 0.0
	fx.add_child(box)
	box.reset_size()
	box.position = Vector2(lane_cx - w / 2.0, 420 - box.size.y / 2.0)
	var tw := box.create_tween()
	tw.tween_interval(t)
	tw.tween_property(box, "modulate:a", 1.0, 0.2)
	tw.tween_interval(hold)
	tw.tween_property(box, "modulate:a", 0.0, 0.35)
	tw.tween_callback(box.queue_free)


## Cinematic band announcing who plays first: a dark strip across the board with a gold title.
func first_banner(p: int) -> void:
	var mine: bool = p == viewer if (online or vs_ai) else true
	var title := "VOCÊ COMEÇA" if mine else "OPONENTE COMEÇA"
	if not online and not vs_ai:
		title = "%s COMEÇA" % host._pname(p).to_upper()
	var tint: Color = UITheme.GOLD_LIGHT if mine else Color("#ff8a80")
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.z_index = 40
	band.modulate.a = 0.0
	fx.add_child(band)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.size = Vector2(stage_w, 120)
	bg.position = Vector2(0, 360)
	band.add_child(bg)
	for y in [360.0, 478.0]:
		var line := ColorRect.new()
		line.color = Color(tint, 0.85)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.size = Vector2(stage_w, 2)
		line.position = Vector2(0, y)
		band.add_child(line)
	var sub: Label = host._label("PRIMEIRO TURNO", 16, Color(UITheme.TEXT, 0.65), HORIZONTAL_ALIGNMENT_CENTER, "body")
	sub.size = Vector2(stage_w, 24)
	sub.position = Vector2(0, 376)
	band.add_child(sub)
	var lb: Label = host._label(title, 46, tint, HORIZONTAL_ALIGNMENT_CENTER, "bold", 6)
	lb.size = Vector2(stage_w, 64)
	lb.position = Vector2(0, 404)
	band.add_child(lb)
	band.pivot_offset = Vector2(stage_w / 2.0, 420)
	band.scale = Vector2(1.12, 1.12)
	var tw := band.create_tween()
	tw.set_parallel(true)
	tw.tween_property(band, "modulate:a", 1.0, 0.3)
	tw.tween_property(band, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.3)
	tw.chain().tween_property(band, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(band.queue_free)


func elem_color(card_id: String) -> Color:
	return Color(CardDB.essence(CardDB.essences_of(CardDB.card(card_id))[0]).get("color", "#ffffff"))


func _count_ghosts(old: Dictionary) -> int:
	var n := 0
	for k in old:
		if k is int and k > 0 and not views.has(k) and not old[k]["hand"] and old[k]["inst"].has("damage"):
			n += 1
	return n


const LEADER_DEATH_LAG := 0.1 ## the Leader's burst starts this long after the blow that kills it

## The dead Leader bursts at `burst_time`; the result screen waits for the burst to finish.
## Returns the moment (s) when the burst is over.
func play_leader_death(leader_view: LeaderView, burst_time: float) -> float:
	var burst_end: float = burst_time + host.fx_leader_death.play(leader_view, burst_time)
	host._leader_ko_t = maxf(host._leader_ko_t, burst_end - host.KO_OVERLAY_DELAY)
	return burst_end

## Plays the events out over the freshly rendered table: cards fly from where
## they were, attackers lunge, victims shake, numbers float, the dead dissolve.
## Returns the time (s) at which everything has settled.
func animate(events: Array, old: Dictionary) -> float:
	if pending_pass or fx == null:
		return 0.0
	var bursts := 0
	for e in events:
		if e["type"] == "trigger":
			bursts += 1
	fx_library.fx_chain_scale = 1.0 / maxf(1.0, (bursts + _count_ghosts(old)) / 3.0)
	fx_library.fx_scale = fx_library.fx_chain_scale * GraphicsQuality.effect_detail
	var actors := views.duplicate()
	var ghosts: Array = []
	var exiled := { } ## uids banished by these events: they get the banish effect, not the death dissolve
	var special_relic_exit_uids := { } ## relics whose dedicated event already animates their exit
	for e in events:
		if e["type"] == "banish":
			exiled[e["uid"]] = true
		elif e["type"] == "lethal_ward":
			special_relic_exit_uids[int(e["uid"])] = true
		elif e["type"] == "death_prevented":
			special_relic_exit_uids[int(e["ward_uid"])] = true
	var ghost_exiled: Array = [] ## parallel to ghosts
	for k in old:
		if k is int and k > 0 and not views.has(k) and not old[k]["hand"] and old[k]["inst"].has("damage"):
			var gh := fx_library._ghost(old[k]["card_id"], old[k]["inst"], old[k]["pose"])
			actors[k] = gh
			ghosts.append(gh)
			ghost_exiled.append(exiled.has(k))
	# A unit summoned and killed inside the same batch (the Fantoche de Trapos taking a blow in Hikari's
	# place) is neither in `old` nor on the re-rendered table, so nothing would show it. Give it a ghost
	# standing in the next free cell of its owner's lane: it pops in at its "summon" event, takes the
	# hit like any unit, and dissolves at its "death" event.
	var died_uids := { }
	for e in events:
		if e["type"] == "death":
			died_uids[e["uid"]] = true
	var short_lived := { } ## uid -> ghost of a unit that lives and dies inside this batch
	var short_lived_per_player := { }
	var dissolved_early := { } ## ghosts already dissolved at their death (the settle loop skips them)
	for e in events:
		if (
			e["type"] != "summon" or not died_uids.has(e["uid"])
			or views.has(e["uid"]) or old.has(e["uid"]) or short_lived.has(e["uid"])
		):
			continue
		var owner_player: int = e["player"]
		var lane_index: int = host._laid_out_slots(owner_player) + int(short_lived_per_player.get(owner_player, 0))
		short_lived_per_player[owner_player] = int(short_lived_per_player.get(owner_player, 0)) + 1
		var lane_cell: Vector2 = host._board_cell(lane_index + 1, lane_index)
		var lane_y := 460.0 if owner_player == viewer else 172.0
		var short_ghost := fx_library._ghost(e["card_id"], { }, { "c": Vector2.ZERO, "rot": 0.0, "w": 1.0 })
		fx_library._apply_pose(
			short_ghost,
			{
				"c": Vector2(roundf(lane_cell.x + lane_cell.y / 2.0), roundf(lane_y) + short_ghost.size.y / 2.0),
				"rot": 0.0,
				"w": short_ghost.size.x,
			},
		)
		short_ghost.scale = Vector2.ZERO # hidden until its summon event pops it in
		short_ghost.z_index = 20
		actors[e["uid"]] = short_ghost
		short_lived[e["uid"]] = short_ghost
		ghosts.append(short_ghost)
		ghost_exiled.append(false)
	var cursor := 0.0
	var handled := { }
	var appear := { }
	var placed_uids := { } ## units whose "card placed" sound already played with their "play" event
	var in_combat := false
	var last_src := 0
	var last_dst := 0
	var hit_t := 0.0
	var trig_src := 0 ## unit whose trigger caused the events that follow (0 = none)
	var trig_style := "" ## how that unit's shots fly: its card's "hit_fx", or the chosen option's own "hit_fx"
	var trig_shots := 0 ## bolts that trigger already fired (only the first one charges up slowly)
	var volley_land_t := 0.0 ## when the trigger's last shot lands (the next one follows VOLLEY_GAP later)
	var trig_color := Color.TRANSPARENT ## color of the shots of a spell (its element); transparent = each effect's own color
	var area_cast_active := false ## an area cast just played: its hits land without shots and its destroys without the X
	var destroy_cast_style := "" ## the spell being resolved burns ("fogo") or drowns ("agua") the unit it destroys instead of the X
	var fatigue_pending := false ## a Fadiga was just announced: the Leader hit that follows is the game's rule, not a card's effect
	# Leader HP: _render drew the final value, so rewind it to what it was before these events
	# and step it down/up at each hit's moment instead of jumping straight to the end.
	var leader_hp := { }
	for e in events:
		if e["type"] == "leader_executed" and views.get(e["uid"]) is LeaderView:
			# the execution animation drains the HP itself, so only rewind it to the value before the kill
			if not leader_hp.has(e["uid"]):
				leader_hp[e["uid"]] = views[e["uid"]].hp
			leader_hp[e["uid"]] += int(e["hp_before"])
		elif e["type"] in ["damage", "heal"] and e["uid"] < 0 and views.get(e["uid"]) is LeaderView:
			if not leader_hp.has(e["uid"]):
				leader_hp[e["uid"]] = views[e["uid"]].hp
			leader_hp[e["uid"]] += e["amount"] if e["type"] == "damage" else -e["amount"]
	# a Leader that ends up dead was drawn without its top half: it must be whole until its burst
	var dying_leaders := { }
	for uid in leader_hp:
		if views[uid].hp <= 0:
			views[uid].top_destroyed = false
			dying_leaders[uid] = true
		views[uid].hp = leader_hp[uid]
	# Same for units on the board: rewind the damage counter shown on each card to what it was
	# before these events, then step it at each hit (so an AoE visibly ticks every card).
	var unit_damage := { }
	for e in events:
		if e["type"] in ["damage", "heal"] and e["uid"] > 0 and views.get(e["uid"]) is CardView and views[e["uid"]].inst.has("damage"):
			if not unit_damage.has(e["uid"]):
				unit_damage[e["uid"]] = views[e["uid"]].inst["damage"]
			unit_damage[e["uid"]] += -e["amount"] if e["type"] == "damage" else e["amount"]
	for uid in unit_damage:
		views[uid].inst["damage"] = unit_damage[uid]
		views[uid].queue_redraw()
	for e in events:
		var et: String = e["type"]
		# a new action or a blow from some other unit ends the trigger's chain of effects
		# (damage the trigger's own unit deals outside combat still belongs to the trigger)
		# (a spell cast from a Leader, trig_src < 0, deals its damage with the spell card as source, so
		# that does not end it; the spell's chain ends at the next action)
		if et in ["play", "ability", "passive", "resolve", "attack", "combat_damage", "start_turn", "end_turn"]:
			trig_src = 0
			trig_color = Color.TRANSPARENT
			area_cast_active = false
			destroy_cast_style = ""
		elif et in ["damage", "shield_break"] and e.get("src", 0) > 0 and trig_src >= 0 and (in_combat or e["src"] != trig_src):
			trig_src = 0
			trig_color = Color.TRANSPARENT
		# Fadiga damage has no source card even when a trigger's draw caused it, so no bolt flies for it.
		# Only the hit right after the "fatigue" event counts (a Leader guard may come between them).
		var is_fatigue_hit := fatigue_pending and et == "damage"
		if et == "fatigue":
			fatigue_pending = true
		elif et != "leader_guard":
			fatigue_pending = false
		# effects of a trigger fly out of their source as a bolt and land when it arrives
		# (a unit sent back to the hand only gets a shot from a spell, the ones with an element color,
		# like the wind blade of Rajada de Quintal; a unit's own bounce triggers keep no shot)
		var is_spell_bounce := et == "return_to_hand" and trig_color.a > 0.0
		if (
			(
				trig_src != 0 and not area_cast_active and not is_fatigue_hit
				and (
					is_spell_bounce
					or et
					in [
						"damage",
						"heal",
						"shield_break",
						"buff",
						"dot",
						"freeze",
						"exhaust",
						"stun",
						"condemn",
						"tide_mark",
						"magic_shield_break",
						"supreme_shield_break",
						"summon",
					]
				)
			) \
					and e["uid"] != trig_src
			and actors.has(trig_src) and actors.has(e["uid"])
		):
			# good effects are carried over as an orb; everything else is fired in the source's own style
			var hit_style := "boon" if fx_shots._is_boon_event(e) else trig_style
			var first_shot := trig_shots == 0
			var timing := fx_shots._shot_timing(hit_style, first_shot)
			var shot_time: float = timing["charge"] + timing["flight"]
			var land_t := cursor + shot_time
			if hit_style == "boon":
				land_t -= 0.02 # orbs go one after the other, never in a burst like the shots
			elif not first_shot:
				# rapid fire: this shot lands VOLLEY_GAP after the previous one, so it is already in the
				# air while that one hits. Only something slower than a plain hit in between (each hit
				# moves the cursor 0.12 on) holds it back.
				land_t = maxf(volley_land_t + FxShots.VOLLEY_GAP, cursor - 0.12)
			var shot_color := fx_shots._bolt_color(e)
			if trig_color.a > 0.0 and hit_style != "boon":
				shot_color = trig_color # a spell's shot carries the color of its element
			elif hit_style == "" and actors[trig_src] is CardView:
				# a unit firing the default bolt also takes its element's shot color when it has one
				# (a luz unit like Seymour fires the same white-yellow light as the luz spells)
				shot_color = fx_shots.spell_shot_color((actors[trig_src] as CardView).card_id, shot_color)
			fx_shots._effect_hit(hit_style, actors[trig_src], actors[e["uid"]], land_t - shot_time, shot_color, first_shot)
			volley_land_t = land_t
			cursor = land_t
			trig_shots += 1
		# Sound: most events play theirs right here, at the moment their animation starts. The ones
		# below time their own: hits and heals land at `t` (after the lunge), deaths and banishes play
		# with the dissolve at the end, and a played card makes its sound when it lands.
		# both players mulligan at the start; the card-fan sound plays once, for the player who goes first
		if not et in ["play", "damage", "shield_break", "heal", "death", "banish", "leader_hit_negated"] \
				and not (et == "summon" and placed_uids.has(e["uid"])) \
				and not (et == "enter_from_deck" and views.get(e["uid"]) is CardView) \
				and not (et == "mulligan" and int(e["player"]) != g.first):
			Sfx.play_event(e, cursor, in_combat)
		match et:
			"trigger":
				if actors.has(e["uid"]):
					fx_library._trigger_fx(actors[e["uid"]], e["trigger"], cursor)
					trig_src = e["uid"]
					trig_style = fx_shots._hit_style_of(actors[trig_src])
					# what it destroys follows the same rule as what it hits: the card's own cast_fx or its
					# element first, the X only when it has neither
					destroy_cast_style = fx_casts.destroy_style_of(String(e["card_id"]))
					trig_shots = 0
					trig_color = Color.TRANSPARENT
					cursor += 0.3
					# a trigger that hits a whole group of units (D'Lorafya's fire) plays one area cast
					# from the unit instead of one shot per target
					area_cast_active = fx_casts.is_area(String(e["card_id"]), String(e["trigger"]))
					if area_cast_active:
						cursor += fx_casts.area_cast(String(e["card_id"]), fx_library._center_of(actors[e["uid"]]), cursor)
			"effect_choice_chosen":
				# only an option that names its own "hit_fx" flies its effects out of the card (the choice
				# comes in a batch of its own, after the trigger that offered it)
				if actors.has(e["uid"]) and String(e.get("hit_fx", "")) != "":
					trig_src = e["uid"]
					trig_style = String(e["hit_fx"])
					trig_shots = 0
					trig_color = Color.TRANSPARENT
			"trigger_end":
				destroy_cast_style = ""
				trig_src = 0 # the effects that follow have no card to fly out of
				area_cast_active = false
			"shout":
				if actors.has(e["uid"]):
					cursor = fx_library._shout_fx(actors[e["uid"]], String(e["text"]), cursor, String(e.get("style", "")))
			"buff":
				if actors.has(e["uid"]):
					var parts: Array = []
					if int(e["atk"]) != 0 or int(e["hp"]) != 0:
						parts.append("%+d/%+d" % [e["atk"], e["hp"]])
					for kw in e.get("keywords", []):
						parts.append(String(CardDB.data()["keywords"].get(kw, { }).get("name", kw)))
					if not parts.is_empty():
						fx_library._impact(actors[e["uid"]], " ".join(parts), Color("#a8ffa0"), cursor, false)
				cursor += 0.15
			"play":
				var uid: int = e["uid"]
				var cd := CardDB.card(e["card_id"])
				var origin: Dictionary = { "c": Vector2(lane_cx + host.EHAND_DX, 30), "rot": 0.0, "w": 96.0 }
				if e.get("incarnation", false) and old.has("cmd%d" % e["player"]):
					origin = old["cmd%d" % e["player"]]["pose"]
				elif e.get("requiem", false):
					# a Réquiem spell rises from its caster's graveyard
					origin = { "c": host._graveyard_pose(int(e["player"]))["c"], "rot": 0.0, "w": 96.0 }
				elif e.has("source_uid") and old.has(e["source_uid"]):
					origin = old[e["source_uid"]]["pose"] # cast by a unit (Bola de Neve of Tempesfrost): it leaves that unit
				elif old.has(uid):
					origin = old[uid]["pose"]
				if cd["type"] == "unit" and views.has(uid):
					var v: CardView = views[uid]
					var to := fx_library.pose_of(v)
					var previous_cost_override := v.cost_override
					var captured_cost := int(e.get("cost", -1))
					if captured_cost >= 0:
						v.cost_override = captured_cost
						v.queue_redraw()
					handled[uid] = true
					# the card is heard when it lands on the board (the Encarnação also gets its bell as it leaves the Santuário)
					placed_uids[uid] = true
					if e.get("incarnation", false):
						Sfx.play_in("incarnation", cursor)
					Sfx.play_in("card_place", cursor + 0.38)
					v.z_index = 20
					var tw := fx_library._fly(v, origin, to, cursor, 0.42, 70.0, true)
					tw.tween_callback(
						func():
							v.z_index = 0,
					)
					var fs: Vector2 = Vector2.ONE * (to["w"] / v.size.x)
					tw.tween_property(v, "scale", fs * 1.1, 0.06)
					tw.tween_property(v, "scale", fs, 0.1)
					if captured_cost >= 0:
						tw.tween_interval(0.35)
						tw.tween_callback(
							func():
								if is_instance_valid(v):
									v.cost_override = previous_cost_override
									v.queue_redraw(),
						)
					cursor += 0.45
				else:
					Sfx.play_event(e, cursor, false)
					var gh := fx_library._ghost(e["card_id"], { }, origin, REVEAL_W / CardView.BASE.x) # built at its final size: scaling up would blur the text
					if e.has("cost"):
						gh.cost_override = int(e["cost"])
						gh.queue_redraw()
					gh.z_index = 30
					var tw := fx_library._fly(
						gh,
						origin,
						{ "c": Vector2(lane_cx, 420), "rot": 0.0, "w": REVEAL_W },
						cursor,
						0.35,
						40.0,
						true,
					)
					tw.tween_callback(
						func():
							gh.z_index = 0,
					)
					var hold := _reveal_hold(e["player"])
					gh.dissolve(cursor + 0.35 + hold, elem_color(e["card_id"]).lightened(0.15), 0.6)
					cursor += 0.35 + hold - 0.15
			"enter_from_deck":
				# any card that enters straight from the deck (a deck_effects "summon_self") flies out of its owner's pile instead of popping in from nowhere
				var uid: int = e["uid"]
				if views.get(uid) is CardView:
					handled[uid] = true
					placed_uids[uid] = true
					cursor += fx_library._enter_from_deck(views[uid], int(e["player"]), cursor)
			"fatigue":
				# shown like a played card, so the hit on the Leader that follows makes sense
				var fv := CardView.new().setup("", { }, FATIGUE_W / CardView.BASE.x)
				fv.fatigue = int(e["amount"])
				fv.mouse_filter = Control.MOUSE_FILTER_IGNORE
				fv.pivot_offset = fv.size / 2.0
				fv.z_index = 30
				fx.add_child(fv)
				var from_y: float = 860.0 + host.BOT if e["player"] == viewer else 30.0
				fx_library._fly(
					fv,
					{ "c": Vector2(lane_cx + host.EHAND_DX, from_y), "rot": 0.0, "w": 96.0 },
					{ "c": Vector2(lane_cx, 420), "rot": 0.0, "w": FATIGUE_W },
					cursor,
					0.35,
					40.0,
					true,
				)
				fv.dissolve(cursor + 0.35 + REVEAL_HOLD * 0.7, Color(0.75, 0.6, 1.0), 0.6)
				cursor += 0.35 + REVEAL_HOLD * 0.5
			"ability":
				var hold := _reveal_hold(e["player"])
				_ability_banner(e["player"], cursor, hold)
				cursor += 0.2 + hold - 0.15
			"passive":
				var hold := _reveal_hold(e["player"]) * 0.6
				_ability_banner(e["player"], cursor, hold, true)
				cursor += 0.2 + hold - 0.15
			"resolve":
				cursor += 0.15
				# a spell goes off from its caster's Leader: an area spell plays its cast over the whole
				# arena, a spell with targets fires its shots from the Leader in the color of its element
				var resolved_card_id := String(e.get("card_id", ""))
				# a unit's activated ability announces itself ("trigger") BEFORE it resolves, and the resolve clears
				# the chain above, so link the unit back as the source: its hits, area cast and destroys then work
				# exactly like the ones of an Ao Entrar
				var ability_source_uid := int(e.get("uid", 0))
				if e["kind"] == "unit_ability" and actors.has(ability_source_uid):
					trig_src = ability_source_uid
					trig_style = fx_shots._hit_style_of(actors[trig_src])
					trig_shots = 0
					destroy_cast_style = fx_casts.destroy_style_of(resolved_card_id)
					area_cast_active = fx_casts.is_area(resolved_card_id, "on_activate")
				var caster_leader = actors.get(GameState.LEADER_UID[int(e["player"])])
				if (
					e["kind"] == "card" and resolved_card_id != "" and caster_leader != null
					and String(CardDB.card(resolved_card_id).get("type", "")) == "spell"
				):
					if fx_casts.is_area(resolved_card_id, "on_play"):
						cursor += fx_casts.area_cast(resolved_card_id, fx_library._center_of(caster_leader), cursor)
						area_cast_active = true
					else:
						trig_src = GameState.LEADER_UID[int(e["player"])]
						trig_style = fx_shots.spell_hit_style(resolved_card_id)
						trig_shots = 0
						trig_color = fx_shots.spell_shot_color(resolved_card_id, elem_color(resolved_card_id).lightened(0.25))
						destroy_cast_style = fx_casts.destroy_style_of(resolved_card_id)
			"fizzle":
				host._toast(
					"%s não teve alvo e foi anulado."
					% (host._cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "A habilidade")
				)
				cursor += 0.3
			"countered":
				host._toast("%s foi anulado!" % ("A habilidade do Líder" if e["kind"] == "ability" else host._cname(e["card_id"])))
				cursor += 0.4
			"magic_shield_break", "supreme_shield_break", "tide_mark", "tide_draw", "dot", "dot_immune", "freeze", "exhaust", "ready", "stun", "stun_tick", "shrink", "condemn", "doom", "doom_resisted", "thaw", "dodge", "crit", "crit_negated", "critico_up", "heal_block", "heal_prevented":
				if actors.has(e["uid"]):
					var dot_name: String = { "queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento" }.get(
						String(e.get("dot", "")),
						"Marcador",
					)
					var dot_label := "%s %d" % [dot_name, int(e.get("amount", 0))]
					if not e.get("cleared", false):
						dot_label = "%s +%d" % [dot_name, int(e.get("amount", 0))]
					var lbl: String = {
						"magic_shield_break": "Anulado!",
						"supreme_shield_break": "Absorvido!",
						"tide_mark": "Maré",
						"tide_draw": "+1 carta",
						"dot": dot_label,
						"dot_immune": "Imune!",
						"freeze": "Congelada!",
						"exhaust": "Exausta!",
						"ready": "Desvirou!",
						"stun": "Atordoada!",
						"stun_tick": "Recuperando…",
						"shrink": "Encolhida!",
						"condemn": "Condenada!",
						"doom": "Ceifada!",
						"doom_resisted": "Resistiu!",
						"thaw": "Descongelou",
						"dodge": "Esquivou!",
						"crit": "Crítico!",
						"crit_negated": "Desdém!",
						"critico_up": "Crítico %d!" % int(e.get("level", 0)),
						"heal_block": "Cura bloqueada!",
						"heal_prevented": "Bloqueada!",
					}[e["type"]]
					var col: Color = Color("#6fd0ff")
					if e["type"] == "magic_shield_break":
						col = Color("#c9a8ff")
					elif e["type"] == "supreme_shield_break":
						col = Color("#ffd86b")
					elif e["type"] in ["freeze", "thaw"]:
						col = ICE
					elif e["type"] in ["stun", "stun_tick"]:
						col = CardView.STUN_COL
					elif e["type"] == "shrink":
						col = Color("#ffb347")
					elif e["type"] in ["condemn", "doom", "doom_resisted"]:
						col = CardView.DOOM_COL
					elif e["type"] in ["dot", "dot_immune"]:
						col = CardView.dot_badge_color(String(e.get("dot", "")))
					elif e["type"] in ["crit", "crit_negated", "critico_up"]:
						col = Color("#ff9d6e") # same warm tone as the Crítico tag
					elif e["type"] in ["heal_block", "heal_prevented"]:
						col = CardView.HEAL_BLOCK_COL
					fx_library._impact(actors[e["uid"]], lbl, col, cursor, false)
					if e["type"] == "freeze":
						fx_library._freeze_fx(actors[e["uid"]], cursor)
					elif e["type"] == "thaw":
						fx_library._frost_shards(fx_library._center_of(actors[e["uid"]]), cursor, 16)
					elif e["type"] == "supreme_shield_break":
						fx_library._supreme_shield_fx(actors[e["uid"]], cursor)
					elif e["type"] in ["condemn", "doom"]:
						fx_library._doom_fx(actors[e["uid"]], cursor, e["type"] == "doom")
					elif e["type"] in ["heal_block", "heal_prevented"]:
						fx_library._heal_block_fx(actors[e["uid"]], cursor, e["type"] == "heal_prevented")
				cursor += 0.2
			"transform":
				# a unit becomes another card in place (Transformar, transform_self)
				if actors.has(e["uid"]):
					fx_library._transform_fx(e["uid"], e["from"], e["card_id"], actors, old, cursor)
					cursor += FxLibraryScript.TRANSFORM_TIME
			"snowball_evolve":
				# Bola de Neve cards turning into Grande Bola de Neve: the ones in hand are visible
				var evolved_in_view := false
				for evolved_uid in e.get("uids", []):
					if actors.has(evolved_uid) and old.has(evolved_uid):
						fx_library._transform_fx(
							evolved_uid,
							old[evolved_uid]["card_id"],
							actors[evolved_uid].card_id,
							actors,
							old,
							cursor,
						)
						evolved_in_view = true
				if evolved_in_view:
					cursor += FxLibraryScript.TRANSFORM_TIME
			"snowball_devolve":
				# Grande Bola de Neve cards going back to Bola de Neve when the level resets
				var devolved_in_view := false
				for devolved_uid in e.get("uids", []):
					if actors.has(devolved_uid) and old.has(devolved_uid):
						fx_library._transform_fx(
							devolved_uid,
							old[devolved_uid]["card_id"],
							actors[devolved_uid].card_id,
							actors,
							old,
							cursor,
						)
						devolved_in_view = true
				if devolved_in_view:
					cursor += FxLibraryScript.TRANSFORM_TIME
			"slots_frozen":
				if int(e["blocked"]) > 0:
					host._toast("%s: %d espaço(s) vazio(s) congelado(s)!" % [host._pname(e["player"]), e["blocked"]])
				fx_library._freeze_slots_fx(int(e["player"]), cursor)
				cursor += 0.5
			"summon", "draw", "search_take":
				appear[e["uid"]] = cursor
				cursor += 0.1
				if short_lived.has(e["uid"]):
					# pops in with a flash and stays a moment, so the player sees it arrive before the blow lands
					var arriving: CardView = short_lived[e["uid"]]
					var pop := arriving.create_tween()
					pop.tween_interval(cursor)
					pop.tween_property(arriving, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					fx_library._embers(fx_library._center_of(arriving), cursor, elem_color(arriving.card_id).lightened(0.3), 20)
					cursor += FxLibraryScript.SHORT_LIVED_ARRIVAL_TIME
				if e["type"] == "search_take" and int(e["player"]) != viewer:
					host._toast("%s pegou %s do deck" % [host._pname(e["player"]), host._cname(e["card_id"])])
					cursor += 0.5
			"search_reveal", "look_top":
				cursor += 0.35
			"mill":
				cursor += fx_library._mill_fx(int(e["player"]), e["cards"], cursor)
			"destroy":
				# a "destroy" effect (from any card): the same X as the Leader's execution forms and crosses
				# over the unit, and only then does it die the usual way (the dissolve)
				var destroyed_view = actors.get(e["uid"])
				if destroyed_view is CardView and area_cast_active:
					# destroyed by an area cast (the flood of Julgamento): no X, the unit just goes under
					# right away, a little after the previous one
					if ghosts.has(destroyed_view) and not short_lived.has(e["uid"]) and not dissolved_early.has(destroyed_view):
						destroyed_view.dissolve(cursor, elem_color(destroyed_view.card_id).lightened(0.2), 0.75)
						Sfx.play_in("death", cursor)
						dissolved_early[destroyed_view] = true
					cursor += 0.08
				elif destroyed_view is CardView and destroy_cast_style != "":
					# destroyed by an element spell (Reduzir a Cinzas, Afogar, Desabamento Oportuno): no X, the
					# unit burns / drowns / is crushed and dissolves inside the animation
					cursor += fx_casts.destroy_cast(destroy_cast_style, destroyed_view, cursor)
					if ghosts.has(destroyed_view) and not short_lived.has(e["uid"]) and not dissolved_early.has(destroyed_view):
						destroyed_view.dissolve(cursor, FxCasts.dissolve_color_of(destroy_cast_style), 0.75)
						Sfx.play_in("death", cursor)
						dissolved_early[destroyed_view] = true
					cursor += 0.3
				elif destroyed_view is CardView:
					var cross_half_extent: Vector2 = destroyed_view.size * destroyed_view.scale * 0.55
					fx_library._cross_slash_fx(fx_library._center_of(destroyed_view), cross_half_extent, Color("#ff4040"), cursor)
					cursor += FxLibraryScript.CROSS_SLASH_SECOND_DELAY + FxLibraryScript.CROSS_SLASH_FORM_TIME + 0.12
					# a table ghost does not wait for the end of the batch: it dissolves right after the X.
					# (a stand-in summoned and killed in this batch dissolves at its own "death" event)
					if ghosts.has(destroyed_view) and not short_lived.has(e["uid"]) and not dissolved_early.has(destroyed_view):
						var destroyed_color := elem_color(destroyed_view.card_id)
						destroyed_view.dissolve(cursor, destroyed_color.lightened(0.2), 0.75)
						fx_library._embers(fx_library._center_of(destroyed_view), cursor + 0.1, destroyed_color)
						Sfx.play_in("death", cursor)
						dissolved_early[destroyed_view] = true
						cursor += 0.2
			"banish":
				# a unit banished by an element spell (Capina Seletiva, Ponto Final sem Vírgula): the vines /
				# the venom take it first, then it leaves with the usual banish look (not the death dissolve)
				var banished_view = actors.get(e["uid"])
				if banished_view is CardView and destroy_cast_style != "" and not area_cast_active:
					cursor += fx_casts.destroy_cast(destroy_cast_style, banished_view, cursor)
					if ghosts.has(banished_view) and not short_lived.has(e["uid"]) and not dissolved_early.has(banished_view):
						banished_view.banish(cursor, FxLibraryScript.BANISH_COL, 0.9)
						fx_library._banish_fx(fx_library._center_of(banished_view), fx_library.pose_of(banished_view)["w"], cursor)
						Sfx.play_in("banish", cursor)
						dissolved_early[banished_view] = true # the settle loop must not banish it again
					cursor += 0.3
				# a free-standing artifact banished to make room; other banished units go through the ghost path
				var banished_relic_uid: int = int(e["uid"])
				if e.get("relic", false) and old.has(banished_relic_uid):
					var banished_relic_ghost := fx_library._ghost(
						String(e["card_id"]),
						old[banished_relic_uid]["inst"],
						old[banished_relic_uid]["pose"],
					)
					banished_relic_ghost.z_index = 20
					banished_relic_ghost.banish(cursor, FxLibraryScript.BANISH_COL, 0.9)
					fx_library._banish_fx(
						fx_library._center_of(banished_relic_ghost),
						fx_library.pose_of(banished_relic_ghost)["w"],
						cursor,
					)
					Sfx.play_in("banish", cursor)
			"relic_destroyed":
				# Relics do not use the unit ghost path (they have no damage field), so give every
				# ordinary artifact removal a readable dissolve. Dedicated wards keep their own fx_library._ward_fx.
				var relic_uid: int = int(e["uid"])
				if not special_relic_exit_uids.has(relic_uid) and old.has(relic_uid):
					var relic_color := elem_color(String(e["card_id"]))
					var relic_ghost := fx_library._ghost(String(e["card_id"]), old[relic_uid]["inst"], old[relic_uid]["pose"])
					relic_ghost.z_index = 20
					relic_ghost.dissolve(cursor, relic_color.lightened(0.2), 0.75)
					fx_library._embers(fx_library._center_of(relic_ghost), cursor + 0.1, relic_color)
					Sfx.play_in("death", cursor)
			"return_to_hand":
				# an opponent's unit going back to their hand has no card on the table to fly (its hand is
				# face down), so its ghost makes the trip instead of dissolving as if it had died.
				# A token is deleted rather than returned: it keeps the plain dissolve.
				var bounced_ghost = actors.get(e["uid"])
				if (
						bounced_ghost is CardView and ghosts.has(bounced_ghost) and not dissolved_early.has(bounced_ghost) \
							and int(e["player"]) != viewer
					and not CardDB.card(e["card_id"]).get("token", false)
				):
					fx_library._bounce_to_enemy_hand_fx(bounced_ghost, int(e["player"]), cursor)
					dissolved_early[bounced_ghost] = true # the settle loop must not dissolve it too
					cursor += 0.25
			"death":
				if short_lived.has(e["uid"]):
					# the stand-in falls right after taking the blow, not at the end of the whole batch
					var fallen: CardView = short_lived[e["uid"]]
					var fall_t := maxf(cursor, hit_t) + 0.1
					var fall_col := elem_color(fallen.card_id)
					fallen.dissolve(fall_t, fall_col.lightened(0.2), 0.6)
					fx_library._embers(fx_library._center_of(fallen), fall_t + 0.1, fall_col)
					dissolved_early[fallen] = true
					Sfx.play_in("death", fall_t)
					cursor = maxf(cursor, fall_t + 0.3)
			"combat_damage":
				in_combat = true
			"start_turn", "end_turn", "combat_end":
				in_combat = false
			"lethal_ward":
				# Câmara de Êxtase: the blow lands on the Leader, the Chamber answers and fades away
				var ward_leader: Control = actors.get(GameState.LEADER_UID[e["player"]])
				var ward_src: int = e.get("src", 0)
				var ward_t := cursor + 0.12
				if in_combat and ward_src > 0 and actors.has(ward_src) and ward_leader != null:
					if ward_src == last_src:
						ward_t = hit_t
					else:
						fx_library._lunge(actors[ward_src], ward_leader, cursor)
						hit_t = cursor + FxLibraryScript.LUNGE_IMPACT_TIME
						ward_t = hit_t
						last_src = ward_src
						last_dst = GameState.LEADER_UID[e["player"]]
						cursor += FxLibraryScript.LUNGE_TOTAL_TIME
				var ward_ghost: CardView = null
				if old.has(e["uid"]): # the Chamber is already gone from the table: a ghost stands in for it
					ward_ghost = fx_library._ghost(old[e["uid"]]["card_id"], old[e["uid"]]["inst"], old[e["uid"]]["pose"])
					ward_ghost.z_index = 20
				fx_library._ward_fx(ward_leader, ward_ghost, ward_t, elem_color(e["card_id"]).lightened(0.3))
				if ward_leader is LeaderView:
					ward_leader.play_ward_forge(ward_t + 0.3, int(e.get("hits", 3)))
				cursor = maxf(cursor, ward_t + FxLibraryScript.WARD_FADE_DELAY + FxLibraryScript.WARD_FADE_TIME)
			"leader_hit_negated":
				# Câmara de Êxtase aftermath: the hit lands, the outermost shell shatters and the Leader takes nothing
				var negated_leader: Control = actors.get(e["uid"])
				var negated_src: int = e.get("src", 0)
				var negated_t := cursor + 0.12
				if in_combat and negated_src > 0 and actors.has(negated_src) and negated_leader != null:
					if negated_src == last_src:
						negated_t = hit_t
					else:
						fx_library._lunge(actors[negated_src], negated_leader, cursor)
						hit_t = cursor + FxLibraryScript.LUNGE_IMPACT_TIME
						negated_t = hit_t
						last_src = negated_src
						last_dst = e["uid"]
						cursor += FxLibraryScript.LUNGE_TOTAL_TIME
				else:
					cursor += 0.12
				Sfx.play_event(e, negated_t, in_combat)
				if negated_leader is LeaderView:
					negated_leader.play_ward_break(negated_t, int(e["left"]))
					fx_library._impact(negated_leader, "Anulado!", LeaderView.WARD_COL, negated_t, false)
					fx_library._embers(fx_library._center_of(negated_leader), negated_t, LeaderView.WARD_COL, 10)
				cursor = maxf(cursor, negated_t + 0.3)
			"death_prevented":
				# Baluarte Santo: same beat as the Câmara — the blow lands on the unit, the Baluarte answers and fades away
				var saved_unit_view: Control = actors.get(e["uid"])
				var saved_src: int = e.get("src", 0)
				var saved_t := cursor + 0.12
				if in_combat and saved_src > 0 and actors.has(saved_src) and saved_unit_view != null:
					if saved_src == last_src:
						saved_t = hit_t
					else:
						fx_library._lunge(actors[saved_src], saved_unit_view, cursor)
						hit_t = cursor + FxLibraryScript.LUNGE_IMPACT_TIME
						saved_t = hit_t
						last_src = saved_src
						last_dst = e["uid"]
						cursor += FxLibraryScript.LUNGE_TOTAL_TIME
				var baluarte_ghost: CardView = null
				if old.has(e["ward_uid"]): # the Baluarte is already gone from the table: a ghost stands in for it
					baluarte_ghost = fx_library._ghost(
						old[e["ward_uid"]]["card_id"],
						old[e["ward_uid"]]["inst"],
						old[e["ward_uid"]]["pose"],
					)
					baluarte_ghost.z_index = 20
				fx_library._ward_fx(saved_unit_view, baluarte_ghost, saved_t, elem_color(e["ward_card_id"]).lightened(0.3))
				cursor = maxf(cursor, saved_t + FxLibraryScript.WARD_FADE_DELAY + FxLibraryScript.WARD_FADE_TIME)
			"leader_executed":
				# a card effect killed the Leader outright: not a hit, so it gets its own animation
				var doomed_leader = views.get(e["uid"])
				if doomed_leader is LeaderView:
					var execution_color := Color("#ff4040")
					if e.has("dot"):
						execution_color = CardView.dot_badge_color(String(e["dot"]))
					var execution_end := fx_library._execution_fx(doomed_leader, int(e["hp_before"]), cursor, execution_color)
					host._leader_ko_t = maxf(host._leader_ko_t, execution_end - 0.5)
					cursor = execution_end
					if dying_leaders.has(e["uid"]):
						dying_leaders.erase(e["uid"])
						cursor = maxf(cursor, play_leader_death(doomed_leader, execution_end - 0.5))
			"damage", "shield_break", "heal":
				var dst: int = e["uid"]
				var t := cursor
				if (
					e["type"] in ["damage", "shield_break"] and in_combat
					and e.get("src", 0) > 0 and actors.has(e["src"]) and actors.has(dst)
				):
					var src: int = e["src"]
					if src == last_src or (src == last_dst and dst == last_src):
						t = hit_t
					else:
						fx_library._lunge(actors[src], actors[dst], cursor)
						hit_t = cursor + FxLibraryScript.LUNGE_IMPACT_TIME
						t = hit_t
						last_src = src
						last_dst = dst
						cursor += FxLibraryScript.LUNGE_TOTAL_TIME
				else:
					cursor += 0.12
				Sfx.play_event(e, t, in_combat)
				if leader_hp.has(dst) and e["type"] in ["damage", "heal"]:
					leader_hp[dst] += -e["amount"] if e["type"] == "damage" else e["amount"]
					var lv: LeaderView = views[dst]
					var hp_change: int = -e["amount"] if e["type"] == "damage" else e["amount"]
					var ltw := lv.create_tween()
					ltw.tween_interval(t)
					host._leader_ko_t = maxf(host._leader_ko_t, t)
					if leader_hp[dst] <= 0 and dying_leaders.has(dst):
						dying_leaders.erase(dst)
						cursor = maxf(cursor, play_leader_death(lv, t + LEADER_DEATH_LAG))
					# each hit adds its own change instead of writing a total: the hits are not always
					# shown in event order (a retaliation lands with the blow, a reflection after it),
					# and a total written late would overwrite the hits shown before it
					ltw.tween_callback(
						func():
							lv.hp += hp_change
							lv.queue_redraw(),
					)
				if unit_damage.has(dst) and e["type"] in ["damage", "heal"]:
					unit_damage[dst] += e["amount"] if e["type"] == "damage" else -e["amount"]
					var card_view: CardView = views[dst]
					var damage_change: int = e["amount"] if e["type"] == "damage" else -e["amount"]
					var card_tween := card_view.create_tween()
					card_tween.tween_interval(t)
					card_tween.tween_callback(
						func(): # adds its own change, same reason as the Leader above
							card_view.inst["damage"] += damage_change
							card_view.queue_redraw(),
					)
				if actors.has(dst):
					match e["type"]:
						"damage":
							fx_library._impact(actors[dst], "-%d" % e["amount"], Color("#ff5050"), t, true)
							if in_combat and int(e["amount"]) >= FxLibraryScript.CRUSHING_BLOW_DAMAGE and e.get("src", 0) > 0:
								fx_library._crushing_blow_fx(actors[dst], int(e["amount"]), t)
								cursor = maxf(cursor, t + 0.35) # let the blow land before the next event
						"heal":
							fx_library._impact(actors[dst], "+%d" % e["amount"], Color("#5dff8a"), t, false)
						"shield_break":
							fx_library._impact(actors[dst], "Escudo!", Color("#9fe3ff"), t, false)
	var settle := cursor + 0.1
	var board_t := settle + (0.4 if not ghosts.is_empty() else 0.0)
	for i in ghosts.size():
		var gh: CardView = ghosts[i]
		if dissolved_early.has(gh):
			continue
		if ghost_exiled[i]:
			gh.banish(settle + i * 0.06, FxLibraryScript.BANISH_COL, 0.9)
			fx_library._banish_fx(fx_library._center_of(gh), fx_library.pose_of(gh)["w"], settle + i * 0.06)
			Sfx.play_in("banish", settle + i * 0.06)
			continue
		var col := elem_color(gh.card_id)
		gh.dissolve(settle + i * 0.06, col.lightened(0.2), 0.75)
		fx_library._embers(fx_library._center_of(gh), settle + i * 0.06 + 0.1, col)
		Sfx.play_in("death", settle + i * 0.06)
	var deck_n := 0
	var board_end := board_t + 0.3 ## when the last card has finished moving into place
	# A lane that gains a unit in this batch (and loses none) slides its cards apart right away, so the
	# newcomer never lands on top of a card still standing in its slot. A lane that lost a unit waits
	# for the dissolve before closing the gap, as before.
	var lanes_with_newcomer := { }
	var lanes_with_ghost := { }
	for k in views:
		var lane_view = views[k]
		if lane_view is CardView and not hand_uids.has(k) and lane_view.inst.has("owner") and (not old.has(k) or old[k]["hand"]):
			lanes_with_newcomer[int(lane_view.inst["owner"])] = true
	for gh: CardView in ghosts:
		if gh.inst.has("owner"):
			lanes_with_ghost[int(gh.inst["owner"])] = true
	for k in views:
		var v = views[k]
		if handled.has(k) or not (v is CardView):
			continue
		var to := fx_library.pose_of(v)
		if old.has(k):
			var from: Dictionary = old[k]["pose"]
			var turns := absf(from["rot"] - to["rot"]) > 0.01 # tapping or untapping
			if turns:
				# lies down (or stands up) slowly, only after the hit is over and the card is back home
				fx_library._fly(v, from, to, board_t + FxLibraryScript.TAP_DELAY, FxLibraryScript.TAP_TIME)
				board_end = maxf(board_end, board_t + FxLibraryScript.TAP_DELAY + FxLibraryScript.TAP_TIME)
			elif from["c"].distance_to(to["c"]) > 1.0 or abs(from["w"] - to["w"]) > 1.0:
				var lane_owner := int(v.inst.get("owner", -1))
				var makes_room := lanes_with_newcomer.has(lane_owner) and not lanes_with_ghost.has(lane_owner)
				fx_library._fly(v, from, to, 0.0 if hand_uids.has(k) or makes_room else board_t, 0.28)
		elif hand_uids.has(k):
			fx_library._draw_from_deck(v, to, appear.get(k, 0.0) + 0.18 * deck_n)
			deck_n += 1
		else:
			var resting_scale: Vector2 = v.scale # a tapped unit rests smaller (see _render_board)
			v.scale = Vector2.ZERO
			var tw: Tween = v.create_tween()
			tw.tween_interval(appear.get(k, settle))
			tw.tween_property(v, "scale", resting_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return max(settle + 0.8, board_end)
