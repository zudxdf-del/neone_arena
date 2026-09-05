const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT || 8080);
const WORLD = { w: 1000, h: 700 };
const TICK = 50;
const SPEED = 300;
const BULLET_SPEED = 650;
const HIT_R = 28;
const FIRE_COOLDOWN = 220;

const rooms = new Map();
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function roomCode(){ let s=''; for(let i=0;i<6;i++) s += alphabet[Math.floor(Math.random()*alphabet.length)]; return s; }
function makeRoom(){ let c; do c=roomCode(); while(rooms.has(c)); const r={code:c,players:[null,null],bullets:[],lastTick:Date.now(),scores:[0,0],running:false}; rooms.set(c,r); return r; }
function reset(room){
  room.players[0].x=250; room.players[0].y=350; room.players[0].hp=100;
  room.players[1].x=750; room.players[1].y=350; room.players[1].hp=100;
  room.bullets=[]; room.running=true;
}
function send(ws,obj){ if(ws && ws.readyState===1) ws.send(JSON.stringify(obj)); }
function snapshot(r){ return {type:'snapshot', world:WORLD, players:r.players.map(p=>({x:p.x,y:p.y,hp:p.hp,score:p.score})), bullets:r.bullets.map(b=>({x:b.x,y:b.y,owner:b.owner}))}; }
function broadcast(r,obj){ r.players.forEach(p=>send(p?.ws,obj)); }
function closeRoomIfEmpty(r){ if(!r.players[0]&&!r.players[1]) rooms.delete(r.code); }
function endRound(r,winner){
  r.scores[winner]++;
  r.players.forEach((p,i)=>{ if(p) p.score=r.scores[i]; });
  broadcast(r,{type:'round', winner, scores:r.scores});
  reset(r);
}
function fire(r,i){
  if(!r.running) return;
  const p=r.players[i], other=r.players[1-i];
  if(!p||!other) return;
  const now=Date.now(); if(now-p.lastShot<FIRE_COOLDOWN) return; p.lastShot=now;
  let dx=other.x-p.x, dy=other.y-p.y, len=Math.hypot(dx,dy)||1;
  r.bullets.push({owner:i,x:p.x,y:p.y,vx:dx/len*BULLET_SPEED,vy:dy/len*BULLET_SPEED,life:1.6});
}
function tick(r,dt){
  if(!r.running || !r.players[0] || !r.players[1]) return;
  for(const p of r.players){
    const l=Math.hypot(p.input.x,p.input.y)||1;
    const scale=Math.min(1,l);
    p.x=Math.max(25,Math.min(WORLD.w-25,p.x+(p.input.x/Math.max(1,l))*SPEED*dt*scale));
    p.y=Math.max(70,Math.min(WORLD.h-25,p.y+(p.input.y/Math.max(1,l))*SPEED*dt*scale));
  }
  for(const b of r.bullets){b.x+=b.vx*dt;b.y+=b.vy*dt;b.life-=dt;}
  for(let i=r.bullets.length-1;i>=0;i--){
    const b=r.bullets[i], t=r.players[1-b.owner];
    if(Math.hypot(b.x-t.x,b.y-t.y)<HIT_R){
      r.bullets.splice(i,1); t.hp-=20;
      if(t.hp<=0){ endRound(r,b.owner); return; }
    }
  }
  r.bullets=r.bullets.filter(b=>b.life>0 && b.x>-50 && b.x<WORLD.w+50 && b.y>20 && b.y<WORLD.h+50);
}

const server=http.createServer((req,res)=>{
  const u=(req.url||'/').split('?')[0];
  if(u==='/health'){res.writeHead(200,{'content-type':'application/json'});return res.end(JSON.stringify({ok:true,rooms:rooms.size}));}
  if(u==='/' || u==='/index.html'){
    const file=path.join(__dirname,'index.html');
    fs.readFile(file,(err,data)=>{
      if(err){res.writeHead(500,{'content-type':'text/plain; charset=utf-8'});return res.end('index.html not found');}
      res.writeHead(200,{'content-type':'text/html; charset=utf-8','cache-control':'no-store'});res.end(data);
    });
    return;
  }
  res.writeHead(404,{'content-type':'text/plain; charset=utf-8'});res.end('Not found');
});
const wss=new WebSocketServer({server});

wss.on('connection',(ws)=>{
  let room=null, index=-1;
  send(ws,{type:'hello'});
  ws.on('message',(raw)=>{
    let m; try{m=JSON.parse(raw)}catch{return;}
    if(m.type==='create'){
      if(room) return;
      room=makeRoom(); index=0;
      room.players[0]={ws,input:{x:0,y:0},x:250,y:350,hp:100,score:0,lastShot:0};
      send(ws,{type:'created',room:room.code});
      return;
    }
    if(m.type==='join'){
      if(room) return;
      const code=String(m.room||'').toUpperCase(); const r=rooms.get(code);
      if(!r || r.players[1]) return send(ws,{type:'error',message:'Комната не найдена или уже занята.'});
      room=r; index=1;
      room.players[1]={ws,input:{x:0,y:0},x:750,y:350,hp:100,score:0,lastShot:0};
      reset(room);
      broadcast(room,{type:'start',room:room.code});
      return;
    }
    if(!room || index<0) return;
    if(m.type==='input'){
      room.players[index].input={x:Math.max(-1,Math.min(1,Number(m.x)||0)),y:Math.max(-1,Math.min(1,Number(m.y)||0))};
    } else if(m.type==='shoot') fire(room,index);
  });
  ws.on('close',()=>{
    if(!room||index<0) return;
    room.players[index]=null; room.running=false; room.bullets=[];
    const other=room.players[1-index]; if(other) send(other.ws,{type:'opponent_left'});
    closeRoomIfEmpty(room);
  });
});

setInterval(()=>{
  const now=Date.now();
  for(const r of rooms.values()){
    const dt=Math.min(0.1,(now-r.lastTick)/1000); r.lastTick=now;
    tick(r,dt);
    if(r.running) broadcast(r,snapshot(r));
  }
},TICK);

server.listen(PORT,'0.0.0.0',()=>console.log(`NEON ARENA server listening on ${PORT}`));
