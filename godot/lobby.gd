extends Node

var root: Node
var net: Node
var panel: Control
var selector_box: HBoxContainer
var players_box: VBoxContainer
var count_label: Label
var room_code_label: Label
var start_button: Button
var player_count := 2
var room_code := ""
var is_host := false
var in_lobby := false
var current_players: Array = []

func _ready() -> void:
    root = get_parent()
    await get_tree().process_frame
    net = root.get("net")
    if net and net.has_signal("message_received"):
        net.message_received.connect(_on_net_message)
    _hook_buttons()
    _build_player_selector()
    root.in_match = false
    root.menu.visible = true
    root.hud.visible = false

func _hook_buttons() -> void:
    for n in root.find_children("*", "Button", true, false):
        if not n is Button: continue
        if n.text == "СОЗДАТЬ ИГРУ":
            if n.pressed.is_connected(root._create_room): n.pressed.disconnect(root._create_room)
            n.pressed.connect(_create_room)
        elif n.text == "ПОДКЛЮЧИТЬСЯ":
            if n.pressed.is_connected(root._join_room): n.pressed.disconnect(root._join_room)
            n.pressed.connect(_join_room)

func _build_player_selector() -> void:
    var label := Label.new()
    label.text = "ИГРОКОВ В КОМНАТЕ:"
    label.position = Vector2(50, 372)
    label.add_theme_font_size_override("font_size", 15)
    label.modulate = Color("#8eb9dc")
    root.menu.add_child(label)
    selector_box = HBoxContainer.new()
    selector_box.position = Vector2(225, 366)
    selector_box.size = Vector2(310, 42)
    selector_box.add_theme_constant_override("separation", 6)
    root.menu.add_child(selector_box)
    for n in [2,3,4,6,8]:
        var b := Button.new()
        b.text = str(n)
        b.custom_minimum_size = Vector2(52, 40)
        b.add_theme_font_size_override("font_size", 16)
        b.pressed.connect(func(): set_player_count(n))
        selector_box.add_child(b)
    set_player_count(2)

func set_player_count(value: int) -> void:
    player_count = clamp(value, 2, 8)
    if selector_box:
        for c in selector_box.get_children():
            if c is Button: c.modulate = Color("#48ff9a") if int(c.text) == player_count else Color("#ffffff")

func _create_room() -> void:
    if not net or not root.connected:
        root.status_label.text = "Сервер не подключен."
        return
    var nick := root.nick_edit.text.strip_edges()
    if nick == "": nick = "Игрок"
    var room_name := root.room_name_edit.text.strip_edges()
    if room_name == "": room_name = "Неоновая арена"
    net.send_message({"type":"create","name":nick,"roomName":room_name,"password":root.password_edit.text,"maxPlayers":player_count})

func _join_room() -> void:
    if not net or not root.connected:
        root.status_label.text = "Сервер не подключен."
        return
    var nick := root.nick_edit.text.strip_edges()
    if nick == "": nick = "Игрок"
    net.send_message({"type":"join","room":root.room_code_edit.text.strip_edges().to_upper(),"password":root.password_edit.text,"name":nick})

func _on_net_message(data: Dictionary) -> void:
    var t := str(data.get("type", ""))
    if t == "created":
        room_code = str(data.get("room", ""))
        player_count = int(data.get("maxPlayers", player_count))
        is_host = true
        in_lobby = true
    elif t == "lobby":
        room_code = str(data.get("room", room_code))
        player_count = int(data.get("maxPlayers", player_count))
        current_players = data.get("players", [])
        is_host = int(data.get("selfId", -1)) == int(data.get("host", -2))
        in_lobby = true
        _show_lobby()
    elif t == "start":
        in_lobby = false
        if panel: panel.visible = false
        root.menu.visible = false
        root.hud.visible = true
        root.in_match = true
        root.local_id = int(data.get("player", 0))
        root.use_server_state = true
    elif t == "error":
        root.status_label.text = str(data.get("message", "Ошибка сервера"))

func _show_lobby() -> void:
    if not panel: _build_lobby()
    panel.visible = true
    root.menu.visible = false
    root.hud.visible = false
    _refresh_lobby()

