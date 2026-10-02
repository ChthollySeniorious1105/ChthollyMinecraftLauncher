// Main-process gameplay: 每日任务 (daily quests) / 外出探险 (timed adventures) / 钓鱼图鉴 bookkeeping /
// 宠物花园 (real-time crops) / 扭蛋机 (collectible figures).
// Wired from main.js via init(deps); all state lives in the shared `data` store.
const QUEST_POOL = [
  { key: 'wins', text: n => `赢得 ${n} 局小游戏`, n: [1, 2, 3], coins: 8 },
  { key: 'pomos', text: n => `完成 ${n} 个番茄钟`, n: [1, 2], coins: 10 },
  { key: 'feeds', text: n => `喂食 ${n} 次`, n: [2, 3], coins: 6 },
  { key: 'pets', text: n => `摸摸宠物 ${n} 次`, n: [3, 5], coins: 5 },
  { key: 'play', text: () => '陪宠物玩耍 1 次', n: [1], coins: 6 },
  { key: 'bath', text: () => '给宠物洗 1 次澡', n: [1], coins: 6 },
  { key: 'fish', text: n => `钓到 ${n} 条鱼`, n: [3, 5], coins: 8 },
  { key: 'rare', text: () => '钓到 1 条稀有以上的鱼', n: [1], coins: 12 },
  { key: 'trip', text: () => '完成 1 次外出探险', n: [1], coins: 10 },
  { key: 'checkin', text: () => '完成每日签到', n: [1], coins: 4 },
  { key: 'harvest', text: n => `在花园收获 ${n} 次作物`, n: [1, 2], coins: 8 },
  { key: 'water', text: n => `给花园浇水 ${n} 次`, n: [2, 3], coins: 5 },
  { key: 'gacha', text: () => '扭 1 次扭蛋', n: [1], coins: 5 }
];
const QUEST_BONUS = 20;

// minutes, energy cost, level needed; loot is rolled when the trip starts
const DESTS = [
  { id: 'park', name: '街角公园', icon: '🌳', min: 15, energy: 10, lv: 1, coins: [6, 12], desc: '去草坪上打个滚',
    finds: [['acorn', '橡果', '🌰', 1], ['leaf', '四叶草', '🍀', 3], ['feather', '鸽子羽毛', '🪶', 1], ['marble', '玻璃弹珠', '🔮', 2]] },
  { id: 'beach', name: '海边', icon: '🏖️', min: 30, energy: 15, lv: 2, coins: [12, 22], desc: '捡贝壳、看日落',
    finds: [['shell', '扇贝壳', '🐚', 1], ['starfish', '海星', '⭐', 2], ['bottle', '漂流瓶', '🍾', 3], ['coral', '红珊瑚', '🪸', 3]] },
  { id: 'forest', name: '森林', icon: '🌲', min: 60, energy: 25, lv: 3, coins: [22, 40], desc: '采蘑菇，小心别迷路',
    finds: [['mushroom', '小红蘑菇', '🍄', 1], ['pinecone', '松果', '🌲', 1], ['butterfly', '蝴蝶标本', '🦋', 2], ['crystal', '林间水晶', '💎', 3]] },
  { id: 'mountain', name: '雪山', icon: '🏔️', min: 120, energy: 35, lv: 5, coins: [45, 75], desc: '爬到山顶看云海',
    finds: [['snowball', '不化的雪球', '❄️', 1], ['edelweiss', '雪绒花', '🌼', 2], ['yeti', '雪怪脚印拓片', '🐾', 3], ['aurora', '极光瓶', '🌌', 3]] },
  { id: 'space', name: '月球', icon: '🌕', min: 240, energy: 50, lv: 8, coins: [90, 150], desc: '坐纸箱火箭去月球',
    finds: [['moonrock', '月岩', '🪨', 1], ['stardust', '星尘', '✨', 2], ['ufo', '迷你飞碟', '🛸', 3], ['rabbit', '玉兔的胡萝卜', '🥕', 3]] }
];
const STORIES = {
  park: ['在长椅下睡了个午觉', '和邻居家的小狗赛跑，赢了！', '追着泡泡跑了好几圈', '帮老爷爷捡回了风筝'],
  beach: ['堆了一座超大的沙堡', '被小螃蟹夹了一下尾巴', '在浪花里踩水玩', '看到了粉红色的晚霞'],
  forest: ['跟着松鼠找到了秘密树洞', '在溪边喝了清凉的泉水', '听猫头鹰讲了一个故事', '差点迷路，幸好有萤火虫带路'],
  mountain: ['在山顶看到了云海日出', '和雪人合了影', '滑雪摔了个屁股墩', '在温泉里泡得暖呼呼'],
  space: ['在月球上一跳三米高', '从月亮上看到了我们的家', '和外星人交换了零食', '在环形山里捉迷藏']
};
const FOOD_DROPS = ['apple', 'milk', 'onigiri', 'fish', 'icecream'];

