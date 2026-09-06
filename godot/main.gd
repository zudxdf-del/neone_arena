extends Node3D

# NEON ARENA — complete Godot 4 rebuild.
# This version deliberately does not depend on the network to show a complete game scene.
# A local training opponent is always visible; server snapshots replace it when online.

const NET_SCRIPT = preload("res://godot/network.gd")
const S := 0.02
const WORLD_W := 1000.0
const WORLD_H := 700.0
const ARENA_W := WORLD_W * S
const ARENA_H := WORLD_H * S
const PLAYER_Y := 0.0
const BOT_ID := 1

const OBSTACLES := [
    {"x": 420.0, "y": 120.0, "w": 160.0, "h": 45.0},
    {"x": 420.0, "y": 535.0, "w": 160.0, "h": 45.0},
    {"x": 150.0, "y": 270.0, "w": 190.0, "h": 55.0},
    {"x": 660.0, "y": 375.0, "w": 190.0, "h": 55.0},
    {"x": 455.0, "y": 285.0, "w": 90.0, "h": 130.0},
    {"x": 55.0, "y": 90.0, "w": 90.0, "h": 90.0},
    {"x": 855.0, "y": 520.0, "w": 90.0, "h": 90.0}
]

var arena: Node3D
var actors: Node3D
var fx: Node3D
var camera: Camera3D
var net: NeonNetwork

var menu: Control
var hud: Control
var room_code_edit: LineEdit
var nick_edit: LineEdit
var room_name_edit: LineEdit
var password_edit: LineEdit
var status_label: Label
var rooms_box: VBoxContainer
var hp_bar: ProgressBar
var ammo_label: Label
var weapon_label: Label
var score_label: Label
var online_label: Label
var event_label: Label
var crosshair: Label
var fire_button: Button
var reload_button: Button
var weapon_button: Button
var leave_button: Button
var joystick_base: Panel
var joystick_knob: Panel

var local_id := 0
var connected := false
var in_match := false
var fire_down := false
var reload_down := false
var joystick_touch := -1
var joystick_start := Vector2.ZERO
var joystick_vec := Vector2.ZERO
var aim_angle := 0.0
var camera_yaw := 0.0
var last_server_send := 0.0
var local_shot_timer := 0.0
var bot_shot_timer := 1.2
var bot_phase := 0.0
var flash_timer := 0.0
var round_time := 0.0

var local_hp := 100.0
var local_score := 0
var local_ammo := 12
var local_mag := 12
var local_weapon := "pistol"
var local_reloading := false
var local_pos := Vector2(250, 350)
var bot_pos := Vector2(750, 350)
var bot_hp := 100.0
var bot_score := 0

var server_players: Array = []
var server_bullets: Array = []
var use_server_state := false
var visual_players: Array[Node3D] = []

func _ready() -> void:
    _build_arena()
    _build_camera()
    _build_menu()
    _build_hud()
    _setup_network()
    _start_local_match()

func _process(delta: float) -> void:
    _animate_world(delta)
    if in_match:
        _process_local_match(delta)
        _process_bot(delta)
        _process_network_input(delta)
        _update_camera(delta)
        _update_hud()
    else:
        _update_menu_animation(delta)

func _build_arena() -> void:
    arena = Node3D.new()
    arena.name = "Arena"
    add_child(arena)
    actors = Node3D.new()
    actors.name = "Actors"
    arena.add_child(actors)
    fx = Node3D.new()
    fx.name = "FX"
    arena.add_child(fx)

    var env_node := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#030816")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#8ac8ff")
    env.ambient_light_energy = 1.25
    env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
    env_node.environment = env
    arena.add_child(env_node)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-65, -25, 0)
    sun.light_color = Color("#b9ddff")
    sun.light_energy = 1.35
    sun.shadow_enabled = true
    arena.add_child(sun)

    var floor := _box(Vector3(ARENA_W, 0.12, ARENA_H), Color("#08182d"), Color("#0a2e55"), 0.6)
    floor.position = Vector3(ARENA_W / 2.0, -0.08, ARENA_H / 2.0)
    arena.add_child(floor)

    # Grid is deliberately oversized and bright enough to read on a phone.
    for x in range(0, 51):
        var gx := _box(Vector3(0.012, 0.018, ARENA_H), Color("#12345a"), Color("#12345a"), 1.2)
        gx.position = Vector3(x * ARENA_W / 50.0, 0.01, ARENA_H / 2.0)
        arena.add_child(gx)
    for z in range(0, 36):
        var gz := _box(Vector3(ARENA_W, 0.018, 0.012), Color("#12345a"), Color("#12345a"), 1.2)
        gz.position = Vector3(ARENA_W / 2.0, 0.012, z * ARENA_H / 35.0)
        arena.add_child(gz)

    _build_border()
    for o in OBSTACLES:
        _build_obstacle(o)
    _build_spawn_pad(Vector2(250, 350), Color("#00eaff"))
    _build_spawn_pad(Vector2(750, 350), Color("#ff2f69"))
    _build_center_marker()

