tool
extends Control

const DEFAULT_TAB = 1
const DEFAULT_FLOOD_CAP = 15000
const DEFAULT_SHADER_REFRESH = .5

var disabled = false

#Colors for drawing on erase canvas
const emptyColor 	= Color(0,0,0)
const usedColor 	= Color(1,1,1)

#World viewport offset
const worldDisplayOffset = Vector2(5,25)

#File Windows
const fileWindows = ["file_save","file_load"]
const fileFilter = ["*.png","*.wav"]
const audioFileFilter = ["*.tres","*.smp","*.xml","*.xsmp"]

#Color displays.
const colorDisplaySize = Vector2(30,30)

#Nodes
onready var worldView 				= get_node("viewport")#rendertarget for world.
onready var worldDisplay 			= get_node("viewDisplay")#Displays the sprite world.
onready var displayHandle 			= get_node("viewport/main")#Used for dragging the canvas around
onready var canvasDisplay 			= get_node("viewport/main/canvasDisplay")#Displays the canvas
onready var previewPaint 			= get_node("viewport/canvasOutput/previewPaint") #Previews the draw brush.
onready var canvasOutput 			= get_node("viewport/canvasOutput")#The rendertarget that combines all data
onready var colorPicker				= get_node("toolsPanel/colorPicker")
onready var grid 					= get_node("viewport/main/canvasDisplay/grid")
onready var toolsPanel 				= get_node("toolsPanel")
onready var toolbar 				= get_node("toolbar")

#Canvas Storage
var canvasList = []
var canvasSprites = []
var canvasEraseMaps = []

var curEditingCanvas
var curEditingImage
var curEditingEraseImage

#Extra Image variables
var activeImagePath = ""
var editingBounds

#Saving
var saving = false
var savePath = ""

#Selected colors
var color 			= Color(1,1,1)
var colorSecondary 	= Color(0,0,0)

#Getting color vars
var gettingColor = false
var gettingColorFunc
var gettingColorPos

#Flooding a color
var floodColor = false
var floodPos = false

#Dragging the view
var dragStartMouse = Vector2()
var dragStartNode = Vector2()
var dragging = false

#Zooming
var zoomPower 		= Vector2()
var zoomMin 		= Vector2()
var zoomMax 		= Vector2()
var zoomHideGrid	= Vector2()
var zoomLevel 		= Vector2()

#Drawing States
var erasing = false
var lineStart = false
var circleStart = false
var freeDraw = false
var freeDrawUndoGroup
var freeDrawPlaced

#Selection States
var selectionActive = false
var selectingRect = false
var selectionStart = false
var selectionEnd = false
var selectionCopiedImage = false #Stores Image() when copying selection
var selectionCopiedRect = false
var copyWasCut = false

#Draw Settings
const drawSizeMax = 100
const drawSizeMin = 1
var drawSize = Vector2(1,1)

#Shader
onready var shaderRefreshTimer = Timer.new()

#Listening/audio
var listening = false
var sampleList = []
var savingAudio = false

onready var sampleFreeTimer = Timer.new()
onready var sampleLib = SampleLibrary.new()
onready var samplePlayer = SamplePlayer.new()

#Capturing the image
var captureMode = -1
const CAPTUREMODES = {
	save = 0,
	getColor = 1,
	floodColor = 2,
	listen = 3,
	copySelection = 4
}

#Tools
const TOOLS = {
	pencil = 1,
	bucket = 2,
	select = 3
}

const toolButtons = {
	TOOLS.pencil : "btn_tool_pencil",
	TOOLS.bucket : "btn_tool_bucket",
	TOOLS.select : "btn_tool_select"
}

const toolKeys = {
	TOOLS.pencil : KEY_D,
	TOOLS.bucket : KEY_F,
	TOOLS.select : KEY_S
}

const toolButtonScaleStart = Vector2(1,1)
const toolButtonScale = Vector2(.7,.7)
const toolButtonScaleOffset = 4

var curTool

#Actions
const ACTIONS = {
	none = 0,
	drawingFree = 1,
	drawingLine = 2,
	drawingCircle = 3,
	selecting = 4
}

#Undo control.
var activeCommands = []
var removedCommands = []

func Close():
	samplePlayer.stop_all()
	FreeSamples()
	queue_free()

#Scaling editor.
const prefEditorSize = Vector2(1306,885)
onready var starts = {
	"toolsPanel" : Rect2(toolsPanel.get_pos(),toolsPanel.get_size()),
	"toolbar" : Rect2(toolbar.get_pos(),toolbar.get_size())
}
onready var prefSizeDiffs = {
	"worldView" : prefEditorSize-worldView.get_rect().size
}
var toolbarButtonStarts = {}
var prevPanelSize

var imageInfoPrefixes = {}
onready var imageInfoLabels = get_node("toolsPanel/imageInfo").get_children()

