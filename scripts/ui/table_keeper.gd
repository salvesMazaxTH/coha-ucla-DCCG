class_name TableKeeper
extends RefCounted
## Keeps pieces of the match table (cards, Leaders, piles, buttons) alive between redraws.
## A redraw asks for each piece by a name ("unit12", "hand40", "turn_plaque"...) and a signature: the data
## the piece was built from. Same signature = the piece already on the table is used again as it is, so
## it is not drawn again (rebuilding every piece on every action was most of each action's frame on a phone).
## Pieces nobody asked for in a redraw are freed at the end of it.

var _nodes := { } ## name -> node on the table
var _signatures := { } ## name -> copy of the signature the node was built from
var _claimed := { } ## names asked for in the redraw going on


## Start of a redraw: frees every table child that is not a kept piece (those are rebuilt as before).
## Like the whole old table did, they stay in the tree until the end of the frame, but are never drawn again.
func begin(layer: Control) -> void:
	_claimed.clear()
	var kept_nodes := { }
	for node_name in _nodes:
		var node: Node = _nodes[node_name]
		if is_instance_valid(node):
			kept_nodes[node] = true
	for child in layer.get_children():
		if not kept_nodes.has(child):
			child.queue_free()


## The piece called `node_name` if it is still on `layer` and was built from the same signature; it is
## moved to the end of the layer (drawn on top, as if added now). null = build a new one and call keep().
func reuse(layer: Control, node_name: String, signature: Array) -> Node:
	if _claimed.has(node_name) or not _nodes.has(node_name):
		return null
	var node: Node = _nodes[node_name]
	if not is_instance_valid(node) or node.is_queued_for_deletion() or node.get_parent() != layer:
		_forget(node_name)
		return null
	if _signatures[node_name] != signature:
		_drop(node_name)
		return null
	_claimed[node_name] = true
	layer.move_child(node, -1)
	return node


## Adds a newly built piece to `layer` and remembers it under `node_name` for the next redraw.
func keep(layer: Control, node_name: String, node: Node, signature: Array) -> void:
	if _nodes.has(node_name) and _nodes[node_name] != node:
		_drop(node_name)
	if node.get_parent() != layer:
		layer.add_child(node)
	_nodes[node_name] = node
	_signatures[node_name] = signature.duplicate(true)
	_claimed[node_name] = true


## Frees a piece reuse() gave back that does not fit after all (a card being dragged, a view whose live data
## an animation left different); the redraw then builds a new one.
func drop(node_name: String) -> void:
	if _nodes.has(node_name):
		_drop(node_name)


## End of a redraw: frees the kept pieces that were not asked for (a unit that died, a button that is gone).
func finish() -> void:
	for node_name in _nodes.keys():
		if not _claimed.has(node_name):
			_drop(node_name)


## Forgets every piece without freeing it (the layer they live in is being freed anyway).
func clear() -> void:
	_nodes.clear()
	_signatures.clear()
	_claimed.clear()


func _drop(node_name: String) -> void:
	var node: Node = _nodes[node_name]
	if is_instance_valid(node):
		node.queue_free()
	_forget(node_name)


func _forget(node_name: String) -> void:
	_nodes.erase(node_name)
	_signatures.erase(node_name)
	_claimed.erase(node_name)