// 宠物花园: seed price, minutes to grow while watered, sell price, level needed
const CROPS = [
  { id: 'radish', name: '小萝卜', seed: 4, min: 10, sell: 7, lv: 1 },
  { id: 'carrot', name: '胡萝卜', seed: 8, min: 20, sell: 14, lv: 1 },
  { id: 'tomato', name: '番茄', seed: 12, min: 40, sell: 22, lv: 2 },
  { id: 'corn', name: '玉米', seed: 18, min: 90, sell: 34, lv: 3 },
  { id: 'strawberry', name: '草莓', seed: 25, min: 180, sell: 48, lv: 4 },
  { id: 'pumpkin', name: '南瓜', seed: 40, min: 360, sell: 80, lv: 5 }
];
const PLOT_BASE = 4;
const PLOT_PRICE = [50, 100, 160, 240];   // plots 5..8
const GOLDEN_CHANCE = 0.06;

// 扭蛋机: [id, name, emoji, rarity]
const GACHA = [
  ['cat', '招手猫', '🐱', 1], ['dog', '柴犬', '🐶', 1], ['bunny', '垂耳兔', '🐰', 1], ['bear', '小熊', '🐻', 1],
  ['panda', '熊猫', '🐼', 1], ['koala', '考拉', '🐨', 1], ['pig', '小猪', '🐷', 1], ['frog', '青蛙', '🐸', 1],
  ['chick', '小鸡', '🐤', 1], ['hamster', '仓鼠', '🐹', 1], ['penguin', '企鹅', '🐧', 1], ['turtle', '乌龟', '🐢', 1],
  ['fox', '狐狸', '🦊', 2], ['owl', '猫头鹰', '🦉', 2], ['octopus', '章鱼', '🐙', 2], ['butterfly', '蝴蝶', '🦋', 2],
  ['parrot', '鹦鹉', '🦜', 2], ['hedgehog', '刺猬', '🦔', 2], ['dolphin', '海豚', '🐬', 2], ['sloth', '树懒', '🦥', 2],
  ['unicorn', '彩虹独角兽', '🦄', 3], ['dragon', '小青龙', '🐲', 3], ['whale', '星空鲸', '🐳', 3], ['peacock', '金孔雀', '🦚', 3]
];
const GACHA_PRICE = 10, GACHA_DUP = 3, GACHA_PITY = 15;
const RARITY = { 1: '普通', 2: '稀有', 3: '珍贵' };