func _fixed_process(delta): #Update scale
	if !disabled:
		var mousePos = MousePos() #Update mouse position display.
		get_node("toolsPanel/imageInfo/position").set_text(imageInfoPrefixes["position"] + " %s %s" % [mousePos.x+1, mousePos.y+1])
	
	var editorPanelSize = get_parent().get_size()
	if editorPanelSize == prevPanelSize: #Only update on change.
		return
	else:
		prevPanelSize = editorPanelSize
	
	worldView.set_rect(Rect2(Vector2(),(editorPanelSize-prefSizeDiffs["worldView"]).floorf()))
	var worldViewSize = worldView.get_rect().size
	worldDisplay.set_pos(worldDisplayOffset+worldViewSize/2)
	
	toolsPanel.set_pos(worldDisplay.get_pos()+Vector2(worldViewSize.x/2,-worldViewSize.y/2))
	toolsPanel.set_size(Vector2(starts["toolsPanel"].size.x,worldViewSize.y))
	
	toolbar.set_size(Vector2((toolsPanel.get_pos().x+toolsPanel.get_size().x)-starts["toolbar"].pos.x,starts["toolbar"].size.y))
	
	for btn in toolbar.get_children():
		btn.set_pos(toolbarButtonStarts[btn.get_name()].pos*(toolbar.get_size()/starts["toolbar"].size))
		btn.set_size(toolbarButtonStarts[btn.get_name()].size*(toolbar.get_size()/starts["toolbar"].size))
	update()

var zoomNudgeMinimum
var imageStartZoom
var imageDimensionDiff

func _ready():
	if get_tree().get_edited_scene_root() != null and get_tree().get_edited_scene_root().get_name() == get_name(): #Avoid being active in this editor's scene file.
		disabled = true
		return false
	print("OPEN EDITOR(EDITOR.GD/_READY())")
	set_fixed_process(true)
	set_focus_mode(FOCUS_ALL)
	colorPicker.get_node("HBoxContainer/ToolButton").set_hidden(true) #Hide built-in color-picker.
	worldDisplay.set_texture(worldView.get_render_target_texture())
	canvasDisplay.set_texture(canvasOutput.get_render_target_texture()) #Displays the canvas in the sprite world.
	canvasDisplay.set_pos(worldView.get_rect().size/2)
	
	for n in fileWindows:
		n = get_node(n)
		n.set_size(get_size())
		n.set_filters(fileFilter)
	
	#Scaling
	for n in toolbar.get_children():
		toolbarButtonStarts[n.get_name()] = Rect2(n.get_pos(),n.get_size())
	
	#Info Panel
	for n in toolsPanel.get_node("imageInfo").get_children():
		imageInfoPrefixes[n.get_name()] = n.get_text()
	
	curTool = PressToolButton(TOOLS.pencil)
	
	var win = get_node("win_shader_edit")
	var tabs = win.get_node("tabs")
	tabs.add_tab("Vertex",load("icon - Copy.png"))
	tabs.add_tab("Fragment",load("icon - Copy.png"))
	tabs.set_current_tab(DEFAULT_TAB)
	win_shader_tab_changed(DEFAULT_TAB)
	
	win.get_node("vertexInput").connect("text_changed",self,"SetCompileCountdown")
	win.get_node("fragmentInput").connect("text_changed",self,"SetCompileCountdown")
	
	shaderRefreshTimer.connect("timeout",self,"CompileShaderCode")
	add_child(shaderRefreshTimer)
	
	#Audio
	samplePlayer.set_sample_library(sampleLib)
	sampleFreeTimer.set_wait_time(.1)
	sampleFreeTimer.connect("timeout",self,"FreeSamples")
	add_child(sampleFreeTimer)
	
	get_node("file_save_audio").set_filters(audioFileFilter)
	
	SetEnabled(false)
	
	#LoadImage("icon.png")

func _draw(): #Draw the color displays.
	if toolsPanel.is_hidden():
		return
	var pos = get_node("toolsPanel/colorDisplay").get_pos()+toolsPanel.get_pos()
	draw_rect(Rect2(pos,colorDisplaySize),color)
	draw_rect(Rect2(pos+colorDisplaySize/2,colorDisplaySize),colorSecondary)

func GetSelectionRect():
	return Rect2(selectionStart,selectionEnd-selectionStart+Vector2(1,1))#Rect2(selectionStart,MousePos()-selectionStart+Vector2(1,1))

func CopySelection(cut=false):
	if selectionActive == false or CaptureImage() == false:
		return false
	captureMode = CAPTUREMODES.copySelection
	copyWasCut = cut
	if cut:
		selectionActive = false
	selectingRect = false

func PasteClipboard():
	if typeof(selectionCopiedImage) == TYPE_IMAGE:
		selectingRect = false
		selectionActive = false
		var tex = CreateTexture(null,null,selectionCopiedImage) #Convert image to texture
		erasing = false
		CreateCommand(curEditingCanvas,self,"DrawTexture",[ImageID(),Rect2(MousePos(),selectionCopiedRect.size),tex,selectionCopiedRect,null,usedColor],["erasing"],"UndoDraw").Execute()

