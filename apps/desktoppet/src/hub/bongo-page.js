// 键鼠映射看板 settings page (the overlay itself lives in src/bongo/).
(function () {
  const api = window.api;
  const A = window.BongoArt;
  let off = null;
  const MODES = [
    ['cat', '猫猫桌面', '敲键盘 + 握鼠标'], ['keyboard', '完整键盘', '按键实时点亮'], ['bongo', '邦戈鼓', '经典 Bongo Cat'],
    ['piano', '钢琴猫', '按键即弹琴'], ['gamepad', '手柄', '支持真实手柄'], ['strip', '按键条', '直播 / 录屏用'],
    ['lkeys', '线条猫·键盘', '黑白简笔 · 拍键盘'], ['ldesk', '线条猫·键鼠', '打字 + 握鼠标'], ['lbongo', '线条猫·鼓', '左右爪敲邦戈鼓'], ['ltable', '线条猫·拍桌', '按键就拍桌子']
  ];
  Hub.register({
    id: 'bongo', title: '键鼠映射', group: 'pet', order: 1.8,
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="2.5" y="11" width="13" height="8" rx="1.8"/><path d="M5.5 14h1M8.5 14h1M11.5 14h1M6 16.5h6" stroke-linecap="round"/><rect x="17.5" y="10" width="4" height="9" rx="2"/><path d="M5 11V8.5L7 6l2 2.5h1.5L12.5 6l2 2.5V11"/></svg>',
    mount(el, ctx) {
      let c = api.bongo.get();
      const running = () => api.settings.get().bongo && api.settings.get().bongo.on;
      el.innerHTML = `
        <h2 class="page-title">键鼠映射看板 <span class="set-sub">在桌面上显示一只跟着你敲键盘、握鼠标的小猫（类似 BongoCat）</span></h2>
        <div class="bg-wrap">
          <div class="card bg-preview">
            <div class="bg-stage"><svg class="bg-svg" xmlns="http://www.w3.org/2000/svg"></svg></div>
            <button class="btn primary bg-toggle"></button>
            <div class="set-sub bg-tip">快捷键 <b class="bg-hk"></b> 随时召唤 / 收起 · 看板上悬停猫咪头部可拖动、右键打开菜单</div>
          </div>
          <div class="card bg-opts">
            <div class="side-title">样式</div>
            <div class="bg-modes">${MODES.map(([m, t, d]) => `<button data-mode="${m}"><b>${t}</b><span>${d}</span></button>`).join('')}</div>
            <div class="set-row bg-sound"><div><div>钢琴音效</div><div class="set-sub">按键时弹出对应音符</div></div><label class="switch"><input type="checkbox" data-c="sound"><span></span></label></div>
            <div class="set-row bg-skinrow"><span>花色</span><div class="bg-skins">${Object.entries(A.SKINS).map(([k, s]) => `<button data-skin="${k}" title="${s.name}"><i style="background:${s.fur};border-color:${s.line}"></i>${s.name}</button>`).join('')}</div></div>
            <div class="set-row"><span>大小</span><input type="range" min="0.6" max="1.6" step="0.05" data-r="scale"><em class="bg-val" data-v="scale"></em></div>
            <div class="set-row"><span>不透明度</span><input type="range" min="0.3" max="1" step="0.05" data-r="opacity"><em class="bg-val" data-v="opacity"></em></div>
            <div class="side-title" style="margin-top:12px">行为</div>
            <div class="set-row"><div><div>显示按键文字</div><div class="set-sub">按下的键 / 组合键飘在猫咪上方，适合录屏教学</div></div><label class="switch"><input type="checkbox" data-c="showKeys"><span></span></label></div>
            <div class="set-row"><div><div>鼠标穿透</div><div class="set-sub">开启后点击会穿过看板，不挡住下面的窗口</div></div><label class="switch"><input type="checkbox" data-c="clickThrough"><span></span></label></div>
            <div class="set-row"><div><div>召唤快捷键</div><div class="set-sub">点击后按下组合键；Backspace 清除</div></div><input class="input bg-key" readonly></div>
            <div class="set-sub bg-note">键鼠监听只在看板打开时运行，仅用于驱动动画，不记录、不保存任何按键内容。</div>
          </div>
        </div>`;
      const q = s => el.querySelector(s);
      const svg = q('.bg-svg');
      function preview() {
        const skin = A.SKINS[c.skin] || A.SKINS.orange;
        const EX = window.BongoModes || {};
        if (EX[c.mode]) {
          const m = EX[c.mode];
          svg.setAttribute('viewBox', `0 0 ${m.size[0]} ${m.size[1]}`);
          svg.innerHTML = m.svg(skin, A);
          const inst = m.create(svg, { A, skin, cfg: Object.assign({}, c, { sound: false }), note() {}, caption() {}, heldMods: () => [] });
          // a representative pose for each board
          const demo = { bongo: [[30, true]], piano: [[33, true], [36, true], [23, true]], gamepad: [[36, true], [17, true], [30, true]], strip: [[35, true], [18, true], [38, true], [38, true], [24, true]], lkeys: [[30, true], [37, true]], ldesk: [[31, true]], lbongo: [[30, true]], ltable: [[37, true]] }[c.mode] || [];
          for (const [code, down] of demo) inst.key && inst.key(down, code);
          if (inst.dispose) setTimeout(() => inst.dispose(), 400);
          return;
        }
        svg.setAttribute('viewBox', c.mode === 'keyboard' ? '0 0 640 300' : '0 0 380 300');
        svg.innerHTML = c.mode === 'keyboard' ? A.kbSvg(skin) : A.catSvg(skin);
        if (c.mode === 'cat') {
          // strike a typing pose for the preview
          const kp = A.keyPoint(33), mp = A.mousePoint(0.6, 0.4);
          svg.querySelectorAll('#armL path').forEach(p => p.setAttribute('d', A.armPath(A.SHOULDER_L, kp)));
          svg.querySelector('#pawL').setAttribute('transform', `translate(${kp[0]} ${kp[1]}) rotate(-20)`);
          svg.querySelector('#pawL .pads').setAttribute('display', 'none');
          svg.querySelector('#pawL .top').setAttribute('display', '');
          svg.querySelector('#mouse').setAttribute('transform', `translate(${mp[0]} ${mp[1]}) scale(.9)`);
          const rp = [mp[0] + 1, mp[1] - 14];
          svg.querySelectorAll('#armR path').forEach(p => p.setAttribute('d', A.armPath(A.SHOULDER_R, rp)));
          svg.querySelector('#pawR').setAttribute('transform', `translate(${rp[0]} ${rp[1]}) rotate(-8)`);
          const k = svg.querySelector('#ck-33'); if (k) k.classList.add('on');
        } else {
          for (const code of [17, 30, 31, 32, 57]) { const k = svg.querySelector('#kk-' + code); if (k) k.classList.add('on'); }
        }
      }
      function render() {
        c = api.bongo.get();
        el.querySelectorAll('[data-mode]').forEach(b => b.classList.toggle('on', b.dataset.mode === c.mode));
        q('.bg-sound').style.display = c.mode === 'piano' ? '' : 'none';
        q('.bg-skinrow').style.display = /^l(keys|desk|bongo|table)$/.test(c.mode) ? 'none' : '';  // line-art cat is always black & white
        el.querySelectorAll('[data-skin]').forEach(b => b.classList.toggle('on', b.dataset.skin === c.skin));
        el.querySelectorAll('[data-r]').forEach(r => { r.value = c[r.dataset.r]; q(`[data-v=${r.dataset.r}]`).textContent = Math.round(c[r.dataset.r] * 100) + '%'; });
        el.querySelectorAll('[data-c]').forEach(i => { i.checked = !!c[i.dataset.c]; });
        q('.bg-key').value = c.hotkey || '未设置';
        q('.bg-hk').textContent = c.hotkey || '（未设置）';
        const on = running();
        q('.bg-toggle').textContent = on ? '收起看板' : '召唤看板';
        q('.bg-toggle').classList.toggle('primary', !on);
        preview();
      }
      const set = patch => { api.bongo.update(patch); setTimeout(render, 30); };
      q('.bg-toggle').onclick = () => { api.bongo.toggle(); setTimeout(render, 150); };
      el.querySelectorAll('[data-mode]').forEach(b => b.onclick = () => set({ mode: b.dataset.mode }));
      el.querySelectorAll('[data-skin]').forEach(b => b.onclick = () => set({ skin: b.dataset.skin }));
      el.querySelectorAll('[data-r]').forEach(r => {
        r.oninput = () => { q(`[data-v=${r.dataset.r}]`).textContent = Math.round(r.value * 100) + '%'; };
        r.onchange = () => set({ [r.dataset.r]: Number(r.value) });
      });
      el.querySelectorAll('[data-c]').forEach(i => i.onchange = () => set({ [i.dataset.c]: i.checked }));
      const key = q('.bg-key');
      key.onkeydown = e => {
        e.preventDefault();
        if (e.key === 'Escape') return key.blur();
        if (e.key === 'Backspace' || e.key === 'Delete') { set({ hotkey: '' }); return; }
        if (['Control', 'Alt', 'Shift', 'Meta'].includes(e.key)) return;
        const mods = [e.ctrlKey && 'Ctrl', e.altKey && 'Alt', e.shiftKey && 'Shift'].filter(Boolean);
        if (!mods.length) return ctx.toast('请同时按住 Ctrl / Alt / Shift');
        set({ hotkey: [...mods, e.key.length === 1 ? e.key.toUpperCase() : e.key].join('+') });
        key.blur();
        ctx.toast('快捷键已设置');
      };
      render();
      off = api.settings.onChange(() => render());
    },
    unmount() { if (off) off(); off = null; }
  });
})();
