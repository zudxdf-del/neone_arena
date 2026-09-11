const http=require('http'),fs=require('fs'),{WebSocketServer}=require('ws');
const PORT=process.env.PORT||8080,rooms=new Map();
const send=(w,x)=>w.readyState===1&&w.send(JSON.stringify(x));
const code=()=>{let c;do c=String(Math.floor(1000+Math.random()*9000));while(rooms.has(c));return c};
function makeMines(seed){let x=seed>>>0,s=new Set;while(s.size<15){x=(Math.imul(x,1664525)+1013904223)>>>0;s.add(x%100)}return s}
function adjacent(i,mines){let n=0,x=i%10,y=Math.floor(i/10);for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;let nx=x+dx,ny=y+dy;if(nx>=0&&nx<10&&ny>=0&&ny<10&&mines.has(ny*10+nx))n++}return n}
const state=r=>({type:'state',turn:r.turn,scores:r.scores,opened:[...r.opened],moves:r.moves});
function broadcast(r,x){r.p.forEach(q=>q&&send(q.ws,x))}
function publicRooms(){return [...rooms.entries()].filter(([,r])=>r.p[0]&&!r.p[1]).map(([id],r)=>({id,name:'Секретная сессия',players:1,maxPlayers:2}))}
const server=http.createServer((req,res)=>{const path=(req.url||'/').split('?')[0];
if(path==='/api/servers'){res.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(publicRooms()));return}
if(path==='/'||path==='/index.html'||path==='/strike.html'||path==='/criminal-mines.html'){const file=__dirname+'/criminal-mines.html';if(fs.existsSync(file)){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});fs.createReadStream(file).pipe(res)}else{res.writeHead(500);res.end('Game page not found')}return}
res.writeHead(404);res.end('Not found')});
const wss=new WebSocketServer({server});
wss.on('connection',ws=>{let r=null,i=-1;
ws.on('message',b=>{let m;try{m=JSON.parse(b)}catch{return}
if(m.type==='servers'){send(ws,{type:'servers',servers:publicRooms()});return}
if(m.type==='create'){r={code:code(),seed:(Math.floor(Math.random()*0xffffffff)>>>0),p:[null,null],turn:0,scores:[0,0],opened:new Set,moves:0,mines:null};r.mines=makeMines(r.seed);i=0;r.p[0]={ws,name:String(m.nick||'Игрок 1').slice(0,18)};rooms.set(r.code,r);send(ws,{type:'room',room:r.code,role:0,seed:r.seed});send(ws,{type:'waiting'});return}
if(m.type==='join'){r=rooms.get(String(m.room||''));if(!r)return send(ws,{type:'error',message:'Комната не найдена. Проверь код.'});if(r.p[1])return send(ws,{type:'error',message:'Комната уже заполнена.'});i=1;r.p[1]={ws,name:String(m.nick||'Игрок 2').slice(0,18)};send(ws,{type:'room',room:r.code,role:1,seed:r.seed});broadcast(r,{type:'ready',names:r.p.map(p=>p.name),seed:r.seed});setTimeout(()=>broadcast(r,state(r)),50);return}
if(m.type==='move'){if(!r||i<0)return;if(i!==r.turn)return send(ws,{type:'error',message:'Сейчас ход другого хакера.'});let idx=Number(m.index);if(!Number.isInteger(idx)||idx<0||idx>=100)return;if(r.opened.has(idx))return send(ws,{type:'error',message:'Эта ячейка уже открыта.'});let mine=r.mines.has(idx);r.opened.add(idx);if(mine){r.scores[i]-=50;r.scores[1-i]+=50}else r.scores[i]+=10;r.turn=1-r.turn;r.moves++;broadcast(r,{type:'move',index:idx,mine,number:mine?0:adjacent(idx,r.mines),by:i,scores:r.scores,turn:r.turn});broadcast(r,state(r));return}
});
ws.on('close',()=>{if(r&&i>=0){r.p[i]=null;if(!r.p[0]&&!r.p[1])rooms.delete(r.code);else broadcast(r,{type:'left'})}})});
server.listen(PORT,'0.0.0.0',()=>console.log('Криминальный Сапёр on '+PORT));