func _input(ev):
	if ev.is_echo():
		return
	if ev.type == InputEvent.MOUSE_BUTTON and (ev.button_index == BUTTON_MIDDLE) and MouseInCanvas():
		grab_focus()
		freeDraw = false
	
	if !is_visible() or (!has_focus()):
		return false
	var handled = false
	var type = ev.type
	var controlPressed = false
	if ev.is_pressed():
		handled = true
		
		if Input.is_key_pressed(KEY_CONTROL):
			controlPressed = true
			if Input.is_key_pressed(KEY_S):
				SaveImageQuick()
			elif Input.is_key_pressed(KEY_Z):
				Undo()
			elif Input.is_key_pressed(KEY_Y):
				Redo()
			elif Input.is_key_pressed(KEY_X):
				CopySelection(true)
			elif Input.is_key_pressed(KEY_C):
				CopySelection()
			elif Input.is_key_pressed(KEY_V):
				PasteClipboard()
			else:
				handled = false
		elif Input.is_key_pressed(KEY_X): #Control not pressed, check non-control keys
			SwapColors()
		elif Input.is_key_pressed(KEY_G):
			ToggleGrid()
		else:
			var toolKeyPressed = false
			for key in toolKeys:
				if Input.is_key_pressed(toolKeys[key]):
					PressToolButton(key)
					toolKeyPressed = true
			if !toolKeyPressed:
				handled = false
	
	var mouseInCanvas = MouseInCanvas()
	
	var zoom = GetZoom()
	if type == InputEvent.MOUSE_BUTTON:
		var leftClick = (ev.button_index == BUTTON_LEFT)
		var rightClick = (ev.button_index == BUTTON_RIGHT)
		if leftClick or rightClick:
			var click = (ev.pressed and mouseInCanvas)
			var clickPos = MousePos()
			erasing = rightClick
			var curAction = CurAction()
			if click: #If it was a click
				if curTool == TOOLS.select:
					if curAction != ACTIONS.selecting:
						selectingRect = true
						selectionActive = true
						selectionStart = clickPos
						selectionEnd = clickPos
					if rightClick == true:
						selectionActive = false
				else:
					if curAction != ACTIONS.drawingLine: #If not drawing line
						if Input.is_key_pressed(KEY_SHIFT): #Begin drawing line if shift is held
							lineStart = clickPos
						elif controlPressed:
							circleStart = clickPos
						elif Input.is_key_pressed(KEY_MENU) or Input.is_key_pressed(KEY_ALT):
							PickColor(clickPos)
						else: #Or begin free-drawing pixels.
							freeDraw = true
							freeDrawUndoGroup = []
							freeDrawPlaced = {}
							#FloodPosColor(clickPos,color)
							ApplyAction(ImageID(),null,null,true)
			else: #If it was a release
				if curAction == ACTIONS.selecting: #Stop selecting
					selectingRect = false
					selectionEnd = clickPos
				elif curAction == ACTIONS.drawingLine: #If drawing a line, stop and apply line
					ApplyAction(ImageID(),true,null,true)
				elif curAction == ACTIONS.drawingCircle:
					ApplyAction(ImageID(),true,null,true)
				freeDraw = false #Stop drawing freely
			handled = true
		elif ev.is_pressed() and mouseInCanvas: #If not a drawing action (left/right click), try to manipulate the view.
			#Zoom needs to be less powerful the more you zoom in.
			
			#var scaledSize = ((GetImageBounds().size.x*zoom)/GetImageBounds().size.x)/2
			#print("SCALE SIZE: ",scaledSize)
			var change = zoomPower#zoomPower*(zoom/imageStartZoom)
			#print(change," MOD: ",mod," ZOOM: ",zoom," ZOOM MIN: ",zoomMin)#" POWER ",zoomPower," START ZOOM ",imageStartZoom," MAX ",zoomMin)
			#print(change," ",zoom)
			if ev.button_index == BUTTON_WHEEL_DOWN:
				if controlPressed:
					SetDrawSize(drawSize.x-1)
				else:
					zoom -= change
				handled = true
			elif ev.button_index == BUTTON_WHEEL_UP:
				if controlPressed:
					SetDrawSize(drawSize.x+1)
				else:
					zoom += change
				handled = true
		if ev.button_index == BUTTON_MIDDLE:
			if mouseInCanvas and Input.is_mouse_button_pressed(BUTTON_MIDDLE): #Checking mouseInCanvas again for drag outside viewport.
				dragStartMouse = worldView.get_mouse_pos()
				dragStartNode = displayHandle.get_pos()
				dragging = true
			else:
				dragging = false
			handled = true
	elif type == InputEvent.MOUSE_MOTION:
		if dragging:
			var mousePos = worldView.get_mouse_pos()#*zoom
			var dist = dragStartMouse - mousePos
			var newPos = (dragStartNode - dist)
			
			#Clamp movement to view
			displayHandle.set_pos(newPos)
			
			ClampCanvasPos()
		elif freeDraw: #Draw Freely
			ApplyAction(ImageID(),true,null,true)
		elif selectingRect == true:
			selectionEnd = MousePos()
	
	if handled:
		get_tree().set_input_as_handled()
	
	SetZoom(zoom,true)

