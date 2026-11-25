class_name DialogueDef
extends ContentDef
## A conversation graph (data/dialogues/<id>.tres). Nodes are linked by id; a choice with an empty
## next ends the conversation. Run it with DialogueRunner (logic) and DialogueView (UI).

const TYPE := &"dialogues"

@export var start := &"start"
@export var nodes: Array[DialogueNode] = []


func find_node(node_id: StringName) -> DialogueNode:
	for node in nodes:
		if node != null and node.id == node_id:
			return node
	return null


func validate() -> PackedStringArray:
	var issues := super()
	var node_ids := {}
	for node in nodes:
		if node == null:
			issues.append("empty node slot")
			continue
		if node_ids.has(node.id):
			issues.append("duplicate node '%s'" % node.id)
		node_ids[node.id] = true
	if not node_ids.has(start):
		issues.append("start node '%s' is missing" % start)
	for node in nodes:
		if node == null:
			continue
		for link in [node.next, node.else_next]:
			if link != &"" and not node_ids.has(link):
				issues.append("node '%s' links to missing node '%s'" % [node.id, link])
		for choice in node.choices:
			if choice == null:
				issues.append("node '%s' has an empty choice" % node.id)
				continue
			for next_id in [choice.next, choice.fail_next]:
				if next_id != &"" and not node_ids.has(next_id):
					issues.append("node '%s' links to missing node '%s'" % [node.id, next_id])
	return issues