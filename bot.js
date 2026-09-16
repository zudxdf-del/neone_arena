const mineflayer = require('mineflayer')
const { pathfinder, Movements, goals } = require('mineflayer-pathfinder')
const mcDataLib = require('minecraft-data')
const fs = require('fs')

const CFG = {
  host: process.env.MC_HOST || 'funvanillaworld.aternos.me',
  port: Number(process.env.MC_PORT || 57004),
  username: process.env.MC_USERNAME || 'Bot_Vanilla',
  version: process.env.MC_VERSION || '1.21.11',
  ollama: process.env.OLLAMA_URL || 'http://127.0.0.1:11434/api/generate',
  model: process.env.OLLAMA_MODEL || 'llama3',
  memory: process.env.MEMORY_FILE || './memory.json'
}

const sleep = ms => new Promise(r => setTimeout(r, ms))
const OPEN = new Set(['air','cave_air','void_air','water','lava','short_grass','tall_grass','fern','large_fern','snow','vine','glow_lichen'])
const HOSTILE = new Set(['zombie','skeleton','creeper','spider','cave_spider','drowned','husk','stray','witch','pillager','vindicator','evoker','ravager','silverfish','endermite','phantom','piglin_brute'])
const ORE = { coal_ore:['coal_ore','deepslate_coal_ore'], iron_ore:['iron_ore','deepslate_iron_ore'], copper_ore:['copper_ore','deepslate_copper_ore'], gold_ore:['gold_ore','deepslate_gold_ore'], redstone_ore:['redstone_ore','deepslate_redstone_ore'], lapis_ore:['lapis_ore','deepslate_lapis_ore'], diamond_ore:['diamond_ore','deepslate_diamond_ore'], emerald_ore:['emerald_ore','deepslate_emerald_ore'] }

class Agent {
  constructor(bot) {
    this.bot = bot
    this.task = 0
    this.busy = false
    this.memory = this.loadMemory()
  }
  loadMemory() { try { return JSON.parse(fs.readFileSync(CFG.memory,'utf8')) } catch (_) { return { players:{}, locations:{}, history:[] } } }
  saveMemory() { try { fs.writeFileSync(CFG.memory, JSON.stringify(this.memory,null,2)) } catch (_) {} }
  remember(user, message) { this.memory.players[user] = { ...(this.memory.players[user]||{}), lastMessage:message, lastSeen:Date.now() }; this.memory.history.push({user,message,at:Date.now()}); this.memory.history=this.memory.history.slice(-80); this.saveMemory() }
  say(text) { text=String(text||'').replace(/\s+/g,' ').trim().slice(0,240); if(text) this.bot.chat(text) }
  stop(text='Остановился.') { this.task++; this.busy=false; this.bot.pathfinder.setGoal(null); this.bot.clearControlStates(); this.say(text) }

  world() {
    const p=this.bot.entity?.position
    return { position:p?{x:Math.round(p.x),y:Math.round(p.y),z:Math.round(p.z)}:null, health:this.bot.health, food:this.bot.food, dimension:this.bot.game?.dimension, players:Object.values(this.bot.players).filter(x=>x.username).map(x=>({name:x.username,visible:!!x.entity})), entities:Object.values(this.bot.entities).filter(e=>e?.position).slice(0,30).map(e=>({name:e.username||e.name||e.type,type:e.type,distance:p?Number(e.position.distanceTo(p).toFixed(1)):0})) }
  }

