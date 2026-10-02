// Theme bridge for the hub and pet windows (window.PetTheme).
// The palette comes from the CML launcher: src/theme-bridge.js (main process) reads and watches theme.json
// and pushes it through preload (window.cmlTheme). Here it is mapped onto the CSS variables the pages use:
//   --bg --panel --line --accent --accent-2 --text --muted --field --on-accent --shadow (+ .theme-dark on <html>)
// CML's accent2 is a light secondary hue (gradients), while DesktopPet's --accent-2 is the strong heading / title
// colour, so --accent-2 is derived from accent + text and CML's accent2 is exposed as --accent-alt.
(function (root) {
  const DEFAULT = {
    id: 'default', name: 'CML 默认', dark: false,
    bg: '#f4f7fa', surface: '#ffffff', panel: '#ffffff', text: '#1d2233', muted: '#6b7280',
    line: '#e3e7ec', field: '#f3f5f8', accent: '#4fa3d9', accent2: '#7fd3c8', onAccent: '#ffffff',
    paper: '#ffffff', ink: '#23283a', art: ['#4fa3d9', '#7fd3c8']
  };
  let current = DEFAULT;

  function vars(t) {
    return {
      '--bg': t.bg, '--panel': t.panel, '--surface': t.surface, '--line': t.line,
      '--accent': t.accent,
      '--accent-2': `color-mix(in srgb, ${t.accent} ${t.dark ? 35 : 45}%, ${t.text})`,
      '--accent-alt': t.accent2,
      '--text': t.text, '--muted': t.muted, '--field': t.field, '--on-accent': t.onAccent,
      '--shadow': t.dark ? '0 4px 16px rgba(0, 0, 0, .35)' : `0 4px 16px color-mix(in srgb, ${t.text} 10%, transparent)`
    };
  }
  function apply(t, el) {
    t = Object.assign({}, DEFAULT, t || {});
    const r = el || document.documentElement;
    for (const [k, v] of Object.entries(vars(t))) r.style.setProperty(k, v);
    r.dataset.theme = t.id;
    r.classList.toggle('theme-dark', !!t.dark);
    if (!el) current = t;
    return t;
  }
  // paint synchronously with the current CML theme, then follow live changes
  function init(onChange) {
    const bridge = root.cmlTheme;
    apply(bridge ? bridge.get() : DEFAULT);
    if (bridge) bridge.onChange(t => { const prev = current; apply(t); if (onChange) onChange(current, prev); });
    return current;
  }
  root.PetTheme = { DEFAULT, vars, apply, init, get: () => current, HINT: '主题跟随 CML 启动器，在 CML 设置 → 外观 中切换' };
})(window);
