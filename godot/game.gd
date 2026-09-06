extends Node3D
class_name NeonArenaGame

const NET_SCRIPT = preload("res://godot/network.gd")
const S := 0.02
const W := 1000.0
const H := 700.0
const AW := W*S
const AH := H*S
const OBS := [{"x":420.0,"y":120.0,"w":160.0,"h":45.0},{"x":420.0,"y":535.0,"w":160.0,"h":45.0},{"x":150.0,"y":270.0,"w":190.0,"h":55.0},{"x":660.0,"y":375.0,"w":190.0,"h":55.0},{"x":455.0,"y":285.0,"w":90.0,"h":130.0},{"x":55.0,"y":90.0,"w":90.0,"h":90.0},{"x":855.0,"y":520.0,"w":90.0,"h":90.0}]
const COLORS := ["#25e8ff","#ff3d70","#b85cff","#ffe45c","#4dff8b","#ff8a3d","#4f8dff","#ff55d6"]

var net:NeonNetwork
var connected:=false
var in_match:=false
var use_server_state:=false
var local_id:=0
var players:Array=[]
var bullets:Array=[]
var visual_players:Dictionary={}
var bullet_nodes:Dictionary={}
var arena:Node3D
var actors:Node3D
var camera:Camera3D
var menu:Control
var hud:Control
var status_label:Label
var nick_edit:LineEdit
var room_name_edit:LineEdit
var password_edit:LineEdit
var room_code_edit:LineEdit
var hp_bar:ProgressBar
var ammo_label:Label
var weapon_label:Label
var score_label:Label
var online_label:Label
var event_label:Label
var fire_button:Button
var reload_button:Button
var weapon_button:Button
var joystick_base:Panel
var joystick_knob:Panel
var joystick_vec:=Vector2.ZERO
var fire_down:=false
var last_input:=0.0
var aim:=Vector2(1,0)

func _ready():
    _arena(); _camera(); _menu(); _hud(); _network()
    menu.visible=true; hud.visible=false

func _process(delta):
    _animate()
    if in_match:
        _controls()
        _render_players()
        _render_bullets()
        _camera_follow(delta)
        _hud_update()

func _network():
    net=NET_SCRIPT.new(); add_child(net)
    net.message_received.connect(_message)
    net.connected.connect(func(): connected=true; status_label.text="СЕРВЕР: ПОДКЛЮЧЕН")
    net.disconnected.connect(func(): connected=false; status_label.text="СЕРВЕР: ОТКЛЮЧЕН")
    net.failed.connect(func(r): status_label.text=str(r))
    net.connect_to_server()

func _arena():
    arena=Node3D.new(); add_child(arena); actors=Node3D.new(); arena.add_child(actors)
    var we:=WorldEnvironment.new(); var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color("#020611"); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color("#9bd0ff"); env.ambient_light_energy=1.4; we.environment=env; arena.add_child(we)
    var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-60,-25,0); light.light_energy=1.7; light.shadow_enabled=true; arena.add_child(light)
    var floor:=_box(Vector3(AW,.12,AH),Color("#07192f"),Color("#0b3d70"),.9); floor.position=Vector3(AW/2,-.06,AH/2); arena.add_child(floor)
    for x in range(51): var g:=_box(Vector3(.012,.018,AH),Color("#12385e"),Color("#14517d"),1.2); g.position=Vector3(x*AW/50,.01,AH/2); arena.add_child(g)
    for z in range(36): var g2:=_box(Vector3(AW,.018,.012),Color("#12385e"),Color("#14517d"),1.2); g2.position=Vector3(AW/2,.012,z*AH/35); arena.add_child(g2)
    _border()
    for o in OBS: _obstacle(o)
    for p in [Vector2(120,120),Vector2(880,120),Vector2(120,580),Vector2(880,580)]: _spawn(p)
    var center:=_ring(Color.WHITE,.75,.035); center.position=Vector3(AW/2,.04,AH/2); arena.add_child(center)

func _border():
    var c:=Color("#19d3ff")
    var a:=_box(Vector3(AW,.55,.1),c,c,4); a.position=Vector3(AW/2,.26,0); arena.add_child(a)
    var b:=_box(Vector3(AW,.55,.1),c,c,4); b.position=Vector3(AW/2,.26,AH); arena.add_child(b)
    var d:=_box(Vector3(.1,.55,AH),c,c,4); d.position=Vector3(0,.26,AH/2); arena.add_child(d)
    var e:=_box(Vector3(.1,.55,AH),c,c,4); e.position=Vector3(AW,.26,AH/2); arena.add_child(e)

