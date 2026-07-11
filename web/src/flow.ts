// how-it-works diagram: three devices → the webbridge window → chrome devtools + safari web
// inspector. white connections light up and a non-uniform stream of dots flows left→right through
// webbridge and out to the devtools. built as one inline SVG driven by a single rAF loop.

const NS = 'http://www.w3.org/2000/svg'
type Attrs = Record<string, string | number>
type Pt = { x: number; y: number }

function el<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Attrs = {}): SVGElementTagNameMap[K] {
  const e = document.createElementNS(NS, tag)
  for (const k in attrs) e.setAttribute(k, String(attrs[k]))
  return e
}
function text(x: number, y: number, cls: string, s: string, anchor?: string) {
  const e = el('text', { x, y, class: cls })
  if (anchor) e.setAttribute('text-anchor', anchor)
  e.textContent = s
  return e
}
const clamp01 = (t: number) => (t < 0 ? 0 : t > 1 ? 1 : t)
const lerp = (a: number, b: number, t: number) => a + (b - a) * t
const rnd = (a: number, b: number) => a + Math.random() * (b - a)

const VB_W = 1000, VB_H = 420

// left: devices
const DEVICES = [
  { type: 'iphone', name: 'iPhone', x: 74, y: 100 },
  { type: 'android', name: 'Android', x: 74, y: 210 },
  { type: 'ipad', name: 'iPad', x: 78, y: 320 },
]
const exitOf = (d: { type: string; x: number; y: number }): Pt => ({ x: d.x + (d.type === 'ipad' ? 34 : 21), y: d.y })

// center: webbridge window
const WX = 416, WY = 136, WW = 168, WH = 148
const INLET: Pt = { x: WX, y: WY + WH / 2 }
const OUTLET: Pt = { x: WX + WW, y: WY + WH / 2 }

// right: devtools targets
const TOOLS = [
  { key: 'chrome', label: 'Chrome DevTools', x: 742, y: 142, w: 206, h: 62 },
  { key: 'safari', label: 'Safari Web Inspector', x: 742, y: 218, w: 206, h: 62 },
]
// how many webview lines fan out of webbridge into each devtool
const TOOL_LINES: Record<string, number> = { chrome: 3, safari: 4 }

interface Dot { c: SVGCircleElement; off: number; spd: number }
interface Stream { from: Pt; to: Pt; dots: Dot[]; period: number }

