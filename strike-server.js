const http=require('http'),fs=require('fs'),{WebSocketServer}=require('ws');
const PORT=process.env.PORT||8080,rooms=new Map();
const send=(w,x)=>w.readyState===1&&w.send(JSON.stringify(x));
const code=()=>{let c;do c=String(Math.floor(1000+Math.random()*9000));while(rooms.has(c));return c};
function broadcast(r,x){r.p.forEach(q=>q&&send(q.ws,x))}
function publicRooms(){return [...rooms.entries()].filter(([,r])=>r.p[0]&&!r.p[1]).map(([id],n)=>({id,name:'Секретная сессия '+(n+1),players:1,maxPlayers:2}))}
const server=http.createServer((req,res)=>{const path=(req.url||'/').split('?')[0];
if(path==='/api/servers'){res.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(publicRooms()));return}
if(path==='/'||path==='/index.html'||path==='/strike.html'||path==='/criminal-mines.html'){const file=__dirname+'/criminal-mines.html';if(fs.existsSync(file)){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});fs.createReadStream(file).pipe(res)}else{res.writeHead(500);res.end('Game page not found')}return}
res.writeHead(404);res.end('Not found')});
const wss=new WebSocketServer({server});
wss.on('connection',ws=>{let r=null,i=-1;
ws.on('message',b=>{let m;try{m=JSON.parse(b)}catch{return}
if(m.type==='servers'){send(ws,{type:'servers',servers:publicRooms()});return}
if(m.type==='create'){r={code:code(),p:[null,null]};i=0;r.p[0]={ws,name:String(m.nick||'Игрок 1').slice(0,18)};rooms.set(r.code,r);send(ws,{type:'created',player:0});send(ws,{type:'room',room:r.code,role:0});send(ws,{type:'waiting'});return}
if(m.type==='join'){r=rooms.get(String(m.room||''));if(!r)return send(ws,{type:'error',message:'Комната не найдена. Проверь код.'});if(r.p[1])return send(ws,{type:'error',message:'Комната уже заполнена.'});i=1;r.p[1]={ws,name:String(m.nick||'Игрок 2').slice(0,18)};send(ws,{type:'room',room:r.code,role:1});broadcast(r,{type:'ready',names:r.p.map(p=>p.name)});return}
});
ws.on('close',()=>{if(r&&i>=0){r.p[i]=null;if(!r.p[0]&&!r.p[1])rooms.delete(r.code);else broadcast(r,{type:'left'})}})});
server.listen(PORT,'0.0.0.0',()=>console.log('Криминальный Сапёр on '+PORT));