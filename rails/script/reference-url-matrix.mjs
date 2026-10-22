// Pure local parsing: about:blank, new URL and a detached anchor. No destination is opened.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
const root=resolve(import.meta.dirname,'../..'),evidence=resolve(process.env.ACCIO_QA_EVIDENCE||resolve(root,'docs/assets/p1.2f/f2a'))
const session=process.env.ACCIO_QA_SESSION||'accio-f2a-parser'
mkdirSync(evidence,{recursive:true})
const rows=JSON.parse(readFileSync(resolve(root,'rails/test/fixtures/files/reference_urls.json'),'utf8'))
const b=(...args)=>{const r=JSON.parse(execFileSync('agent-browser',['--session',session,'--json',...args],{encoding:'utf8'}));assert.equal(r.success,true);return r.data}
try{
 b('--args','--no-sandbox','open','about:blank');b('snapshot','-i')
 const code=`(()=>{const before=performance.getEntriesByType('resource').length;const rows=${JSON.stringify(rows)};const results=rows.map(row=>{try{const parsed=new URL(row.url);const anchor=document.createElement('a');anchor.setAttribute('href',row.url);return {...row,whatwg:{href:parsed.href,host:parsed.hostname,port:parsed.port,protocol:parsed.protocol,anchorHref:anchor.href}}}catch{return {...row,whatwg:null}}});return {userAgent:navigator.userAgent,location:location.href,resourceRequests:performance.getEntriesByType('resource').length-before,results}})()`
 const response=JSON.parse(execFileSync('agent-browser',['--session',session,'--json','eval','--stdin'],{input:code,encoding:'utf8'}));assert.equal(response.success,true)
 const browser=response.data.result;assert.equal(browser.location,'about:blank');assert.equal(browser.resourceRequests,0)
 const rubyScript=`require "active_support/core_ext/object/blank"; require "json"; require_relative "./app/services/safe_reference_url"; rows=JSON.parse(STDIN.read); puts JSON.generate(rows.map { |row| value=SafeReferenceUrl.call(row.fetch("url")); parsed=(URI.parse(row.fetch("url")) rescue nil); row.merge("ruby"=>{ "accepted"=>!!value,"returned"=>value,"uri_host"=>parsed&.hostname,"uri_port"=>(parsed&.port rescue nil) }) })`
 const ruby=JSON.parse(execFileSync('bundle',['exec','ruby','-e',rubyScript],{cwd:resolve(root,'rails'),input:JSON.stringify(rows),encoding:'utf8'}))
 const combined=browser.results.map((row,i)=>({...row,ruby:ruby[i].ruby}))
 for(const row of combined){assert.equal(row.ruby.accepted,row.accepted,row.id);if(row.accepted){assert.ok(row.whatwg,row.id);assert.equal(row.ruby.returned,row.url,row.id)}}
 writeFileSync(resolve(evidence,'url-matrix.json'),JSON.stringify({browser:{userAgent:browser.userAgent,location:browser.location,resourceRequests:browser.resourceRequests},count:combined.length,results:combined},null,2)+'\n')
 writeFileSync(resolve(evidence,'url-matrix.md'),'| Caso | URL (JSON) | Política Ruby | Host WHATWG |\n|---|---|---|---|\n'+combined.map(row=>`| ${row.id} | \`${JSON.stringify(row.url).replaceAll('|','\\|')}\` | ${row.ruby.accepted?'aceita':'rejeita'} | ${row.whatwg?.host||'inválida'} |`).join('\n')+'\n')
 console.log(JSON.stringify({cases:combined.length,accepted:combined.filter(x=>x.accepted).length,allAcceptedParsedByChromium:true,resourceRequests:0}))
}finally{b('close')}
