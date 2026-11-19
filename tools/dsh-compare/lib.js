// Helpers injected into each step via window.__d
window.__d = window.__d || {
  click(label) {
    const els = [...document.querySelectorAll('button,[role=button],[role=menuitem],[role=tab],a,[role=option]')]
      .filter(e => e.offsetParent || e.getClientRects().length);
    const e = els.find(e => (e.getAttribute('aria-label') || '').trim() === label) ||
              els.find(e => (e.innerText || '').trim() === label) ||
              els.find(e => (e.getAttribute('aria-label') || e.innerText || '').trim().startsWith(label));
    if (!e) return 'not found: ' + label;
    e.click(); return 'clicked ' + label;
  },
  list() {
    return JSON.stringify([...document.querySelectorAll('button,[role=button],[role=menuitem],[role=tab],a,input,textarea,[contenteditable=true]')]
      .filter(e => e.offsetParent || e.getClientRects().length).slice(0, 80)
      .map(e => (e.getAttribute('aria-label') || e.innerText || e.placeholder || '').trim().slice(0, 40)).filter(Boolean));
  }
};
window.__d.type = function (el, text) {
  if (typeof el === 'string') el = document.querySelector(el);
  if (!el) return 'no element';
  el.focus();
  if (el.isContentEditable) { document.execCommand('selectAll'); document.execCommand('insertText', false, text); return 'typed (ce)'; }
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return 'typed';
};
window.__d.enter = function (el) {
  if (typeof el === 'string') el = document.querySelector(el);
  el = el || document.activeElement;
  for (const t of ['keydown', 'keypress', 'keyup'])
    el.dispatchEvent(new KeyboardEvent(t, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
  return 'enter';
};
window.__d.inputs = function () {
  return JSON.stringify([...document.querySelectorAll('input,textarea,[contenteditable=true]')].filter(e => e.offsetParent)
    .map(e => e.tagName + '|' + (e.getAttribute('aria-label') || e.placeholder || '') + '|' + (e.value || '').slice(0, 40)));
};
window.__d.clickText = function (text, nth) {
  const all = [...document.querySelectorAll('body *')].filter(e => e.offsetParent && (e.innerText || '').trim() === text);
  const e = all[nth || 0];
  if (!e) return 'no text: ' + text;
  e.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  return 'clicked text ' + text + ' (' + e.tagName + ', of ' + all.length + ')';
};
window.__d.top = function () {
  [...document.querySelectorAll('*')].filter(e => e.scrollHeight > e.clientHeight + 50 && /auto|scroll/.test(getComputedStyle(e).overflowY)).forEach(e => e.scrollTop = 0);
  return 'top';
};
window.__d.at = function (text, nth) {
  const all = [...document.querySelectorAll('body *')].filter(e => e.offsetParent &&
    ((e.innerText || '').trim() === text || (e.getAttribute('aria-label') || '').trim() === text));
  // Deepest match: a wrapper whose only text is the label would be clicked in its middle.
  const leaves = all.filter(e => !all.some(o => o !== e && e.contains(o)));
  const e = leaves[nth || 0];
  if (!e) return 'no text: ' + text;
  const r = e.getBoundingClientRect();
  return '@click ' + Math.round(r.left + r.width / 2) + ',' + Math.round(r.top + r.height / 2);
};
// Wait up to `ms` for an element with this text / aria-label, then return its
// "@click x,y"; resolves "absent: <text>" when it never shows up.
window.__d.waitAt = function (text, ms) {
  const deadline = Date.now() + (ms || 6000);
  return new Promise(resolve => {
    const tick = () => {
      const r = window.__d.at(text);
      if (r.startsWith('@click')) return resolve(r);
      if (Date.now() > deadline) return resolve('absent: ' + text);
      setTimeout(tick, 200);
    };
    tick();
  });
};
// Outline of a subtree: tag.classes size bg border radius shadow, `depth` levels.
window.__d.outline = function (sel, depth) {
  const root = typeof sel === 'string' ? document.querySelector(sel) : sel;
  if (!root) return 'none: ' + sel;
  const out = [];
  const walk = (e, d) => {
    if (!e.offsetParent && e !== document.body && getComputedStyle(e).position !== 'fixed') return;
    const r = e.getBoundingClientRect(), c = getComputedStyle(e);
    const cls = (e.className && e.className.baseVal === undefined ? e.className : '').toString().trim().split(/\s+/).slice(0, 3).join('.');
    out.push('  '.repeat(d) + e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + (cls ? '.' + cls : '') +
      ` ${Math.round(r.left)},${Math.round(r.top)} ${Math.round(r.width)}x${Math.round(r.height)}` +
      (c.backgroundColor !== 'rgba(0, 0, 0, 0)' ? ' bg=' + c.backgroundColor : '') +
      (c.borderTopStyle !== 'none' && c.borderTopWidth !== '0px' ? ' bd=' + c.borderTopWidth + ' ' + c.borderTopColor : '') +
      (c.borderRadius !== '0px' ? ' r=' + c.borderRadius : '') +
      (c.boxShadow !== 'none' ? ' sh' : '') + ' f=' + c.fontSize + '/' + c.fontWeight);
    if (d < depth) for (const k of e.children) walk(k, d + 1);
  };
  walk(root, 0);
  return out.join('\n');
};