  async askAI(message,user) {
    const prompt=`Ты управляешь Minecraft AI-агентом. Отвечай кратко. Никакого X-Ray: агент не знает содержимое блоков за стенами. Он может использовать только то, что реально наблюдает через Mineflayer. Если руда скрыта, нужно физически исследовать местность. Не придумывай координаты и находки.\nМИР=${JSON.stringify(this.world())}\nИГРОК=${user}\nКОМАНДА=${message}\nВерни JSON: {"type":"chat|mine|follow|stop|jump|explore|inspect","target":"","count":0,"text":""}`
    const controller=new AbortController(); const timer=setTimeout(()=>controller.abort(),7000)
    try {
      const r=await fetch(CFG.ollama,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({model:CFG.model,prompt,stream:false,format:'json'}),signal:controller.signal})
      if(!r.ok) throw Error('Ollama HTTP '+r.status)
      const d=await r.json(); let s=String(d.response||'').trim(); const a=s.indexOf('{'),b=s.lastIndexOf('}'); if(a>=0&&b>a)s=s.slice(a,b+1); return JSON.parse(s)
    } catch(e) { console.log('[AI]',e.name==='AbortError'?'timeout':e.message); return this.parseCommand(message,user) }
    finally { clearTimeout(timer) }
  }

  parseCommand(message,user) {
    const m=message.toLowerCase()
    if(/стой|останов|отмен/.test(m)) return {type:'stop'}
    if(/ко мне|иди сюда|за мной|следуй/.test(m)) return {type:'follow'}
    if(/прыг/.test(m)) return {type:'jump'}
    if(/исслед|развед|поищ/.test(m)) return {type:'explore'}
    if(/что вокруг|осмотр|обстановка|где я/.test(m)) return {type:'inspect'}
    const x=m.match(/(?:добудь|накопай|собери|найди|принеси|сруби)\s*(\d+)?\s*(камн|булыж|дерев|бревн|угл|желез|мед|золот|алмаз|изумруд|редстоун|лазур|земл|песок|гравий)/i)
    if(x){const map={камн:'stone',булыж:'cobblestone',дерев:'log',бревн:'log',угл:'coal_ore',желез:'iron_ore',мед:'copper_ore',золот:'gold_ore',алмаз:'diamond_ore',изумруд:'emerald_ore',редстоун:'redstone_ore',лазур:'lapis_ore',земл:'dirt',песок:'sand',гравий:'gravel'}; const k=Object.keys(map).find(k=>x[2].includes(k)); return {type:'mine',target:map[k],count:Number(x[1]||10)}}
    return {type:'chat',text:`Да, ${user}, я здесь. Напиши, например: «бот добудь 10 железа» или «бот иди за мной».`}
  }

  exposed(block) {
    if(!block?.position) return false
    const p=block.position
    const around=[this.bot.blockAt(p.offset(1,0,0)),this.bot.blockAt(p.offset(-1,0,0)),this.bot.blockAt(p.offset(0,1,0)),this.bot.blockAt(p.offset(0,-1,0)),this.bot.blockAt(p.offset(0,0,1)),this.bot.blockAt(p.offset(0,0,-1))]
    if(!around.some(b=>!b||OPEN.has(b.name)||b.boundingBox==='empty')) return false
    try { if(typeof this.bot.canSeeBlock==='function' && !this.bot.canSeeBlock(block)) return false } catch (_) {}
    return true
  }
  match(block,target) {
    if(!block) return false
    const aliases={log:['oak_log','birch_log','spruce_log','jungle_log','acacia_log','dark_oak_log','mangrove_log','cherry_log'],stone:['stone','cobblestone','deepslate'],dirt:['dirt','grass_block','coarse_dirt','rooted_dirt'],sand:['sand','red_sand']}
    return (aliases[target]||ORE[target]||[target]).includes(block.name)
  }
  findVisible(target) {
    const positions=this.bot.findBlocks({maxDistance:32,count:120,matching:b=>this.match(b,target)})
    for(const pos of positions){const b=this.bot.blockAt(pos); if(this.exposed(b)) return b}
    return null
  }
  async moveTo(pos,id,timeout=18000) {
    this.bot.pathfinder.setGoal(new goals.GoalNear(pos.x,pos.y,pos.z,2)); const t=Date.now()
    while(Date.now()-t<timeout){ if(id!==this.task||!this.bot.entity)return false; if(this.bot.entity.position.distanceTo(pos)<=3.5){this.bot.pathfinder.setGoal(null);return true} await sleep(250) }
    this.bot.pathfinder.setGoal(null); return false
  }
  async tool(blockName) {
    const type=blockName.includes('log')?'axe':blockName.includes('dirt')||blockName.includes('sand')||blockName.includes('gravel')?'shovel':blockName.includes('ore')||['stone','cobblestone','deepslate'].includes(blockName)?'pickaxe':null
    if(!type)return
    const items=this.bot.inventory.items().filter(i=>i.name.endsWith('_'+type)).sort((a,b)=>b.name.length-a.name.length)
    if(items[0])try{await this.bot.equip(items[0],'hand')}catch(_){}
  }
  count(target) {
    const r=target==='log'?/_log$/:target==='stone'?/^(stone|cobblestone|deepslate)$/:target==='coal_ore'?/^(coal|coal_ore|deepslate_coal_ore)$/:target==='iron_ore'?/^(raw_iron|iron_ore|deepslate_iron_ore)$/:target==='copper_ore'?/^(raw_copper|copper_ore|deepslate_copper_ore)$/:target==='gold_ore'?/^(raw_gold|gold_ore|deepslate_gold_ore)$/:target==='diamond_ore'?/^diamond$/:target==='emerald_ore'?/^emerald$/:target==='redstone_ore'?/^redstone$/:target==='lapis_ore'?/^lapis_lazuli$/:new RegExp('^'+target.replace(/[.*+?^${}()|[\\]\\]/g,'\\$&')+'$')
    return this.bot.inventory.items().filter(i=>r.test(i.name)).reduce((n,i)=>n+i.count,0)
  }
  async mine(target,total,user) {
    if(this.busy){this.say('Я уже добываю. Скажи «бот стой», чтобы отменить.');return}
    this.busy=true; const id=++this.task; let got=0
    try {
      this.say(`Принял. Ищу ${target} без X-Ray.`)
      for(let attempt=0;attempt<40&&got<total&&id===this.task;attempt++){
        const block=this.findVisible(target)
        if(block){ const before=this.count(target); if(await this.moveTo(block.position,id)){ await this.tool(block.name); try{await this.bot.lookAt(block.position.offset(.5,.5,.5),true);await this.bot.dig(block,true)}catch(e){console.log('[DIG]',e.message)} await sleep(400); const gain=this.count(target)-before; if(gain>0)got+=gain; continue }}
        if(!await this.prospect(id)) break
      }
      if(got)this.say(`Готово. Я реально добыл ${got} шт. ${target}.`); else if(id===this.task)this.say(`Не нашёл ${target} обычным исследованием.`)
    } finally { if(id===this.task)this.busy=false }
  }
  async prospect(id) {
    if(id!==this.task||!this.bot.entity)return false
    const yaw=this.bot.entity.yaw; const dirs=[{x:Math.round(-Math.sin(yaw)),z:Math.round(-Math.cos(yaw))},{x:Math.round(Math.cos(yaw)),z:Math.round(-Math.sin(yaw))},{x:Math.round(Math.sin(yaw)),z:Math.round(Math.cos(yaw))}]; const d=dirs[Math.floor(Math.random()*dirs.length)]
    for(let i=0;i<8&&id===this.task;i++){
      const p=this.bot.entity.position; const front=this.bot.blockAt(p.offset(d.x,0,d.z)); const head=this.bot.blockAt(p.offset(d.x,1,d.z))
      if(front&&!OPEN.has(front.name)&&front.name!=='bedrock'){await this.tool(front.name);try{await this.bot.lookAt(front.position.offset(.5,.5,.5),true);await this.bot.dig(front,true)}catch(_) {}}
      if(head&&!OPEN.has(head.name)&&head.name!=='bedrock'){try{await this.bot.lookAt(head.position.offset(.5,.5,.5),true);await this.bot.dig(head,true)}catch(_) {}}
      this.bot.setControlState('forward',true); await sleep(650); this.bot.setControlState('forward',false)
      if(this.findVisible('diamond_ore')||this.findVisible('iron_ore')||this.findVisible('coal_ore')) return true
    }
    return true
  }
  async follow(user){const p=this.bot.players[user]?.entity;if(!p){this.say('Я тебя сейчас не вижу.');return}this.task++;this.busy=false;this.bot.pathfinder.setGoal(new goals.GoalFollow(p,2),true);this.say('Иду за тобой.')}
  async explore(){if(this.busy){this.say('Я уже занят.');return}this.busy=true;const id=++this.task;try{const p=this.bot.entity.position,a=Math.random()*Math.PI*2;await this.moveTo({x:p.x+Math.cos(a)*20,y:p.y,z:p.z+Math.sin(a)*20},id,15000);this.say('Разведка закончена.')}finally{if(id===this.task)this.busy=false}}
  inspect(){const w=this.world();this.say(`Я на ${w.position?.x}, ${w.position?.y}, ${w.position?.z}. HP ${Math.round(w.health)}, еда ${Math.round(w.food)}.`)}
  async handle(user,message){
    if(!message||user===this.bot.username)return
    this.remember(user,message)
    const addressed=/^(бот|bot)\b/i.test(message.trim())
    if(!addressed&&!this.busy)return
    const command=message.replace(/^(бот|bot)[,!: ]*/i,'').trim()||message
    this.say('Принял команду.')
    const a=await this.askAI(command,user)
    if(a.type==='chat')this.say(a.text); else if(a.type==='stop')this.stop(); else if(a.type==='follow')await this.follow(user); else if(a.type==='jump'){this.bot.setControlState('jump',true);await sleep(180);this.bot.setControlState('jump',false)} else if(a.type==='mine')await this.mine(String(a.target||'stone'),Math.min(64,Math.max(1,Number(a.count)||1)),user); else if(a.type==='explore')await this.explore(); else if(a.type==='inspect')this.inspect()
  }
}

function start(){
  const bot=mineflayer.createBot({host:CFG.host,port:CFG.port,username:CFG.username,version:CFG.version}); bot.loadPlugin(pathfinder); let agent
  bot.once('spawn',()=>{const data=mcDataLib(bot.version),mov=new Movements(bot,data);mov.canDig=true;mov.allowParkour=true;mov.allowSprinting=true;bot.pathfinder.setMovements(mov);agent=new Agent(bot);bot.chat('Я онлайн. Пиши «бот привет».');console.log('[BOT] online')})
  bot.on('chat',(u,m)=>agent?.handle(u,m).catch(e=>console.log('[CHAT]',e.message)))
  bot.on('error',e=>console.log('[ERROR]',e.message)); bot.on('kicked',r=>console.log('[KICKED]',r)); bot.on('end',()=>{console.log('[BOT] reconnect in 8s');setTimeout(start,8000)})
}
start()
