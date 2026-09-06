const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT || 8080);
const WORLD = { w: 1000, h: 700 };
const TICK = 50;
const SPEED = 300;
const BULLET_SPEED = 720;
const HIT_R = 25;
const FIRE_COOLDOWN = 180;
const MAX_ROOMS = 100;

// Shared map: x/y are the floor plane coordinates used by the server.
const OBSTACLES = [
  {x:420,y:120,w:160,h:45},
  {x:420,y:535,w:160,h:45},
  {x:150,y:270,w:190,h:55},
  {x:660,y:375,w:190,h:55},
  {x:455,y:285,w:90,h:130},
  {x:55,y:90,w:90,h:90},
  {x:855,y:520,w:90,h:90}
];

const rooms = new Map();
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function roomCode(){let s='';for(let i=0;i<6;i++)s+=alphabet[Math.floor(Math.random()*alphabet.length)];return s;}
function makeRoom(name,password){let code;do code=roomCode();while(rooms.has(code));const r={code,name:name||'Комната',password:password||'',players:[null,null],bullets:[],lastTick:Date.now(),scores:[0,0],running:false,createdAt:Date.now()};rooms.set(code,r);return r;}
function reset(room){if(!room.players[0]||!room.players[1])return;room.players[0].x=250;room.players[0].y=350;room.players[0].hp=100;room.players[0].aim={x:1,y:0};room.players[1].x=750;room.players[1].y=350;room.players[1].hp=100;room.players[1].aim={x:-1,y:0};room.bullets=[];room.running=true;}
function send(ws,obj){if(ws&&ws.readyState===1)ws.send(JSON.stringify(obj));}
function snapshot(r){return{type:'snapshot',world:WORLD,obstacles:OBSTACLES,players:r.players.map(p=>({x:p.x,y:p.y,hp:p.hp,score:p.score,name:p.name})),bullets:r.bullets.map(b=>({x:b.x,y:b.y,owner:b.owner}))};}
function broadcast(r,obj){r.players.forEach(p=>send(p?.ws,obj));}
function closeRoomIfEmpty(r){if(!r.players[0]&&!r.players[1])rooms.delete(r.code);}
function roomList(){return[...rooms.values()].filter(r=>r.players[0]&&!r.players[1]).map(r=>({code:r.code,name:r.name,host:r.players[0].name,locked:Boolean(r.password),players:1,maxPlayers:2})).sort((a,b)=>a.name.localeCompare(b.name,'ru'));}
function circleHitsRect(x,y,r,o){const cx=Math.max(o.x,Math.min(x,o.x+o.w)),cy=Math.max(o.y,Math.min(y,o.y+o.h));return Math.hypot(x-cx,y-cy)<r;}
function blocked(x,y,radius=22){if(x<radius||x>WORLD.w-radius||y<radius||y>WORLD.h-radius)return true;return OBSTACLES.some(o=>circleHitsRect(x,y,radius,o));}
function movePlayer(p,dt){const ix=p.input.x,iy=p.input.y,l=Math.hypot(ix,iy)||1,scale=Math.min(1,l);const dx=ix/l*SPEED*dt*scale,dy=iy/l*SPEED*dt*scale;const nx=p.x+dx,ny=p.y+dy;if(!blocked(nx,p.y))p.x=nx;if(!blocked(p.x,ny))p.y=ny;}
function endRound(r,winner){r.scores[winner]++;r.players.forEach((p,i)=>{if(p)p.score=r.scores[i];});broadcast(r,{type:'round',winner,scores:r.scores});reset(r);}
function fire(r,i){if(!r.running)return;const p=r.players[i];if(!p)return;const now=Date.now();if(now-p.lastShot<FIRE_COOLDOWN)return;p.lastShot=now;const ax=Number(p.aim?.x)||0,ay=Number(p.aim?.y)||0,len=Math.hypot(ax,ay)||1;r.bullets.push({owner:i,x:p.x+ax/len*28,y:p.y+ay/len*28,vx:ax/len*BULLET_SPEED,vy:ay/len*BULLET_SPEED,life:1.5});}
function tick(r,dt){if(!r.running||!r.players[0]||!r.players[1])return;for(const p of r.players)movePlayer(p,dt);for(const b of r.bullets){b.x+=b.vx*dt;b.y+=b.vy*dt;b.life-=dt;}for(let i=r.bullets.length-1;i>=0;i--){const b=r.bullets[i];if(b.x<0||b.x>WORLD.w||b.y<0||b.y>WORLD.h||OBSTACLES.some(o=>circleHitsRect(b.x,b.y,5,o))){r.bullets.splice(i,1);continue;}const t=r.players[1-b.owner];if(t&&Math.hypot(b.x-t.x,b.y-t.y)<HIT_R){r.bullets.splice(i,1);t.hp-=20;if(t.hp<=0){endRound(r,b.owner);return;}}}r.bullets=r.bullets.filter(b=>b.life>0);}
function lanAddresses(){const out=[];const nets=os.networkInterfaces();for(const name of Object.keys(nets))for(const n of(nets[name]||[]))if(n.family==='IPv4'&&!n.internal)out.push(n.address);return out;}

