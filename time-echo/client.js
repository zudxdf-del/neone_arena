class EventBus {
  constructor() { this.listeners = new Map(); }
  on(event, listener) { if (!this.listeners.has(event)) this.listeners.set(event, new Set()); this.listeners.get(event).add(listener); return () => this.listeners.get(event)?.delete(listener); }
  emit(event, payload) { for (const listener of this.listeners.get(event) || []) listener(payload); }
}

class NetworkManager {
  constructor() {
    this.events = new EventBus();
    this.ws = null;
    this.room = '';
    this.playerId = '';
    this.role = '';
    this.connected = false;
    this.serverOffset = 0;
    this.sequence = 0;
    this.lastServerVersion = -1;
    this.reconnectTimer = null;
  }
  on(event, listener) { return this.events.on(event, listener); }
  connect() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) return;
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${protocol}//${location.host}`;
    this.ws = new WebSocket(url);
    this.ws.addEventListener('open', () => { this.connected = true; this.events.emit('connected'); });
    this.ws.addEventListener('message', event => this.handleMessage(event.data));
    this.ws.addEventListener('close', () => {
      this.connected = false;
      this.events.emit('disconnected');
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = setTimeout(() => this.connect(), 1500);
    });
    this.ws.addEventListener('error', () => this.events.emit('error', 'Ошибка сетевого соединения.'));
  }
  send(message) { if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(message)); }
  createRoom(name) { this.send({ type: 'createRoom', name }); }
  joinRoom(room, name) { this.send({ type: 'joinRoom', room, name }); }
  resumeRoom(room, role) { this.send({ type: 'resumeRoom', room, role }); }
  sendPlayerMove(state) {
    this.sequence += 1;
    this.send({ type: 'playerMove', ...state, sequence: this.sequence });
    return this.sequence;
  }
  changeObject(objectId, state, active = true) { this.send({ type: 'onObjectStateChanged', objectId, state, active }); }
  spawnObject(object) { this.send({ type: 'onObjectSpawned', ...object }); }
  requestSnapshot() { this.send({ type: 'requestSnapshot' }); }
  handleMessage(raw) {
    let message;
    try { message = JSON.parse(raw); } catch { return; }
    if (Number.isFinite(message.serverTime)) this.serverOffset = message.serverTime - Date.now();
    switch (message.type) {
      case 'connected': this.events.emit('connected', message); break;
      case 'roomJoined':
        this.room = message.room;
        this.playerId = message.playerId;
        this.role = message.role;
        this.events.emit('roomJoined', message);
        break;
      case 'waitingForOpponent': this.events.emit('waiting', message); break;
      case 'roomReady': this.events.emit('roomReady', message); break;
      case 'stateSnapshot':
        if (message.version < this.lastServerVersion) return;
        this.lastServerVersion = message.version;
        this.events.emit('stateSnapshot', message);
        break;
      case 'playerMove': this.events.emit('onPlayerMove', message); break;
      case 'onObjectSpawned': this.events.emit('onObjectSpawned', message); break;
      case 'onObjectStateChanged': this.events.emit('onObjectStateChanged', message); break;
      case 'playerDisconnected': this.events.emit('playerDisconnected', message); break;
      case 'playerReconnected': this.events.emit('playerReconnected', message); break;
      case 'error': this.events.emit('error', message.message); break;
    }
  }
}

class StateStore {
  constructor() {
    this.state = { version: -1, epoch: 'future', objects: new Map(), players: new Map() };
  }
  applySnapshot(snapshot) {
    this.state.version = snapshot.version;
    this.state.epoch = snapshot.epoch;
    this.state.objects = new Map(snapshot.objects.map(object => [object.id, { ...object }]));
    for (const player of snapshot.players) this.state.players.set(player.id, { ...player });
  }
  applyPlayerMove(player) { this.state.players.set(player.id, { ...player }); }
  applyObject(object) { this.state.objects.set(object.id, { ...object }); }
}

class MotionSmoother {
  constructor() { this.targets = new Map(); }
  setTarget(player) { this.targets.set(player.id, { ...player, receivedAt: performance.now() }); }
  getInterpolated(id, current) {
    const target = this.targets.get(id);
    if (!target) return current;
    const elapsed = Math.min(1, (performance.now() - target.receivedAt) / 100);
    return { ...current, x: current.x + (target.x - current.x) * elapsed, y: current.y + (target.y - current.y) * elapsed, vx: target.vx, vy: target.vy };
  }
}