func SetDrawSize(value):
	value = min(drawSizeMax,max(drawSizeMin,value))
	drawSize = Vector2(value,value)
	get_node("toolbar/slider_size/display").set_text(str(value))
	get_node("toolbar/slider_size").set_val(value)

func RunDrawFunc(name,args,ignoreErasing=null,drawColor=null,eraseColorUsed=usedColor):
	if drawColor == null:
		drawColor = color
	
	var num = 0
	for n in args:
		if n == null:
			break
		num += 1
	
	if num == args.size():
		args.resize(num+1)
	if erasing and ignoreErasing == null:
		args[num] = emptyColor#Set color to erase maps "empty" color.
	else:
		args[num] = drawColor#Set color as user-selected color
		VisualServer.callv(name,args) #Draw to the image normally.
		if ignoreErasing != null: #So previewPaint doesn't mess with the erase map.
			return false
		args[num] = eraseColorUsed#Change color to the erase map's "used" color.
	args[0] = EraseMapID() #Set target to erase map
	VisualServer.call_deferred("callv",name,args) #Apply changes

func DrawPixel(rid,pos,ignoreErasing=null):
	RunDrawFunc("canvas_item_add_rect",[rid,Rect2(pos-(drawSize/2).floor(),drawSize)],ignoreErasing)

func DrawLine(rid,pos1,pos2,ignoreErasing=null):
	RunDrawFunc("canvas_item_add_line",[rid,pos1+Vector2(0,1),pos2,null,drawSize.x],ignoreErasing)

func DrawCircle(rid,pos,radius,ignoreErasing=null):
	RunDrawFunc("canvas_item_add_circle",[rid,pos,radius],ignoreErasing)

#Draws a texture to the canvas. Black pixels are erased & white pixels are unaffected by the eraseColorUsed.
func DrawTexture(rid,rect1,tex,rect2,ignoreErasing=null,eraseColorUsed=Color(1,1,1)):
	#var spr = Sprite.new() #This is required for using tex.get_rid()
	#spr.set_texture(tex)
	RunDrawFunc("canvas_item_add_texture_rect_region",[rid,rect1,tex.get_rid(),rect2],null,Color(1,1,1),eraseColorUsed)

func DrawRect(rid,rect,ignoreErasing=null):
	RunDrawFunc("canvas_item_add_rect",[rid,rect],ignoreErasing)

func ApplyAction(rid,userApplied=null,ignoreErasing=null,saveUndo=null):
	var action = CurAction()
	if action == ACTIONS.selecting:
		RunDrawFunc("canvas_item_add_rect",[rid,GetSelectionRect()],ignoreErasing,Color(1,1,1,.5))
	elif action == ACTIONS.drawingLine:
		var args = [rid,lineStart,MousePos(),ignoreErasing]
		if saveUndo != true:
			callv("DrawLine",args)
		else:
			CreateCommand(curEditingCanvas,self,"DrawLine",args,["erasing","color","drawSize"],"UndoDraw").Execute()
		if userApplied:
			lineStart = false
	elif action == ACTIONS.drawingCircle:
		var args = [rid,circleStart,MousePos().distance_to(circleStart),ignoreErasing]
		if saveUndo != true:
			callv("DrawCircle",args)
		else:
			CreateCommand(curEditingCanvas,self,"DrawCircle",args,["erasing","color","drawSize"],"UndoDraw").Execute()
		if userApplied:
			circleStart = false
	else:
		if curTool == TOOLS.pencil:
			var args = [rid,MousePos(),ignoreErasing]
			if saveUndo != true:
				callv("DrawPixel",args)
			else:
				var group = null
				if freeDraw:
					group = freeDrawUndoGroup
					if freeDrawPlaced.has(args[1]):
						return
					else:
						freeDrawPlaced[args[1]] = true
					
				CreateCommand(curEditingCanvas,self,"DrawPixel",args,["erasing","color","drawSize"],"UndoDraw",group).Execute()
		elif curTool == TOOLS.bucket:
			if saveUndo:
				FloodPosColor(MousePos(),color)

#Saves image to disk
func SaveImage(path):
	if CaptureImage() == false:
		return false
	captureMode = CAPTUREMODES.save
	savePath = path

func SaveImageQuick():
	if activeImagePath == "":
		OpenSaveWindow()
	else:
		SaveImage(activeImagePath)

#Saving audio
func SaveAudio(path):
	if CaptureImage() == false:
		return false
	captureMode = CAPTUREMODES.listen
	savePath = path
	savingAudio = true

func FloodPosColor(pos,fColor):
	FloodColor(pos,fColor)

func FloodColor(pos,fColor):
	if CaptureImage() == false:
		return false
	captureMode = CAPTUREMODES.floodColor
	floodPos = pos
	floodColor = fColor

func RetrieveColor(pos,callback,args):
	if CaptureImage() == false:
		return false
	captureMode = CAPTUREMODES.getColor
	gettingColorPos = pos
	var result = yield()
	args.append(result)
	callv(callback,args)