func _build_border() -> void:
    var c := Color("#19bfff")
    var e := Color("#00aaff")
    var north := _box(Vector3(ARENA_W, 0.65, 0.12), c, e, 3.0)
    north.position = Vector3(ARENA_W/2.0, 0.28, 0)
    arena.add_child(north)
    var south := _box(Vector3(ARENA_W, 0.65, 0.12), c, e, 3.0)
    south.position = Vector3(ARENA_W/2.0, 0.28, ARENA_H)
    arena.add_child(south)
    var west := _box(Vector3(0.12, 0.65, ARENA_H), c, e, 3.0)
    west.position = Vector3(0, 0.28, ARENA_H/2.0)
    arena.add_child(west)
    var east := _box(Vector3(0.12, 0.65, ARENA_H), c, e, 3.0)
    east.position = Vector3(ARENA_W, 0.28, ARENA_H/2.0)
    arena.add_child(east)

func _build_obstacle(o: Dictionary) -> void:
    var size := Vector3(float(o.w) * S, 1.25, float(o.h) * S)
    var center := Vector3((float(o.x)+float(o.w)/2.0)*S, 0.62, (float(o.y)+float(o.h)/2.0)*S)
    var wall := _box(size, Color("#182b54"), Color("#167cff"), 1.8)
    wall.position = center
    arena.add_child(wall)
    var cap := _box(Vector3(size.x + 0.05, 0.08, size.z + 0.05), Color("#22d9ff"), Color("#22d9ff"), 4.0)
    cap.position = center + Vector3(0, 0.67, 0)
    arena.add_child(cap)
    var edge := _box(Vector3(size.x + 0.01, 0.08, 0.06), Color("#ffffff"), Color("#42eaff"), 4.0)
    edge.position = center + Vector3(0, 0.12, -size.z/2.0)
    arena.add_child(edge)

func _build_spawn_pad(p: Vector2, color: Color) -> void:
    var pad := _box(Vector3(3.1, 0.035, 2.5), Color(color, 0.10), color, 2.0)
    pad.position = Vector3(p.x*S, 0.02, p.y*S)
    arena.add_child(pad)
    var ring := _ring(color, 1.55, 0.035)
    ring.position = Vector3(p.x*S, 0.045, p.y*S)
    arena.add_child(ring)

func _build_center_marker() -> void:
    var ring := _ring(Color("#ffffff"), 1.0, 0.025)
    ring.position = Vector3(ARENA_W/2.0, 0.04, ARENA_H/2.0)
    arena.add_child(ring)
    for i in range(4):
        var beam := _box(Vector3(0.06, 0.025, 0.7), Color("#ffffff"), Color("#ffffff"), 2.0)
        beam.position = Vector3(ARENA_W/2.0, 0.05, ARENA_H/2.0)
        beam.rotation.y = i * PI / 2.0
        arena.add_child(beam)

func _box(size: Vector3, color: Color, emission: Color = Color.BLACK, energy := 1.0) -> MeshInstance3D:
    var m := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    m.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.42
    if emission != Color.BLACK:
        mat.emission_enabled = true
        mat.emission = emission
        mat.emission_energy_multiplier = energy
    m.material_override = mat
    return m

