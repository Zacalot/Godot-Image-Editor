tool
extends EditorPlugin

const DEBUG = false

var docks = []
var editor = null

var tabButton

#func FindTabButton(node):
#	for n in node.get_children():
#		if n.has_method("get_text") and n.get_text() == "Image":
#			tabButton = n
#		FindTabButton(n)

func CloseEditor():
	if editor != null:
		if editor.get_ref(): #Remove if it hasn't been already.
			editor.get_ref().Close()
		editor = null
		return true

func CreateEditor(path):
	if CloseEditor():
		return false
	editor = load("res://addons/imgeditor/editor.tscn").instance()
	editor.set_name("Image Editor")
	#get_base_control().add_child(editor)
	get_editor_viewport().add_child(editor)
	editor.LoadImage(path)
	editor = weakref(editor)

func NewDock(btnText,btnFunc):
	var dock = preload("res://addons/imgeditor/open.scn").instance()
	var btn = dock.get_node("open")
	btn.connect("pressed",self,btnFunc)
	btn.set_text(btnText)
	docks.append(dock)
	return dock

func _enter_tree():
	#FindTabButton(get_node("/root/EditorNode"))
	if !DEBUG:
		CreateEditor("")
		editor.get_ref().set_hidden(true)

func OpenEditorTab():
	tabButton.emit_signal("pressed")

func get_state():
	return {}

func has_main_screen():
	return true

func get_name():
	return "Image"

func handles(object):
	var type = object.get_type()
	return (type == "ImageTexture")# or (type == "Sprite" and object.get_texture() != null)) #Missing animaated sprite.

func make_visible(visible):
	if DEBUG:
		CreateEditor("")
	else:
		editor.get_ref().set_hidden(!editor.get_ref().is_hidden())

func edit(object):
	editor.get_ref().LoadImage(GetTexturePath(object))

func btn_toolbar():
	CreateEditor("")

func GetTexturePath(obj):
	var type = obj.get_type()
	var tex
	if type != "ImageTexture":
		tex = obj.get_texture()
	else:
		tex = obj
	return tex.get_path()

func _exit_tree():
	for n in docks:
		n.queue_free()
	CloseEditor()