export function initFlow() {
  const host = document.getElementById('flow')
  if (!host) return
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  const svg = el('svg', { viewBox: `0 0 ${VB_W} ${VB_H}`, xmlns: NS })

  // glow filter for the streaming dots
  const defs = el('defs')
  const glow = el('filter', { id: 'fd-glow', x: '-300%', y: '-300%', width: '700%', height: '700%' })
  glow.appendChild(el('feGaussianBlur', { stdDeviation: 1.5, result: 'b' }))
  const merge = el('feMerge')
  merge.appendChild(el('feMergeNode', { in: 'b' }))
  merge.appendChild(el('feMergeNode', { in: 'SourceGraphic' }))
  glow.appendChild(merge)
  defs.appendChild(glow)
  svg.appendChild(defs)

  // ── wires: dim guide + white lit line, both for every leg ──
  // left: one leg per device → the window inlet
  const legs: { from: Pt; to: Pt }[] = []
  DEVICES.forEach((d) => legs.push({ from: exitOf(d), to: INLET }))
  const leftCount = legs.length
  // right: several legs per devtool (one per webview being bridged), fanning out of the window's
  // right edge to evenly spaced entry points on each card.
  const rightTargets: Pt[] = []
  TOOLS.forEach((t) => {
    const n = TOOL_LINES[t.key] ?? 1
    for (let i = 0; i < n; i++) rightTargets.push({ x: t.x, y: t.y + (t.h * (i + 1)) / (n + 1) })
  })
  rightTargets.forEach((to, i) => {
    const fy = lerp(OUTLET.y - 40, OUTLET.y + 40, rightTargets.length === 1 ? 0.5 : i / (rightTargets.length - 1))
    legs.push({ from: { x: OUTLET.x, y: fy }, to })
  })
  const litWires = legs.map((l) => {
    svg.appendChild(el('line', { x1: l.from.x, y1: l.from.y, x2: l.to.x, y2: l.to.y, stroke: 'var(--ink-4)', 'stroke-width': 1.1, 'stroke-dasharray': '2 6' }))
    const w = el('line', { x1: l.from.x, y1: l.from.y, x2: l.to.x, y2: l.to.y, stroke: '#fff', 'stroke-width': 1.2, opacity: 0 })
    svg.appendChild(w)
    return w
  })

  // ── center window (minimal): title bar + the app icon ──
  const win = el('g')
  win.appendChild(el('rect', { x: WX, y: WY, width: WW, height: WH, rx: 13, fill: 'var(--ink-2)', stroke: 'var(--ink-4)' }))
  win.appendChild(el('path', { d: `M${WX} ${WY + 13} a13 13 0 0 1 13 -13 h${WW - 26} a13 13 0 0 1 13 13 v21 h${-WW} z`, fill: 'var(--ink-3)' }))
  ;[0, 1, 2].forEach((i) => win.appendChild(el('circle', { cx: WX + 16 + i * 13, cy: WY + 17, r: 4, fill: '#2c2c2c' })))
  win.appendChild(text(WX + WW / 2, WY + 21, 'fd-wtitle', 'webbridge', 'middle'))
  const hub = el('circle', { cx: WX + WW / 2, cy: WY + 34 + (WH - 34) / 2, r: 30, fill: 'none', stroke: '#fff', opacity: 0, filter: 'url(#fd-glow)' })
  win.appendChild(hub)
  const iconSize = 46
  win.appendChild(el('image', { href: '/icon.svg', x: WX + WW / 2 - iconSize / 2, y: WY + 34 + (WH - 34) / 2 - iconSize / 2, width: iconSize, height: iconSize, opacity: 0.96 }))
  svg.appendChild(win)

  // ── right: devtools cards ──
  TOOLS.forEach((t) => {
    const g = el('g')
    g.appendChild(el('rect', { x: t.x, y: t.y, width: t.w, height: t.h, rx: 12, fill: 'var(--ink-2)', stroke: 'var(--ink-4)' }))
    const cy = t.y + t.h / 2
    const ix = t.x + 30
    const ig = el('g', { stroke: 'var(--ash)', 'stroke-width': 1.4, fill: 'none' })
    if (t.key === 'chrome') {
      // devtools-ish mark: circle + inner circle + three spokes
      ig.appendChild(el('circle', { cx: ix, cy, r: 11 }))
      ig.appendChild(el('circle', { cx: ix, cy, r: 4 }))
      ig.appendChild(el('path', { d: `M${ix} ${cy - 11} V${cy - 4} M${ix + 9.5} ${cy + 5.5} L${ix + 3.5} ${cy + 2} M${ix - 9.5} ${cy + 5.5} L${ix - 3.5} ${cy + 2}` }))
    } else {
      // compass mark for safari: ring + a single needle (rhombus) pointing NE→SW
      ig.appendChild(el('circle', { cx: ix, cy, r: 11 }))
      ig.appendChild(el('path', { d: `M${ix + 5.5} ${cy - 5.5} L${ix + 1.6} ${cy + 1.6} L${ix - 5.5} ${cy + 5.5} L${ix - 1.6} ${cy - 1.6} Z`, fill: 'var(--ash)', stroke: 'none' }))
    }
    g.appendChild(ig)
    g.appendChild(text(t.x + 52, cy + 4, 'fd-title', t.label))
    svg.appendChild(g)
  })

  // ── left: device glyphs ──
  DEVICES.forEach((d) => {
    const g = el('g')
    const cx = d.x, cy = d.y
    if (d.type === 'ipad') {
      g.appendChild(el('rect', { x: cx - 32, y: cy - 23, width: 64, height: 46, rx: 7, fill: 'var(--ink-2)', stroke: 'var(--ink-4)' }))
      g.appendChild(el('circle', { cx: cx + 25, cy, r: 1.6, fill: 'var(--mute)' }))
    } else {
      g.appendChild(el('rect', { x: cx - 18, y: cy - 32, width: 36, height: 64, rx: 9, fill: 'var(--ink-2)', stroke: 'var(--ink-4)' }))
      if (d.type === 'iphone') g.appendChild(el('rect', { x: cx - 5, y: cy - 27, width: 10, height: 2.4, rx: 1.2, fill: 'var(--mute)' }))
      else g.appendChild(el('circle', { cx, cy: cy - 24, r: 1.7, fill: 'var(--mute)' }))
    }
    g.appendChild(text(cx, d.type === 'ipad' ? cy + 40 : cy + 48, 'fd-name', d.name, 'middle'))
    svg.appendChild(g)
  })

  // ── ports + non-uniform streams (top layer) ──
  const portIn = el('circle', { cx: INLET.x, cy: INLET.y, r: 4.5, fill: 'none', stroke: '#fff', opacity: 0, filter: 'url(#fd-glow)' })
  const portOut = el('circle', { cx: OUTLET.x, cy: OUTLET.y, r: 4.5, fill: 'none', stroke: '#fff', opacity: 0, filter: 'url(#fd-glow)' })
  svg.appendChild(portIn)
  svg.appendChild(portOut)

  const streams: Stream[] = legs.map((l, i) => {
    const isIn = i < leftCount
    const K = isIn ? 12 : 8
    const dots: Dot[] = []
    for (let k = 0; k < K; k++) {
      const c = el('circle', { r: rnd(0.9, 1.7), fill: '#fff', opacity: 0, filter: 'url(#fd-glow)' })
      svg.appendChild(c)
      dots.push({ c, off: Math.random(), spd: rnd(0.78, 1.28) })
    }
    return { from: l.from, to: l.to, dots, period: isIn ? 1550 : 1350 }
  })

  host.appendChild(svg)

  const start = performance.now()

  function frame(now: number) {
    const abs = now - start
    const intro = reduced ? 1 : clamp01(abs / 750)

    litWires.forEach((w) => w.setAttribute('opacity', String(intro * 0.3)))

    if (!reduced) {
      streams.forEach((s) => {
        s.dots.forEach((dt) => {
          const ph = ((abs / s.period) * dt.spd + dt.off) % 1
          dt.c.setAttribute('cx', String(lerp(s.from.x, s.to.x, ph)))
          dt.c.setAttribute('cy', String(lerp(s.from.y, s.to.y, ph)))
          const edge = Math.min(clamp01(ph / 0.08), clamp01((1 - ph) / 0.12))
          dt.c.setAttribute('opacity', String(edge * 0.92 * intro))
        })
      })
      const pulse = 0.24 + 0.12 * Math.sin(abs / 240)
      portIn.setAttribute('opacity', String(pulse * intro))
      portOut.setAttribute('opacity', String(pulse * intro))
      portIn.setAttribute('r', String(4.5 + 1.2 * Math.sin(abs / 240)))
      portOut.setAttribute('r', String(4.5 + 1.2 * Math.sin(abs / 240)))
      hub.setAttribute('opacity', String((0.05 + 0.05 * Math.sin(abs / 300)) * intro))
    } else {
      streams.forEach((s) => s.dots.forEach((dt) => dt.c.setAttribute('opacity', '0')))
    }

    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}