func _ring(color: Color, radius: float, height: float) -> MeshInstance3D:
    var m := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    m.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(color, 0.9)
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = 2.5
    m.material_override = mat
    return m

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 52
    camera.near = 0.05
    camera.far = 100
    add_child(camera)
    camera.position = Vector3(10.0, 15.5, 12.0)
    camera.look_at(Vector3(10, 0, 7), Vector3.UP)

func _make_player(is_local: bool) -> Node3D:
    var root := Node3D.new()
    root.name = "LOCAL_PLAYER" if is_local else "ENEMY_PLAYER"

    var shadow := _box(Vector3(0.95, 0.025, 0.95), Color("#000000"), Color("#000000"), 0)
    shadow.position.y = 0.03
    root.add_child(shadow)

    var body := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.34
    capsule.height = 1.45
    body.mesh = capsule
    body.position.y = 0.82
    body.material_override = _player_mat(Color("#00e8ff") if is_local else Color("#ff356f"))
    root.add_child(body)

    var armor := _box(Vector3(0.68, 0.32, 0.40), Color("#dffaff") if is_local else Color("#ffe1e8"), Color("#80f5ff") if is_local else Color("#ff7195"), 1.6)
    armor.position = Vector3(0, 0.83, -0.13)
    root.add_child(armor)

    var head := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.31
    sphere.height = 0.62
    head.mesh = sphere
    head.position.y = 1.62
    head.material_override = _player_mat(Color("#b9f6ff") if is_local else Color("#ffd0db"))
    root.add_child(head)

    var visor := _box(Vector3(0.46, 0.16, 0.10), Color("#ffffff"), Color("#ffffff"), 3.0)
    visor.position = Vector3(0, 1.62, -0.28)
    root.add_child(visor)

    var gun := _box(Vector3(0.18, 0.18, 0.78), Color("#111827"), Color("#1c2f4c"), 0.8)
    gun.position = Vector3(0.42, 0.85, -0.46)
    root.add_child(gun)
    var barrel := _box(Vector3(0.22, 0.22, 0.18), Color("#fff06a"), Color("#fff06a"), 5.0)
    barrel.position = Vector3(0.42, 0.85, -0.91)
    root.add_child(barrel)

    var ring := _ring(Color("#00eaff") if is_local else Color("#ff356f"), 0.55, 0.035)
    ring.position.y = 0.05
    root.add_child(ring)

    var hp_bg := _box(Vector3(1.0, 0.08, 0.06), Color("#160a12"), Color.BLACK, 0)
    hp_bg.position = Vector3(0, 2.05, 0)
    root.add_child(hp_bg)
    var hp_fg := _box(Vector3(0.96, 0.055, 0.065), Color("#4dff91") if is_local else Color("#ff4775"), Color("#4dff91") if is_local else Color("#ff4775"), 2.5)
    hp_fg.position = Vector3(0, 2.05, -0.01)
    hp_fg.name = "HP"
    root.add_child(hp_fg)

    var label := Label3D.new()
    label.text = "YOU" if is_local else "ENEMY"
    label.position = Vector3(0, 2.35, 0)
    label.font_size = 32
    label.outline_size = 8
    label.modulate = Color("#5cf4ff") if is_local else Color("#ff5d82")
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    root.add_child(label)
    return root

func _player_mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.metallic = 0.35
    m.roughness = 0.28
    m.emission_enabled = true
    m.emission = c
    m.emission_energy_multiplier = 1.8
    return m

func _start_local_match() -> void:
    in_match = true
    menu.visible = false
    hud.visible = true
    local_pos = Vector2(250, 350)
    bot_pos = Vector2(750, 350)
    local_hp = 100
    bot_hp = 100
    local_ammo = 12
    local_weapon = "pistol"
    local_score = 0
    bot_score = 0
    _clear_actors()
    _ensure_visual_player(0, true)
    _ensure_visual_player(1, false)
    _sync_local_visuals()
    event_label.text = "БОЕВОЙ ПОЛИГОН • ВТОРОЙ ИГРОК УЖЕ НА КАРТЕ"

func _clear_actors() -> void:
    for c in actors.get_children():
        c.queue_free()
    visual_players.clear()

