// Recheck a partially painted controlled screenshot, using the owned QA profile.
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
const repo=resolve(import.meta.dirname,'../..'), out=resolve(repo,'docs/assets/p1.2f/f4/paint-review');mkdirSync(out,{recursive:true})
const args=['--session','accio-f4-visual','--json']
const b=(...cmd)=>{const r=JSON.parse(execFileSync('agent-browser',[...args,...cmd],{encoding:'utf8',timeout:45000}));assert.equal(r.success,true);return r.data}
const ev=code=>JSON.parse(execFileSync('agent-browser',[...args,'eval','--stdin'],{input:code,encoding:'utf8',timeout:45000})).data.result
const settled=()=>ev('document.fonts.ready.then(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true)))))')
const rows=[]
function capture(name){settled();const row=ev(`(()=>{const el=document.querySelector('.board-titleline h1'),r=el.getBoundingClientRect();const range=document.createRange();range.selectNodeContents(el);return {text:el.textContent,rect:{x:r.x,y:r.y,width:r.width,height:r.height},textWidth:range.getBoundingClientRect().width,color:getComputedStyle(el).color,overflow:getComputedStyle(el).overflow,theme:document.documentElement.dataset.theme}})()`);assert.equal(row.text,'Seu espaço.');assert.ok(row.textWidth<=row.rect.width);b('screenshot',resolve(out,name+'.png'));rows.push({name,...row})}
b('open','http://127.0.0.1:3127/');b('wait','[data-ready=true]');b('set','viewport','1440','1000');capture('clean-current')
const css=execFileSync('git',['show','HEAD:rails/app/assets/stylesheets/foundation.css'],{cwd:repo,encoding:'utf8'})
ev(`(()=>{document.querySelectorAll('link[rel=stylesheet]').forEach(el=>{if(el.href.includes('/foundation-')||el.href.includes('/foundation.')){el.dataset.f4Disabled='true';el.disabled=true}});const s=document.createElement('style');s.id='f4-original-css';s.textContent=${JSON.stringify(css)};document.head.append(s);return true})()`)
capture('original-css')
ev('document.querySelector("#f4-original-css").remove();document.querySelectorAll("[data-f4-disabled]").forEach(el=>{el.disabled=false;delete el.dataset.f4Disabled});true')
capture('restored-current');b('reload');b('wait','[data-ready=true]');capture('after-reload')
writeFileSync(resolve(out,'observations.json'),JSON.stringify({rows,conclusion:'DOM text and containment pass; original partial raster retained as inconclusive capture, no product defect inferred'},null,2)+'\n');b('close')