func _obstacle(o):
    var s:=Vector3(float(o.w)*S,1.15,float(o.h)*S); var m:=_box(s,Color("#182d53"),Color("#1c82ff"),2.5); m.position=Vector3((float(o.x)+float(o.w)/2)*S,.58,(float(o.y)+float(o.h)/2)*S); arena.add_child(m)
    var t:=_box(Vector3(s.x+.08,.08,s.z+.08),Color("#20e0ff"),Color("#20e0ff"),5); t.position=m.position+Vector3(0,.62,0); arena.add_child(t)

func _spawn(p):
    var r:=_ring(Color("#2c8dff"),.85,.035); r.position=Vector3(p.x*S,.04,p.y*S); arena.add_child(r)

func _box(size,c,e=Color.BLACK,en=1.0):
    var m:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=size; m.mesh=mesh; var mat:=StandardMaterial3D.new(); mat.albedo_color=c; mat.roughness=.35
    if e!=Color.BLACK: mat.emission_enabled=true; mat.emission=e; mat.emission_energy_multiplier=en
    m.material_override=mat; return m

func _ring(c,r,h):
    var m:=MeshInstance3D.new(); var mesh:=CylinderMesh.new(); mesh.top_radius=r; mesh.bottom_radius=r; mesh.height=h; m.mesh=mesh; var mat:=StandardMaterial3D.new(); mat.albedo_color=c; mat.emission_enabled=true; mat.emission=c; mat.emission_energy_multiplier=3; m.material_override=mat; return m

func _camera():
    camera=Camera3D.new(); camera.current=true; camera.fov=55; camera.near=.05; camera.far=100; camera.position=Vector3(AW/2,18,AH/2+1); camera.look_at(Vector3(AW/2,0,AH/2),Vector3.UP); add_child(camera)

func _menu():
    menu=Control.new(); menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(menu); var bg:=ColorRect.new(); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.color=Color("#020611"); menu.add_child(bg)
    var title:=Label.new(); title.text="NEON ARENA"; title.position=Vector2(70,55); title.add_theme_font_size_override("font_size",52); title.modulate=Color("#49eaff"); menu.add_child(title)
    var sub:=Label.new(); sub.text="ONLINE // 2–8 PLAYERS"; sub.position=Vector2(74,118); sub.add_theme_font_size_override("font_size",18); sub.modulate=Color("#7898b8"); menu.add_child(sub)
    nick_edit=_field("НИК",Vector2(70,185),"Игрок"); room_name_edit=_field("НАЗВАНИЕ КОМНАТЫ",Vector2(70,255),"Неоновая арена"); password_edit=_field("ПАРОЛЬ",Vector2(70,325),""); room_code_edit=_field("КОД КОМНАТЫ",Vector2(70,395),"")
    var create:=Button.new(); create.text="СОЗДАТЬ ИГРУ"; create.position=Vector2(500,185); create.size=Vector2(390,72); create.add_theme_font_size_override("font_size",24); menu.add_child(create)
    var join:=Button.new(); join.text="ПОДКЛЮЧИТЬСЯ"; join.position=Vector2(500,275); join.size=Vector2(390,72); join.add_theme_font_size_override("font_size",24); menu.add_child(join)
    status_label=Label.new(); status_label.text="СЕРВЕР: ПОДКЛЮЧЕНИЕ..."; status_label.position=Vector2(500,375); status_label.add_theme_font_size_override("font_size",18); status_label.modulate=Color("#6eeaff"); menu.add_child(status_label)
    var hint:=Label.new(); hint.text="Создатель выбирает 2 / 3 / 4 / 6 / 8 игроков.\nВ лобби видны все подключившиеся игроки."; hint.position=Vector2(500,425); hint.add_theme_font_size_override("font_size",17); hint.modulate=Color("#8aa8c0"); menu.add_child(hint)

func _field(t,p,ph):
    var l:=Label.new(); l.text=t; l.position=p; l.add_theme_font_size_override("font_size",13); l.modulate=Color("#6f91ad"); menu.add_child(l)
    var f:=LineEdit.new(); f.placeholder_text=ph; f.position=p+Vector2(0,22); f.size=Vector2(380,43); f.add_theme_font_size_override("font_size",18); menu.add_child(f); return f