func _ensure_visual_player(index: int, is_local: bool) -> void:
    while visual_players.size() <= index:
        var node := _make_player(visual_players.size() == local_id)
        actors.add_child(node)
        visual_players.append(node)
    visual_players[index].visible = true
    visual_players[index].name = "YOU" if is_local else "ENEMY"

func _sync_local_visuals() -> void:
    if visual_players.size() < 2:
        return
    visual_players[0].position = Vector3(local_pos.x*S, PLAYER_Y, local_pos.y*S)
    visual_players[0].rotation.y = -aim_angle
    visual_players[1].position = Vector3(bot_pos.x*S, PLAYER_Y, bot_pos.y*S)
    var ba := atan2(local_pos.y-bot_pos.y, local_pos.x-bot_pos.x)
    visual_players[1].rotation.y = -ba
    _set_hp_visual(visual_players[0], local_hp)
    _set_hp_visual(visual_players[1], bot_hp)

func _set_hp_visual(node: Node3D, hp: float) -> void:
    var bar := node.get_node_or_null("HP") as MeshInstance3D
    if bar:
        bar.scale.x = max(0.02, hp / 100.0)
        bar.position.x = -(1.0 - hp / 100.0) * 0.48

func _process_local_match(delta: float) -> void:
    round_time += delta
    local_shot_timer = max(0.0, local_shot_timer - delta)
    flash_timer = max(0.0, flash_timer - delta)
    var move := _keyboard_move()
    if joystick_vec.length() > 0.05:
        move = joystick_vec
    if move.length() > 1.0:
        move = move.normalized()
    var speed := 260.0
    var next := local_pos + move * speed * delta
    if not _blocked(next, 18.0):
        local_pos = next
    local_pos.x = clamp(local_pos.x, 28.0, WORLD_W-28.0)
    local_pos.y = clamp(local_pos.y, 28.0, WORLD_H-28.0)
    if fire_down:
        _local_fire()
    if reload_down:
        _reload_local()
    _sync_local_visuals()

func _keyboard_move() -> Vector2:
    var v := Vector2.ZERO
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1.0
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1.0
    return v

func _process_bot(delta: float) -> void:
    if use_server_state:
        return
    bot_phase += delta
    bot_shot_timer -= delta
    var target := local_pos
    var dir := target - bot_pos
    if dir.length() > 190:
        var move := dir.normalized()
        move += Vector2(cos(bot_phase*1.7), sin(bot_phase*1.3)) * 0.28
        var next := bot_pos + move.normalized() * 92.0 * delta
        if not _blocked(next, 18.0):
            bot_pos = next
    if bot_shot_timer <= 0:
        bot_shot_timer = 1.0 + fmod(abs(sin(bot_phase)), 1.5)
        _bot_fire()
    _sync_local_visuals()

func _local_fire() -> void:
    if local_shot_timer > 0 or local_reloading:
        return
    if local_ammo <= 0:
        _reload_local()
        return
    local_ammo -= 1
    local_shot_timer = 0.26 if local_weapon == "pistol" else 0.10
    _spawn_shot_fx(local_pos, aim_angle, Color("#5cf4ff"))
    var dir := Vector2(cos(aim_angle), sin(aim_angle))
    var to_bot := bot_pos - local_pos
    if dir.dot(to_bot.normalized()) > 0.94 and _line_clear(local_pos, bot_pos):
        bot_hp -= 25.0 if local_weapon == "pistol" else 12.0
        _hit_fx(bot_pos, Color("#ff386c"))
        if bot_hp <= 0:
            local_score += 1
            event_label.text = "УНИЧТОЖЕНИЕ • ВТОРОЙ ИГРОК ВОЗРОДИЛСЯ"
            bot_hp = 100
            bot_pos = Vector2(750, 350)

func _bot_fire() -> void:
    var dir := (local_pos - bot_pos).normalized()
    var angle := atan2(dir.y, dir.x)
    _spawn_shot_fx(bot_pos, angle, Color("#ff3d71"))
    if _line_clear(bot_pos, local_pos) and dir.dot((local_pos-bot_pos).normalized()) > 0.96:
        local_hp -= 15
        _hit_fx(local_pos, Color("#ff3d71"))
        if local_hp <= 0:
            bot_score += 1
            local_hp = 100
            local_pos = Vector2(250, 350)
            event_label.text = "ТЫ УНИЧТОЖЕН • ВОЗРОЖДЕНИЕ"

