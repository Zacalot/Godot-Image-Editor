tool
extends Node2D

onready var master = get_parent().get_parent().get_parent()

func _ready():
	#if master.disabled:
	#	return false
	set_process(true)

func _process(delta):
	if master.disabled:
		#set_process(false)
		return false
	update()

func _draw():
	if master.disabled or !master.has_focus():
		return false
	master.ApplyAction(get_canvas_item(),null,true)
	if master.selectionActive == true:#typeof(master.selectionEnd) != TYPE_BOOL:
		master.RunDrawFunc("canvas_item_add_rect",[get_canvas_item(),master.GetSelectionRect()],true,Color(1,1,1,.5))
#Rect2(master.selectionStart,master.selectionEnd-master.selectionStart+Vector2(1,1))