func _hud():
    hud=Control.new(); hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(hud)
    var top:=ColorRect.new(); top.size=Vector2(1280,82); top.color=Color(0.01,0.03,0.08,.94); hud.add_child(top)
    online_label=_label("",Vector2(25,18),18); hp_bar=ProgressBar.new(); hp_bar.position=Vector2(300,20); hp_bar.size=Vector2(270,30); hp_bar.max_value=100; hud.add_child(hp_bar)
    ammo_label=_label("",Vector2(610,15),22); weapon_label=_label("",Vector2(610,46),14); weapon_label.modulate=Color("#91a8bf"); score_label=_label("",Vector2(900,18),20)
    event_label=_label("",Vector2(380,100),22); crosshair:=_label("+",Vector2(625,340),38); crosshair.modulate=Color.WHITE
    joystick_base=Panel.new(); joystick_base.position=Vector2(45,500); joystick_base.size=Vector2(190,190); joystick_base.modulate=Color(0.1,.7,1,.25); hud.add_child(joystick_base)
    joystick_knob=Panel.new(); joystick_knob.position=Vector2(110,565); joystick_knob.size=Vector2(60,60); joystick_knob.modulate=Color(.3,1,1,.85); hud.add_child(joystick_knob)
    fire_button=_action("ОГОНЬ",Vector2(1035,510),Vector2(195,80)); fire_button.button_down.connect(func():fire_down=true); fire_button.button_up.connect(func():fire_down=false)
    reload_button=_action("ПЕРЕЗАРЯДКА",Vector2(1035,605),Vector2(195,55)); reload_button.pressed.connect(func():net.send_message({"type":"reload"}))
    weapon_button=_action("ОРУЖИЕ",Vector2(820,605),Vector2(195,55)); weapon_button.pressed.connect(_weapon)
    var leave:=_action("ВЫЙТИ",Vector2(45,700),Vector2(150,45)); leave.pressed.connect(_leave)

func _label(t,p,size):
    var l:=Label.new(); l.text=t; l.position=p; l.add_theme_font_size_override("font_size",size); hud.add_child(l); return l

func _action(t,p,s):
    var b:=Button.new(); b.text=t; b.position=p; b.size=s; b.add_theme_font_size_override("font_size",18); hud.add_child(b); return b

func _controls():
    var mv:=joystick_vec
    if Input.is_key_pressed(KEY_W): mv.y-=1
    if Input.is_key_pressed(KEY_S): mv.y+=1
    if Input.is_key_pressed(KEY_A): mv.x-=1
    if Input.is_key_pressed(KEY_D): mv.x+=1
    if mv.length()>1: mv=mv.normalized()
    if Input.is_key_pressed(KEY_LEFT): aim=Vector2(-1,0)
    if Input.is_key_pressed(KEY_RIGHT): aim=Vector2(1,0)
    if Input.is_key_pressed(KEY_UP): aim=Vector2(0,-1)
    if Input.is_key_pressed(KEY_DOWN): aim=Vector2(0,1)
    var now=Time.get_ticks_msec()/1000.0
    if now-last_input>.05: net.send_message({"type":"input","x":mv.x,"y":mv.y,"aimX":aim.x,"aimY":aim.y}); last_input=now
    if fire_down or Input.is_key_pressed(KEY_SPACE): net.send_message({"type":"shoot"})
    joystick_knob.position=Vector2(110,565)+joystick_vec*58

func _weapon():
    var cur=weapon_label.text.to_lower(); var n="pistol"
    if "pistol" in cur: n="smg"
    elif "smg" in cur: n="shotgun"
    net.send_message({"type":"weapon","weapon":n})

func _render_players():
    for i in range(players.size()):
        var p=players[i]
        if p==null:
            if visual_players.has(i): visual_players[i].queue_free(); visual_players.erase(i)
            continue
        if not visual_players.has(i): visual_players[i]=_player(i)
        var v:Node3D=visual_players[i]; v.position=Vector3(float(p.get("x",500))*S,.0,float(p.get("y",350))*S)
        var hp:MeshInstance3D=v.get_node("HP"); hp.scale.x=max(.02,float(p.get("hp",0))/100.0)
        var name:Label3D=v.get_node("Name"); name.text=("YOU  " if i==local_id else "P%d  "%[i+1])+str(p.get("name","Игрок"))+"  %dHP"%int(p.get("hp",0))
        var a=p.get("aim",{"x":1,"y":0}); var gun:Node3D=v.get_node("Gun"); gun.rotation.y=-atan2(float(a.get("y",0)),float(a.get("x",1)))