func PickColor(pos):
	gettingColorFunc = RetrieveColor(pos,"SetColor",[])

func Listen():
	if CaptureImage() == false:
		return false
	captureMode = CAPTUREMODES.listen

#Used in FloodFill to discover target pixels.
func FloodCheckHelper(checked,queue,image,pos,targetColor):
	if !checked.has(pos) and ValidPos(pos) and image.get_pixel(pos.x,pos.y) == targetColor:
		queue.append(pos)
		checked[pos] = true

#Standard bucket fill function.
func FloodFill(image,startPos,targetColor,newColor):
	newColor = color
	if image.get_pixel(startPos.x,startPos.y) == newColor:
		return
	
	var queue = []
	var checked = {}
	var lowest = startPos
	var highest = startPos
	var count = 0
	var fillPositions = {}
	queue.append(startPos)
	while queue.size() > 0:
		if count >= DEFAULT_FLOOD_CAP:
			break
		count += 1 
		
		var pos = queue[0]
		queue.remove(0)
		fillPositions[pos] = true
		
		FloodCheckHelper(checked,queue,image,pos+Vector2(1,0),targetColor)
		FloodCheckHelper(checked,queue,image,pos+Vector2(-1,0),targetColor)
		FloodCheckHelper(checked,queue,image,pos+Vector2(0,1),targetColor)
		FloodCheckHelper(checked,queue,image,pos+Vector2(0,-1),targetColor)
		
		if lowest.x > pos.x:
			lowest.x = pos.x
		if lowest.y > pos.y:
			lowest.y = pos.y
		
		if highest.x < pos.x:
			highest.x = pos.x
		if highest.y < pos.y:
			highest.y = pos.y
	
	var fillRect = Rect2(lowest,highest-lowest+Vector2(1,1))
	var paintData = Image(fillRect.size.width,fillRect.size.height,false,Image.FORMAT_RGBA) #Create an empty image with the dimensions of the filled pixels
	
	var fillPos = fillRect.pos #Fill the new image
	for pos in fillPositions:
		paintData.put_pixel(pos.x-fillPos.x,pos.y-fillPos.y,newColor)
	
	var tex = CreateTexture(null,null,paintData) #Convert image to texture
	var eraseColor
	if erasing: #Erasing with bucket.
		eraseColor = emptyColor
	else:
		eraseColor = usedColor
	CreateCommand(curEditingCanvas,self,"DrawTexture",[ImageID(),fillRect,tex,Rect2(Vector2(),fillRect.size),null,eraseColor],["erasing","color"],"UndoDraw").Execute()

#Starts capturing image, enabled _process to wait for capture
func CaptureImage():
	if is_processing(): #Don't capture if already in progress.
		return false
	previewPaint.set_hidden(true) #Hide the draw previewPaint until capture is done.
	canvasOutput.queue_screen_capture()
	set_process(true) #Start waiting for the capture to finish

#Used for waiting for image to capture
func _process(delta):
	var image = canvasOutput.get_screen_capture()
	if !image.empty(): #Capture has finished.
		if captureMode == CAPTUREMODES.floodColor and ValidPos(floodPos):
			var target = image.get_pixel(floodPos.x,floodPos.y)
			FloodFill(image,floodPos,target,floodColor)
			floodColor = false
		elif captureMode == CAPTUREMODES.getColor:
			gettingColorFunc.resume(image.get_pixel(gettingColorPos.x,gettingColorPos.y))
			gettingColor = false
		elif captureMode == CAPTUREMODES.save:
			activeImagePath = savePath
			image.save_png(savePath)
			var mainLoop = OS.get_main_loop()
			mainLoop.notification(mainLoop.NOTIFICATION_WM_FOCUS_IN) #Reload file tree
		elif captureMode == CAPTUREMODES.copySelection:
			selectionCopiedImage = image
			selectionCopiedRect = GetSelectionRect()
			if copyWasCut == true:
				erasing = true
				CreateCommand(curEditingCanvas,self,"DrawRect",[ImageID(),GetSelectionRect()],["erasing"],"UndoDraw").Execute()
		elif captureMode == CAPTUREMODES.listen:
				var imageData = image.get_data()
				var length = imageData.size()/2
				var sample = Sample.new()
				sample.create(1,false,length)
				sample.set_data(imageData)
				
				if !savingAudio:
					if sampleLib.has_sample("sample"):
						sampleLib.remove_sample("sample")
					sampleLib.add_sample("sample",sample)
					samplePlayer.play("sample")
				else:#Save
					ResourceSaver.save(savePath,sample)
				
				sampleList.append(sample)
				sampleFreeTimer.start()
				
		set_process(false)
		previewPaint.set_hidden(false)
		captureMode = -1

func FreeSamples():
	if !samplePlayer.is_active():
		sampleFreeTimer.stop()
		for n in sampleList:
			n.unreference()
			sampleList.remove(sampleList.find(n))

