extends Node3D
class_name NeonArenaGameFinal

const NET_SCRIPT = preload("res://godot/network.gd")
const S := 0.02
const W := 1000.0
const H := 700.0
const AW := W * S
const AH := H * S
const OBS := [
    {"x":420.0,"y":120.0,"w":160.0,"h":45.0},
    {"x":420.0,"y":535.0,"w":160.0,"h":45.0},
    {"x":150.0,"y":270.0,"w":190.0,"h":55.0},
    {"x":660.0,"y":375.0,"w":190.0,"h":55.0},
    {"x":455.0,"y":285.0,"w":90.0,"h":130.0},
    {"x":55.0,"y":90.0,"w":90.0,"h":90.0},
    {"x":855.0,"y":520.0,"w":90.0,"h":90.0}
]
const COLORS := ["#25e8ff","#ff3d70","#b85cff","#ffe45c","#4dff8b","#ff8a3d","#4f8dff","#ff55d6"]

var net: NeonNetwork
var connected := false
var in_match := false
var use_server_state := false
var local_id := 0
var players: Array = []
var bullets: Array = []
var actor_nodes: Dictionary = {}
var bullet_nodes: Dictionary = {}
var arena: Node3D
var actors: Node3D
var camera: Camera3D
var menu: Control
var hud: Control
var status_label: Label
var nick_edit: LineEdit
var room_name_edit: LineEdit
var password_edit: LineEdit
var room_code_edit: LineEdit
var hp_bar: ProgressBar
var ammo_label: Label
var weapon_label: Label
var score_label: Label
var online_label: Label
var event_label: Label
var joystick_base: Panel
var joystick_knob: Panel
var joystick_vec := Vector2.ZERO
var fire_down := false
var aim := Vector2(1, 0)
var last_input := 0.0

func _ready() -> void:
    build_arena()
    build_camera()
    build_menu()
    build_hud()
    setup_network()
    menu.visible = true
    hud.visible = false

func _process(delta: float) -> void:
    animate_arena()
    if in_match:
        process_controls()
        render_players()
        render_bullets()
        update_camera(delta)
        update_hud()

func _input(event: InputEvent) -> void:
    if not in_match:
        return
    if event is InputEventScreenTouch:
        if event.pressed and Rect2(35,490,210,210).has_point(event.position):
            joystick_vec = (event.position - Vector2(140,595)) / 90.0
            joystick_vec = joystick_vec.limit_length(1.0)
        elif event.pressed and Rect2(1010,490,250,120).has_point(event.position):
            fire_down = true
        elif not event.pressed:
            fire_down = false
            joystick_vec = Vector2.ZERO
    elif event is InputEventScreenDrag:
        if Rect2(35,490,210,210).has_point(event.position):
            joystick_vec = (event.position - Vector2(140,595)) / 90.0
            joystick_vec = joystick_vec.limit_length(1.0)
        elif event.position.x > 700:
            var center := Vector2(1050, 560)
            var v := event.position - center
            if v.length() > 12.0:
                aim = Vector2(v.x, v.y).normalized()

func _create_room() -> void:
    if not connected:
        status_label.text = "СЕРВЕР НЕ ПОДКЛЮЧЕН"
        return
    var nick := nick_edit.text.strip_edges()
    if nick == "": nick = "Игрок"
    var rn := room_name_edit.text.strip_edges()
    if rn == "": rn = "Неоновая арена"
    net.send_message({"type":"create","name":nick,"roomName":rn,"password":password_edit.text,"maxPlayers":2})

func _join_room() -> void:
    if not connected:
        status_label.text = "СЕРВЕР НЕ ПОДКЛЮЧЕН"
        return
    var nick := nick_edit.text.strip_edges()
    if nick == "": nick = "Игрок"
    net.send_message({"type":"join","room":room_code_edit.text.strip_edges().to_upper(),"password":password_edit.text,"name":nick})

func setup_network() -> void:
    net = NET_SCRIPT.new()
    add_child(net)
    net.message_received.connect(_on_message)
    net.connected.connect(_on_connected)
    net.disconnected.connect(_on_disconnected)
    net.failed.connect(func(reason): status_label.text = str(reason))
    net.connect_to_server()

func _on_connected() -> void:
    connected = true
    status_label.text = "СЕРВЕР: ПОДКЛЮЧЕН"