class PredictionController {
  constructor(network, store) {
    this.network = network;
    this.store = store;
    this.input = { x: 0, y: 0 };
    this.local = { x: 180, y: 300, vx: 0, vy: 0 };
    this.speed = 210;
    this.pending = [];
  }
  setInput(x, y) { this.input.x = x; this.input.y = y; }
  update(dt) {
    if (!this.network.playerId) return;
    this.local.vx = this.input.x * this.speed;
    this.local.vy = this.input.y * this.speed;
    this.local.x = Math.max(40, Math.min(760, this.local.x + this.local.vx * dt));
    this.local.y = Math.max(80, Math.min(520, this.local.y + this.local.vy * dt));
    const sequence = this.network.sendPlayerMove({ x: this.local.x, y: this.local.y, inputX: this.input.x, inputY: this.input.y });
    this.pending.push({ sequence, x: this.local.x, y: this.local.y });
    if (this.pending.length > 90) this.pending.shift();
    this.store.applyPlayerMove({ id: this.network.playerId, role: this.network.role, x: this.local.x, y: this.local.y, vx: this.local.vx, vy: this.local.vy });
  }
  reconcile(serverPlayer) {
    if (serverPlayer.id !== this.network.playerId) return;
    const error = Math.hypot(this.local.x - serverPlayer.x, this.local.y - serverPlayer.y);
    if (error > 35) { this.local.x = serverPlayer.x; this.local.y = serverPlayer.y; }
    else { this.local.x += (serverPlayer.x - this.local.x) * 0.18; this.local.y += (serverPlayer.y - this.local.y) * 0.18; }
    this.pending = this.pending.filter(item => item.sequence > serverPlayer.lastAck);
  }
}

class Renderer {
  constructor(canvas, store, network, smoother, prediction) {
    this.canvas = canvas; this.ctx = canvas.getContext('2d'); this.store = store; this.network = network; this.smoother = smoother; this.prediction = prediction;
  }
  draw() {
    const c = this.ctx, w = this.canvas.width, h = this.canvas.height;
    c.clearRect(0, 0, w, h);
    c.fillStyle = '#090d1a'; c.fillRect(0, 0, w, h);
    c.strokeStyle = '#17213d'; c.lineWidth = 1;
    for (let x = 0; x <= w; x += 40) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h); c.stroke(); }
    for (let y = 0; y <= h; y += 40) { c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke(); }
    c.fillStyle = '#27345c'; c.fillRect(40, 520, 720, 4);
    for (const object of this.store.state.objects.values()) this.drawObject(object);
    for (const player of this.store.state.players.values()) {
      const current = player.id === this.network.playerId ? this.prediction.local : { x: player.x, y: player.y, vx: player.vx, vy: player.vy };
      const position = player.id === this.network.playerId ? current : this.smoother.getInterpolated(player.id, current);
      this.drawPlayer(position, player);
    }
  }
  drawPlayer(p, data) {
    const c = this.ctx;
    c.beginPath(); c.arc(p.x, p.y, 17, 0, Math.PI * 2); c.fillStyle = data.role === 'past' ? '#67e8f9' : '#c084fc'; c.fill();
    c.fillStyle = '#fff'; c.font = '12px system-ui'; c.textAlign = 'center'; c.fillText(data.role === 'past' ? 'ПРОШЛОЕ' : 'БУДУЩЕЕ', p.x, p.y - 25);
  }
  drawObject(o) {
    const c = this.ctx; c.textAlign = 'center'; c.font = '28px system-ui';
    let icon = '•'; if (o.id === 'seed-001') icon = o.state === 'tree_grown' ? '🌳' : '🌱'; if (o.id === 'bridge-001') icon = o.state === 'bridge_broken' ? '🪨' : '🌉'; if (o.id === 'capsule-001') icon = o.state === 'stored' ? '🎁' : '📦';
    c.fillText(icon, o.x, o.y);
    c.fillStyle = '#aeb8d8'; c.font = '11px system-ui'; c.fillText(o.state, o.x, o.y + 24);
  }
}

const network = new NetworkManager();
const store = new StateStore();
const smoother = new MotionSmoother();
const prediction = new PredictionController(network, store);
const canvas = document.getElementById('canvas');
const renderer = new Renderer(canvas, store, network, smoother, prediction);
const $ = id => document.getElementById(id);

