extends Node3D

const NET_SCRIPT = preload("res://godot/network.gd")
const SCALE := 0.018
const WORLD_W := 1000.0
const WORLD_H := 700.0

var net: NeonNetwork
var camera: Camera3D
var arena: Node3D
var players_root: Node3D
var bullets_root: Node3D
var players: Array = []
var bullets: Array = []
var obstacles: Array = []
var local_id := -1
var game_started := false
var hp := 100
var ammo := 12
var mag := 12
var weapon := "pistol"
var reloading := false
var scores := [0, 0]
var move_input := Vector2.ZERO
var fire_down := false
var yaw := 0.0
var last_input := 0.0
var last_shot := 0.0
var joystick_id := -1
var joystick_center := Vector2.ZERO
var joystick_radius := 82.0

var menu: Control
var game_ui: Control
var room_code_edit: LineEdit
var nick_edit: LineEdit
var room_name_edit: LineEdit
var password_edit: LineEdit
var status: Label
var rooms_box: VBoxContainer
var hp_bar: ProgressBar
var ammo_label: Label
var score_label: Label
var weapon_label: Label
var fire_button: Button

func _ready() -> void:
    _create_world()
    _create_menu()
    _create_game_ui()
    _connect_server()
    _refresh_rooms()

func _material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.55
    if emission != Color.BLACK:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 2.5
    return m

func _mesh_box(size: Vector3, color: Color, glow := false) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    n.mesh = mesh
    n.material_override = _material(color, color if glow else Color.BLACK)
    return n

func _create_world() -> void:
    arena = Node3D.new()
    arena.name = "Arena"
    add_child(arena)
    players_root = Node3D.new()
    players_root.name = "Players"
    arena.add_child(players_root)
    bullets_root = Node3D.new()
    bullets_root.name = "Bullets"
    arena.add_child(bullets_root)

    var environment_node := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#a9d9ff")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#e9f7ff")
    env.ambient_light_energy = 1.7
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment_node.environment = env
    arena.add_child(environment_node)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -25, 0)
    sun.light_energy = 2.0
    sun.shadow_enabled = true
    arena.add_child(sun)

    camera = Camera3D.new()
    camera.current = true
    camera.fov = 68
    camera.near = 0.05
    camera.far = 150.0
    add_child(camera)

    _build_fixed_arena()

func _build_fixed_arena() -> void:
    # The map is built locally first, so it is visible even before the first network snapshot.
    obstacles = [
        {"x":420,"y":120,"w":160,"h":45},
        {"x":420,"y":535,"w":160,"h":45},
        {"x":150,"y":270,"w":190,"h":55},
        {"x":660,"y":375,"w":190,"h":55},
        {"x":455,"y":285,"w":90,"h":130},
        {"x":55,"y":90,"w":90,"h":90},
        {"x":855,"y":520,"w":90,"h":90}
    ]
    var floor := _mesh_box(Vector3(WORLD_W*SCALE, 0.18, WORLD_H*SCALE), Color("#77bff0"))
    floor.position = Vector3(WORLD_W*SCALE/2.0, -0.12, WORLD_H*SCALE/2.0)
    arena.add_child(floor)

    # Bright lane markings.
    for i in range(1, 10):
        var line := _mesh_box(Vector3(0.018, 0.015, WORLD_H*SCALE), Color("#bfeaff"), true)
        line.position = Vector3(i*WORLD_W*SCALE/10.0, 0.015, WORLD_H*SCALE/2.0)
        arena.add_child(line)
    for i in range(1, 7):
        var line2 := _mesh_box(Vector3(WORLD_W*SCALE, 0.015, 0.018), Color("#bfeaff"), true)
        line2.position = Vector3(WORLD_W*SCALE/2.0, 0.016, i*WORLD_H*SCALE/7.0)
        arena.add_child(line2)

    # Arena boundary.
    var border_color := Color("#1976d2")
    var north := _mesh_box(Vector3(WORLD_W*SCALE, 1.2, 0.18), border_color, true)
    north.position = Vector3(WORLD_W*SCALE/2.0, 0.6, 0.0)
    arena.add_child(north)
    var south := _mesh_box(Vector3(WORLD_W*SCALE, 1.2, 0.18), border_color, true)
    south.position = Vector3(WORLD_W*SCALE/2.0, 0.6, WORLD_H*SCALE)
    arena.add_child(south)
    var west := _mesh_box(Vector3(0.18, 1.2, WORLD_H*SCALE), border_color, true)
    west.position = Vector3(0.0, 0.6, WORLD_H*SCALE/2.0)
    arena.add_child(west)
    var east := _mesh_box(Vector3(0.18, 1.2, WORLD_H*SCALE), border_color, true)
    east.position = Vector3(WORLD_W*SCALE, 0.6, WORLD_H*SCALE/2.0)
    arena.add_child(east)

    for o in obstacles:
        _add_obstacle(o)