#Creates a new canvas for drawing.
func CreateCanvas(tex):
	var newCanvas = load("res://addons/imgeditor/canvas.tscn").instance()
	newCanvas.SetTexture(tex)
	
	canvasOutput.add_child(newCanvas)
	canvasList.append(newCanvas)
	return newCanvas

#Resets all canvases.
func ClearCanvases():
	for n in canvasList:
		n.queue_free()
	canvasList.clear()
	canvasSprites.clear()
	canvasEraseMaps.clear()
	activeCommands.clear()
	removedCommands.clear()

#Returns current draw action being performed.
func CurAction():
	if typeof(circleStart) != TYPE_BOOL:
		return ACTIONS.drawingCircle
	if typeof(lineStart) != TYPE_BOOL:
		return ACTIONS.drawingLine
	if freeDraw == true:
		return ACTIONS.drawingFree
	if selectionActive:
		if selectingRect == true:
			return ACTIONS.selecting
	return ACTIONS.none

#Loads an image.
func LoadImage(path):
	var tex
	if typeof(path) == TYPE_STRING:
		var pathExt = path.extension()
		if !fileFilter.has("*."+pathExt.to_lower()):
			return false
		var f = File.new()
		if !f.file_exists(path):
			return false
		activeImagePath = path
		if pathExt == "wav": #Wav file for fun
			var sample = load(path)
			var data = sample.get_data()
			var imgSize = data.size()/2#60
			var img = Image(imgSize,imgSize,false,Image.FORMAT_RGBA)
			
			var x = 0
			var y = 0
			
			for n in data:
				x += 1
				if x >= imgSize:
					x = 0
					y += 1
				if y >= imgSize:
					break
				var c = n
				img.put_pixel(x,y,n)
			
			tex = CreateTexture(null,null,img)
		else: #Image
			tex = load(path).duplicate() #uses duplicate() to fix a bug that reloads the texture upon reloading the file system.
	else:
		activeImagePath = ""
		tex = path
	
	var editingSize = tex.get_size()
	get_node("toolsPanel/imageInfo/size").set_text(imageInfoPrefixes["size"] + " %s %s" % [editingSize.x,editingSize.y])
	
	#Extra image vars
	editingBounds = Rect2(Vector2(),editingSize)
	
	SetEnabled(true)
	
	ClearCanvases()
	
	curEditingCanvas = CreateCanvas(tex)
	canvasOutput.set_rect(Rect2(Vector2(),editingSize))
	
	displayHandle.set_pos(Vector2())
	grid.update()
	
	#Tune zoom settings
	var biggestAxis
	var smallestAxis
	if editingSize.x > editingSize.y:
		biggestAxis = editingSize.x
		smallestAxis = editingSize.y
	else:
		biggestAxis = editingSize.y
		smallestAxis = editingSize.x
	
	zoomNudgeMinimum = smallestAxis/biggestAxis#editingSize/(biggestAxis/smallestAxis)#(editingSize.x+editingSize.y)#/32
	zoomNudgeMinimum = Vector2(zoomNudgeMinimum,zoomNudgeMinimum)
	var sizeSum = editingSize.x + editingSize.y
	
	var m 			= ((worldView.get_rect().size.x)/biggestAxis)/1.5 #Get good scale to fit view to
	imageStartZoom = m
	imageDimensionDiff = zoomNudgeMinimum
	zoomMax 		= (Vector2(sizeSum,sizeSum)/32) * m #Closest the camera can zoom in
	zoomPower 		= zoomNudgeMinimum #Camera zoom scroll interval.
	var mn			= max(.02,zoomPower.x * 2)
	zoomMin 		= Vector2(m,m)/3#Farthest the camera can zoom out
	zoomHideGrid	= zoomMax/6 #Zoom level the grid is hidden
	
	SetZoom(m)
	grab_focus()

#Reloads active image.
func ReloadImage():
	LoadImage(activeImagePath)

#Creates a texture with size parameters or from an image.
func CreateTexture(width,height,image=null):
	var tex = ImageTexture.new()
	var img
	if image == null:
		img = Image(width,height,false,Image.FORMAT_RGBA)
	else:
		img = image
	tex.create_from_image(img,0)
	return tex

#Color control.
#Swap Colors
func SwapColors():
	var prevColor = colorSecondary
	colorSecondary = color
	SetColor(prevColor)

#Set color of currently selected.
func SetColor(newColor):
	color = newColor
	colorPicker.set_color(newColor)
	update()

#RIDs for painting.
func ImageID():
	return curEditingCanvas.GetSurface("sprite").GetRID()

func EraseMapID():
	return curEditingCanvas.GetSurface("eraseMap").GetRID()

func SetEnabled(enabled):
	disabled = !enabled
	set_process_input(enabled)
	#set_fixed_process(enabled)

