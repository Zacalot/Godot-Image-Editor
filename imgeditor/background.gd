tool
#The master node for the "Sprite world." This is used to moved the canvasDisplay (or other children) around when dragged.
#The background color for the canvas is also drawn here.
extends Node2D

var bgColor = Color(.3,.3,.3)

func _draw():
	var rect = get_parent().get_rect()
	rect.pos = -rect.size
	rect.size *= get_parent().get_parent().GetZoom()
	draw_rect(rect,bgColor)
	get_node("canvasDisplay/grid").update()