func _add_obstacle(o: Dictionary) -> void:
    var size := Vector3(float(o.w)*SCALE, 1.45, float(o.h)*SCALE)
    var wall := _mesh_box(size, Color("#2457b8"), true)
    wall.position = Vector3((float(o.x)+float(o.w)/2.0)*SCALE, 0.73, (float(o.y)+float(o.h)/2.0)*SCALE)
    arena.add_child(wall)
    var top := _mesh_box(Vector3(size.x*1.04, 0.09, size.z*1.04), Color("#75e8ff"), true)
    top.position = wall.position + Vector3(0, 0.78, 0)
    arena.add_child(top)

func _player_model(local: bool) -> Node3D:
    var root := Node3D.new()
    var body := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.33
    capsule.height = 1.25
    body.mesh = capsule
    body.material_override = _material(Color("#00cfff") if local else Color("#ff416c"), Color("#00bfff") if local else Color("#ff164f"))
    body.position.y = 0.72
    root.add_child(body)

    var head := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.30
    sphere.height = 0.60
    head.mesh = sphere
    head.material_override = _material(Color("#d8f5ff") if local else Color("#ffd8e1"))
    head.position.y = 1.48
    root.add_child(head)

    var visor := _mesh_box(Vector3(0.40,0.15,0.08), Color("#ffffff"), true)
    visor.position = Vector3(0,1.48,-0.27)
    root.add_child(visor)

    var gun := _mesh_box(Vector3(0.16,0.14,0.72), Color("#182536"))
    gun.position = Vector3(0.34,0.72,-0.42)
    root.add_child(gun)
    var muzzle := _mesh_box(Vector3(0.19,0.18,0.12), Color("#ffdf55"), true)
    muzzle.position = Vector3(0.34,0.72,-0.82)
    root.add_child(muzzle)

    var ring := MeshInstance3D.new()
    var ring_mesh := CylinderMesh.new()
    ring_mesh.top_radius = 0.48
    ring_mesh.bottom_radius = 0.48
    ring_mesh.height = 0.025
    ring.mesh = ring_mesh
    ring.material_override = _material(Color("#72ecff") if local else Color("#ff668b"), Color("#72ecff") if local else Color("#ff668b"))
    ring.position.y = 0.02
    root.add_child(ring)
    return root

func _sync_players() -> void:
    while players_root.get_child_count() < players.size():
        var idx := players_root.get_child_count()
        players_root.add_child(_player_model(idx == local_id))
    while players_root.get_child_count() > players.size():
        players_root.get_child(players_root.get_child_count()-1).queue_free()
    for i in range(players.size()):
        var p: Dictionary = players[i]
        var node := players_root.get_child(i) as Node3D
        node.visible = true
        node.position = Vector3(float(p.get("x",0))*SCALE, 0, float(p.get("y",0))*SCALE)
        var a: Dictionary = p.get("aim", {"x":1,"y":0})
        node.rotation.y = -atan2(float(a.get("y",0)), float(a.get("x",1)))

    for c in bullets_root.get_children():
        c.queue_free()
    for b in bullets:
        var shot := MeshInstance3D.new()
        var sphere := SphereMesh.new()
        sphere.radius = 0.075
        sphere.height = 0.15
        shot.mesh = sphere
        shot.material_override = _material(Color("#fff25a"), Color("#fff25a"))
        shot.position = Vector3(float(b.get("x",0))*SCALE, 0.78, float(b.get("y",0))*SCALE)
        bullets_root.add_child(shot)

