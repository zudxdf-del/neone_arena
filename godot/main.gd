extends Node3D

const NET_SCRIPT := preload("res://godot/network.gd")
const WORLD_W := 1000.0
const WORLD_H := 700.0
const ARENA_SCALE := 0.018

var net: NeonNetwork
var http: HTTPRequest
var camera: Camera3D
var world_root: Node3D
var players_root: Node3D
var bullets_root: Node3D
var local_player := -1
var room_code := ""
var game_started := false
var players: Array = []
var bullets: Array = []
var obstacle_cache: Array = []
var scores := [0, 0]
var hp := 100
var ammo := 12
var mag := 12
var weapon := "pistol"
var reloading := false
var fire_down := false
var yaw := 0.0
var pitch := -0.10
var move_input := Vector2.ZERO
var look_input := Vector2.ZERO
var last_input_send := 0.0
var last_fire_send := 0.0

var menu: Control
var game_ui: Control
var nick_edit: LineEdit
var room_edit: LineEdit
var room_name_edit: LineEdit
var password_edit: LineEdit
var status_label: Label
var room_list_box: VBoxContainer
var hp_bar: ProgressBar
var ammo_label: Label
var score_label: Label
var weapon_label: Label
var crosshair: Label
var fire_button: Button

func _ready() -> void:
    _build_scene()
    _build_menu()
    _build_game_ui()
    _connect_network()
    _refresh_rooms()

func _build_scene() -> void:
    world_root = Node3D.new()
    world_root.name = "World"
    add_child(world_root)
    players_root = Node3D.new()
    players_root.name = "Players"
    world_root.add_child(players_root)
    bullets_root = Node3D.new()
    bullets_root.name = "Bullets"
    world_root.add_child(bullets_root)
    var env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#b9ddff")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#dff2ff")
    environment.ambient_light_energy = 1.25
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.environment = environment
    world_root.add_child(env)
    var sun := DirectionalLight3D.new()
    sun.light_energy = 1.8
    sun.rotation_degrees = Vector3(-55, -25, 0)
    sun.shadow_enabled = true
    world_root.add_child(sun)
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 72
    camera.near = 0.05
    camera.far = 1000
    add_child(camera)

