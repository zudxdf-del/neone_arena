const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT) || 8080;
const TICK_RATE = 30;
const TICK_MS = 1000 / TICK_RATE;
const MAX_PLAYERS = 2;
const ROOM_TTL_MS = 30 * 60 * 1000;
const PLAYER_TIMEOUT_MS = 15000;
const WORLD_EPOCH = 'future';
const rooms = new Map();

function send(ws, message) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(message));
}
function broadcast(room, message) { room.players.forEach(p => send(p.ws, message)); }
function now() { return Date.now(); }
function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }
function makeRoomCode() {
  let code;
  do code = String(Math.floor(1000 + Math.random() * 9000)); while (rooms.has(code));
  return code;
}
function sanitizeName(name) {
  const value = typeof name === 'string' ? name.trim() : '';
  return value.slice(0, 18) || 'Игрок';
}
function createPlayer(id, role, name) {
  return { id, role, name, x: role === 'past' ? 180 : 620, y: 300, vx: 0, vy: 0, inputX: 0, inputY: 0, sequence: 0, lastInputAt: now(), lastAck: 0, ws: null };
}
function createWorld() {
  return {
    epoch: WORLD_EPOCH,
    objects: [
      { id: 'seed-001', x: 400, y: 180, state: 'seed_planted', active: true, epoch: 'past' },
      { id: 'bridge-001', x: 400, y: 300, state: 'bridge_intact', active: true, epoch: 'shared' },
      { id: 'capsule-001', x: 400, y: 420, state: 'empty', active: true, epoch: 'shared' }
    ]
  };
}
function createRoom(code) {
  return { code, createdAt: now(), lastActivityAt: now(), version: 0, players: [createPlayer('player-1', 'past', 'Игрок 1'), createPlayer('player-2', 'future', 'Игрок 2')], world: createWorld() };
}
function serializePlayer(player) {
  return { id: player.id, role: player.role, name: player.name, x: player.x, y: player.y, vx: player.vx, vy: player.vy, lastAck: player.lastAck };
}
function serializeState(room) {
  return { type: 'stateSnapshot', version: room.version, serverTime: now(), room: room.code, epoch: room.world.epoch, objects: room.world.objects.map(o => ({ ...o })), players: room.players.map(serializePlayer) };
}
function reject(ws, message) { send(ws, { type: 'error', message }); }
function getRoomPlayer(room, ws) { return room.players.findIndex(player => player.ws === ws); }
function sendRoomInfo(room, index, resumed = false) {
  const player = room.players[index];
  send(player.ws, { type: 'roomJoined', room: room.code, playerId: player.id, role: player.role, playerNumber: index + 1, resumed, serverTime: now() });
}
function sendSnapshot(room) { room.version += 1; room.lastActivityAt = now(); broadcast(room, serializeState(room)); }

function handleCreate(ws, message) {
  const code = makeRoomCode();
  const room = createRoom(code);
  room.players[0].name = sanitizeName(message.name);
  room.players[0].ws = ws;
  rooms.set(code, room);
  ws.roomCode = code;
  ws.playerIndex = 0;
  sendRoomInfo(room, 0);
  send(ws, { type: 'waitingForOpponent', room: code, players: 1, maxPlayers: MAX_PLAYERS });
}
function handleJoin(ws, message) {
  const code = String(message.room || '').trim();
  const room = rooms.get(code);
  if (!room) return reject(ws, 'Комната с таким кодом не найдена.');
  if (room.players[1].ws) return reject(ws, 'Комната уже заполнена.');
  room.players[1].name = sanitizeName(message.name);
  room.players[1].ws = ws;
  room.players[1].lastInputAt = now();
  ws.roomCode = code;
  ws.playerIndex = 1;
  room.lastActivityAt = now();
  sendRoomInfo(room, 1);
  sendRoomInfo(room, 0);
  broadcast(room, { type: 'roomReady', room: room.code, players: 2, maxPlayers: MAX_PLAYERS });
  sendSnapshot(room);
}
function handleResume(ws, message) {
  const code = String(message.room || '').trim();
  const room = rooms.get(code);
  if (!room) return reject(ws, 'Сессию восстановить не удалось.');
  const role = message.role === 'future' ? 'future' : 'past';
  const index = room.players.findIndex(player => player.role === role);
  if (index < 0) return reject(ws, 'Роль не найдена.');
  const player = room.players[index];
  player.ws = ws;
  player.lastInputAt = now();
  ws.roomCode = code;
  ws.playerIndex = index;
  room.lastActivityAt = now();
  sendRoomInfo(room, index, true);
  send(ws, serializeState(room));
  broadcast(room, { type: 'playerReconnected', playerId: player.id, role: player.role });
}
function validateInput(message) {
  const sequence = Number(message.sequence), x = Number(message.x), y = Number(message.y);
  const inputX = clamp(Number(message.inputX) || 0, -1, 1), inputY = clamp(Number(message.inputY) || 0, -1, 1);
  if (!Number.isInteger(sequence) || sequence < 0 || ![x, y].every(Number.isFinite)) return null;
  return { sequence, x, y, inputX, inputY };
}
function handlePlayerMove(room, index, message) {
  const player = room.players[index], input = validateInput(message);
  if (!input || input.sequence <= player.sequence) return;
  player.sequence = input.sequence;
  player.inputX = input.inputX;
  player.inputY = input.inputY;
  player.lastInputAt = now();
  player.lastAck = input.sequence;
  if (Math.hypot(input.x - player.x, input.y - player.y) <= 180) {
    player.x = clamp(input.x, 40, 760);
    player.y = clamp(input.y, 80, 520);
  }
  room.lastActivityAt = now();
  broadcast(room, { type: 'playerMove', player: serializePlayer(player), sequence: input.sequence, serverTime: now() });
}
function findObject(room, id) { return room.world.objects.find(object => object.id === id) || null; }
function handleObjectStateChanged(room, index, message) {
  const objectId = typeof message.objectId === 'string' ? message.objectId : '';
  const object = findObject(room, objectId);
  if (!object) return reject(room.players[index].ws, 'Объект не найден.');
  const allowed = new Set(['seed_planted', 'tree_grown', 'bridge_intact', 'bridge_broken', 'empty', 'stored']);
  const state = typeof message.state === 'string' ? message.state : '';
  if (!allowed.has(state)) return reject(room.players[index].ws, 'Недопустимое состояние объекта.');
  if (object.id === 'seed-001' && index !== 0) return reject(room.players[index].ws, 'Только Прошлое может изменить саженец.');
  if (object.id === 'bridge-001' && state === 'bridge_broken' && index !== 0) return reject(room.players[index].ws, 'Мост можно изменить из Прошлого.');
  if (object.id === 'capsule-001' && state === 'stored' && index !== 0) return reject(room.players[index].ws, 'Капсулу можно заполнить из Прошлого.');
  object.state = state;
  object.active = message.active !== false;
  room.version += 1;
  room.lastActivityAt = now();
  broadcast(room, { type: 'onObjectStateChanged', object: { ...object }, changedBy: room.players[index].id, epoch: room.world.epoch, version: room.version, serverTime: now() });
}
function handleObjectSpawned(room, index, message) {
  const id = typeof message.objectId === 'string' ? message.objectId.trim() : '';
  if (!id || findObject(room, id)) return;
  const object = { id: id.slice(0, 64), x: clamp(Number(message.x) || 0, 0, 800), y: clamp(Number(message.y) || 0, 0, 600), state: typeof message.state === 'string' ? message.state.slice(0, 40) : 'active', active: message.active !== false, epoch: message.epoch === 'past' ? 'past' : 'future' };
  room.world.objects.push(object);
  room.version += 1;
  room.lastActivityAt = now();
  broadcast(room, { type: 'onObjectSpawned', object, spawnedBy: room.players[index].id, version: room.version, serverTime: now() });
}
function tickRoom(room) {
  const timestamp = now();
  for (const player of room.players) {
    if (!player.ws || timestamp - player.lastInputAt > PLAYER_TIMEOUT_MS) continue;
    const dt = TICK_MS / 1000, speed = 210;
    player.vx = player.inputX * speed;
    player.vy = player.inputY * speed;
    player.x = clamp(player.x + player.vx * dt, 40, 760);
    player.y = clamp(player.y + player.vy * dt, 80, 520);
  }
}