function status(text) { $('status').textContent = text; }
function renderRole(role) { $('role').textContent = role === 'past' ? 'Игрок 1 — Прошлое' : role === 'future' ? 'Игрок 2 — Будущее' : '—'; }
function renderObjects() {
  for (const object of store.state.objects.values()) {
    if (object.id === 'seed-001') $('seedState').textContent = object.state;
    if (object.id === 'bridge-001') $('bridgeState').textContent = object.state;
    if (object.id === 'capsule-001') $('capsuleState').textContent = object.state;
  }
}

network.on('connected', () => status('Сервер подключён. Создайте комнату или введите код.'));
network.on('disconnected', () => status('Соединение потеряно. Идёт автоматическое переподключение…'));
network.on('roomJoined', message => { $('roomCode').textContent = message.room; renderRole(message.role); $('game').classList.remove('hidden'); status(message.resumed ? 'Сессия восстановлена.' : `Вы подключены как ${message.playerNumber === 1 ? 'Прошлое' : 'Будущее'}.`); });
network.on('waiting', message => { $('roomCode').textContent = message.room; renderRole('past'); status(`Комната ${message.room}: ждём второго игрока…`); $('game').classList.remove('hidden'); });
network.on('roomReady', message => { $('players').textContent = `Игроков: ${message.players}/${message.maxPlayers}`; status('Оба игрока подключены. Состояние мира синхронизировано.'); });
network.on('stateSnapshot', snapshot => {
  store.applySnapshot(snapshot); renderObjects();
  $('net').textContent = `version ${snapshot.version} • epoch ${snapshot.epoch} • объектов ${snapshot.objects.length}`;
  $('players').textContent = `Игроков: ${snapshot.players.filter(p => p.id).length}/2`;
  const local = snapshot.players.find(p => p.id === network.playerId); if (local) prediction.reconcile(local);
  snapshot.players.filter(p => p.id !== network.playerId).forEach(p => smoother.setTarget(p));
});
network.on('onPlayerMove', message => { store.applyPlayerMove(message.player); if (message.player.id === network.playerId) prediction.reconcile(message.player); else smoother.setTarget(message.player); });
network.on('onObjectSpawned', message => { store.applyObject(message.object); renderObjects(); });
network.on('onObjectStateChanged', message => { store.applyObject(message.object); renderObjects(); $('net').textContent = `version ${message.version} • epoch ${message.epoch}`; });
network.on('playerDisconnected', message => status(`${message.role === 'past' ? 'Игрок Прошлого' : 'Игрока Будущего'} нет в сети. Ожидание…`));
network.on('playerReconnected', () => status('Игрок снова подключён.'));
network.on('error', message => status(message));

$('create').addEventListener('click', () => { network.createRoom($('name').value); });
$('join').addEventListener('click', () => { const room = $('room').value.trim(); if (!/^\d{4}$/.test(room)) return status('Введите 4-значный код комнаты.'); network.joinRoom(room, $('name').value); });
$('tree').addEventListener('click', () => { if (network.role === 'past') network.changeObject('seed-001', 'tree_grown'); else status('Только Игрок 1 — Прошлое — может посадить дерево.'); });
$('bridge').addEventListener('click', () => { if (network.role === 'past') network.changeObject('bridge-001', 'bridge_broken'); else status('Изменение моста доступно Игроку 1 — Прошлое.'); });
$('capsule').addEventListener('click', () => { if (network.role === 'past') network.changeObject('capsule-001', 'stored'); else status('Капсулу заполняет Игрок 1 — Прошлое.'); });

const keys = new Set();
window.addEventListener('keydown', e => { if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','KeyW','KeyA','KeyS','KeyD'].includes(e.code)) { e.preventDefault(); keys.add(e.code); } });
window.addEventListener('keyup', e => keys.delete(e.code));
function updateInput() {
  prediction.setInput((keys.has('ArrowRight') || keys.has('KeyD') ? 1 : 0) - (keys.has('ArrowLeft') || keys.has('KeyA') ? 1 : 0), (keys.has('ArrowDown') || keys.has('KeyS') ? 1 : 0) - (keys.has('ArrowUp') || keys.has('KeyW') ? 1 : 0));
}

network.connect();
let last = performance.now();
function frame(time) {
  const dt = Math.min(0.05, (time - last) / 1000); last = time; updateInput();
  if (network.connected && network.playerId) prediction.update(dt);
  renderer.draw(); requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