func _on_disconnected() -> void:
    connected = false
    status_label.text = "СЕРВЕР: ОТКЛЮЧЕН"

func build_arena() -> void:
    arena = Node3D.new()
    arena.name = "Arena"
    add_child(arena)
    actors = Node3D.new()
    actors.name = "Actors"
    arena.add_child(actors)
    var env_node := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#020611")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#9bd0ff")
    env.ambient_light_energy = 1.4
    env_node.environment = env
    arena.add_child(env_node)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-60,-25,0)
    light.light_energy = 1.7
    light.shadow_enabled = true
    arena.add_child(light)
    var floor := box(Vector3(AW,0.12,AH),Color("#07192f"),Color("#0b3d70"),0.9)
    floor.position = Vector3(AW/2,-0.06,AH/2)
    arena.add_child(floor)
    for x in range(51):
        var line_x := box(Vector3(0.012,0.018,AH),Color("#12385e"),Color("#14517d"),1.2)
        line_x.position = Vector3(x*AW/50,0.01,AH/2)
        arena.add_child(line_x)
    for z in range(36):
        var line_z := box(Vector3(AW,0.018,0.012),Color("#12385e"),Color("#14517d"),1.2)
        line_z.position = Vector3(AW/2,0.012,z*AH/35)
        arena.add_child(line_z)
    build_border()
    for obstacle in OBS:
        build_obstacle(obstacle)
    for spawn in [Vector2(120,120),Vector2(880,120),Vector2(120,580),Vector2(880,580)]:
        build_spawn(spawn)
    var center := ring(Color.WHITE,0.75,0.035)
    center.position = Vector3(AW/2,0.04,AH/2)
    arena.add_child(center)

func build_border() -> void:
    var c := Color("#19d3ff")
    var north := box(Vector3(AW,0.55,0.1),c,c,4)
    north.position = Vector3(AW/2,0.26,0)
    arena.add_child(north)
    var south := box(Vector3(AW,0.55,0.1),c,c,4)
    south.position = Vector3(AW/2,0.26,AH)
    arena.add_child(south)
    var west := box(Vector3(0.1,0.55,AH),c,c,4)
    west.position = Vector3(0,0.26,AH/2)
    arena.add_child(west)
    var east := box(Vector3(0.1,0.55,AH),c,c,4)
    east.position = Vector3(AW,0.26,AH/2)
    arena.add_child(east)

func build_obstacle(o: Dictionary) -> void:
    var size := Vector3(float(o.w)*S,1.15,float(o.h)*S)
    var wall := box(size,Color("#182d53"),Color("#1c82ff"),2.5)
    wall.position = Vector3((float(o.x)+float(o.w)/2)*S,0.58,(float(o.y)+float(o.h)/2)*S)
    arena.add_child(wall)
    var cap := box(Vector3(size.x+0.08,0.08,size.z+0.08),Color("#20e0ff"),Color("#20e0ff"),5)
    cap.position = wall.position + Vector3(0,0.62,0)
    arena.add_child(cap)

func build_spawn(p: Vector2) -> void:
    var r := ring(Color("#2c8dff"),0.85,0.035)
    r.position = Vector3(p.x*S,0.04,p.y*S)
    arena.add_child(r)

func box(size: Vector3, c: Color, e: Color = Color.BLACK, energy: float = 1.0) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = c
    mat.roughness = 0.35
    if e != Color.BLACK:
        mat.emission_enabled = true
        mat.emission = e
        mat.emission_energy_multiplier = energy
    node.material_override = mat
    return node

func ring(c: Color, radius: float, height: float) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    node.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = c
    mat.emission_enabled = true
    mat.emission = c
    mat.emission_energy_multiplier = 3.0
    node.material_override = mat
    return node

func build_camera() -> void:
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 55
    camera.position = Vector3(AW/2,18,AH/2+1)
    camera.look_at(Vector3(AW/2,0,AH/2),Vector3.UP)
    add_child(camera)

