tool
#This node displays the canvas in the "Sprite world"
#It also is unaffected by the canvas' resolution, so it draws the grid below.
extends Node2D

onready var master = get_parent().get_parent()
onready var window = get_parent().get_parent().get_parent().get_parent()
onready var disabled = window.disabled

var active = true
var gridSize = 1

func UpdateVisibility():
	set_hidden(window.GetZoom() < window.zoomHideGrid/gridSize)

func SetActive(status):
	if active != status:
		active = status
		update()

func GetActive():
	return active

func SetSize(size):
	if typeof(size) == TYPE_STRING:
		size = int(size)
	if size < 1:
		return false
	gridSize = size
	UpdateVisibility()
	update()

func _draw():
	if disabled:
		return false
	if !active:
		return false
	var size = (get_parent().get_texture().get_size()/2)
	var offset = Vector2()
	
	if !window.EvenDimensions():
		offset = -Vector2(.5,.5)
		size = Vector2(ceil(size.x),ceil(size.y))+offset
	else:
		size = size.floor()
	
	var width = size.x
	var height = size.y
	var x = -width
	var y = -height
	var color = master.bgColor
	color = Color(1-color.r,1-color.g,1-color.b,1)
	
	while x <= width:
		draw_line(Vector2(x,-height)+offset,Vector2(x,height)+offset,color)
		x += gridSize
	
	while y <= height:
		draw_line(Vector2(-width,y)+offset,Vector2(width,y)+offset,color)
		y += gridSize





