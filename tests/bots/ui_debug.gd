extends BotScenario
## Prints the layout rects of the UI tree (diagnostic for anchor/size problems).


func _dump(n: Node, depth: int) -> void:
	if n is Control:
		var c := n as Control
		print("%s%s [%s] pos=%s size=%s vis=%s" % ["  ".repeat(depth), c.name, c.get_class(), c.global_position, c.size, c.visible])
	for ch in n.get_children():
		if depth < 2:
			_dump(ch, depth + 1)


func run() -> void:
	await wait(1.5)
	print("viewport=", get_viewport().get_visible_rect().size)
	_dump(get_tree().root.get_node("Main/UI"), 0)
	finish()
