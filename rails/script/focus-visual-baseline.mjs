import { execFileSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
const evidence = resolve(import.meta.dirname, '../../docs/assets/p1.2e2'), args = ['--session', 'accio-e2-p04-visual', '--json']
const b = (...cmd) => { const r = JSON.parse(execFileSync('agent-browser', [...args, ...cmd], { encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data }
const ev = code => { const r = JSON.parse(execFileSync('agent-browser', [...args, 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })); assert.equal(r.success, true); return r.data.result }
const measurements = []
try {
 b('--args', '--no-sandbox', 'open', 'http://127.0.0.1:3113/'); b('wait', '.dial')
 for (const theme of ['dark', 'light']) {
  ev(`const s=JSON.parse(localStorage.getItem('accio-hub-p0.3-studio'));s.theme=${JSON.stringify(theme)};s.accent='#8050b0';localStorage.setItem('accio-hub-p0.3-studio',JSON.stringify(s));true`); b('reload'); b('wait', '.dial')
  for (const width of [320,390,768,1440,1920]) {
   b('set', 'viewport', String(width), '1000'); b('screenshot', resolve(evidence, `p04-dashboard-${theme}-${width}.png`))
   measurements.push({ theme, width, elements: ev(`Array.from(document.querySelectorAll('.rail,.headbar,.music-zone,.dial,.dial-inner,.round-btn')).map(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {class:el.className,width:r.width,height:r.height,font:s.fontFamily,background:s.backgroundImage,color:s.color}})`) })
  }
 }
 writeFileSync(resolve(evidence, 'p04-focus-geometry.json'), JSON.stringify(measurements, null, 2) + '\n')
} finally { b('close') }
