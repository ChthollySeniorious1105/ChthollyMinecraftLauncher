# Hub module contract

The hub window (src/hub/index.html) is a plain HTML page (no bundler, no frameworks,
contextIsolation on, no node). It loads `hub.css`, `hub.js`, then each module's
`<script src="games/xxx.js">` and `<link rel="stylesheet" href="games/xxx.css">`.

Each module registers itself:

```js
Hub.register({
  id: 'minesweeper',          // unique
  title: '扫雷',
  group: 'game',              // 'game' | 'tool'
  icon: '<svg viewBox="0 0 24 24">…</svg>',  // 24x24 inline SVG string, uses currentColor
  mount(el, ctx) { … },       // el = empty <div> filling the content area (scrollable)
  unmount() { … }             // remove window listeners, clear timers/rAF
});
```

`ctx`:
- `ctx.store.get(key, defaultValue)` / `ctx.store.set(key, value)` — JSON persisted, namespaced per module.
- `ctx.say(text)` — make the desktop pet show a speech bubble (e.g. on new record / win).
- `ctx.isActive()` — true while the module is the visible page (pause games when false).
- `ctx.toast(text)` — small transient message at the bottom of the window.
- `ctx.reward(coins, reason)` — give the player 小鱼干 coins (pet currency). Call once per win /
  achievement, e.g. `ctx.reward(10, '扫雷胜利')`. Typical amounts: easy win 3-5, medium 8-10, hard 15-20.
  Do not call it repeatedly for the same game.

Rules:
- All CSS scoped under a root class (e.g. `.ms-root …`). Do not style body/html/global tags.
- Theme variables available (colours follow the CML launcher theme; defaults = CML default palette):
  --bg #f4f7fa, --panel #ffffff, --line #e3e7ec, --accent #4fa3d9, --accent-2 (strong heading colour,
  derived from accent + text), --accent-alt (CML's secondary hue), --text #1d2233, --muted #6b7280,
  --field #f3f5f8, --on-accent, --radius 14px, --shadow. Dark CML themes add `.theme-dark` on <html>.
- UI text in Simplified Chinese. All graphics drawn with inline SVG / CSS / canvas; no external images, no network.
- Keyboard listeners on `window` must ignore events when `!ctx.isActive()` and must be removed in unmount.
- Content area is ~ 760x600 px (window 960x680 minus 200px sidebar); layout should center and fit.
