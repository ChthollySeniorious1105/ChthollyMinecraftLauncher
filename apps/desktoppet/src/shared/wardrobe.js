// Wardrobe: SVG accessories drawn over the pet artwork. Shared by the pet window and the hub.
// Each item: slot (one item per slot), price, svg (viewBox 0 0 100 60 unless noted), and placement:
//   anchor 'top'  -> centred on the head, bottom edge sits at the top of the head
//   anchor 'face' -> centred on the head at `y` (fraction of body height from the top)
//   anchor 'neck' -> centred at `y` like face
// `w` is the width relative to the measured head width.
(function (root) {
  const ITEMS = {
    crown: { name: '小皇冠', slot: 'head', price: 120, anchor: 'top', w: 0.55, sink: 0.35,
      svg: '<svg viewBox="0 0 100 60"><path d="M8 54 4 14l24 20L50 4l22 30 24-20-4 40z" fill="#f7c948" stroke="#b8860b" stroke-width="3" stroke-linejoin="round"/><circle cx="50" cy="30" r="7" fill="#e8553a"/><circle cx="24" cy="40" r="5" fill="#6aa7e0"/><circle cx="76" cy="40" r="5" fill="#5da35a"/><path d="M8 54h84" stroke="#b8860b" stroke-width="4"/></svg>' },
    partyhat: { name: '派对帽', slot: 'head', price: 40, anchor: 'top', w: 0.36, sink: 0.25, aspect: 1.1,
      svg: '<svg viewBox="0 0 60 66"><path d="M30 4 6 62h48z" fill="#f06f7e" stroke="#c23b52" stroke-width="3" stroke-linejoin="round"/><path d="M12 48l36-12M18 34l24-8M24 20l10-4" stroke="#fff3c9" stroke-width="5" stroke-linecap="round"/><circle cx="30" cy="6" r="6" fill="#f7c948"/></svg>' },
    tophat: { name: '绅士礼帽', slot: 'head', price: 90, anchor: 'top', w: 0.62, sink: 0.3, aspect: 0.8,
      svg: '<svg viewBox="0 0 100 80"><rect x="24" y="6" width="52" height="56" rx="6" fill="#3a2a22"/><rect x="24" y="44" width="52" height="10" fill="#e8553a"/><ellipse cx="50" cy="66" rx="48" ry="10" fill="#3a2a22"/><rect x="30" y="10" width="8" height="30" rx="4" fill="#fff" opacity=".15"/></svg>' },
    beret: { name: '贝雷帽', slot: 'head', price: 50, anchor: 'top', w: 0.7, sink: 0.45, aspect: 0.5,
      svg: '<svg viewBox="0 0 100 50"><path d="M6 36c0-18 22-30 48-30s42 12 40 26c-1 8-14 10-44 12S6 46 6 36z" fill="#e8553a"/><path d="M12 40c20 6 56 6 78-4" stroke="#b33f28" stroke-width="4" fill="none"/><path d="M52 6c0-4 4-6 6-4" stroke="#b33f28" stroke-width="4" fill="none" stroke-linecap="round"/></svg>' },
    flower: { name: '小花', slot: 'head', price: 25, anchor: 'top', w: 0.26, sink: 0.55, dx: 0.28, aspect: 1,
      svg: '<svg viewBox="0 0 60 60"><g fill="#f7b6c8" stroke="#e8638a" stroke-width="2"><circle cx="30" cy="14" r="11"/><circle cx="46" cy="26" r="11"/><circle cx="40" cy="45" r="11"/><circle cx="20" cy="45" r="11"/><circle cx="14" cy="26" r="11"/></g><circle cx="30" cy="31" r="9" fill="#f7c948"/></svg>' },
    bow: { name: '蝴蝶结', slot: 'head', price: 30, anchor: 'top', w: 0.36, sink: 0.5, dx: -0.22, aspect: 0.6,
      svg: '<svg viewBox="0 0 100 60"><path d="M50 30 8 6c-6 10-6 38 0 48zM50 30 92 6c6 10 6 38 0 48z" fill="#f06f7e" stroke="#c23b52" stroke-width="3" stroke-linejoin="round"/><circle cx="50" cy="30" r="10" fill="#e8475f"/></svg>' },
    glasses: { name: '圆框眼镜', slot: 'face', price: 45, anchor: 'face', y: 0.30, w: 0.62, aspect: 0.4,
      svg: '<svg viewBox="0 0 100 40"><g fill="rgba(200,230,255,.25)" stroke="#4a3426" stroke-width="4"><circle cx="26" cy="20" r="16"/><circle cx="74" cy="20" r="16"/></g><path d="M42 18q8-6 16 0" stroke="#4a3426" stroke-width="4" fill="none"/></svg>' },
    sunglasses: { name: '墨镜', slot: 'face', price: 70, anchor: 'face', y: 0.30, w: 0.66, aspect: 0.36,
      svg: '<svg viewBox="0 0 100 36"><path d="M4 6h40l-4 22c-2 6-28 6-32 0zM56 6h40l-4 22c-2 6-28 6-32 0z" fill="#222"/><path d="M44 10q6-4 12 0" stroke="#222" stroke-width="4" fill="none"/><path d="M12 12l10 0M64 12l10 0" stroke="#fff" stroke-width="3" opacity=".5" stroke-linecap="round"/></svg>' },
    scarf: { name: '红围巾', slot: 'neck', price: 55, anchor: 'neck', y: 0.53, w: 0.8, aspect: 0.55,
      svg: '<svg viewBox="0 0 100 55"><path d="M6 10c20 10 68 10 88 0v14c-20 10-68 10-88 0z" fill="#e8553a"/><path d="M62 24l4 28h14l-4-30z" fill="#d44a30"/><path d="M14 16v12M26 18v12M38 19v12M50 19v12M62 19v12M74 18v12M86 16v12" stroke="#b33f28" stroke-width="2" opacity=".5"/><path d="M66 50h14" stroke="#f7c948" stroke-width="3"/></svg>' },
    bowtie: { name: '领结', slot: 'neck', price: 35, anchor: 'neck', y: 0.55, w: 0.34, aspect: 0.55,
      svg: '<svg viewBox="0 0 100 55"><path d="M50 27 6 6v42zM50 27l44-21v42z" fill="#6aa7e0" stroke="#3a6fa8" stroke-width="3" stroke-linejoin="round"/><rect x="40" y="17" width="20" height="20" rx="5" fill="#3a6fa8"/><g fill="#fff" opacity=".6"><circle cx="20" cy="20" r="3"/><circle cx="24" cy="36" r="3"/><circle cx="80" cy="20" r="3"/><circle cx="76" cy="36" r="3"/></g></svg>' },
    bell: { name: '铃铛项圈', slot: 'neck', price: 40, anchor: 'neck', y: 0.53, w: 0.62, aspect: 0.45,
      svg: '<svg viewBox="0 0 100 45"><path d="M4 6q46 18 92 0" stroke="#e8553a" stroke-width="8" fill="none" stroke-linecap="round"/><circle cx="50" cy="26" r="13" fill="#f7c948" stroke="#b8860b" stroke-width="3"/><path d="M40 28h20" stroke="#b8860b" stroke-width="3"/><circle cx="50" cy="34" r="3" fill="#b8860b"/></svg>' }
  };
  const SLOTS = { head: '头饰', face: '脸部', neck: '颈部' };

  // anchors: measured per pet image (fractions of the image box).
  // Face items are centred between the eyes and sized from the eye spacing; neck items
  // hang a fixed distance below the eyes; head items sit on the top of the head.
  function place(item, a) {
    const hw = a.hw || 0.45;
    const es = a.es || hw * 0.4;
    const aspect = item.aspect || 0.6;
    let width, cx, top, rot = 0;
    if (item.anchor === 'face' && a.ex != null) {
      width = es * 2.05 * (item.w / 0.62);
      cx = a.ex;
      top = a.ey - width * aspect / 2 + es * 0.04;
      rot = Math.atan(a.tilt || 0) * 180 / Math.PI;
    } else if (item.anchor === 'neck' && a.ex != null) {
      width = es * 2.6 * (item.w / 0.8);
      cx = a.ex;
      top = a.ey + es * 0.62;
      rot = Math.atan(a.tilt || 0) * 90 / Math.PI;
    } else {
      // head items: scale with the eyes and sit at the head top (or above the eyes when the
      // silhouette top is far away, e.g. the turtle's shell or rabbit ears)
      const headW = a.ex != null ? Math.min(hw, es * 2.4) : hw;
      width = headW * item.w * 1.1;
      cx = (a.ex != null ? a.ex : a.cx || 0.5) + (item.dx || 0) * headW;
      const height = width * aspect;
      const headTop = a.ex != null ? Math.max(a.top, a.ey - es * 1.25) : a.top;
      top = headTop - height * (1 - (item.sink || 0.3));
      if (item.anchor !== 'top') top = a.top + (a.bottom - a.top) * item.y - height / 2;
    }
    return { left: cx - width / 2, top, width, height: width * aspect, rot };
  }

  root.Wardrobe = { ITEMS, SLOTS, place };
})(typeof window !== 'undefined' ? window : globalThis);