func _spawn_shot_fx(origin: Vector2, angle: float, color: Color) -> void:
    var root := Node3D.new()
    root.position = Vector3(origin.x*S, 0.85, origin.y*S)
    fx.add_child(root)
    var tracer := _box(Vector3(0.035, 0.035, 0.75), color, color, 5.0)
    tracer.position.z = -0.38
    tracer.rotation.y = -angle
    root.add_child(tracer)
    var light := OmniLight3D.new()
    light.light_color = color
    light.light_energy = 5.0
    light.omni_range = 3.5
    root.add_child(light)
    get_tree().create_timer(0.08).timeout.connect(root.queue_free)

func _hit_fx(pos: Vector2, color: Color) -> void:
    var root := Node3D.new()
    root.position = Vector3(pos.x*S, 0.8, pos.y*S)
    fx.add_child(root)
    for i in range(6):
        var p := _box(Vector3(0.07, 0.07, 0.20), color, color, 4.0)
        p.rotation.y = i * PI / 3.0
        p.position = Vector3(cos(i*PI/3.0)*0.35, 0, sin(i*PI/3.0)*0.35)
        root.add_child(p)
    get_tree().create_timer(0.18).timeout.connect(root.queue_free)

func _reload_local() -> void:
    if local_reloading or local_ammo == local_mag:
        return
    local_reloading = true
    event_label.text = "ПЕРЕЗАРЯДКА..."
    get_tree().create_timer(0.9).timeout.connect(_finish_reload)

func _finish_reload() -> void:
    local_reloading = false
    local_ammo = local_mag
    event_label.text = "ГОТОВО"

func _blocked(p: Vector2, r: float) -> bool:
    if p.x < r or p.y < r or p.x > WORLD_W-r or p.y > WORLD_H-r:
        return true
    for o in OBSTACLES:
        if p.x > o.x-r and p.x < o.x+o.w+r and p.y > o.y-r and p.y < o.y+o.h+r:
            return true
    return false

func _line_clear(a: Vector2, b: Vector2) -> bool:
    var steps := max(1, int(a.distance_to(b) / 12.0))
    for i in range(1, steps):
        var p := a.lerp(b, float(i)/steps)
        if _blocked(p, 5.0):
            return false
    return true

func _update_camera(delta: float) -> void:
    if visual_players.size() < 2:
        return
    var target := Vector3(local_pos.x*S, 0.4, local_pos.y*S)
    var desired := target + Vector3(5.6*sin(camera_yaw), 9.8, 5.6*cos(camera_yaw))
    camera.position = camera.position.lerp(desired, min(1.0, delta*7.0))
    camera.look_at(target, Vector3.UP)

func _animate_world(delta: float) -> void:
    var pulse := 1.0 + sin(Time.get_ticks_msec()/220.0)*0.12
    for child in arena.get_children():
        if child is MeshInstance3D and child.material_override is StandardMaterial3D:
            var mat := child.material_override as StandardMaterial3D
            if mat.emission_enabled and mat.emission_energy_multiplier > 2.0:
                mat.emission_energy_multiplier = clamp(mat.emission_energy_multiplier * 0.98 + pulse*0.08, 1.5, 5.5)