func _create_menu() -> void:
    menu = Control.new()
    menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(menu)
    var bg := ColorRect.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.color = Color("#071522")
    menu.add_child(bg)

    var title := Label.new()
    title.text = "NEON ARENA"
    title.position = Vector2(36,28)
    title.add_theme_font_size_override("font_size",42)
    title.modulate = Color("#5ce8ff")
    menu.add_child(title)
    var sub := Label.new()
    sub.text = "GODOT 4 • 3D ONLINE ARENA"
    sub.position = Vector2(40,78)
    sub.modulate = Color("#a9d7f5")
    menu.add_child(sub)

    nick_edit = _field("Ник", Vector2(40,125), "Игрок")
    room_name_edit = _field("Название комнаты", Vector2(40,185), "Неоновая арена")
    password_edit = _field("Пароль", Vector2(40,245), "")
    room_code_edit = _field("Код комнаты", Vector2(40,305), "")

    var create := _menu_button("СОЗДАТЬ", Vector2(40,370))
    create.pressed.connect(_create_room)
    var join := _menu_button("ВОЙТИ", Vector2(250,370))
    join.pressed.connect(_join_room)
    var refresh := _menu_button("ОБНОВИТЬ", Vector2(40,435))
    refresh.pressed.connect(_refresh_rooms)

    status = Label.new()
    status.position = Vector2(40,500)
    status.size = Vector2(440,100)
    status.text = "Подключение к серверу..."
    status.modulate = Color("#d9efff")
    menu.add_child(status)

    rooms_box = VBoxContainer.new()
    rooms_box.position = Vector2(540,125)
    rooms_box.size = Vector2(650,500)
    menu.add_child(rooms_box)

func _field(placeholder: String, pos: Vector2, value: String) -> LineEdit:
    var f := LineEdit.new()
    f.position = pos
    f.size = Vector2(430,48)
    f.placeholder_text = placeholder
    f.text = value
    f.add_theme_font_size_override("font_size",19)
    menu.add_child(f)
    return f

func _menu_button(text: String, pos: Vector2) -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = Vector2(195,54)
    b.add_theme_font_size_override("font_size",17)
    b.modulate = Color("#39d7ff")
    menu.add_child(b)
    return b