function init(d) {
  const { store, save, broadcast, notify, care, careLog, careChanged, addExp, clamp, today } = d;
  const rnd = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
  const pick = arr => arr[Math.floor(Math.random() * arr.length)];

  // ---------- 每日任务 ----------
  function quests() {
    const data = store();
    const t = today();
    if (!data.quests || data.quests.date !== t) {
      const pool = QUEST_POOL.slice().sort(() => Math.random() - 0.5).slice(0, 3);
      data.quests = {
        date: t, bonus: false,
        list: pool.map(q => { const n = pick(q.n); return { key: q.key, text: q.text(n), n, prog: 0, coins: q.coins + (n - 1) * 3, done: false }; })
      };
      save();
    }
    return data.quests;
  }
  function questEvent(key, n = 1) {
    const qs = quests();
    let changed = false;
    for (const q of qs.list) {
      if (q.key !== key || q.done) continue;
      q.prog = Math.min(q.n, q.prog + n);
      changed = true;
      if (q.prog >= q.n) {
        q.done = true;
        const c = care();
        c.coins += q.coins;
        addExp(q.coins * 2);
        careLog(`完成每日任务「${q.text}」+${q.coins} 小鱼干`);
        broadcast('pet:say', { text: `每日任务完成：${q.text} ✔ +${q.coins} 小鱼干`, mood: 'happy', ms: 5000 });
      }
    }
    if (changed && !qs.bonus && qs.list.every(q => q.done)) {
      qs.bonus = true;
      const c = care();
      c.coins += QUEST_BONUS;
      c.mood = clamp(c.mood + 10);
      careLog(`今日任务全部完成！额外奖励 ${QUEST_BONUS} 小鱼干`);
      notify('每日任务', `今天的任务全部完成啦！额外奖励 ${QUEST_BONUS} 小鱼干`);
      const s = stats(); s.questDays = (s.questDays || 0) + 1;
      d.checkAchievements();
    }
    if (changed) { careChanged(); broadcast('play', playState()); }
  }
  const stats = () => d.stats();

  // ---------- 外出探险 ----------
  function trip() { return store().trip || null; }
  function tripStart(id) {
    const data = store();
    const dest = DESTS.find(x => x.id === id);
    const c = care();
    if (!dest) return { ok: false };
    if (data.trip) return { ok: false, msg: data.trip.end > Date.now() ? '已经在外面探险啦' : '先把上次的收获领回来吧' };
    if (c.level < dest.lv) return { ok: false, msg: `需要宠物达到 Lv.${dest.lv}` };
    if (c.energy < dest.energy) return { ok: false, msg: '精力不够，先休息一下吧' };
    c.energy = clamp(c.energy - dest.energy);
    c.hunger = clamp(c.hunger - dest.energy / 3);
    // roll loot now so re-opening the page can't re-roll it
    const weights = dest.finds.map(f => (f[3] === 1 ? 60 : f[3] === 2 ? 28 : 12));
    let r = Math.random() * weights.reduce((a, b) => a + b, 0), fi = 0;
    while ((r -= weights[fi]) > 0) fi++;
    const find = dest.finds[fi];
    const loot = {
      coins: rnd(dest.coins[0], dest.coins[1]),
      exp: dest.min,
      find: { id: `${dest.id}.${find[0]}`, name: find[1], icon: find[2], rarity: find[3] },
      food: Math.random() < 0.5 ? pick(FOOD_DROPS) : null,
      story: pick(STORIES[dest.id])
    };
    data.trip = { dest: dest.id, start: Date.now(), end: Date.now() + dest.min * 60e3, loot, told: false };
    careLog(`出发去${dest.name}探险`);
    careChanged();
    broadcast('pet:say', { text: `我去${dest.name}探险啦，${dest.min >= 60 ? dest.min / 60 + ' 小时' : dest.min + ' 分钟'}后回来！${dest.icon}`, mood: 'happy', ms: 6000 });
    broadcast('play', playState());
    return { ok: true };
  }
  function tripClaim() {
    const data = store();
    const t = data.trip;
    if (!t || t.end > Date.now()) return { ok: false, msg: '还没回来哦' };
    const dest = DESTS.find(x => x.id === t.dest);
    const c = care();
    c.coins += t.loot.coins;
    c.mood = clamp(c.mood + 12);
    addExp(t.loot.exp);
    if (t.loot.food) c.inventory[t.loot.food] = (c.inventory[t.loot.food] || 0) + 1;
    data.souvenirs = data.souvenirs || {};
    const isNew = !data.souvenirs[t.loot.find.id];
    data.souvenirs[t.loot.find.id] = (data.souvenirs[t.loot.find.id] || 0) + 1;
    careLog(`从${dest ? dest.name : '远方'}带回了${t.loot.find.name} +${t.loot.coins} 小鱼干`);
    const s = stats(); s.trips = (s.trips || 0) + 1;
    data.trip = null;
    questEvent('trip');
    d.checkAchievements();
    careChanged();
    broadcast('play', playState());
    return { ok: true, loot: t.loot, isNew, dest: dest && dest.name };
  }
  function tripRecall() {
    const data = store();
    if (!data.trip || data.trip.end <= Date.now()) return { ok: false };
    data.trip = null;   // come home early: nothing found, energy already spent
    careLog('提前把宠物叫回了家');
    careChanged();
    broadcast('play', playState());
    broadcast('pet:say', { text: '我回来啦~ 这次什么也没找到', mood: 'normal', ms: 4000 });
    return { ok: true };
  }
  // called every minute: announce the return once
  function tick() {
    const t = trip();
    if (t && !t.told && t.end <= Date.now()) {
      t.told = true;
      const dest = DESTS.find(x => x.id === t.dest);
      notify('探险归来', `宠物从${dest ? dest.name : '远方'}回来了，快去看看带回了什么！`);
      broadcast('pet:say', { text: `我从${dest ? dest.name : '远方'}回来啦！带了礼物哦 🎁`, mood: 'happy', ms: 10000 });
      save();
      broadcast('play', playState());
    }
    gardenTick();
    quests();   // roll over at midnight
  }

  // ---------- 宠物花园 ----------
  // crops grow at full speed while the soil is wet and at half speed when dry (also while the app is closed)
  function garden() {
    const data = store();
    const g = data.garden = data.garden || { plots: Array(PLOT_BASE).fill(null), harvests: 0 };
    const now = Date.now();
    for (const p of g.plots) {
      if (!p) continue;
      const wet = Math.max(0, Math.min(now, p.wet) - p.last);
      p.grow += wet + (now - p.last - wet) * 0.5;
      p.last = now;
    }
    return g;
  }
  const cropOf = p => CROPS.find(c => c.id === p.crop);
  const ripe = p => p.grow >= cropOf(p).min * 60e3;
  function gardenState() {
    const g = garden(), now = Date.now();
    return {
      crops: CROPS, harvests: g.harvests, nextPlot: PLOT_PRICE[g.plots.length - PLOT_BASE] || 0,
      plots: g.plots.map(p => p && {
        crop: p.crop, golden: p.golden, pct: Math.min(1, p.grow / (cropOf(p).min * 60e3)), ripe: ripe(p), wet: p.wet > now,
        // real ms until ripe at the current watering state
        left: Math.max(0, (() => { let need = cropOf(p).min * 60e3 - p.grow; const w = Math.max(0, p.wet - now); if (need <= w) return need; need -= w; return w + need * 2; })())
      })
    };
  }
  function gardenOp(op, a) {
    const g = garden(), c = care(), now = Date.now();
    let res = { ok: true };
    if (op === 'plant') {
      const crop = CROPS.find(x => x.id === (a && a.crop)), i = a && a.i;
      if (!crop || !(i in g.plots)) return { ok: false };
      if (g.plots[i]) return { ok: false, msg: '这块地已经种上啦' };
      if (c.level < crop.lv) return { ok: false, msg: `需要宠物达到 Lv.${crop.lv}` };
      if (c.coins < crop.seed) return { ok: false, msg: '小鱼干不够买种子啦' };
      c.coins -= crop.seed;
      g.plots[i] = { crop: crop.id, grow: 0, last: now, wet: 0, golden: Math.random() < GOLDEN_CHANCE, told: false };
    } else if (op === 'water') {
      // a = plot index, or -1 for every dry plot
      let n = 0;
      g.plots.forEach((p, i) => {
        if (!p || (a !== -1 && a !== i) || p.wet > now || ripe(p)) return;
        p.wet = now + cropOf(p).min * 30e3;   // stays wet for half the grow time
        n++;
      });
      if (!n) return { ok: false, msg: '没有需要浇水的作物' };
      questEvent('water', n);
      res.n = n;
    } else if (op === 'harvest') {
      let coins = 0, exp = 0;
      const got = [];
      g.plots.forEach((p, i) => {
        if (!p || (a !== -1 && a !== i) || !ripe(p)) return;
        const crop = cropOf(p), v = crop.sell * (p.golden ? 3 : 1);
        coins += v; exp += Math.ceil(crop.min / 5) + 2;
        got.push({ i, crop: crop.id, name: crop.name, golden: p.golden, coins: v });
        g.plots[i] = null;
        g.harvests++;
        if (p.golden) stats().golden = true;
      });
      if (!got.length) return { ok: false, msg: '还没有成熟的作物' };
      c.coins += coins;
      c.mood = clamp(c.mood + 2 * got.length);
      addExp(exp);
      careLog(`花园收获 ${got.map(x => (x.golden ? '金色' : '') + x.name).join('、')} +${coins} 小鱼干`);
      stats().harvests = g.harvests;
      questEvent('harvest', got.length);
      d.checkAchievements();
      res = { ok: true, got, coins };
    } else if (op === 'dig') {
      if (!g.plots[a]) return { ok: false };
      g.plots[a] = null;   // seeds are not refunded
    } else if (op === 'unlock') {
      const price = PLOT_PRICE[g.plots.length - PLOT_BASE];
      if (!price) return { ok: false, msg: '已经是最大的花园啦' };
      if (c.coins < price) return { ok: false, msg: '小鱼干不够扩建啦' };
      c.coins -= price;
      g.plots.push(null);
      careLog(`花园扩建到 ${g.plots.length} 块地`);
    } else return { ok: false };
    careChanged();
    broadcast('play', playState());
    return { ...res, garden: gardenState() };
  }
  function gardenTick() {
    const g = garden();
    const fresh = g.plots.filter(p => p && !p.told && ripe(p));
    if (!fresh.length) return;
    fresh.forEach(p => { p.told = true; });
    const names = [...new Set(fresh.map(p => cropOf(p).name))].join('、');
    broadcast('pet:say', { text: `花园里的${names}成熟啦，快去收获吧 🌱`, mood: 'happy', ms: 8000 });
    save();
    broadcast('play', playState());
  }

  // ---------- 扭蛋机 ----------
  function gachaSpin() {
    const data = store(), c = care(), t = today();
    const free = data.gachaFree !== t;
    if (!free && c.coins < GACHA_PRICE) return { ok: false, msg: `需要 ${GACHA_PRICE} 小鱼干` };
    if (free) data.gachaFree = t; else c.coins -= GACHA_PRICE;
    data.gacha = data.gacha || {};
    data.gachaPity = (data.gachaPity || 0) + 1;
    // 70 / 25 / 5, with a guaranteed 珍贵 after GACHA_PITY spins without one
    const roll = Math.random() * 100;
    const r = data.gachaPity >= GACHA_PITY ? 3 : roll < 5 ? 3 : roll < 30 ? 2 : 1;
    if (r === 3) data.gachaPity = 0;
    const [id, name, icon, rarity] = pick(GACHA.filter(x => x[3] === r));
    const isNew = !data.gacha[id];
    data.gacha[id] = (data.gacha[id] || 0) + 1;
    const refund = isNew ? 0 : GACHA_DUP;
    c.coins += refund;
    addExp(3);
    careLog(`扭蛋扭到了${RARITY[rarity]}的${name}${refund ? `（重复，换回 ${refund} 小鱼干）` : ''}`);
    const s = stats(); s.gacha = (s.gacha || 0) + 1;
    questEvent('gacha');
    if (rarity === 3) broadcast('pet:say', { text: `哇！扭到了珍贵的${name} ${icon}！`, mood: 'happy', ms: 6000 });
    d.checkAchievements();
    careChanged();
    broadcast('play', playState());
    return { ok: true, item: { id, name, icon, rarity }, isNew, free, refund };
  }

  // ---------- 钓鱼 ----------
  // the fishing game reports each catch; coins are capped per day so it can't be farmed
  const FISH_DAILY_CAP = 80;
  function fishCatch(f) {
    const data = store();
    if (!f || typeof f.id !== 'string') return { ok: false };
    data.fishdex = data.fishdex || {};
    const e = data.fishdex[f.id] || { n: 0, best: 0 };
    const isNew = !e.n;
    e.n++; e.best = Math.max(e.best, Number(f.size) || 0);
    data.fishdex[f.id] = e;
    const t = today();
    if (!data.fishDay || data.fishDay.date !== t) data.fishDay = { date: t, coins: 0 };
    const want = Math.max(0, Math.min(30, Math.round(Number(f.coins) || 0)));
    const coins = Math.min(want, FISH_DAILY_CAP - data.fishDay.coins);
    data.fishDay.coins += coins;
    const c = care();
    c.coins += coins;
    addExp(Math.ceil(want / 2) + 1);
    const s = stats(); s.fish = (s.fish || 0) + 1;
    questEvent('fish');
    if (f.rarity >= 2) questEvent('rare');
    d.checkAchievements();
    careChanged();
    return { ok: true, coins, capped: coins < want, isNew, dex: data.fishdex, left: FISH_DAILY_CAP - data.fishDay.coins };
  }

  function playState() {
    const data = store();
    return {
      quests: quests(), bonus: QUEST_BONUS, trip: trip(), now: Date.now(),
      dests: DESTS.map(({ finds, ...x }) => ({ ...x, finds: finds.map(([id, name, icon, rarity]) => ({ id: `${x.id}.${id}`, name, icon, rarity })) })),
      souvenirs: data.souvenirs || {}, fishdex: data.fishdex || {}, rarity: RARITY,
      fishLeft: data.fishDay && data.fishDay.date === today() ? FISH_DAILY_CAP - data.fishDay.coins : FISH_DAILY_CAP,
      garden: gardenState(),
      gacha: {
        list: GACHA.map(([id, name, icon, rarity]) => ({ id, name, icon, rarity })), owned: data.gacha || {},
        price: GACHA_PRICE, dup: GACHA_DUP, free: data.gachaFree !== today(), pity: GACHA_PITY - (data.gachaPity || 0)
      }
    };
  }
  const souvenirTotal = () => DESTS.reduce((n, x) => n + x.finds.length, 0);

  return { quests, questEvent, tripStart, tripClaim, tripRecall, tick, fishCatch, playState, trip, souvenirTotal, gardenOp, gachaSpin };
}

module.exports = { init, DESTS, GACHA };
