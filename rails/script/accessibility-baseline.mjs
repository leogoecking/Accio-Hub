// Read-only P0.4 visual reference, served locally with already installed fonts.
import { execFileSync, spawn } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, copyFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import assert from 'node:assert/strict'
const repo = resolve(import.meta.dirname, '../..'), evidence = resolve(repo, 'docs/assets/p1.2f/f4/baseline-p04')
mkdirSync(evidence, { recursive: true })
const area = mkdtempSync(resolve(repo, 'rails/tmp/f4-baseline-'))
const files = execFileSync('git', ['ls-tree', '-r', '--name-only', 'p0.4-approved', 'prototype'], { cwd: repo, encoding: 'utf8' }).trim().split('\n')
for (const file of files) {
  const destination = resolve(area, file.slice('prototype/'.length)); mkdirSync(dirname(destination), { recursive: true })
  writeFileSync(destination, execFileSync('git', ['show', `p0.4-approved:${file}`], { cwd: repo }))
}
let index = readFileSync(resolve(area, 'index.html'), 'utf8')
index = index.replace(/<link[^>]+https:\/\/fonts\.[^>]+>/g, '').replace('</head>', '<link rel="stylesheet" href="./local-fonts.css"></head>')
writeFileSync(resolve(area, 'index.html'), index)
const fonts = readFileSync(resolve(repo, 'rails/app/assets/stylesheets/fonts.css'), 'utf8')
writeFileSync(resolve(area, 'local-fonts.css'), fonts)
for (const match of fonts.matchAll(/url\(([^)]+)\)/g)) copyFileSync(resolve(repo, 'rails/app/assets/fonts', match[1]), resolve(area, match[1]))
const server = spawn('python3', ['-m', 'http.server', '3131', '--bind', '127.0.0.1', '--directory', area], { stdio: 'ignore' })
const args = ['--session', 'accio-f4-baseline', '--json']
const b = (...cmd) => { const r = JSON.parse(execFileSync('agent-browser', [...args, ...cmd], { encoding: 'utf8', timeout: 60000 })); assert.equal(r.success, true); return r.data }
const ev = code => JSON.parse(execFileSync('agent-browser', [...args, 'eval', '--stdin'], { input: code, encoding: 'utf8', timeout: 45000 })).data.result
try {
  await new Promise((done, reject) => { server.once('error', reject); const start = Date.now(); const poll = async () => { try { const response = await fetch('http://127.0.0.1:3131/'); if (response.ok) return done() } catch {} if (Date.now() - start > 10000) return reject(new Error('Local baseline server unavailable')); setTimeout(poll, 50) }; poll() })
  b('--args', '--no-sandbox', 'open', 'http://127.0.0.1:3131/#/home'); b('wait', '.board')
  const comparisons = []
  for (const theme of ['dark', 'light']) for (const width of [320, 390, 768, 1440, 1920]) {
    const current = JSON.parse(readFileSync(resolve(repo, `docs/assets/p1.2f/f4/after-reviewed/${theme}-${width}-dashboard.json`)))
    ev(`(()=>{const key='accio-hub-p0.3-studio',s=JSON.parse(localStorage.getItem(key));s.theme=${JSON.stringify(theme)};s.wallpaper=${JSON.stringify(current.wallpaper)};s.accent='#b1f07d';s.page='home';localStorage.setItem(key,JSON.stringify(s));return true})()`)
    b('reload'); b('wait', '.board'); b('set', 'viewport', String(width), '1000'); ev('document.fonts.ready.then(()=>true)')
    ev('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))')
    b('screenshot', resolve(evidence, `${theme}-${width}.png`))
    const metrics = ev(`(()=>{const selectors=['.rail','.headbar','.music-zone','.app-dock','.widget-grid','.dial','.dial-inner'];return selectors.map(selector=>{const el=document.querySelector(selector);if(!el)return {selector,missing:true};const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {selector,x:r.x,y:r.y,width:r.width,height:r.height,font:s.fontFamily,color:s.color,background:s.backgroundImage,borderRadius:s.borderRadius}})})()`)
    comparisons.push({ theme, width, wallpaper: current.wallpaper, prototype: metrics, source: 'p0.4-approved', fontDeliveryOnly: 'remote font links replaced by identical locally available families in private temporary copy' })
  }
  writeFileSync(resolve(evidence, 'geometry.json'), JSON.stringify(comparisons, null, 2) + '\n')
  console.log('10 P0.4 reference captures, both themes / five widths; prototype checkout unchanged.')
} finally { b('close'); server.kill('SIGTERM') }