func mat(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.72
    if emission != Color.BLACK:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 2.0
    return m

func box(size: Vector3, color: Color, glow := false) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    n.mesh = mesh
    n.material_override = mat(color, color if glow else Color.BLACK)
    return n

func _build_arena() -> void:
    for child in world_root.get_children():
        if child != players_root and child != bullets_root and not child is WorldEnvironment and not child is DirectionalLight3D:
            child.queue_free()
    var floor := box(Vector3(WORLD_W * ARENA_SCALE, 0.2, WORLD_H * ARENA_SCALE), Color("#7ec8ff"))
    floor.position = Vector3(WORLD_W * ARENA_SCALE * 0.5, -0.1, WORLD_H * ARENA_SCALE * 0.5)
    world_root.add_child(floor)
    var grid := GridMap.new()
    grid.visible = false
    # Decorative lane strips keep the bright map readable on phones.
    for i in range(1, 10):
        var strip := box(Vector3(0.025, 0.012, WORLD_H * ARENA_SCALE), Color("#a9e2ff"), true)
        strip.position = Vector3(i * WORLD_W * ARENA_SCALE / 10.0, 0.012, WORLD_H * ARENA_SCALE * 0.5)
        world_root.add_child(strip)
    for o in obstacle_cache:
        var obs := box(Vector3(float(o.w) * ARENA_SCALE, 1.6, float(o.h) * ARENA_SCALE), Color("#2563eb"), true)
        obs.position = Vector3((float(o.x) + float(o.w) / 2.0) * ARENA_SCALE, 0.8, (float(o.y) + float(o.h) / 2.0) * ARENA_SCALE)
        world_root.add_child(obs)
        var top := box(Vector3(float(o.w) * ARENA_SCALE * 1.03, 0.08, float(o.h) * ARENA_SCALE * 1.03), Color("#7ee7ff"), true)
        top.position = obs.position + Vector3(0, 0.84, 0)
        world_root.add_child(top)

func _make_player(local: bool) -> Node3D:
    var root := Node3D.new()
    var body := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.32
    capsule.height = 1.25
    body.mesh = capsule
    body.material_override = mat(Color("#00d9ff") if local else Color("#ff3b6b"), Color("#00d9ff") if local else Color("#ff1e55"))
    body.position.y = 0.75
    root.add_child(body)
    var visor := box(Vector3(0.38, 0.16, 0.08), Color("#f4ffff"), true)
    visor.position = Vector3(0, 1.15, -0.27)
    root.add_child(visor)
    var gun := box(Vector3(0.12, 0.12, 0.65), Color("#182335"))
    gun.position = Vector3(0.28, 0.62, -0.4)
    root.add_child(gun)
    var ring := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.46
    cyl.bottom_radius = 0.46
    cyl.height = 0.025
    ring.mesh = cyl
    ring.material_override = mat(Color("#7ee7ff") if local else Color("#ff6b8a"), Color("#7ee7ff") if local else Color("#ff6b8a"))
    ring.position.y = 0.02
    root.add_child(ring)
    return root

func _sync_visuals() -> void:
    while players_root.get_child_count() < players.size():
        players_root.add_child(_make_player(players_root.get_child_count() == local_player))
    while players_root.get_child_count() > players.size():
        players_root.get_child(players_root.get_child_count() - 1).queue_free()
    for i in range(players.size()):
        var p = players[i]
        var node := players_root.get_child(i) as Node3D
        node.position = Vector3(float(p.x) * ARENA_SCALE, 0, float(p.y) * ARENA_SCALE)
        node.visible = true
        node.rotation.y = -atan2(float(p.aim.y), float(p.aim.x)) + PI / 2.0 if p.has("aim") else 0.0
    for child in bullets_root.get_children(): child.queue_free()
    for b in bullets:
        var s := MeshInstance3D.new()
        var sphere := SphereMesh.new()
        sphere.radius = 0.07
        sphere.height = 0.14
        s.mesh = sphere
        s.material_override = mat(Color("#fff36a"), Color("#fff36a"))
        s.position = Vector3(float(b.x) * ARENA_SCALE, 0.72, float(b.y) * ARENA_SCALE)
        bullets_root.add_child(s)

func _build_menu() -> void:
    menu = Control.new()
    menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(menu)
    var bg := ColorRect.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.color = Color("#06101d")
    menu.add_child(bg)
    var title := Label.new()
    title.text = "NEON ARENA"
    title.position = Vector2(40, 28)
    title.add_theme_font_size_override("font_size", 42)
    title.modulate = Color("#5ce8ff")
    menu.add_child(title)
    var sub := Label.new()
    sub.text = "3D ONLINE SHOOTER • GODOT 4"
    sub.position = Vector2(44, 78)
    sub.modulate = Color("#a7c9e8")
    menu.add_child(sub)
    nick_edit = _field("Ник", Vector2(44, 130), "Игрок")
    room_name_edit = _field("Название комнаты", Vector2(44, 195), "Неоновая арена")
    password_edit = _field("Пароль (необязательно)", Vector2(44, 260), "")
    room_edit = _field("Код комнаты", Vector2(44, 325), "ABC123")
    var create := _button("СОЗДАТЬ КОМНАТУ", Vector2(44, 390), Color("#00c8ff"))
    create.pressed.connect(_create_room)
    var join := _button("ВОЙТИ В КОМНАТУ", Vector2(260, 390), Color("#ff4f8b"))
    join.pressed.connect(_join_room)
    var refresh := _button("ОБНОВИТЬ СПИСОК", Vector2(44, 455), Color("#28577e"))
    refresh.pressed.connect(_refresh_rooms)
    status_label = Label.new()
    status_label.position = Vector2(44, 515)
    status_label.text = "Подключение..."
    status_label.modulate = Color("#d8efff")
    menu.add_child(status_label)
    room_list_box = VBoxContainer.new()
    room_list_box.position = Vector2(520, 130)
    room_list_box.size = Vector2(620, 450)
    menu.add_child(room_list_box)

func _field(placeholder: String, pos: Vector2, value: String) -> LineEdit:
    var f := LineEdit.new()
    f.position = pos
    f.size = Vector2(400, 50)
    f.placeholder_text = placeholder
    f.text = value
    f.add_theme_font_size_override("font_size", 20)
    menu.add_child(f)
    return f

func _button(text: String, pos: Vector2, color: Color) -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = Vector2(200, 52)
    b.add_theme_font_size_override("font_size", 16)
    b.modulate = color
    menu.add_child(b)
    return b

func _build_game_ui() -> void:
    game_ui = Control.new()
    game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    game_ui.visible = false
    add_child(game_ui)
    hp_bar = ProgressBar.new()
    hp_bar.position = Vector2(24, 24)
    hp_bar.size = Vector2(260, 28)
    hp_bar.max_value = 100
    game_ui.add_child(hp_bar)
    ammo_label = Label.new()
    ammo_label.position = Vector2(24, 58)
    ammo_label.add_theme_font_size_override("font_size", 22)
    game_ui.add_child(ammo_label)
    weapon_label = Label.new()
    weapon_label.position = Vector2(24, 88)
    weapon_label.add_theme_font_size_override("font_size", 18)
    game_ui.add_child(weapon_label)
    score_label = Label.new()
    score_label.position = Vector2(0, 24)
    score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
    score_label.add_theme_font_size_override("font_size", 26)
    game_ui.add_child(score_label)
    crosshair = Label.new()
    crosshair.text = "+"
    crosshair.set_anchors_preset(Control.PRESET_CENTER)
    crosshair.add_theme_font_size_override("font_size", 30)
    crosshair.modulate = Color("#ffffff")
    game_ui.add_child(crosshair)
    fire_button = Button.new()
    fire_button.text = "FIRE"
    fire_button.position = Vector2(0, -155)
    fire_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    fire_button.size = Vector2(145, 125)
    fire_button.modulate = Color("#ff416c")
    fire_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    game_ui.add_child(fire_button)
    fire_button.button_down.connect(func(): fire_down = true)
    fire_button.button_up.connect(func(): fire_down = false)
    var reload_btn := Button.new()
    reload_btn.text = "RELOAD"
    reload_btn.position = Vector2(0, -290)
    reload_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    reload_btn.size = Vector2(145, 65)
    game_ui.add_child(reload_btn)
    reload_btn.pressed.connect(_reload)
    var weapon_btn := Button.new()
    weapon_btn.text = "WEAPON"
    weapon_btn.position = Vector2(165, -155)
    weapon_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    weapon_btn.size = Vector2(120, 70)
    game_ui.add_child(weapon_btn)
    weapon_btn.pressed.connect(_cycle_weapon)
    var hint := Label.new()
    hint.text = "Левый экран — движение • правый — обзор"
    hint.position = Vector2(0, -35)
    hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.modulate = Color("#d9efff")
    game_ui.add_child(hint)

func _connect_network() -> void:
    net = NET_SCRIPT.new()
    add_child(net)
    net.message_received.connect(_on_message)
    net.connected.connect(func(): status_label.text = "Сервер подключён")
    net.disconnected.connect(func(): status_label.text = "Соединение закрыто")
    net.failed.connect(func(r): status_label.text = r)
    net.connect_to_server()

func _create_room() -> void:
    if net == null: return
    net.send_message({"type":"create","name":nick_edit.text,"roomName":room_name_edit.text,"password":password_edit.text})
    status_label.text = "Создаём комнату..."

func _join_room() -> void:
    net.send_message({"type":"join","room":room_edit.text,"name":nick_edit.text,"password":password_edit.text})
    status_label.text = "Входим..."

func _refresh_rooms() -> void:
    if http == null:
        http = HTTPRequest.new()
        add_child(http)
        http.request_completed.connect(_on_rooms_http)
    http.request("https://neone-arena.layero.app/rooms?g=godot")

func _on_rooms_http(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
    if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
    var data = JSON.parse_string(body.get_string_from_utf8())
    if not data is Dictionary: return
    for c in room_list_box.get_children(): c.queue_free()
    for r in data.get("rooms", []):
        var b := Button.new()
        b.text = "%s   [%s]   %s" % [r.name, r.code, "🔒" if r.locked else "🌐"]
        b.custom_minimum_size = Vector2(580, 52)
        b.add_theme_font_size_override("font_size", 18)
        b.pressed.connect(func(): room_edit.text = r.code; password_edit.grab_focus())
        room_list_box.add_child(b)

func _on_message(m: Dictionary) -> void:
    match String(m.get("type", "")):
        "created":
            room_code = String(m.room)
            status_label.text = "Комната %s создана. Ждём второго игрока..." % room_code
        "start":
            local_player = int(m.player)
            room_code = String(m.room)
            game_started = true
            menu.visible = false
            game_ui.visible = true
            obstacle_cache = []
            _build_arena()
        "snapshot":
            players = m.get("players", [])
            bullets = m.get("bullets", [])
            obstacle_cache = m.get("obstacles", obstacle_cache)
            if game_started and obstacle_cache.size() > 0 and world_root.get_child_count() < 20:
                _build_arena()
            if local_player >= 0 and local_player < players.size():
                var me = players[local_player]
                hp = int(me.hp); ammo = int(me.ammo); mag = int(me.mag); weapon = String(me.weapon); reloading = bool(me.reloading)
            _sync_visuals()
        "round":
            scores = m.get("scores", scores)
            score_label.text = "%d  :  %d" % [scores[0], scores[1]]
        "password_required":
            status_label.text = "Нужен пароль комнаты"
        "opponent_left":
            game_started = false
            game_ui.visible = false
            menu.visible = true
            status_label.text = "Соперник вышел"
        "error":
            status_label.text = String(m.get("message", "Ошибка"))

func _reload() -> void:
    net.send_message({"type":"reload"})

func _cycle_weapon() -> void:
    var next := "smg" if weapon == "pistol" else ("shotgun" if weapon == "smg" else "pistol")
    net.send_message({"type":"weapon","weapon":next})

func _process(delta: float) -> void:
    if not game_started: return
    _update_input(delta)
    _update_camera(delta)
    hp_bar.value = hp
    ammo_label.text = "%02d / %02d" % [ammo, mag]
    weapon_label.text = weapon.to_upper() + (" • ПЕРЕЗАРЯДКА" if reloading else "")
    score_label.text = "%d  :  %d" % [scores[0], scores[1]]

func _update_input(delta: float) -> void:
    var key := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if key.length() > 0.01: move_input = key
    else: move_input = Vector2.ZERO
    var aim := Vector2(sin(yaw), cos(yaw))
    var now := Time.get_ticks_msec() / 1000.0
    if now - last_input_send > 0.045:
        last_input_send = now
        net.send_message({"type":"input","x":move_input.x,"y":move_input.y,"aimX":aim.x,"aimY":aim.y})
    if Input.is_action_pressed("fire") or fire_down:
        if now - last_fire_send > 0.06:
            last_fire_send = now
            net.send_message({"type":"shoot"})
    if Input.is_action_just_pressed("reload"):
        _reload()

func _update_camera(_delta: float) -> void:
    if local_player < 0 or local_player >= players.size(): return
    var p = players[local_player]
    var target := Vector3(float(p.x) * ARENA_SCALE, 1.25, float(p.y) * ARENA_SCALE)
    camera.position = target + Vector3(0, 0.18, 0)
    camera.rotation = Vector3(pitch, yaw, 0)

func _unhandled_input(event: InputEvent) -> void:
    if not game_started: return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= event.relative.x * 0.004
        pitch = clamp(pitch - event.relative.y * 0.003, -1.1, 1.1)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    elif event is InputEventScreenDrag:
        var size := get_viewport().get_visible_rect().size
        if event.position.x > size.x * 0.42:
            yaw -= event.relative.x * 0.006
            pitch = clamp(pitch - event.relative.y * 0.004, -1.0, 1.0)
    elif event is InputEventScreenTouch:
        var size := get_viewport().get_visible_rect().size
        if event.pressed and event.position.x < size.x * 0.42:
            move_input = Vector2.ZERO
        if event.pressed and event.position.x > size.x * 0.72:
            fire_down = true
        elif not event.pressed:
            fire_down = false

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST and game_started:
        game_started = false
        game_ui.visible = false
        menu.visible = true
        net.close()
        _connect_network()
