(()=>{
  const THREE_URL='https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js';
  const look={active:false,id:null,lastX:0,lastY:0,yaw:0};
  let lastAim={x:1,y:0};
  const sensitivity=0.012;
  const blockedTarget=el=>!!(el&&el.closest&&el.closest('#moveStick,#aimStick,#fire,#reload,.screen,button,input'));
  const getTouch=e=>Array.from(e.touches).find(t=>t.identifier===look.id)||null;
  const setAimFromYaw=()=>{const a=look.yaw-Math.PI/2;lastAim={x:Math.cos(a),y:Math.sin(a)}};
  const begin=e=>{
    if(!e.touches||e.touches.length!==1||blockedTarget(e.target)||!document.getElementById('hud')||document.getElementById('hud').classList.contains('hidden'))return;
    const t=e.touches[0];
    look.active=true;look.id=t.identifier;look.lastX=t.clientX;look.lastY=t.clientY;
    look.yaw=Math.atan2(lastAim.y,lastAim.x)+Math.PI/2;
    e.preventDefault();
  };
  const move=e=>{
    if(!look.active)return;
    const t=getTouch(e);if(!t)return;
    const dx=t.clientX-look.lastX;
    look.lastX=t.clientX;look.lastY=t.clientY;
    look.yaw+=dx*sensitivity;
    setAimFromYaw();
    e.preventDefault();
  };
  const end=e=>{
    if(!look.active)return;
    const still=Array.from(e.touches||[]).some(t=>t.identifier===look.id);
    if(!still){look.active=false;look.id=null;}
  };
  window.addEventListener('touchstart',begin,{passive:false});
  window.addEventListener('touchmove',move,{passive:false});
  window.addEventListener('touchend',end,{passive:false});
  window.addEventListener('touchcancel',end,{passive:false});
  const OriginalSend=WebSocket.prototype.send;
  WebSocket.prototype.send=function(data){
    try{
      const m=JSON.parse(data);
      if(m&&m.type==='input'&&look.active){m.aimX=lastAim.x;m.aimY=lastAim.y;data=JSON.stringify(m)}
    }catch{}
    return OriginalSend.call(this,data);
  };
  const style=document.createElement('style');
  style.textContent='#aimStick{display:none!important}.lookHint{position:fixed;left:50%;top:68%;transform:translate(-50%,-50%);padding:6px 12px;border:1px solid #2ce5ff55;border-radius:10px;background:#07142699;color:#8fdfff;font:700 12px system-ui;letter-spacing:.5px;pointer-events:none;opacity:.75;z-index:4}';
  document.head.appendChild(style);
  const hint=document.createElement('div');hint.className='lookHint';hint.textContent='ПРОВЕДИ ПАЛЬЦЕМ — ПОВОРОТ';
  const sync=()=>{const hud=document.getElementById('hud');if(hud&&!hud.contains(hint))hud.appendChild(hint);if(hud)hint.style.display=hud.classList.contains('hidden')?'none':'block'};
  setInterval(sync,500);sync();
  import(THREE_URL).then(THREE=>{
    const originalLookAt=THREE.PerspectiveCamera.prototype.lookAt;
    THREE.PerspectiveCamera.prototype.lookAt=function(x,y,z){
      const dx=x-this.position.x,dz=z-this.position.z,dist=Math.hypot(dx,dz)||1;
      const ca=Math.cos(look.yaw),sa=Math.sin(look.yaw);
      const nx=(dx/dist)*ca-(dz/dist)*sa,nz=(dx/dist)*sa+(dz/dist)*ca;
      const reach=Math.max(8,dist);
      return originalLookAt.call(this,this.position.x+nx*reach,y,this.position.z+nz*reach);
    };
  }).catch(()=>{});
})();