func build_menu() -> void:
    menu = Control.new()
    menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(menu)
    var bg := ColorRect.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.color = Color("#020611")
    menu.add_child(bg)
    var title := Label.new()
    title.text = "NEON ARENA"
    title.position = Vector2(70,55)
    title.add_theme_font_size_override("font_size",52)
    title.modulate = Color("#49eaff")
    menu.add_child(title)
    var sub := Label.new()
    sub.text = "ONLINE // 2–8 PLAYERS"
    sub.position = Vector2(74,118)
    sub.add_theme_font_size_override("font_size",18)
    sub.modulate = Color("#7898b8")
    menu.add_child(sub)
    nick_edit = field("НИК",Vector2(70,185),"Игрок")
    room_name_edit = field("НАЗВАНИЕ КОМНАТЫ",Vector2(70,255),"Неоновая арена")
    password_edit = field("ПАРОЛЬ",Vector2(70,325),"")
    room_code_edit = field("КОД КОМНАТЫ",Vector2(70,395),"")
    var create := Button.new()
    create.text = "СОЗДАТЬ ИГРУ"
    create.position = Vector2(500,185)
    create.size = Vector2(390,72)
    create.add_theme_font_size_override("font_size",24)
    menu.add_child(create)
    var join := Button.new()
    join.text = "ПОДКЛЮЧИТЬСЯ"
    join.position = Vector2(500,275)
    join.size = Vector2(390,72)
    join.add_theme_font_size_override("font_size",24)
    menu.add_child(join)
    status_label = Label.new()
    status_label.text = "СЕРВЕР: ПОДКЛЮЧЕНИЕ..."
    status_label.position = Vector2(500,375)
    status_label.add_theme_font_size_override("font_size",18)
    status_label.modulate = Color("#6eeaff")
    menu.add_child(status_label)
    var hint := Label.new()
    hint.text = "Создатель выбирает 2 / 3 / 4 / 6 / 8 игроков.\nВ лобби видны все подключившиеся игроки."
    hint.position = Vector2(500,425)
    hint.add_theme_font_size_override("font_size",17)
    hint.modulate = Color("#8aa8c0")
    menu.add_child(hint)

func field(t: String, p: Vector2, ph: String) -> LineEdit:
    var label := Label.new()
    label.text = t
    label.position = p
    label.add_theme_font_size_override("font_size",13)
    label.modulate = Color("#6f91ad")
    menu.add_child(label)
    var edit := LineEdit.new()
    edit.placeholder_text = ph
    edit.position = p + Vector2(0,22)
    edit.size = Vector2(380,43)
    edit.add_theme_font_size_override("font_size",18)
    menu.add_child(edit)
    return edit

func build_hud() -> void:
    hud = Control.new()
    hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(hud)
    var top := ColorRect.new()
    top.size = Vector2(1280,82)
    top.color = Color(0.01,0.03,0.08,0.94)
    hud.add_child(top)
    online_label = hud_label("",Vector2(25,18),18)
    hp_bar = ProgressBar.new()
    hp_bar.position = Vector2(300,20)
    hp_bar.size = Vector2(270,30)
    hp_bar.max_value = 100
    hud.add_child(hp_bar)
    ammo_label = hud_label("",Vector2(610,15),22)
    weapon_label = hud_label("",Vector2(610,46),14)
    weapon_label.modulate = Color("#91a8bf")
    score_label = hud_label("",Vector2(900,18),20)
    event_label = hud_label("",Vector2(380,100),22)
    var crosshair := hud_label("+",Vector2(625,340),38)
    crosshair.modulate = Color.WHITE
    joystick_base = Panel.new()
    joystick_base.position = Vector2(45,500)
    joystick_base.size = Vector2(190,190)
    joystick_base.modulate = Color(0.1,0.7,1,0.25)
    hud.add_child(joystick_base)
    joystick_knob = Panel.new()
    joystick_knob.position = Vector2(110,565)
    joystick_knob.size = Vector2(60,60)
    joystick_knob.modulate = Color(0.3,1,1,0.85)
    hud.add_child(joystick_knob)
    var fire := action_button("ОГОНЬ",Vector2(1035,510),Vector2(195,80))
    fire.button_down.connect(func(): fire_down = true)
    fire.button_up.connect(func(): fire_down = false)
    var reload := action_button("ПЕРЕЗАРЯДКА",Vector2(1035,605),Vector2(195,55))
    reload.pressed.connect(func(): net.send_message({"type":"reload"}))
    var weapon := action_button("ОРУЖИЕ",Vector2(820,605),Vector2(195,55))
    weapon.pressed.connect(cycle_weapon)
    var leave := action_button("ВЫЙТИ",Vector2(45,700),Vector2(150,45))
    leave.pressed.connect(_leave_game)

