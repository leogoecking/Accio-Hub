// Browser-side QA only: no persistence, no requests, no application state changes.
(() => {
  const root = document.querySelector('dialog:modal') || document;
  const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const rgba = value => { ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = value; ctx.fillRect(0, 0, 1, 1); return [...ctx.getImageData(0, 0, 1, 1).data]; };
  const selector = el => {
    if (el.id) return '#' + CSS.escape(el.id);
    const parts = [];
    while (el && el.nodeType === 1 && parts.length < 5) {
      if (el.id) { parts.unshift('#' + CSS.escape(el.id)); break; }
      const tag = el.tagName.toLowerCase(), peers = [...(el.parentElement?.children || [])].filter(n => n.tagName === el.tagName);
      parts.unshift(tag + [...el.classList].slice(0, 2).map(c => '.' + CSS.escape(c)).join('') + (peers.length > 1 ? ':nth-of-type(' + (peers.indexOf(el) + 1) + ')' : ''));
      el = el.parentElement;
    }
    return parts.join(' > ');
  };
  const visible = el => el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true }) && !el.closest('[hidden],.sr-only,[inert]');
  const layers = el => {
    let opacity = 1; const unknown = [], effects = [];
    for (let node = el; node; node = node.parentElement) {
      const s = getComputedStyle(node); opacity *= Number(s.opacity);
      if (s.filter.startsWith('drop-shadow(') && node.matches('.dial') && el.closest('.dial-inner')) {
        effects.push({ selector: selector(node), filter: s.filter, reason: 'Drop shadow is behind the opaque dial; it does not change interior foreground RGB or alpha.' });
      } else if (s.filter !== 'none' || s.mixBlendMode !== 'normal') unknown.push(selector(node));
    }
    return { opacity, unknown, effects };
  };
  const rect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
  const onScreen = r => r.width > 0 && r.height > 0 && r.right > 0 && r.left < innerWidth && r.bottom > 0 && r.top < innerHeight;
  const clipped = (el, r) => {
    let left = Math.max(0, r.left), right = Math.min(innerWidth, r.right), top = Math.max(0, r.top), bottom = Math.min(innerHeight, r.bottom);
    for (let parent = el.parentElement; parent; parent = parent.parentElement) {
      const s = getComputedStyle(parent), p = parent.getBoundingClientRect();
      if (['auto', 'hidden', 'scroll', 'clip'].includes(s.overflowX)) { left = Math.max(left, p.left); right = Math.min(right, p.right); }
      if (['auto', 'hidden', 'scroll', 'clip'].includes(s.overflowY)) { top = Math.max(top, p.top); bottom = Math.min(bottom, p.bottom); }
    }
    if (right <= left || bottom <= top) return null;
    const hit = document.elementFromPoint((left + right) / 2, (top + bottom) / 2);
    if (hit && !el.contains(hit) && !hit.contains(el)) return null;
    return { x: left, y: top, width: right - left, height: bottom - top };
  };
  const nodes = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    const el = node.parentElement;
    if (!node.textContent.trim() || !el || !visible(el) || el.closest('script,style,option,svg')) continue;
    const range = document.createRange(); range.selectNodeContents(node);
    const rects = [...range.getClientRects()].filter(onScreen).map(r => clipped(el, r)).filter(Boolean);
    if (!rects.length) continue;
    const s = getComputedStyle(el), font = Number.parseFloat(s.fontSize), large = font >= 24 || (font >= 18.667 && Number(s.fontWeight) >= 700);
    nodes.push({ kind: 'text', selector: selector(el), text: node.textContent.trim(), rects, rgba: rgba(s.webkitTextFillColor || s.color),
      font, weight: s.fontWeight, required: large ? 3 : 4.5, disabled: !!el.closest(':disabled,[aria-disabled=true]'), ...layers(el) });
  }
  for (const el of root.querySelectorAll('input:not([type=hidden]):not([type=password]):not([type=color]):not([type=checkbox]),textarea,select')) {
    if (!visible(el)) continue;
    const r = el.getBoundingClientRect(); if (!onScreen(r)) continue;
    const s = getComputedStyle(el), placeholder = !el.value && el.placeholder, ps = placeholder ? getComputedStyle(el, '::placeholder') : s;
    if (!el.value && !placeholder) continue;
    const inset = 3;
    nodes.push({ kind: placeholder ? 'placeholder' : 'value', selector: selector(el), text: placeholder || (el.tagName === 'SELECT' ? el.selectedOptions[0]?.textContent : el.value),
      rects: [{ x: r.x + Number.parseFloat(s.borderLeftWidth) + inset, y: r.y + Number.parseFloat(s.borderTopWidth) + inset,
        width: r.width - 2 * inset - Number.parseFloat(s.borderLeftWidth) - Number.parseFloat(s.borderRightWidth), height: r.height - 2 * inset - Number.parseFloat(s.borderTopWidth) - Number.parseFloat(s.borderBottomWidth) }],
      rgba: rgba(ps.color), font: Number.parseFloat(s.fontSize), required: 4.5, disabled: el.disabled, placeholderOpacity: Number(ps.opacity), ...layers(el) });
  }
  for (const el of root.querySelectorAll('input:not([type=hidden]):not([type=color]),textarea,select')) {
    if (!visible(el)) continue;
    const r = el.getBoundingClientRect(); if (!onScreen(r)) continue;
    const s = getComputedStyle(el), edge = Number.parseFloat(s.borderTopWidth) === 0 && el.closest('.project-search') || el;
    const es = getComputedStyle(edge);
    nodes.push({ kind: 'boundary', selector: selector(el), text: el.labels?.[0]?.textContent.trim().slice(0, 80) || el.getAttribute('aria-label'),
      rects: [rect(edge.getBoundingClientRect())], rgba: rgba(es.borderTopColor), border: Number.parseFloat(es.borderTopWidth), boundarySource: selector(edge), native: s.appearance !== 'none',
      required: 3, disabled: el.disabled, ...layers(el) });
  }
  for (const el of root.querySelectorAll('button,a')) {
    if (!visible(el)) continue;
    const hasText = nodes.some(n => n.kind === 'text' && n.rects.length && el.contains(document.querySelector(n.selector)));
    if (hasText) continue;
    for (const path of el.querySelectorAll('svg path,svg circle,svg rect,svg line,svg polyline')) {
      const r = path.getBoundingClientRect(); if (!onScreen(r)) continue;
      const s = getComputedStyle(path), color = s.stroke === 'none' ? s.fill : s.stroke;
      if (color === 'none') continue;
      nodes.push({ kind: 'icon', selector: selector(path), text: el.getAttribute('aria-label') || el.title || el.textContent.trim(), rects: [rect(r)],
        rgba: rgba(color), required: 3, disabled: el.disabled, ...layers(path) });
    }
  }
  const focused = document.activeElement;
  if (focused?.matches(':focus-visible')) {
    const s = getComputedStyle(focused);
    nodes.push({ kind: 'focus', selector: selector(focused), rects: [rect(focused.getBoundingClientRect())], rgba: rgba(s.outlineColor),
      outline: s.outlineStyle, width: Number.parseFloat(s.outlineWidth), offset: Number.parseFloat(s.outlineOffset), required: 3, ...layers(focused) });
  }
  return { viewport: { width: innerWidth, height: innerHeight, dpr: devicePixelRatio, scale: visualViewport.scale },
    theme: document.documentElement.dataset.theme, wallpaper: document.documentElement.dataset.wallpaper,
    accent: getComputedStyle(document.documentElement).getPropertyValue('--accent').trim(),
    nodes, active: focused?.id || focused?.getAttribute('aria-label'), modal: document.querySelector('dialog:modal')?.id || null,
    overflow: document.documentElement.scrollWidth > innerWidth, fontsLoaded: document.fonts.status,
    geometry: [...document.querySelectorAll('.rail,.headbar,.music-zone,.apps-dock,.panel,.dial')].filter(visible).map(el => ({ selector: selector(el), rect: rect(el.getBoundingClientRect()), font: getComputedStyle(el).fontFamily })) };
})()