#View zoom control.
func SetZoom(zoom,doNudge=false):
	if typeof(zoom) == TYPE_REAL:
		zoom = Vector2(zoom,zoom)
	if zoom < zoomMin:
		zoom = zoomMin
	if zoom > zoomMax:
		zoom = zoomMax
	
	if zoom == GetZoom():
		return false
	
	if doNudge:
		var zoomPoint = GlobalToSpriteWorld(get_global_mouse_pos())
		displayHandle.set_pos(displayHandle.get_pos()-(zoomPoint * (zoom-zoomLevel)))
		ClampCanvasPos()
	
	zoomLevel = zoom
	canvasDisplay.set_scale(zoom)
	grid.UpdateVisibility()
	
	get_node("toolsPanel/imageInfo/zoom").set_text(imageInfoPrefixes["zoom"]+" %s%%" % (floor(((zoom.x-zoomMin.x)/(zoomMax.x-zoomMin.x))*100)))
	

func GetZoom():
	return zoomLevel

#Shader
func SetCompileCountdown():
	shaderRefreshTimer.set_wait_time(DEFAULT_SHADER_REFRESH)
	shaderRefreshTimer.start()

func CompileShaderCode(vertex=null,fragment=null):
	var win = get_node("win_shader_edit")
	var shdr = curEditingCanvas.get_material().get_shader()
	if !win.get_node("vertexInput").is_hidden():
		var code
		if fragment == null:
			code = win.get_node("vertexInput").get_text()
		else:
			code = vertex
		shdr.set_code(code,shdr.get_fragment_code(),"")
	else:
		var code
		if fragment == null:
			code = win.get_node("fragmentInput").get_text()
		else:
			code = fragment
		shdr.set_code(shdr.get_vertex_code(),code,"")
	shaderRefreshTimer.stop()

#Coordinates
#Converts global (editor) position to be relative to the sprite world.
func GlobalToSpriteWorld(pos):
	return (pos-get_global_pos()-worldDisplayOffset-displayHandle.get_pos()-canvasDisplay.get_pos())/GetZoom()

#Converts global (editor) position to be relative to image.
func GlobalToCanvas(pos):
	return RoundVector(GlobalToSpriteWorld(pos)+(GetImageBounds().size/2))

#Returns mouse position in relation to the image.
func MousePos():
	return GlobalToCanvas(get_global_mouse_pos())

#Returns if mouse is in editor viewport aka the canvas.
func MouseInCanvas():
	return worldView.get_rect().has_point(get_local_mouse_pos()-worldDisplayOffset)

#Clamps the editing canvas to the view.
func ClampCanvasPos():
	var newPos = displayHandle.get_pos()
	var maxDistance = (GetImageBounds().size/2)*GetZoom()
	
	newPos.x = min(maxDistance.x,newPos.x) #Right
	newPos.x = max(-maxDistance.x,newPos.x)
	
	newPos.y = min(maxDistance.y,newPos.y) #Down
	newPos.y = max(-maxDistance.y,newPos.y)
	
	displayHandle.set_pos(newPos)

#Check if position is valid for the image
func ValidPos(pos):
	return GetImageBounds().has_point(pos)

#Returns if the image is even in terms of size.
func EvenDimensions():
	var size = GetImageBounds().size
	return (int(size.x) % 2 == 0 and int(size.y) % 2 == 0)

#Rounds a vector off depending on whether the image is even.
func RoundVector(vec):
	if EvenDimensions():
		return vec.floor()
	else:
		return vec.snapped(Vector2(1,1))

func GetImageBounds():
	return editingBounds

#Undo control.
class Command:
	var master #Node that gets this command added to it's command list
	var caller #Node to call function
	var function #Method to run when executed
	var args #args for method when executed
	var activeCommands #Pointer for accessing the editor-wide activeCommands
	var removedCommands #Same as activeCommands
	var undoFunction#Function called when undone
	var undoGroup
	var state = {}
	
	func _init(master,caller,functionName,argArray,undoFunc,undoGrp,activeCommandList,removedCommandList):
		self.activeCommands = activeCommandList
		self.removedCommands = removedCommandList
		self.undoGroup = undoGrp
		self.caller = caller
		self.master = master
		self.undoFunction = undoFunc
		self.function = functionName
		self.args = argArray
	
	func Execute(reapply=false):
		caller.callv(function,args)
		if reapply:
			return
		undoGroup.append(self)
		Enable()
	
	func Restore():
		Enable()
		caller.call(undoFunction,self)
	
	func Enable():
		var removedPos = removedCommands.find(undoGroup)
		if removedPos != -1:
			removedCommands.remove(removedPos)
			master.removedCommands.remove(master.removedCommands.find(undoGroup))
		if activeCommands.find(undoGroup) == -1:
			activeCommands.append(undoGroup)
			master.activeCommands.append(undoGroup)
	
	func Disable():
		var activeCommandsPos = activeCommands.find(undoGroup)
		if activeCommandsPos != -1:
			activeCommands.remove(activeCommandsPos)
			master.activeCommands.remove(master.activeCommands.find(undoGroup))
			
			removedCommands.append(undoGroup)
			master.removedCommands.append(undoGroup)
		
		caller.call(undoFunction,self)
	
	func PushState(vars):
		for v in vars:
			state[v] = caller[v]
	
	func PullState():
		for v in state:
			caller[v] = state[v]
	
	#Remove from memory.
	#func Free():
	#	removedCommands.remove(removedCommands.find(undoGroup))
	#	master.removedCommands.remove(master.removedCommands.find(undoGroup))
	