func _build_menu() -> void:
    menu = Control.new()
    menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(menu)
    var bg := ColorRect.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.color = Color("#030814")
    menu.add_child(bg)

    var title := Label.new()
    title.text = "NEON ARENA"
    title.position = Vector2(48, 38)
    title.add_theme_font_size_override("font_size", 56)
    title.modulate = Color("#50ecff")
    menu.add_child(title)
    var sub := Label.new()
    sub.text = "2 PLAYER • ONLINE • GODOT 4"
    sub.position = Vector2(52, 102)
    sub.add_theme_font_size_override("font_size", 20)
    sub.modulate = Color("#8eb9dc")
    menu.add_child(sub)

    nick_edit = _input("НИК", "Игрок", Vector2(50, 160))
    room_name_edit = _input("КОМНАТА", "NEON ROOM", Vector2(50, 220))
    password_edit = _input("ПАРОЛЬ", "", Vector2(50, 280))
    room_code_edit = _input("КОД КОМНАТЫ", "", Vector2(50, 340))

    var create := _button("СОЗДАТЬ ИГРУ", Vector2(50, 415), Vector2(235, 58), Color("#00dfff"))
    create.pressed.connect(_create_room)
    var join := _button("ПОДКЛЮЧИТЬСЯ", Vector2(300, 415), Vector2(235, 58), Color("#ff3f75"))
    join.pressed.connect(_join_room)
    var refresh := _button("СПИСОК КОМНАТ", Vector2(50, 490), Vector2(235, 50), Color("#7aa9ff"))
    refresh.pressed.connect(_refresh_rooms)
    var training := _button("ИГРАТЬ ОДНОМУ", Vector2(300, 490), Vector2(235, 50), Color("#63ffad"))
    training.pressed.connect(_start_local_match)

    status_label = Label.new()
    status_label.position = Vector2(50, 560)
    status_label.size = Vector2(485, 80)
    status_label.text = "Онлайн-сервер: подключение...\nТренировочный бой доступен сразу."
    status_label.modulate = Color("#b8d8ee")
    menu.add_child(status_label)

    var panel := Panel.new()
    panel.position = Vector2(600, 145)
    panel.size = Vector2(610, 500)
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#071326")
    style.border_color = Color("#164d77")
    style.set_border_width_all(2)
    style.corner_radius_top_left = 18
    style.corner_radius_top_right = 18
    style.corner_radius_bottom_left = 18
    style.corner_radius_bottom_right = 18
    panel.add_theme_stylebox_override("panel", style)
    menu.add_child(panel)
    var map_title := Label.new()
    map_title.text = "АРЕНА READY"
    map_title.position = Vector2(635, 175)
    map_title.add_theme_font_size_override("font_size", 30)
    map_title.modulate = Color("#ffffff")
    menu.add_child(map_title)
    var info := Label.new()
    info.text = "✓ 7 настоящих укрытий\n✓ 2 бойца на карте\n✓ оружие + перезарядка\n✓ попадания и HP\n✓ онлайн комнаты\n✓ управление телефоном\n\nВ этой версии сцена не пустая даже без сервера:\nсразу запускается полноценный бой против второго игрока."
    info.position = Vector2(635, 225)
    info.add_theme_font_size_override("font_size", 21)
    info.modulate = Color("#bfe8ff")
    menu.add_child(info)

func _input(placeholder: String, value: String, pos: Vector2) -> LineEdit:
    var e := LineEdit.new()
    e.position = pos
    e.size = Vector2(485, 48)
    e.placeholder_text = placeholder
    e.text = value
    e.add_theme_font_size_override("font_size", 18)
    menu.add_child(e)
    return e

func _button(text: String, pos: Vector2, size: Vector2, accent: Color) -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = size
    b.add_theme_font_size_override("font_size", 17)
    b.modulate = accent
    menu.add_child(b)
    return b