const server=http.createServer((req,res)=>{const u=(req.url||'/').split('?')[0];if(u==='/health'){res.writeHead(200,{'content-type':'application/json; charset=utf-8'});return res.end(JSON.stringify({ok:true,rooms:rooms.size}));}if(u==='/info'){res.writeHead(200,{'content-type':'application/json; charset=utf-8','cache-control':'no-store'});return res.end(JSON.stringify({ok:true,port:PORT,addresses:lanAddresses(),rooms:rooms.size}));}if(u==='/rooms'){res.writeHead(200,{'content-type':'application/json; charset=utf-8','cache-control':'no-store'});return res.end(JSON.stringify({rooms:roomList()}));}if(u==='/'||u==='/index.html'){const file=path.join(__dirname,'..','index.html');fs.readFile(file,(err,data)=>{if(err){res.writeHead(500,{'content-type':'text/plain; charset=utf-8'});return res.end('index.html not found');}res.writeHead(200,{'content-type':'text/html; charset=utf-8','cache-control':'no-store'});res.end(data);});return;}res.writeHead(404,{'content-type':'text/plain; charset=utf-8'});res.end('Not found');});
const wss=new WebSocketServer({server});
wss.on('connection',(ws)=>{let room=null,index=-1;send(ws,{type:'hello'});ws.on('message',(raw)=>{let m;try{m=JSON.parse(raw)}catch{return;}if(m.type==='create'){if(room)return;if(rooms.size>=MAX_ROOMS)return send(ws,{type:'error',message:'Сейчас слишком много комнат. Попробуй позже.'});const name=String(m.name||'Игрок 1').trim().slice(0,20)||'Игрок 1';const roomName=String(m.roomName||'Новая комната').trim().slice(0,30)||'Новая комната';const password=String(m.password||'').slice(0,40);room=makeRoom(roomName,password);index=0;room.players[0]={ws,input:{x:0,y:0},aim:{x:1,y:0},x:250,y:350,hp:100,score:0,lastShot:0,name};send(ws,{type:'created',room:room.code,roomName:room.name,locked:Boolean(room.password),player:0,name});return;}if(m.type==='join'){if(room)return;const code=String(m.room||'').trim().toUpperCase();const r=rooms.get(code);if(!r)return send(ws,{type:'error',message:'Комната не найдена.'});if(r.players[0]&&r.players[1])return send(ws,{type:'error',message:'Комната уже заполнена.'});const password=String(m.password||'').slice(0,40);if(r.password&&password!==r.password)return send(ws,{type:'password_required',room:r.code,roomName:r.name});room=r;index=1;const name=String(m.name||'Игрок 2').trim().slice(0,20)||'Игрок 2';room.players[1]={ws,input:{x:0,y:0},aim:{x:-1,y:0},x:750,y:350,hp:100,score:0,lastShot:0,name};reset(room);send(room.players[0].ws,{type:'start',room:room.code,roomName:room.name,player:0,players:room.players.map(p=>({name:p.name}))});send(room.players[1].ws,{type:'start',room:room.code,roomName:room.name,player:1,players:room.players.map(p=>({name:p.name}))});return;}if(!room||index<0)return;if(m.type==='input'){room.players[index].input={x:Math.max(-1,Math.min(1,Number(m.x)||0)),y:Math.max(-1,Math.min(1,Number(m.y)||0))};if(Number.isFinite(Number(m.aimX))&&Number.isFinite(Number(m.aimY))){const ax=Number(m.aimX),ay=Number(m.aimY),l=Math.hypot(ax,ay);if(l>.05)room.players[index].aim={x:ax/l,y:ay/l};}}else if(m.type==='shoot')fire(room,index);});ws.on('close',()=>{if(!room||index<0)return;room.players[index]=null;room.running=false;room.bullets=[];const other=room.players[1-index];if(other)send(other.ws,{type:'opponent_left'});closeRoomIfEmpty(room);});});
setInterval(()=>{const now=Date.now();for(const r of rooms.values()){const dt=Math.min(.1,(now-r.lastTick)/1000);r.lastTick=now;tick(r,dt);if(r.running)broadcast(r,snapshot(r));}},TICK);
server.listen(PORT,'0.0.0.0',()=>{console.log(`NEON ARENA server listening on ${PORT}`);for(const a of lanAddresses())console.log(`LAN: http://${a}:${PORT}`);});