func CreateCommand(target,caller,function,args,stateVars,undoFunc,undoGroup=[]):
	var cmd = Command.new(target,caller,function,args,undoFunc,undoGroup,activeCommands,removedCommands)
	cmd.PushState(stateVars)
	return cmd

func UndoDraw(command):
	var cmdMaster = command.master
	var surfaces = [cmdMaster.GetSurface("sprite"),cmdMaster.GetSurface("eraseMap")]
	for surf in surfaces:
		var rid = surf.GetRID()
		var spr = surf.GetOutput()
		var tex = spr.get_texture()
		VisualServer.canvas_item_clear(rid)
		if tex == null:
			continue
		VisualServer.canvas_item_add_texture_rect(rid,Rect2(Vector2(),tex.get_size()),tex.get_rid(),true)
	surfaces[1].ClearColor(usedColor)
	
	#Image has been reset. Reapply previous draw actions.
	var prevErasing = erasing
	var prevColor = color
	var prevSize = drawSize
	for cmd in cmdMaster.activeCommands:
		if typeof(cmd) == TYPE_ARRAY:
			for n in cmd:
				n.PullState()
				n.Execute(true)
	erasing = prevErasing
	color = prevColor
	drawSize = prevSize

func Undo():
	if activeCommands.size() <= 0:
		return
	var cmd = activeCommands[activeCommands.size()-1]
	if typeof(cmd) == TYPE_ARRAY:
		cmd[0].Disable()
	else:
		cmd.Disable()

func Redo():
	if removedCommands.size() <= 0:
		return
	var cmd = removedCommands[removedCommands.size()-1]
	cmd[0].Restore()

#Tool buttons.
func PressToolButton(t):
	if curTool == t:
		return
	var btn = get_node("toolsPanel/"+toolButtons[t])
	#btn.set_pos(btn.get_pos()+(btn.get_size()*toolButtonScale)/toolButtonScaleOffset)
	btn.set_scale(toolButtonScale)
	
	for n in toolButtons:
		if n != t:
			btn = get_node("toolsPanel/"+toolButtons[n])
			if btn.get_scale() != toolButtonScaleStart:
				#btn.set_pos(btn.get_pos()-(btn.get_size()*toolButtonScale)/toolButtonScaleOffset)
				btn.set_scale(toolButtonScaleStart)
	curTool = t
	return t

func SetBGColor(newColor):
	displayHandle.bgColor = newColor
	displayHandle.update()

func ToggleGrid():
	grid.SetActive(!grid.GetActive())
	get_node("toolbar/btn_menu_view/menu").set_item_checked(0,grid.GetActive())

func btn_newimg_create_pressed(_=null):
	var imageWindow = get_node("win_new")
	var width = int(imageWindow.get_node("input_width").get_text())
	var height = int(imageWindow.get_node("input_height").get_text())
	
	if width > 0 and height > 0:
		var tex = CreateTexture(width,height)
		LoadImage(tex)
		imageWindow.set_hidden(true)
		grab_focus()
		freeDraw = false

func OpenShaderEditor():
	var win = get_node("win_shader_edit")
	win.popup_centered()

func OpenSaveWindow():
	var window = get_node("file_save")
	window.popup_centered()
	window.set_title("Save Image")

func win_shader_tab_changed(tab):
	var win = get_node("win_shader_edit")
	if tab == 0: #Vertex shader
		win.get_node("vertexInput").set_hidden(false)
		win.get_node("fragmentInput").set_hidden(true)
	else:
		win.get_node("vertexInput").set_hidden(true)
		win.get_node("fragmentInput").set_hidden(false)

func open_btn_menu(btnName):
	var btn = get_node("toolbar/"+btnName)
	var menu = btn.get_node("menu")
	menu.popup()
	menu.set_pos(btn.get_global_pos()+Vector2(-3,22))

func menu_item_pressed(id,menuName):
	if menuName == "save":
		if id == 0: #New
			var newImageWindow = get_node("win_new")
			newImageWindow.popup_centered()
			newImageWindow.get_node("input_width").grab_focus()
		elif id == 1: #Open
			var window = get_node("file_load")
			window.popup_centered()
			window.set_title("Load Image")
		elif id == 2: #Save
			SaveImageQuick()
		elif id == 3: #Save As
			OpenSaveWindow()
		elif id == 5: #Reload
			ReloadImage()
	elif menuName == "edit":
		if id == 0: #Undo
			Undo()
		elif id == 1: #Redo
			Redo()
	elif menuName == "view":
		if id == 0: #Grid
			ToggleGrid()
		elif id == 1: #Set BG
			SetBGColor(color)
	elif menuName == "audio":
		if id == 0: # Listen
			Listen()
		elif id == 1: #Export
			var window = get_node("file_save_audio")
			window.popup_centered()
			window.set_title("Export Audio")