func _create_game_ui() -> void:
    game_ui = Control.new()
    game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    game_ui.visible = false
    add_child(game_ui)

    hp_bar = ProgressBar.new()
    hp_bar.position = Vector2(20,20)
    hp_bar.size = Vector2(270,28)
    hp_bar.max_value = 100
    hp_bar.value = 100
    game_ui.add_child(hp_bar)

    ammo_label = Label.new()
    ammo_label.position = Vector2(20,53)
    ammo_label.add_theme_font_size_override("font_size",22)
    game_ui.add_child(ammo_label)
    weapon_label = Label.new()
    weapon_label.position = Vector2(20,82)
    weapon_label.add_theme_font_size_override("font_size",18)
    game_ui.add_child(weapon_label)

    score_label = Label.new()
    score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
    score_label.position = Vector2(0,20)
    score_label.add_theme_font_size_override("font_size",28)
    game_ui.add_child(score_label)

    var cross := Label.new()
    cross.text = "+"
    cross.set_anchors_preset(Control.PRESET_CENTER)
    cross.add_theme_font_size_override("font_size",34)
    cross.modulate = Color("#ffffff")
    game_ui.add_child(cross)

    # Joystick visuals.
    var joy := Label.new()
    joy.name = "Joystick"
    joy.text = "◉"
    joy.position = Vector2(45, -175)
    joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    joy.add_theme_font_size_override("font_size",150)
    joy.modulate = Color(0.2,0.8,1.0,0.32)
    game_ui.add_child(joy)

    fire_button = Button.new()
    fire_button.text = "FIRE"
    fire_button.position = Vector2(-170,-175)
    fire_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    fire_button.size = Vector2(150,125)
    fire_button.modulate = Color("#ff416c")
    fire_button.mouse_filter = Control.MOUSE_FILTER_STOP
    game_ui.add_child(fire_button)
    fire_button.button_down.connect(func(): fire_down=true)
    fire_button.button_up.connect(func(): fire_down=false)

    var reload_btn := Button.new()
    reload_btn.text = "RELOAD"
    reload_btn.position = Vector2(-170,-310)
    reload_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    reload_btn.size = Vector2(150,62)
    reload_btn.mouse_filter = Control.MOUSE_FILTER_STOP
    game_ui.add_child(reload_btn)
    reload_btn.pressed.connect(_reload)

    var weapon_btn := Button.new()
    weapon_btn.text = "WEAPON"
    weapon_btn.position = Vector2(-330,-175)
    weapon_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    weapon_btn.size = Vector2(140,70)
    weapon_btn.mouse_filter = Control.MOUSE_FILTER_STOP
    game_ui.add_child(weapon_btn)
    weapon_btn.pressed.connect(_cycle_weapon)

    var hint := Label.new()
    hint.text = "ЛЕВЫЙ СТИК — ДВИЖЕНИЕ     СВАЙП СПРАВА — ОБЗОР"
    hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hint.position = Vector2(0,-12)
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.modulate = Color("#e7f8ff")
    game_ui.add_child(hint)

func _connect_server() -> void:
    net = NET_SCRIPT.new()
    add_child(net)
    net.message_received.connect(_on_message)
    net.connected.connect(func(): status.text="Сервер подключён")
    net.disconnected.connect(func(): status.text="Соединение закрыто")
    net.failed.connect(func(reason): status.text=reason)
    net.connect_to_server()

func _refresh_rooms() -> void:
    if net == null: return
    var req := HTTPRequest.new()
    add_child(req)
    req.request("https://neone-arena.layero.app/rooms")
    req.request_completed.connect(func(result, code, _headers, body):
        if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
        var data = JSON.parse_string(body.get_string_from_utf8())
        if not data is Dictionary: return
        for c in rooms_box.get_children(): c.queue_free()
        for r in data.get("rooms", []):
            var b := Button.new()
            b.text = "%s   [%s]   %s" % [r.get("name","Комната"), r.get("code",""), "🔒" if r.get("locked",false) else "🌐"]
            b.custom_minimum_size = Vector2(600,52)
            b.add_theme_font_size_override("font_size",18)
            b.pressed.connect(func(): room_code_edit.text=String(r.get("code","")))
            rooms_box.add_child(b)
        req.queue_free()
    )

func _create_room() -> void:
    net.send_message({"type":"create","name":nick_edit.text,"roomName":room_name_edit.text,"password":password_edit.text})
    status.text="Создаём комнату..."

func _join_room() -> void:
    net.send_message({"type":"join","room":room_code_edit.text,"name":nick_edit.text,"password":password_edit.text})
    status.text="Входим в комнату..."