func _build_lobby() -> void:
    panel = Control.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(panel)
    var bg := ColorRect.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.color = Color("#020611")
    panel.add_child(bg)
    var card := Panel.new()
    card.position = Vector2(140, 55)
    card.size = Vector2(1000, 610)
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#08152b")
    style.border_color = Color("#18ddff")
    style.set_border_width_all(2)
    style.set_corner_radius_all(24)
    card.add_theme_stylebox_override("panel", style)
    panel.add_child(card)
    var title := Label.new()
    title.text = "ЛОББИ"
    title.position = Vector2(195, 88)
    title.add_theme_font_size_override("font_size", 44)
    title.modulate = Color("#5ceeff")
    panel.add_child(title)
    room_code_label = Label.new()
    room_code_label.position = Vector2(195, 145)
    room_code_label.add_theme_font_size_override("font_size", 24)
    panel.add_child(room_code_label)
    var hint := Label.new()
    hint.text = "Отправьте код комнаты друзьям. Список игроков обновляется автоматически."
    hint.position = Vector2(195, 185)
    hint.add_theme_font_size_override("font_size", 17)
    hint.modulate = Color("#8eafd0")
    panel.add_child(hint)
    var list_title := Label.new()
    list_title.text = "ИГРОКИ"
    list_title.position = Vector2(195, 235)
    list_title.add_theme_font_size_override("font_size", 20)
    panel.add_child(list_title)
    players_box = VBoxContainer.new()
    players_box.position = Vector2(195, 275)
    players_box.size = Vector2(890, 245)
    players_box.add_theme_constant_override("separation", 8)
    panel.add_child(players_box)
    count_label = Label.new()
    count_label.position = Vector2(195, 535)
    count_label.add_theme_font_size_override("font_size", 18)
    count_label.modulate = Color("#b9d8ee")
    panel.add_child(count_label)
    start_button = Button.new()
    start_button.text = "НАЧАТЬ ИГРУ"
    start_button.position = Vector2(735, 535)
    start_button.size = Vector2(350, 72)
    start_button.add_theme_font_size_override("font_size", 24)
    start_button.modulate = Color("#48ff9a")
    start_button.pressed.connect(_start_game)
    panel.add_child(start_button)
    var leave := Button.new()
    leave.text = "ВЫЙТИ ИЗ КОМНАТЫ"
    leave.position = Vector2(195, 585)
    leave.size = Vector2(250, 50)
    leave.pressed.connect(_leave_lobby)
    panel.add_child(leave)

func _refresh_lobby() -> void:
    if not panel: return
    room_code_label.text = "КОД КОМНАТЫ:  " + room_code
    for c in players_box.get_children(): c.queue_free()
    var actual := 0
    for p in current_players:
        if p == null: continue
        var row := Label.new()
        var host_text := "  ★ СОЗДАТЕЛЬ" if bool(p.get("host", false)) else ""
        row.text = "  ●  %s%s" % [str(p.get("name", "Игрок")), host_text]
        row.custom_minimum_size = Vector2(850, 43)
        row.add_theme_font_size_override("font_size", 21)
        row.modulate = Color("#5ceeff") if bool(p.get("host", false)) else Color("#ff7898")
        players_box.add_child(row)
        actual += 1
    while actual < player_count:
        var wait := Label.new()
        wait.text = "  ○  Ожидание игрока..."
        wait.custom_minimum_size = Vector2(850, 43)
        wait.add_theme_font_size_override("font_size", 19)
        wait.modulate = Color("#536c85")
        players_box.add_child(wait)
        actual += 1
    var real_count := 0
    for p in current_players:
        if p != null: real_count += 1
    count_label.text = "ИГРОКОВ: %d / %d" % [real_count, player_count]
    start_button.disabled = not is_host or real_count < 2

func _start_game() -> void:
    if not is_host or not net or room_code == "": return
    net.send_message({"type":"start_game","room":room_code})
    start_button.disabled = true
    start_button.text = "ЗАПУСК..."

func _leave_lobby() -> void:
    if net: net.close()
    in_lobby = false
    is_host = false
    current_players.clear()
    if panel: panel.visible = false
    root.menu.visible = true
    root.hud.visible = false
    root.in_match = false
