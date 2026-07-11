import './styles.css'
import { initFlow } from './flow'

initFlow()

// sticky header hairline appears once the page scrolls
const hdr = document.querySelector('.hdr')
if (hdr) {
  const onScroll = () => hdr.classList.toggle('scrolled', window.scrollY > 8)
  onScroll()
  window.addEventListener('scroll', onScroll, { passive: true })
}

// the curl command points at wherever this page is actually served from, so a new
// deploy host needs no code change. the hardcoded value in the html is a no-js fallback.
const curlPanel = document.getElementById('panel-curl')
if (curlPanel) {
  const cmd = `curl -fsSL ${location.origin}/install.sh | bash`
  const code = curlPanel.querySelector('code')
  const copy = curlPanel.querySelector('.copybtn')
  if (code) code.textContent = cmd
  if (copy) copy.setAttribute('data-copy', cmd)
}

// the uninstall line mirrors the selected method, in both its text and its copy button's value
const uninstallCmd = document.getElementById('uninstall-cmd')
const uninstallCopy = document.getElementById('uninstall-copy')
const uninstalls: Record<string, string> = {
  brew: 'brew uninstall webbridge',
  curl: `curl -fsSL ${location.origin}/uninstall.sh | bash`,
}

// install method tabs: swap the visible command box (homebrew ↔ curl)
const itabs = document.querySelectorAll<HTMLButtonElement>('.itab')
for (const tab of itabs) {
  tab.addEventListener('click', () => {
    for (const t of itabs) {
      const on = t === tab
      t.classList.toggle('is-active', on)
      t.setAttribute('aria-selected', String(on))
      const panel = document.getElementById(t.getAttribute('aria-controls') ?? '')
      if (panel) panel.hidden = !on
    }
    const method = tab.dataset.method ?? 'brew'
    if (uninstallCmd) uninstallCmd.textContent = uninstalls[method]
    if (uninstallCopy) uninstallCopy.setAttribute('data-copy', uninstalls[method])
  })
}

// the install commands only run on a mac. the html ships them by default; here we detect a non-mac
// client and swap in a short "requires macOS" note instead.
function isMac(): boolean {
  const ua = (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData
  if (ua?.platform) return ua.platform === 'macOS'
  // navigator.platform is "MacIntel" on macs, but ipados reports the same with a touch screen, so
  // require no touch points to exclude ipad.
  return /Mac/.test(navigator.platform) && navigator.maxTouchPoints <= 1
}

if (!isMac()) {
  document.querySelector('.install')?.setAttribute('hidden', '')
  document.querySelector('.install-note')?.removeAttribute('hidden')
}

// copy-to-clipboard on the install line(s)
for (const btn of document.querySelectorAll<HTMLButtonElement>('[data-copy]')) {
  btn.addEventListener('click', async () => {
    const text = btn.getAttribute('data-copy') ?? ''
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      /* clipboard unavailable, ignore */
    }
    const label = btn.querySelector('.lbl')
    const prev = label?.textContent ?? ''
    btn.classList.add('done')
    if (label) label.textContent = 'copied'
    setTimeout(() => {
      btn.classList.remove('done')
      if (label) label.textContent = prev
    }, 1400)
  })
}

// reveal sections as they scroll into view
const revealables = document.querySelectorAll('.reveal')
if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (e.isIntersecting) {
          e.target.classList.add('in')
          io.unobserve(e.target)
        }
      }
    },
    { rootMargin: '0px 0px -8% 0px', threshold: 0.08 },
  )
  for (const el of revealables) io.observe(el)
} else {
  for (const el of revealables) el.classList.add('in')
}
