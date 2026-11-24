class_name ItemStack
extends Resource
## An item id and a count, for inspector-friendly recipe inputs/outputs and supply lists.

@export var item_id: StringName
@export var count := 1


static func make(item: StringName, amount: int) -> ItemStack:
	var stack := ItemStack.new()
	stack.item_id = item
	stack.count = amount
	return stack
