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