func hud_label(t: String, p: Vector2, size: int) -> Label:
    var label := Label.new()
    label.text = t
    label.position = p
    label.add_theme_font_size_override("font_size",size)
    hud.add_child(label)
    return label

func action_button(t: String, p: Vector2, s: Vector2) -> Button:
    var button := Button.new()
    button.text = t
    button.position = p
    button.size = s
    button.add_theme_font_size_override("font_size",18)
    hud.add_child(button)
    return button

func process_controls() -> void:
    var movement := joystick_vec
    if Input.is_key_pressed(KEY_W): movement.y -= 1
    if Input.is_key_pressed(KEY_S): movement.y += 1
    if Input.is_key_pressed(KEY_A): movement.x -= 1
    if Input.is_key_pressed(KEY_D): movement.x += 1
    if movement.length() > 1: movement = movement.normalized()
    if Input.is_key_pressed(KEY_LEFT): aim = Vector2(-1,0)
    if Input.is_key_pressed(KEY_RIGHT): aim = Vector2(1,0)
    if Input.is_key_pressed(KEY_UP): aim = Vector2(0,-1)
    if Input.is_key_pressed(KEY_DOWN): aim = Vector2(0,1)
    var now := Time.get_ticks_msec()/1000.0
    if now - last_input > 0.05:
        net.send_message({"type":"input","x":movement.x,"y":movement.y,"aimX":aim.x,"aimY":aim.y})
        last_input = now
    if fire_down or Input.is_key_pressed(KEY_SPACE):
        net.send_message({"type":"shoot"})
    joystick_knob.position = Vector2(110,565) + joystick_vec*58

func cycle_weapon() -> void:
    var current := weapon_label.text.to_lower()
    var next := "pistol"
    if "pistol" in current: next = "smg"
    elif "smg" in current: next = "shotgun"
    net.send_message({"type":"weapon","weapon":next})

func render_players() -> void:
    for i in range(players.size()):
        var p = players[i]
        if p == null:
            if actor_nodes.has(i):
                actor_nodes[i].queue_free()
                actor_nodes.erase(i)
            continue
        if not actor_nodes.has(i):
            actor_nodes[i] = make_player(i)
        var node: Node3D = actor_nodes[i]
        node.position = Vector3(float(p.get("x",500))*S,0,float(p.get("y",350))*S)
        var hp_node: MeshInstance3D = node.get_node("HP")
        hp_node.scale.x = max(0.02,float(p.get("hp",0))/100.0)
        var name_node: Label3D = node.get_node("Name")
        var prefix := "YOU  " if i == local_id else "P%d  " % (i+1)
        name_node.text = prefix + str(p.get("name","Игрок")) + "  %dHP" % int(p.get("hp",0))
        var a = p.get("aim",{"x":1,"y":0})
        var gun: Node3D = node.get_node("Gun")
        gun.rotation.y = -atan2(float(a.get("y",0)),float(a.get("x",1)))

func make_player(i: int) -> Node3D:
    var root := Node3D.new()
    root.name = "P%d" % i
    actors.add_child(root)
    var color := Color(COLORS[i % COLORS.size()])
    var body := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.34
    capsule.height = 1.45
    body.mesh = capsule
    body.position.y = 0.82
    body.material_override = player_material(color)
    root.add_child(body)
    var head := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.31
    sphere.height = 0.62
    head.mesh = sphere
    head.position.y = 1.62
    head.material_override = player_material(Color("#e9faff"))
    root.add_child(head)
    var visor := box(Vector3(0.46,0.14,0.1),Color.WHITE,color,4)
    visor.position = Vector3(0,1.62,-0.28)
    root.add_child(visor)
    var glow := ring(color,0.58,0.035)
    glow.position.y = 0.05
    root.add_child(glow)
    var gun := box(Vector3(0.18,0.18,0.85),Color("#101827"),Color("#fff06a"),4)
    gun.position = Vector3(0.42,0.85,-0.42)
    gun.name = "Gun"
    root.add_child(gun)
    var hp := box(Vector3(0.95,0.07,0.06),Color("#30101b"))
    hp.position = Vector3(0,2.08,0)
    hp.name = "HP"
    root.add_child(hp)
    var name_label := Label3D.new()
    name_label.name = "Name"
    name_label.position = Vector3(0,2.4,0)
    name_label.font_size = 24
    name_label.outline_size = 7
    name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    name_label.modulate = color
    root.add_child(name_label)
    return root