func _on_message(m: Dictionary) -> void:
    match String(m.get("type","")):
        "created":
            status.text="Комната %s создана. Ждём второго игрока..." % String(m.get("room",""))
        "start":
            local_id = int(m.get("player",0))
            game_started = true
            menu.visible = false
            game_ui.visible = true
            # Immediately show both spawn positions, even before first snapshot.
            players = [
                {"x":250,"y":350,"hp":100,"name":"Игрок 1","weapon":"pistol","ammo":12,"mag":12,"reloading":false,"aim":{"x":1,"y":0}},
                {"x":750,"y":350,"hp":100,"name":"Игрок 2","weapon":"pistol","ammo":12,"mag":12,"reloading":false,"aim":{"x":-1,"y":0}}
            ]
            _sync_players()
        "snapshot":
            players = m.get("players", [])
            bullets = m.get("bullets", [])
            if m.has("obstacles"): obstacles = m.obstacles
            _sync_players()
            if local_id >= 0 and local_id < players.size():
                var me: Dictionary = players[local_id]
                hp = int(me.get("hp",100))
                ammo = int(me.get("ammo",12))
                mag = int(me.get("mag",12))
                weapon = String(me.get("weapon","pistol"))
                reloading = bool(me.get("reloading",false))
        "round":
            scores = m.get("scores",[0,0])
        "opponent_left":
            game_started=false
            game_ui.visible=false
            menu.visible=true
            status.text="Соперник вышел из игры"
        "error":
            status.text=String(m.get("message","Ошибка"))
        "password_required":
            status.text="Нужен пароль комнаты"

func _reload() -> void:
    if game_started: net.send_message({"type":"reload"})

func _cycle_weapon() -> void:
    var next := "smg" if weapon=="pistol" else ("shotgun" if weapon=="smg" else "pistol")
    net.send_message({"type":"weapon","weapon":next})

func _process(delta: float) -> void:
    if not game_started: return
    var now := Time.get_ticks_msec()/1000.0
    var keys := Input.get_vector("move_left","move_right","move_forward","move_back")
    if keys.length() > 0.05: move_input=keys
    elif joystick_id < 0: move_input=Vector2.ZERO

    var aim := Vector2(cos(yaw), sin(yaw))
    if now-last_input > 0.045:
        last_input=now
        net.send_message({"type":"input","x":move_input.x,"y":move_input.y,"aimX":aim.x,"aimY":aim.y})
    if (Input.is_action_pressed("fire") or fire_down) and now-last_shot>0.07:
        last_shot=now
        net.send_message({"type":"shoot"})

    hp_bar.value=hp
    ammo_label.text="%02d / %02d" % [ammo,mag]
    weapon_label.text=weapon.to_upper() + (" • ПЕРЕЗАРЯДКА" if reloading else "")
    score_label.text="%d   :   %d" % [scores[0],scores[1]]
    _update_camera()

func _update_camera() -> void:
    if local_id < 0 or local_id >= players.size(): return
    var me: Dictionary=players[local_id]
    var my_pos:=Vector3(float(me.get("x",250))*SCALE,0,float(me.get("y",350))*SCALE)
    # Third-person shoulder view: the player, opponent and obstacles are actually visible.
    var forward:=Vector3(cos(yaw),0,sin(yaw))
    camera.position=my_pos-forward*4.8+Vector3(0,4.2,0)
    var look:=my_pos+forward*3.0+Vector3(0,0.8,0)
    camera.look_at(look,Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
    if not game_started: return
    if event is InputEventMouseMotion:
        yaw -= event.relative.x*0.006
    elif event is InputEventScreenDrag:
        var w:=get_viewport().get_visible_rect().size.x
        if event.position.x>w*0.42:
            yaw -= event.relative.x*0.006
    elif event is InputEventScreenTouch:
        var w:=get_viewport().get_visible_rect().size.x
        if event.pressed and event.position.x<w*0.42 and joystick_id<0:
            joystick_id=event.index
            joystick_center=event.position
            move_input=Vector2.ZERO
        elif not event.pressed and event.index==joystick_id:
            joystick_id=-1
            move_input=Vector2.ZERO
        elif event.pressed and event.position.x>w*0.78:
            fire_down=true
        elif not event.pressed and event.position.x>w*0.78:
            fire_down=false
    if event is InputEventScreenDrag and event.index==joystick_id:
        var delta:=event.position-joystick_center
        move_input=delta.limit_length(joystick_radius)/joystick_radius

func _notification(what: int) -> void:
    if what==NOTIFICATION_WM_GO_BACK_REQUEST and game_started:
        game_started=false
        game_ui.visible=false
        menu.visible=true
        net.close()
        _connect_server()
