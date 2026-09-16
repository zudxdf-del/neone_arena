const mineflayer = require('mineflayer')
const { pathfinder, Movements, goals } = require('mineflayer-pathfinder')
const minecraftData = require('minecraft-data')
const fs = require('fs')

const CONFIG = {
  host: process.env.MC_HOST || 'funvanillaworld.aternos.me',
  port: Number(process.env.MC_PORT || 57004),
  username: process.env.MC_USERNAME || 'Bot_Vanilla',
  version: process.env.MC_VERSION || '1.21.11',
  ollamaUrl: process.env.OLLAMA_URL || 'http://127.0.0.1:11434/api/generate',
  ollamaModel: process.env.OLLAMA_MODEL || 'llama3',
  memoryFile: process.env.MEMORY_FILE || './memory.json'
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

const HOSTILE = new Set([
  'zombie', 'skeleton', 'creeper', 'spider', 'cave_spider', 'drowned',
  'husk', 'stray', 'witch', 'pillager', 'vindicator', 'evoker',
  'ravager', 'silverfish', 'endermite', 'phantom', 'piglin_brute'
])

const ORES = new Set([
  'coal_ore', 'deepslate_coal_ore',
  'iron_ore', 'deepslate_iron_ore',
  'copper_ore', 'deepslate_copper_ore',
  'gold_ore', 'deepslate_gold_ore',
  'redstone_ore', 'deepslate_redstone_ore',
  'lapis_ore', 'deepslate_lapis_ore',
  'diamond_ore', 'deepslate_diamond_ore',
  'emerald_ore', 'deepslate_emerald_ore',
  'nether_gold_ore', 'nether_quartz_ore', 'ancient_debris'
])

const TRANSPARENT = new Set([
  'air', 'cave_air', 'void_air', 'water', 'lava',
  'short_grass', 'tall_grass', 'fern', 'large_fern',
  'snow', 'vine', 'glow_lichen'
])

class Memory {
  constructor(file) {
    this.file = file
    this.data = this.load()
  }

  load() {
    try {
      const data = JSON.parse(fs.readFileSync(this.file, 'utf8'))
      if (data && typeof data === 'object') return data
    } catch (_) {}
    return { players: {}, locations: {}, events: [] }
  }

  save() {
    try { fs.writeFileSync(this.file, JSON.stringify(this.data, null, 2)) } catch (e) { console.log('[MEMORY]', e.message) }
  }

  player(username, patch = {}) {
    if (!this.data.players[username]) this.data.players[username] = {}
    Object.assign(this.data.players[username], patch)
    this.save()
  }

  location(key, position, note = '') {
    this.data.locations[key] = {
      position: position ? { x: Math.round(position.x), y: Math.round(position.y), z: Math.round(position.z) } : null,
      note,
      at: Date.now()
    }
    this.save()
  }

  event(type, data = {}) {
    this.data.events.push({ type, data, at: Date.now() })
    if (this.data.events.length > 300) this.data.events.splice(0, this.data.events.length - 300)
    this.save()
  }
}

class World {
  constructor(bot) { this.bot = bot }
  position() { const p = this.bot?.entity?.position; return p ? { x: Math.round(p.x), y: Math.round(p.y), z: Math.round(p.z) } : null }
  players() { return Object.values(this.bot.players || {}).filter(p => p.username && p.username !== this.bot.username).map(p => ({ name: p.username, visible: !!p.entity, position: p.entity ? { x: Math.round(p.entity.position.x), y: Math.round(p.entity.position.y), z: Math.round(p.entity.position.z) } : null })) }
  entities() { const pos = this.bot?.entity?.position; if (!pos) return []; return Object.values(this.bot.entities || {}).map(e => ({ entity: e, distance: e.position.distanceTo(pos) })).filter(x => x.distance <= 16).sort((a, b) => a.distance - b.distance).map(x => ({ name: x.entity.name, type: x.entity.type, distance: Math.round(x.distance * 10) / 10 })) }
  danger(radius = 8) { const pos = this.bot?.entity?.position; if (!pos) return null; return Object.values(this.bot.entities || {}).map(e => ({ entity: e, distance: e.position.distanceTo(pos) })).filter(x => x.distance <= radius && HOSTILE.has(x.entity.name)).sort((a, b) => a.distance - b.distance)[0] || null }
  snapshot() { return { position: this.position(), health: this.bot.health, food: this.bot.food, dimension: this.bot.game?.dimension, time: this.bot.time?.timeOfDay, players: this.players().slice(0, 16), entities: this.entities().slice(0, 20), inventory: this.bot.inventory.items().map(i => ({ name: i.name, count: i.count })) } }
}

class Agent {
  constructor(bot) { this.bot = bot; this.world = new World(bot); this.memory = new Memory(CONFIG.memoryFile); this.cancelVersion = 0; this.busy = false; this.following = null; this.lastDanger = 0; this.lastAutonomy = 0 }
  say(text) { const clean = String(text || '').replace(/\s+/g, ' ').trim().slice(0, 240); if (clean) this.bot.chat(clean) }
  cancel(message = '') { this.cancelVersion++; this.busy = false; this.following = null; this.bot.pathfinder.setGoal(null); if (this.bot.clearControlStates) this.bot.clearControlStates(); if (message) this.say(message) }

  async askAI(message, username) {
    const prompt = `
Ты управляешь Minecraft AI-агентом Bot_Vanilla.
Это НЕ X-Ray бот. Агент не видит блоки сквозь стены и не получает координаты скрытых руд.
Он может использовать только физически наблюдаемый мир Minecraft и действия Mineflayer.

Выбирай реальные действия:
chat, follow, stop, jump, mine, explore, go_to_player, inspect, remember, none.

ВАЖНО:
- Для руды нельзя говорить, что она найдена, если бот ее реально не увидел.
- Если ресурс скрыт, агент должен исследовать мир или физически прокладывать безопасную разведочную шахту.
- Не придумывай координаты.
- Если команда неясна, задай вопрос.

МИР:
${JSON.stringify(this.world.snapshot())}

ПАМЯТЬ:
${JSON.stringify(this.memory.data.players[username] || {})}

КОМАНДА ИГРОКА: ${message}

Верни только JSON-массив действий. Пример: [{"type":"mine","target":"dirt","count":5}]
`
    try { const result = await this.ollama(prompt); if (Array.isArray(result)) return result; if (Array.isArray(result.actions)) return result.actions } catch (e) { console.log('[AI]', e.message) }
    return this.fallback(message, username)
  }

  async ollama(prompt) {
    const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 120000)
    try {
      const response = await fetch(CONFIG.ollamaUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ model: CONFIG.ollamaModel, prompt, format: 'json', stream: false, keep_alive: -1, options: { num_ctx: 8192, num_predict: 1600, temperature: 0.1 } }), signal: controller.signal })
      const raw = await response.text(); let data = {}; try { data = JSON.parse(raw) } catch (_) {}
      if (!response.ok) throw Error(`Ollama HTTP ${response.status}: ${data.error || raw}`)
      return JSON.parse(data.response || '{}')
    } catch (e) { if (e.name === 'AbortError') throw Error('таймаут Ollama: 120 секунд'); throw e } finally { clearTimeout(timer) }
  }

  fallback(message, username) {
    const m = message.toLowerCase()
    if (/стой|останов/.test(m)) return [{ type: 'stop' }]
    if (/ко мне|иди сюда|за мной|следуй/.test(m)) return [{ type: 'go_to_player' }]
    if (/прыг/.test(m)) return [{ type: 'jump' }]
    if (/исслед|развед|поищ/.test(m)) return [{ type: 'explore' }]
    if (/что вокруг|осмотр|где я|обстановка/.test(m)) return [{ type: 'inspect' }]
    const match = m.match(/(?:добудь|накопай|собери|найди|принеси|сруби)\s*(\d+)?\s*(камн|булыж|дерев|бревн|угл|желез|мед|золот|алмаз|изумруд|редстоун|лазур|земл|песок|гравий)/i)
    if (match) {
      const count = Number(match[1] || 10); const map = { камн: 'stone', булыж: 'cobblestone', дерев: 'log', бревн: 'log', угл: 'coal_ore', желез: 'iron_ore', мед: 'copper_ore', золот: 'gold_ore', алмаз: 'diamond_ore', изумруд: 'emerald_ore', редстоун: 'redstone_ore', лазур: 'lapis_ore', земл: 'dirt', песок: 'sand', гравий: 'gravel' }; const key = Object.keys(map).find(k => match[2].includes(k)); return [{ type: 'mine', target: map[key], count }]
    }
    return [{ type: 'chat', text: `Слышу тебя, ${username}. Могу исследовать мир, реально искать и добывать ресурсы, следовать за тобой и защищаться.` }]
  }

  blockMatches(block, target) {
    if (!block) return false
    const aliases = { log: ['oak_log', 'birch_log', 'spruce_log', 'jungle_log', 'acacia_log', 'dark_oak_log', 'mangrove_log', 'cherry_log'], stone: ['stone', 'cobblestone', 'deepslate'], dirt: ['dirt', 'grass_block', 'coarse_dirt', 'rooted_dirt'], sand: ['sand', 'red_sand'] }
    return (aliases[target] || [target]).includes(block.name)
  }
  isTransparent(block) { return !block || TRANSPARENT.has(block.name) || block.boundingBox === 'empty' }

  canPhysicallySee(block) {
    if (!block || !block.position || !this.bot.entity) return false
    const eye = this.bot.entity.position.offset(0, Number(this.bot.entity.height || 1.62) * 0.85, 0)
    const center = block.position.offset(0.5, 0.5, 0.5)
    const distance = eye.distanceTo(center)
    if (distance > 32) return false
    if (typeof this.bot.canSeeBlock === 'function') { try { if (!this.bot.canSeeBlock(block)) return false } catch (_) { return false } }
    const steps = Math.max(2, Math.ceil(distance / 0.18))
    for (let i = 1; i < steps; i++) {
      const t = i / steps; const x = eye.x + (center.x - eye.x) * t; const y = eye.y + (center.y - eye.y) * t; const z = eye.z + (center.z - eye.z) * t
      const hit = this.bot.blockAt({ x: Math.floor(x), y: Math.floor(y), z: Math.floor(z) })
      if (hit && hit.position && hit.position.equals(block.position)) continue
      if (hit && !this.isTransparent(hit)) return false
    }
    return true
  }

  findVisibleResource(target, radius = 32) {
    const positions = this.bot.findBlocks({ maxDistance: radius, count: 120, matching: block => this.blockMatches(block, target) })
    for (const pos of positions) { const block = this.bot.blockAt(pos); if (this.canPhysicallySee(block)) return block }
    return null
  }
  findVisibleOre(radius = 32) {
    const positions = this.bot.findBlocks({ maxDistance: radius, count: 160, matching: block => ORES.has(block.name) })
    for (const pos of positions) { const block = this.bot.blockAt(pos); if (this.canPhysicallySee(block)) return block }
    return null
  }

  async lookToward(pos, force = false) {
    if (!pos || !this.bot.entity) return false
    try { await this.bot.lookAt({ x: Number(pos.x) + 0.5, y: Number(pos.y) + 0.5, z: Number(pos.z) + 0.5 }, force); return true } catch (_) { return false }
  }

  async moveNear(pos, version, timeout = 18000) {
    if (!pos || !this.bot.entity) return false
    await this.lookToward(pos, false)
    this.bot.pathfinder.setGoal(new goals.GoalNear(pos.x, pos.y, pos.z, 2))
    const started = Date.now(); let lastLook = 0
    try {
      while (Date.now() - started < timeout) {
        if (version !== this.cancelVersion || !this.bot.entity) return false
        if (this.bot.entity.position.distanceTo(pos) <= 3.5) { await this.lookToward(pos, true); return true }
        if (Date.now() - lastLook >= 250) { lastLook = Date.now(); await this.lookToward(pos, false) }
        if (this.world.danger(8)) await this.defend(version)
        await sleep(150)
      }
      return false
    } finally { this.bot.pathfinder.setGoal(null) }
  }

  inventoryCount(target) {
    const aliases = { log: /_log$/, stone: /^(stone|cobblestone|deepslate)$/, coal_ore: /^(coal|coal_ore|deepslate_coal_ore)$/, iron_ore: /^(iron_ore|deepslate_iron_ore|raw_iron)$/, copper_ore: /^(copper_ore|deepslate_copper_ore|raw_copper)$/, gold_ore: /^(gold_ore|deepslate_gold_ore|raw_gold)$/, diamond_ore: /^(diamond|diamond_ore|deepslate_diamond_ore)$/, emerald_ore: /^(emerald|emerald_ore|deepslate_emerald_ore)$/, redstone_ore: /^(redstone|redstone_ore|deepslate_redstone_ore)$/, lapis_ore: /^(lapis_lazuli|lapis_ore|deepslate_lapis_ore)$/, cobblestone: /^cobblestone$/, dirt: /dirt$/, sand: /sand$/, gravel: /^gravel$/ }
    const rx = aliases[target] || new RegExp(`^${String(target).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)
    return this.bot.inventory.items().filter(i => rx.test(i.name)).reduce((sum, i) => sum + i.count, 0)
  }

  toolTypeFor(blockName) { if (blockName.includes('log') || blockName.includes('wood')) return 'axe'; if (blockName.includes('dirt') || blockName.includes('grass') || blockName.includes('sand') || blockName.includes('gravel')) return 'shovel'; if (blockName.includes('ore') || ['stone', 'cobblestone', 'deepslate'].includes(blockName)) return 'pickaxe'; return null }
  async equipBestTool(blockName) { const need = this.toolTypeFor(blockName); if (!need) return false; const tools = this.bot.inventory.items().filter(i => i.name.endsWith(`_${need}`) || i.name === `wooden_${need}`); if (!tools.length) return false; const rank = item => ['wooden', 'golden', 'stone', 'iron', 'diamond', 'netherite'].findIndex(t => item.name.startsWith(t)); tools.sort((a, b) => rank(b) - rank(a)); await this.bot.equip(tools[0], 'hand'); return true }

  async mineBlock(block, username, version) {
    if (!block) return { ok: false, gained: 0, broken: false }
    if (this.world.danger(8)) { await this.defend(version); if (version !== this.cancelVersion) return { ok: false, gained: 0, broken: false } }
    const before = this.inventoryCount(block.name); await this.equipBestTool(block.name)
    try { await this.lookToward(block.position, true); await this.bot.dig(block, true) } catch (e) { console.log('[DIG]', e.message); return { ok: false, gained: 0, broken: false } }
    await sleep(350)
    const after = this.inventoryCount(block.name); const gained = Math.max(0, after - before); const remaining = this.bot.blockAt(block.position); const broken = !remaining || this.isTransparent(remaining)
    this.memory.event('block_mined', { block: block.name, x: block.position.x, y: block.position.y, z: block.position.z, gained })
    return { ok: broken, broken, gained }
  }

  async craftBasicTool(type) {
    const names = type === 'pickaxe' ? ['wooden_pickaxe', 'stone_pickaxe'] : type === 'axe' ? ['wooden_axe', 'stone_axe'] : ['wooden_shovel', 'stone_shovel']
    if (this.bot.inventory.items().some(i => names.includes(i.name))) return true
    const logs = this.bot.inventory.items().filter(i => /_log$/.test(i.name)); if (!logs.length) return false
    const planksName = `${logs[0].name.replace('_log', '')}_planks`; const planks = this.bot.registry.itemsByName[planksName]; if (!planks) return false
    try { const recipe = this.bot.recipesFor(planks.id, null, 1, null)[0]; if (recipe) await this.bot.craft(recipe, 1) } catch (_) {}
    if (!this.bot.inventory.items().some(i => i.name === planksName)) return false
    const stick = this.bot.registry.itemsByName.stick; if (!stick) return false
    try { const sticks = this.bot.inventory.items().filter(i => i.name === 'stick').reduce((n, i) => n + i.count, 0); if (sticks < 2) { const stickRecipe = this.bot.recipesFor(stick.id, null, 1, null)[0]; if (stickRecipe) await this.bot.craft(stickRecipe, 1) } } catch (_) {}
    const toolId = this.bot.registry.itemsByName[names[0]]; if (!toolId) return false
    try { const recipe = this.bot.recipesFor(toolId.id, null, 1, null)[0]; if (recipe) { await this.bot.craft(recipe, 1); return true } } catch (_) {}
    return false
  }

  async mine(target, count, username) {
    if (this.busy) { this.say('Я уже выполняю другую задачу. Скажи «стой», чтобы отменить её.'); return }
    this.busy = true; const version = ++this.cancelVersion; let collected = 0; let attemptsWithoutProgress = 0
    try {
      this.say(`Начинаю искать ${target}. Я буду искать его обычным способом, без X-Ray.`)
      const neededTool = this.toolTypeFor(target); if (neededTool && !(await this.equipBestTool(target))) await this.craftBasicTool(neededTool)
      while (collected < count && version === this.cancelVersion && attemptsWithoutProgress < 30) {
        if (this.world.danger(8)) { await this.defend(version); if (version !== this.cancelVersion) break }
        let block = this.findVisibleResource(target, 32)
        if (!block && this.isOre(target)) { block = this.findVisibleOre(32); if (block && target !== block.name && !block.name.includes(target.replace('deepslate_', ''))) block = null }
        if (block) {
          const before = this.inventoryCount(target); const ok = await this.moveNear(block.position, version)
          if (!ok || version !== this.cancelVersion) { attemptsWithoutProgress++; continue }
          const mined = await this.mineBlock(block, username, version)
          if (mined.ok) {
            const after = this.inventoryCount(target); const delta = Math.max(0, after - before)
            if (delta > 0) { collected += delta; attemptsWithoutProgress = 0 } else attemptsWithoutProgress++
            if (collected >= count) break
            continue
          }
          attemptsWithoutProgress++
        }
        const explored = await this.prospectTunnel(version); if (!explored) attemptsWithoutProgress++
      }
      if (version === this.cancelVersion) {
        if (collected >= count) this.say(`Готово. Добыто ${collected} из ${count} шт. ${target}.`)
        else if (collected > 0) this.say(`Нашёл и добыл только ${collected} из ${count} шт. ${target}. Остальное не подтверждено физически.`)
        else this.say(`Я не нашёл ${target} в доступном для обычного исследования пространстве.`)
      }
    } finally { if (version === this.cancelVersion) this.busy = false; this.bot.setControlState('forward', false) }
  }

  isOre(target) { return ORES.has(target) || target.endsWith('_ore') || target === 'ancient_debris' }

  async prospectTunnel(version) {
    if (!this.bot.entity || version !== this.cancelVersion) return false
    const yaw = this.bot.entity.yaw; const directions = [{ x: Math.round(-Math.sin(yaw)), z: Math.round(-Math.cos(yaw)) }, { x: Math.round(Math.cos(yaw)), z: Math.round(-Math.sin(yaw)) }, { x: -Math.round(-Math.sin(yaw)), z: -Math.round(-Math.cos(yaw)) }]; const dir = directions[Math.floor(Math.random() * directions.length)]; let moved = false
    for (let step = 0; step < 8 && version === this.cancelVersion; step++) {
      if (this.world.danger(8)) { await this.defend(version); if (version !== this.cancelVersion) return false }
      const pos = this.bot.entity.position; const front = this.bot.blockAt(pos.offset(dir.x, 0, dir.z)); const head = this.bot.blockAt(pos.offset(dir.x, 1, dir.z))
      if (front && !this.isTransparent(front) && front.name !== 'bedrock') { await this.equipBestTool(front.name); try { await this.lookToward(front.position, true); await this.bot.dig(front, true); moved = true } catch (_) {} }
      if (head && !this.isTransparent(head) && head.name !== 'bedrock') { try { await this.lookToward(head.position, true); await this.bot.dig(head, true) } catch (_) {} }
      await this.lookToward({ x: pos.x + dir.x * 2, y: pos.y, z: pos.z + dir.z * 2 }, false); this.bot.setControlState('forward', true); await sleep(700); this.bot.setControlState('forward', false)
      if (this.findVisibleResource('stone', 8) || this.findVisibleOre(8)) moved = true
    }
    this.bot.setControlState('forward', false); if (!moved) return await this.explore(null, true, version); return true
  }

  async explore(username, quiet = false, version = ++this.cancelVersion) {
    if (!this.bot.entity) return false
    if (!quiet) { if (this.busy) { this.say('Я уже занят.'); return false } this.busy = true; version = this.cancelVersion; this.say('Исследую местность и смотрю, что реально есть вокруг.') }
    const start = this.bot.entity.position.clone(); const angle = Math.random() * Math.PI * 2; const distance = 12 + Math.random() * 18; const target = { x: start.x + Math.cos(angle) * distance, y: start.y, z: start.z + Math.sin(angle) * distance }
    try { const ok = await this.moveNear(target, version, 15000); if (ok) { this.memory.location(`explore_${Date.now()}`, this.bot.entity.position, 'Физически исследованная область'); this.memory.event('exploration', { x: Math.round(this.bot.entity.position.x), y: Math.round(this.bot.entity.position.y), z: Math.round(this.bot.entity.position.z) }); if (!quiet) this.say('Разведка закончена. Я запомнил эту область.') } return ok } finally { if (!quiet && version === this.cancelVersion) this.busy = false }
  }

  async defend(version = this.cancelVersion) {
    const danger = this.world.danger(10); if (!danger || version !== this.cancelVersion) return false
    if (Date.now() - this.lastDanger > 5000) { this.lastDanger = Date.now(); this.say(`Вижу угрозу: ${danger.entity.name}. Защищаюсь.`) }
    const weapon = this.bot.inventory.items().filter(i => /_(sword|axe)$/.test(i.name)).sort((a, b) => { const rank = n => ['wooden', 'golden', 'stone', 'iron', 'diamond', 'netherite'].findIndex(x => n.startsWith(x)); return rank(b.name) - rank(a.name) })[0]
    if (weapon) try { await this.bot.equip(weapon, 'hand') } catch (_) {}
    try { await this.lookToward(danger.entity.position, false); if (danger.distance <= 4.5) { this.bot.attack(danger.entity); await sleep(500) } else { this.bot.pathfinder.setGoal(new goals.GoalNear(danger.entity.position.x, danger.entity.position.y, danger.entity.position.z, 3)); await sleep(500); this.bot.pathfinder.setGoal(null) } } catch (_) {}
    return true
  }

  report(username) { const s = this.world.snapshot(); const p = s.position; const mobs = s.entities.filter(e => e.type === 'mob').slice(0, 5); const players = s.players.filter(p => p.visible && p.name !== this.bot.username); this.say(`Я на ${p?.x}, ${p?.y}, ${p?.z}. HP ${Math.round(s.health)}, еда ${Math.round(s.food)}. Рядом игроков: ${players.length}, мобов: ${mobs.length}.`); this.memory.player(username, { lastPosition: p }) }

  async goToPlayer(username) { const player = this.bot.players[username]?.entity; if (!player) { this.say(`Я сейчас не вижу тебя, ${username}.`); return } this.cancel(); this.following = username; this.bot.pathfinder.setGoal(new goals.GoalFollow(player, 2), true); await this.lookToward(player.position, false); this.memory.player(username, { lastPosition: { x: Math.round(player.position.x), y: Math.round(player.position.y), z: Math.round(player.position.z) } }); this.say('Иду к тебе.') }

  async execute(actions, username) { for (const action of actions) { if (!action || !action.type) continue; if (action.type === 'chat') this.say(action.text); else if (action.type === 'stop') this.cancel('Остановился.'); else if (action.type === 'jump') { this.bot.setControlState('jump', true); await sleep(180); this.bot.setControlState('jump', false) } else if (action.type === 'go_to_player' || action.type === 'follow') await this.goToPlayer(username); else if (action.type === 'mine') await this.mine(String(action.target || 'stone'), Math.min(64, Math.max(1, Number(action.count) || 1)), username); else if (action.type === 'explore') await this.explore(username); else if (action.type === 'inspect') this.report(username); else if (action.type === 'remember') { this.memory.event(`${action.key || 'fact'}: ${action.value || ''}`); this.say('Запомнил.') } } }

  async chat(username, message) {
    if (!message || username === this.bot.username) return
    this.memory.player(username); this.memory.event('chat', { username, message }); const lower = message.toLowerCase()
    if (/^бот[, ]*(стой|остановись|отмена)/.test(lower)) { this.cancel('Задачу отменил. Стою.'); return }
    if (!this.busy && !/бот|bot/i.test(message)) return
    const clean = message.replace(/^(бот|bot)[,!: ]*/i, '').trim(); const actions = await this.askAI(clean || message, username); await this.execute(actions, username)
  }

  async autonomousTick() {
    if (!this.bot.entity) return
    if (this.following && !this.busy) {
      const followed = this.bot.players[this.following]?.entity
      if (followed) { try { const currentGoal = this.bot.pathfinder?.goal; if (!(currentGoal instanceof goals.GoalFollow)) this.bot.pathfinder.setGoal(new goals.GoalFollow(followed, 2), true); await this.lookToward(followed.position, false); this.memory.player(this.following, { lastPosition: { x: Math.round(followed.position.x), y: Math.round(followed.position.y), z: Math.round(followed.position.z) } }) } catch (_) {} }
    }
    if (!this.busy && this.world.danger(8)) { await this.defend(this.cancelVersion); return }
    for (const p of Object.values(this.bot.players)) if (p.username && p.entity) this.memory.player(p.username, { lastPosition: { x: Math.round(p.entity.position.x), y: Math.round(p.entity.position.y), z: Math.round(p.entity.position.z) } })
    if (!this.busy && this.bot.food !== undefined && this.bot.food <= 6) { const food = this.bot.inventory.items().find(i => /bread|apple|cooked_|beef|porkchop|chicken|mutton|rabbit/.test(i.name)); if (food) { try { await this.bot.equip(food, 'hand'); await this.bot.consume(); this.say('Я проголодался и поел.') } catch (_) {} } }
  }
}

function createBot() {
  const bot = mineflayer.createBot({ host: CONFIG.host, port: CONFIG.port, username: CONFIG.username, version: CONFIG.version })
  bot.loadPlugin(pathfinder)
  let agent = null
  bot.once('spawn', () => { const mcData = minecraftData(bot.version); const movements = new Movements(bot, mcData); movements.canDig = true; movements.allow1by1towers = false; movements.allowFreeMotion = false; movements.allowParkour = true; movements.allowSprinting = true; bot.pathfinder.setMovements(movements); agent = new Agent(bot); bot.chat('AI-агент онлайн. Я вижу только настоящий мир и не использую X-Ray.'); console.log(`[BOT] ${CONFIG.username} подключён к ${CONFIG.host}:${CONFIG.port}`) })
  bot.on('chat', async (username, message) => { try { if (agent) await agent.chat(username, message) } catch (e) { console.log('[CHAT ERROR]', e.message) } })
  bot.on('health', () => { if (agent && bot.health <= 6) agent.say('У меня мало здоровья, стараюсь выжить.') })
  bot.on('death', () => { if (agent) agent.cancel('Я погиб. Перезапускаю свои задачи.') })
  bot.on('kicked', reason => console.log('[KICKED]', reason))
  bot.on('error', error => console.log('[ERROR]', error.message))
  bot.on('end', () => { console.log('[BOT] Соединение закрыто. Переподключение через 8 секунд...'); setTimeout(createBot, 8000) })
  setInterval(() => { if (agent) agent.autonomousTick().catch(e => console.log('[AUTO]', e.message)) }, 1000)
  return bot
}

createBot()