func _player(i):
    var root:=Node3D.new(); root.name="P%d"%i; actors.add_child(root); var c:=Color(COLORS[i%COLORS.size()])
    var body:=MeshInstance3D.new(); var cap:=CapsuleMesh.new(); cap.radius=.34; cap.height=1.45; body.mesh=cap; body.position.y=.82; body.material_override=_mat(c); root.add_child(body)
    var head:=MeshInstance3D.new(); var sp:=SphereMesh.new(); sp.radius=.31; sp.height=.62; head.mesh=sp; head.position.y=1.62; head.material_override=_mat(Color("#e9faff")); root.add_child(head)
    var visor:=_box(Vector3(.46,.14,.1),Color.WHITE,c,4); visor.position=Vector3(0,1.62,-.28); root.add_child(visor)
    var ring:=_ring(c,.58,.035); ring.position.y=.05; root.add_child(ring)
    var gun:=_box(Vector3(.18,.18,.85),Color("#101827"),Color("#fff06a"),4); gun.position=Vector3(.42,.85,-.42); gun.name="Gun"; root.add_child(gun)
    var hp:=_box(Vector3(.95,.07,.06),Color("#30101b")); hp.position=Vector3(0,2.08,0); hp.name="HP"; root.add_child(hp)
    var label:=Label3D.new(); label.name="Name"; label.position=Vector3(0,2.4,0); label.font_size=24; label.outline_size=7; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.modulate=c; root.add_child(label)
    return root

func _mat(c):
    var m:=StandardMaterial3D.new(); m.albedo_color=c; m.metallic=.3; m.roughness=.25; m.emission_enabled=true; m.emission=c; m.emission_energy_multiplier=1.8; return m

func _render_bullets():
    var alive={}
    for b in bullets: alive[int(b.get("id",0))]=true
    for id in bullet_nodes.keys():
        if not alive.has(int(id)): bullet_nodes[id].queue_free(); bullet_nodes.erase(id)
    for b in bullets:
        var id=int(b.get("id",0)); if not bullet_nodes.has(id): bullet_nodes[id]=_box(Vector3(.08,.08,.42),Color("#fff36a"),Color("#fff36a"),8); arena.add_child(bullet_nodes[id])
        var n:Node3D=bullet_nodes[id]; n.position=Vector3(float(b.x)*S,.65,float(b.y)*S)

func _camera_follow(delta):
    var minx=W; var maxx=0.0; var miny=H; var maxy=0.0; var count=0
    for p in players:
        if p==null: continue
        minx=min(minx,float(p.x)); maxx=max(maxx,float(p.x)); miny=min(miny,float(p.y)); maxy=max(maxy,float(p.y)); count+=1
    if count==0:return
    var center:=Vector3((minx+maxx)*S/2,0,(miny+maxy)*S/2); var span:=max((maxx-minx)*S,(maxy-miny)*S)+7
    var target_y=clamp(11+span*.55,11,24); var target=center+Vector3(0,target_y,span*.28)
    camera.position=camera.position.lerp(target,1-exp(-delta*3.5)); camera.look_at(center,Vector3.UP)

func _hud_update():
    var n=0; for p in players: if p!=null:n+=1
    online_label.text="MATCH  //  %d PLAYERS"%n
    if local_id<players.size() and players[local_id]!=null:
        var p=players[local_id]; hp_bar.value=float(p.get("hp",0)); ammo_label.text="%02d / %02d"%[int(p.get("ammo",0)),int(p.get("mag",12))]; weapon_label.text=str(p.get("weapon","pistol")).to_upper(); score_label.text="SCORE  %d"%int(p.get("score",0))

func _animate():
    var pulse=2.7+sin(Time.get_ticks_msec()/180.0)*.7
    for n in arena.get_children():
        if n is MeshInstance3D and n.material_override is StandardMaterial3D:
            var m=n.material_override as StandardMaterial3D
            if m.emission_enabled and m.emission_energy_multiplier>2:m.emission_energy_multiplier=pulse

func _message(d):
    match str(d.get("type","")):
        "created": local_id=int(d.get("player",0))
        "start":
            local_id=int(d.get("player",local_id)); players=d.get("players",[]); in_match=true; use_server_state=true; menu.visible=false; hud.visible=true; event_label.text="БОЙ НАЧАЛСЯ — %d ИГРОКОВ"%int(d.get("playerCount",2))
        "snapshot": players=d.get("players",[]); bullets=d.get("bullets",[])
        "round": event_label.text="ПОБЕДИТЕЛЬ: ИГРОК %d"%(int(d.get("winner",0))+1)
        "opponent_left": event_label.text="ИГРОК ВЫШЕЛ ИЗ КОМНАТЫ"
        "error": status_label.text=str(d.get("message","Ошибка"))

func _leave():
    net.close(); connected=false; in_match=false; use_server_state=false; players.clear(); bullets.clear(); menu.visible=true; hud.visible=false
    for v in visual_players.values(): v.queue_free()
    visual_players.clear(); bullet_nodes.clear()