func player_material(c: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = c
    mat.metallic = 0.3
    mat.roughness = 0.25
    mat.emission_enabled = true
    mat.emission = c
    mat.emission_energy_multiplier = 1.8
    return mat

func render_bullets() -> void:
    var alive := {}
    for bullet in bullets:
        alive[int(bullet.get("id",0))] = true
    for id in bullet_nodes.keys():
        if not alive.has(int(id)):
            bullet_nodes[id].queue_free()
            bullet_nodes.erase(id)
    for bullet in bullets:
        var id := int(bullet.get("id",0))
        if not bullet_nodes.has(id):
            var node := box(Vector3(0.08,0.08,0.42),Color("#fff36a"),Color("#fff36a"),8)
            arena.add_child(node)
            bullet_nodes[id] = node
        var bullet_node: Node3D = bullet_nodes[id]
        bullet_node.position = Vector3(float(bullet.get("x",0))*S,0.65,float(bullet.get("y",0))*S)

func update_camera(delta: float) -> void:
    var min_x := W
    var max_x := 0.0
    var min_y := H
    var max_y := 0.0
    var count := 0
    for p in players:
        if p == null: continue
        min_x = min(min_x,float(p.get("x",500)))
        max_x = max(max_x,float(p.get("x",500)))
        min_y = min(min_y,float(p.get("y",350)))
        max_y = max(max_y,float(p.get("y",350)))
        count += 1
    if count == 0: return
    var center := Vector3((min_x+max_x)*S/2,0,(min_y+max_y)*S/2)
    var span := max((max_x-min_x)*S,(max_y-min_y)*S)+7.0
    var height := clamp(11.0+span*0.55,11.0,24.0)
    var target := center + Vector3(0,height,span*0.28)
    camera.position = camera.position.lerp(target,1.0-exp(-delta*3.5))
    camera.look_at(center,Vector3.UP)

func update_hud() -> void:
    var count := 0
    for p in players:
        if p != null: count += 1
    online_label.text = "MATCH  //  %d PLAYERS" % count
    if local_id >= 0 and local_id < players.size() and players[local_id] != null:
        var p = players[local_id]
        hp_bar.value = float(p.get("hp",0))
        ammo_label.text = "%02d / %02d" % [int(p.get("ammo",0)),int(p.get("mag",12))]
        weapon_label.text = str(p.get("weapon","pistol")).to_upper()
        score_label.text = "SCORE  %d" % int(p.get("score",0))

func animate_arena() -> void:
    var pulse := 2.7 + sin(Time.get_ticks_msec()/180.0)*0.7
    for node in arena.get_children():
        if node is MeshInstance3D and node.material_override is StandardMaterial3D:
            var mat := node.material_override as StandardMaterial3D
            if mat.emission_enabled and mat.emission_energy_multiplier > 2.0:
                mat.emission_energy_multiplier = pulse

func _on_message(data: Dictionary) -> void:
    match str(data.get("type","")):
        "created":
            local_id = int(data.get("player",0))
        "start":
            local_id = int(data.get("player",local_id))
            players = data.get("players",[])
            bullets.clear()
            in_match = true
            use_server_state = true
            menu.visible = false
            hud.visible = true
            event_label.text = "БОЙ НАЧАЛСЯ — %d ИГРОКОВ" % int(data.get("playerCount",2))
        "snapshot":
            players = data.get("players",[])
            bullets = data.get("bullets",[])
        "round":
            event_label.text = "ПОБЕДИТЕЛЬ: ИГРОК %d" % (int(data.get("winner",0))+1)
        "opponent_left":
            event_label.text = "ИГРОК ВЫШЕЛ ИЗ КОМНАТЫ"
        "error":
            status_label.text = str(data.get("message","Ошибка"))

func _leave_game() -> void:
    net.close()
    connected = false
    in_match = false
    use_server_state = false
    players.clear()
    bullets.clear()
    menu.visible = true
    hud.visible = false
    for node in actor_nodes.values(): node.queue_free()
    actor_nodes.clear()
    for node in bullet_nodes.values(): node.queue_free()
    bullet_nodes.clear()