func _build_hud() -> void:
    hud = Control.new()
    hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud.visible = false
    add_child(hud)

    var top := Panel.new()
    top.position = Vector2(18, 18)
    top.size = Vector2(330, 122)
    top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud.add_child(top)

    hp_bar = ProgressBar.new()
    hp_bar.position = Vector2(32, 32)
    hp_bar.size = Vector2(290, 24)
    hp_bar.max_value = 100
    hp_bar.value = 100
    hud.add_child(hp_bar)

    ammo_label = _hud_label("12 / 12", Vector2(32, 64), 28)
    weapon_label = _hud_label("PISTOL", Vector2(180, 67), 19)
    score_label = _hud_label("0 : 0", Vector2(570, 20), 34)
    score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
    online_label = _hud_label("● TRAINING", Vector2(32, 100), 15)
    event_label = _hud_label("БОЙ НАЧАЛСЯ", Vector2(0, 70), 18)
    event_label.set_anchors_preset(Control.PRESET_CENTER_TOP)

    crosshair = _hud_label("✦", Vector2(0, 0), 34)
    crosshair.set_anchors_preset(Control.PRESET_CENTER)
    crosshair.modulate = Color("#ffffff")

    fire_button = _hud_button("FIRE", Vector2(-175, -190), Vector2(150, 130), Color("#ff356f"))
    fire_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    fire_button.button_down.connect(func(): fire_down = true)
    fire_button.button_up.connect(func(): fire_down = false)

    reload_button = _hud_button("RELOAD", Vector2(-340, -85), Vector2(145, 58), Color("#42e8ff"))
    reload_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    reload_button.pressed.connect(_reload_local)

    weapon_button = _hud_button("WEAPON", Vector2(-185, -85), Vector2(145, 58), Color("#8e79ff"))
    weapon_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    weapon_button.pressed.connect(_switch_weapon)

    leave_button = _hud_button("MENU", Vector2(-115, 20), Vector2(95, 42), Color("#ffffff"))
    leave_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    leave_button.pressed.connect(_leave_match)

    joystick_base = Panel.new()
    joystick_base.position = Vector2(48, -190)
    joystick_base.size = Vector2(155, 155)
    joystick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    joystick_base.modulate = Color(0.1, 0.7, 1.0, 0.22)
    joystick_base.mouse_filter = Control.MOUSE_FILTER_STOP
    hud.add_child(joystick_base)
    joystick_base.gui_input.connect(_joystick_input)

    joystick_knob = Panel.new()
    joystick_knob.size = Vector2(62, 62)
    joystick_knob.position = Vector2(46, 46)
    joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
    joystick_knob.modulate = Color(0.3, 0.9, 1.0, 0.75)
    joystick_base.add_child(joystick_knob)

func _hud_label(text: String, pos: Vector2, size: int) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.add_theme_font_size_override("font_size", size)
    l.modulate = Color("#eafaff")
    hud.add_child(l)
    return l

func _hud_button(text: String, pos: Vector2, size: Vector2, c: Color) -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = size
    b.add_theme_font_size_override("font_size", 18)
    b.modulate = c
    b.mouse_filter = Control.MOUSE_FILTER_STOP
    hud.add_child(b)
    return b

func _joystick_input(e: InputEvent) -> void:
    if e is InputEventScreenTouch:
        if e.pressed:
            joystick_touch = e.index
            joystick_start = e.position
            _set_joystick(e.position)
        elif e.index == joystick_touch:
            joystick_touch = -1
            joystick_vec = Vector2.ZERO
            joystick_knob.position = Vector2(46,46)
    elif e is InputEventScreenDrag and e.index == joystick_touch:
        _set_joystick(e.position)

func _set_joystick(pos: Vector2) -> void:
    var center := joystick_base.size / 2.0
    var v := pos - joystick_base.global_position - center
    if v.length() > 58:
        v = v.normalized() * 58
    joystick_vec = v / 58.0
    joystick_knob.position = center - joystick_knob.size/2.0 + v

func _switch_weapon() -> void:
    if local_weapon == "pistol":
        local_weapon = "smg"
        local_mag = 30
        local_ammo = min(local_ammo, local_mag)
    else:
        local_weapon = "pistol"
        local_mag = 12
        local_ammo = min(local_ammo, local_mag)

func _update_hud() -> void:
    hp_bar.value = local_hp
    ammo_label.text = ("RELOADING..." if local_reloading else "%d / %d" % [local_ammo, local_mag])
    weapon_label.text = local_weapon.to_upper()
    score_label.text = "%d  :  %d" % [local_score, bot_score]
    online_label.text = "● ONLINE" if connected and use_server_state else "● TRAINING"
    if flash_timer > 0:
        crosshair.modulate = Color("#fff35c")
    else:
        crosshair.modulate = Color("#ffffff")

func _setup_network() -> void:
    net = NET_SCRIPT.new()
    add_child(net)
    net.message_received.connect(_on_server_message)
    net.connected.connect(_on_server_connected)
    net.disconnected.connect(_on_server_disconnected)
    net.failed.connect(_on_server_failed)
    net.connect_to_server("wss://neone-arena.layero.app")

