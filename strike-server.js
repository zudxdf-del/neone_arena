const http=require('http'),fs=require('fs'),{WebSocketServer}=require('ws');
const PORT=Number(process.env.PORT)||8080,rooms=new Map(),RECONNECT_MS=600000;
const send=(w,x)=>w&&w.readyState===1&&w.send(JSON.stringify(x));
const code=()=>{let c;do c=''+Math.floor(1000+Math.random()*9000);while(rooms.has(c));return c};
function mines(seed){let x=seed>>>0,s=new Set;while(s.size<15){x=(Math.imul(x,1664525)+1013904223)>>>0;s.add(x%100)}return s}
function near(i,m){let n=0,x=i%10,y=i/10|0;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;let a=x+dx,b=y+dy;if(a>=0&&a<10&&b>=0&&b<10&&m.has(b*10+a))n++}return n}
function zone(i,m){let n=0,x=i%10,y=i/10|0;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){let a=x+dx,b=y+dy;if(a>=0&&a<10&&b>=0&&b<10&&m.has(b*10+a))n++}return n}
function revealed(r){let a={};for(const i of r.opened)a[i]={mine:r.mines.has(i),number:r.mines.has(i)?0:near(i,r.mines)};return a}
function snap(r){return{type:'state',room:r.code,seed:r.seed,turn:r.turn,scores:r.scores,opened:[...r.opened],revealed:revealed(r),finished:r.finished,winner:r.winner,firewall:r.firewall}}
function bc(r,x){r.p.forEach(p=>p&&send(p.ws,x))}
function reset(r){r.seed=Math.floor(Math.random()*0xffffffff)>>>0;r.mines=mines(r.seed);r.opened=new Set;r.scores=[0,0];r.turn=0;r.finished=false;r.winner=null;r.firewall=[false,false];r.utility=[null,null];r.restartPending=false}
const server=http.createServer((q,s)=>{
  const p=(q.url||'/').split('?')[0];
  if(p==='/api/health'){
    s.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Access-Control-Allow-Origin':'*'});
    s.end(JSON.stringify({ok:true,runtime:'node_web',websocket:true,port:PORT,rooms:rooms.size,time:new Date().toISOString()}));
    return;
  }
  if(p==='/api/servers'){
    s.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});
    s.end(JSON.stringify([...rooms].filter(([,r])=>r.p[0]&&!r.p[1]).map(([id])=>({id,name:'Секретная сессия',players:1,maxPlayers:2}))));
    return;
  }
  if(['/','/index.html','/strike.html','/criminal-mines.html'].includes(p)){
    s.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});
    fs.createReadStream(__dirname+'/criminal-mines.html').on('error',()=>s.end('Game file not found')).pipe(s);return;
  }
  s.writeHead(404);s.end();
});
const wss=new WebSocketServer({server});
server.on('upgrade',(req)=>console.log('[ws-upgrade]',req.url,'origin=',req.headers.origin||'-'));
wss.on('connection',(ws,req)=>{
  console.log('[ws-open]',req.url,'ip=',req.socket.remoteAddress||'-');
  let r=null,i=-1;
  ws.on('message',b=>{
    let m;try{m=JSON.parse(b)}catch{return}
    if(m.type==='create'){r={code:code(),p:[null,null]};reset(r);r.p[0]={ws,name:m.nick||'Игрок 1',timer:null};i=0;rooms.set(r.code,r);send(ws,{type:'room',room:r.code,role:0,seed:r.seed});send(ws,{type:'waiting'});return}
    if(m.type==='join'){r=rooms.get(String(m.room));if(!r)return send(ws,{type:'error',message:'Комната не найдена.'});if(r.p[1])return send(ws,{type:'error',message:'Комната уже заполнена.'});r.p[1]={ws,name:m.nick||'Игрок 2',timer:null};i=1;send(ws,{type:'room',room:r.code,role:1,seed:r.seed});bc(r,{type:'ready'});setTimeout(()=>bc(r,snap(r)),30);return}
    if(m.type==='resume'){r=rooms.get(String(m.room));i=Number(m.role);if(!r||!r.p[i])return send(ws,{type:'error',message:'Сессию восстановить не удалось.'});if(r.p[i].timer)clearTimeout(r.p[i].timer);r.p[i].ws=ws;send(ws,{type:'room',room:r.code,role:i,seed:r.seed,resumed:true});send(ws,snap(r));return}
    if(!r||r.finished)return;
    if(m.type==='utility'){if(i!==r.turn)return send(ws,{type:'error',message:'Сейчас ход соперника.'});let u=m.utility,cost={scan:40,firewall:60,skip:30}[u];if(!cost||r.scores[i]<cost)return send(ws,{type:'error',message:'Недостаточно очков.'});if(r.utility[i])return send(ws,{type:'error',message:'Только одна утилита за ход.'});if(u==='scan'){r.scores[i]-=40;r.utility[i]='scan';send(ws,{type:'scanArmed'});bc(r,snap(r))}else if(u==='firewall'){r.scores[i]-=60;r.firewall[i]=true;r.utility[i]='firewall';bc(r,snap(r))}else{r.scores[i]-=30;r.turn=1-i;r.utility=[null,null];bc(r,{type:'utilitySkip',scores:r.scores,turn:r.turn});bc(r,snap(r))}return}
    if(m.type==='scan'){if(i!==r.turn||r.utility[i]!=='scan')return;r.utility[i]=null;let idx=Number(m.index),cells=[];for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){let x=idx%10+dx,y=(idx/10|0)+dy;if(x>=0&&x<10&&y>=0&&y<10){let j=y*10+x;cells.push({index:j,count:zone(j,r.mines)})}}send(ws,{type:'scanResult',cells});return}
    if(m.type==='move'){if(i!==r.turn)return send(ws,{type:'error',message:'Сейчас ход соперника.'});let idx=Number(m.index);if(!Number.isInteger(idx)||idx<0||idx>99||r.opened.has(idx))return;let mine=r.mines.has(idx),fw=r.firewall[i]&&mine;r.opened.add(idx);if(mine){if(fw)r.firewall[i]=false;else{r.scores[i]-=50;r.scores[1-i]+=50}}else r.scores[i]+=10;r.turn=1-i;r.utility=[null,null];let mi=0,sa=0;for(const x of r.opened)r.mines.has(x)?mi++:sa++;if(mi===15||sa===85){r.finished=true;r.winner=r.scores[0]===r.scores[1]?-1:r.scores[0]>r.scores[1]?0:1}bc(r,{type:'move',index:idx,mine,number:mine?0:near(idx,r.mines),scores:r.scores,turn:r.turn,firewall:r.firewall,finished:r.finished,winner:r.winner});bc(r,snap(r));if(r.finished)bc(r,{type:'finished',scores:r.scores,winner:r.winner});return}
    if(m.type==='restart_request'&&i===0&&r.finished){r.restartPending=true;send(r.p[1]&&r.p[1].ws,{type:'restart_offer'});return}
    if(m.type==='restart_response'&&i===1&&r.restartPending){r.restartPending=false;if(m.accept){reset(r);bc(r,{type:'restart_started'});bc(r,snap(r))}else send(r.p[0]&&r.p[0].ws,{type:'restart_rejected'})}
  });
  ws.on('close',()=>{console.log('[ws-close]');if(r&&i>=0&&r.p[i]&&r.p[i].ws===ws){r.p[i].ws=null;r.p[i].timer=setTimeout(()=>{if(r.p[i]&&!r.p[i].ws)r.p[i]=null},RECONNECT_MS)}});
  ws.on('error',e=>console.error('[ws-error]',e.message));
});
process.on('uncaughtException',e=>console.error('[uncaughtException]',e));
process.on('unhandledRejection',e=>console.error('[unhandledRejection]',e));
server.listen(PORT,'0.0.0.0',()=>console.log('Criminal Mines listening on '+PORT));