const server = http.createServer((req, res) => {
  const pathname = (req.url || '/').split('?')[0];
  if (pathname === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ ok: true, game: 'time-echo', rooms: rooms.size, tickRate: TICK_RATE }));
    return;
  }
  let filePath;
  if (pathname === '/' || pathname === '/index.html' || pathname === '/time-echo' || pathname === '/time-echo/') filePath = path.join(__dirname, 'index.html');
  else if (pathname === '/time-echo/client.js') filePath = path.join(__dirname, 'client.js');
  if (!filePath) { res.writeHead(404); res.end('Not Found'); return; }
  const contentType = filePath.endsWith('.js') ? 'application/javascript; charset=utf-8' : 'text/html; charset=utf-8';
  fs.readFile(filePath, (error, data) => {
    if (error) { res.writeHead(500); res.end('Server error'); return; }
    res.writeHead(200, { 'Content-Type': contentType, 'Cache-Control': 'no-store' });
    res.end(data);
  });
});

const wss = new WebSocketServer({ server });
wss.on('connection', ws => {
  ws.roomCode = null;
  ws.playerIndex = -1;
  send(ws, { type: 'connected', serverTime: now(), tickRate: TICK_RATE });
  ws.on('message', raw => {
    let message;
    try { message = JSON.parse(raw.toString()); } catch { return reject(ws, 'Некорректный JSON.'); }
    if (message.type === 'createRoom') return handleCreate(ws, message);
    if (message.type === 'joinRoom') return handleJoin(ws, message);
    if (message.type === 'resumeRoom') return handleResume(ws, message);
    const room = ws.roomCode ? rooms.get(ws.roomCode) : null;
    const index = room ? getRoomPlayer(room, ws) : -1;
    if (!room || index < 0) return reject(ws, 'Сначала подключитесь к комнате.');
    if (message.type === 'playerMove') return handlePlayerMove(room, index, message);
    if (message.type === 'onObjectSpawned') return handleObjectSpawned(room, index, message);
    if (message.type === 'onObjectStateChanged') return handleObjectStateChanged(room, index, message);
    if (message.type === 'requestSnapshot') return send(ws, serializeState(room));
  });
  ws.on('close', () => {
    const room = ws.roomCode ? rooms.get(ws.roomCode) : null;
    if (!room) return;
    const index = getRoomPlayer(room, ws);
    if (index < 0) return;
    room.players[index].ws = null;
    room.lastActivityAt = now();
    broadcast(room, { type: 'playerDisconnected', playerId: room.players[index].id, role: room.players[index].role });
  });
});

setInterval(() => { for (const room of rooms.values()) tickRoom(room); }, TICK_MS);
setInterval(() => {
  const timestamp = now();
  for (const [code, room] of rooms) {
    if (room.players.every(player => !player.ws) && timestamp - room.lastActivityAt > ROOM_TTL_MS) rooms.delete(code);
  }
}, 60000);
process.on('uncaughtException', error => console.error('[uncaughtException]', error));
process.on('unhandledRejection', error => console.error('[unhandledRejection]', error));
server.listen(PORT, '0.0.0.0', () => console.log(`Time Echo server listening on ${PORT}`));