func _on_server_connected() -> void:
    connected = true
    status_label.text = "Онлайн-сервер: подключен.\nМожно создать комнату или играть в тренировке."

func _on_server_disconnected() -> void:
    connected = false
    use_server_state = false

func _on_server_failed(reason: String) -> void:
    connected = false
    status_label.text = "Онлайн временно недоступен.\nТренировочный бой работает локально."

func _on_server_message(data: Dictionary) -> void:
    var t := str(data.get("type", ""))
    if t in ["snapshot", "state", "game_state"]:
        var ps = data.get("players", [])
        if ps is Array and ps.size() >= 2:
            server_players = ps
            server_bullets = data.get("bullets", [])
            use_server_state = true
            _apply_server_state()
    elif t in ["room_created", "created", "room_joined", "joined"]:
        var code := str(data.get("code", data.get("roomCode", "")))
        room_code_edit.text = code
        in_match = true
        menu.visible = false
        hud.visible = true
        event_label.text = "ОНЛАЙН-КОМНАТА СОЗДАНА • КОД %s" % code
    elif t == "rooms":
        _show_rooms(data.get("rooms", []))
    elif t in ["error", "room_error"]:
        status_label.text = str(data.get("message", "Ошибка сервера"))

func _apply_server_state() -> void:
    if server_players.size() < 2:
        return
    for i in range(2):
        var p: Dictionary = server_players[i]
        var pos := Vector2(float(p.get("x",0)), float(p.get("y",0)))
        if i == local_id:
            local_pos = pos
            local_hp = float(p.get("hp",100))
            local_ammo = int(p.get("ammo",local_ammo))
            local_mag = int(p.get("mag",local_mag))
            local_weapon = str(p.get("weapon",local_weapon))
            local_reloading = bool(p.get("reloading",false))
            local_score = int(p.get("score",local_score))
            var a: Dictionary = p.get("aim", {"x":1,"y":0})
            aim_angle = atan2(float(a.get("y",0)), float(a.get("x",1)))
        else:
            bot_pos = pos
            bot_hp = float(p.get("hp",100))
            bot_score = int(p.get("score",bot_score))
    _sync_local_visuals()

func _process_network_input(delta: float) -> void:
    if not connected or not in_match:
        return
    last_server_send -= delta
    if last_server_send > 0:
        return
    last_server_send = 0.05
    var move := _keyboard_move()
    if joystick_vec.length() > 0.05:
        move = joystick_vec
    net.send_message({
        "type":"input",
        "move":{"x":move.x,"y":move.y},
        "aim":{"x":cos(aim_angle),"y":sin(aim_angle)},
        "fire":fire_down,
        "reload":local_reloading,
        "weapon":local_weapon
    })

func _create_room() -> void:
    if not connected:
        event_label.text = "СЕРВЕР НЕ ПОДКЛЮЧЕН • ИГРАЕМ В ТРЕНИРОВКЕ"
        _start_local_match()
        return
    net.send_message({"type":"create_room","name":room_name_edit.text,"password":password_edit.text,"nick":nick_edit.text})

func _join_room() -> void:
    if not connected:
        _start_local_match()
        return
    net.send_message({"type":"join_room","code":room_code_edit.text.strip_edges().to_upper(),"password":password_edit.text,"nick":nick_edit.text})

func _refresh_rooms() -> void:
    if not connected:
        status_label.text = "Сервер еще не подключен.\nНиже доступен локальный бой."
        return
    net.send_message({"type":"rooms"})

func _show_rooms(list: Array) -> void:
    for c in rooms_box.get_children():
        c.queue_free()
    for r in list:
        var b := Button.new()
        b.text = "%s   [%s]   %s" % [str(r.get("name","ROOM")), str(r.get("code","")), str(r.get("players",0))]
        b.custom_minimum_size = Vector2(520, 48)
        b.pressed.connect(func(): room_code_edit.text = str(r.get("code","")); _join_room())
        rooms_box.add_child(b)

func _leave_match() -> void:
    in_match = false
    use_server_state = false
    menu.visible = true
    hud.visible = false

func _update_menu_animation(delta: float) -> void:
    if title_exists():
        pass

func title_exists() -> bool:
    return menu != null
