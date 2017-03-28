tool
extends Sprite

const combinerShader = """
uniform texture eraseMap;
vec4 eraseMapTex = tex(eraseMap,UV);
COLOR.a *= min(1,ceil(eraseMapTex.r+eraseMapTex.g+eraseMapTex.b));
"""

const emptyColor 	= Color(0,0,0)
const usedColor 	= Color(1,1,1)

var activeCommands = []
var removedCommands = []

var surfaces = {}
var canvas

func _ready():
	if canvas != null:
		set_texture(GetTexture()) #Set base of canvas (Sprite) texture to the viewport of the output.

func FindSurfaces():
	surfaces = {}
	canvas = get_node("canvas")
	for n in get_node("canvas").get_children():
		if n.get_type() == "Viewport":
			surfaces[n.get_name()] = surface.new(n)

func SetTexture(tex):
	FindSurfaces()
	SetSize(tex.get_size())
	
	GetSurface("sprite").display.set_texture(tex)
	
	var output = get_node("canvas/surfaceCombiner")
	output.get_material().set_shader_param("eraseMap",GetSurface("eraseMap").GetTexture())
	output.set_texture(GetSurface("sprite").GetTexture())
	#output.get_material().get_shader().set_code("",combinerShader,"")
	
	GetSurface("eraseMap").display.set_texture(tex)
	GetSurface("eraseMap").ClearColor(usedColor)
	
	#Debug erase map.
	#output.get_material().get_shader().set_code("",frag,"") #Clear shader code.
	#output.set_texture(GetSurface("eraseMap").GetTexture())#Display erase map.

func GetSurface(name):
	return surfaces[name]

func SetSize(size):
	canvas.set_rect(Rect2(Vector2(),size))
	for n in surfaces:
		surfaces[n].SetSize(size)

func GetTexture():
	return canvas.get_render_target_texture()

class surface:
	var node
	var display
	
	func _init(classNode):
		node = classNode
		display = node.get_node("image")
	
	func GetOutput():
		return display
	
	func GetTexture():
		return node.get_render_target_texture()
	
	func GetRID():
		return display.get_canvas_item()
	
	func ClearColor(color):
		VisualServer.call_deferred("canvas_item_add_rect",GetRID(),GetBounds(),color)
	
	func GetBounds():
		return node.get_rect()
	
	func SetSize(size):
		node.set_rect(Rect2(Vector2(),size))

