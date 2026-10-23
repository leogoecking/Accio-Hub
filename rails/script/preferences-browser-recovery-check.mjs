import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import assert from "node:assert/strict";
const root=resolve(import.meta.dirname,"../..");
const workspace=readFileSync(resolve(root,"rails/tmp/p12c-workspace"),"utf8").trim();
const credentials=JSON.parse(readFileSync(resolve(workspace,"credentials.json"),"utf8"));
const other=JSON.parse(readFileSync(resolve(workspace,"other-cookie.json"),"utf8"));
const evidence=resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root,"docs/assets/p1.2c"));mkdirSync(evidence,{recursive:true});
const results=[];
let session="accio-p12c-browser-b";
function b(...args){const data=JSON.parse(execFileSync("agent-browser",["--session",session,"--json",...args],{encoding:"utf8",timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:"/tmp"}}));assert.equal(data.success,true);return data.data;}
function evaluate(source){const data=JSON.parse(execFileSync("agent-browser",["--session",session,"--json","eval","--stdin"],{input:source,encoding:"utf8",timeout:45000,env:{...process.env,XDG_RUNTIME_DIR:"/tmp"}}));assert.equal(data.success,true);return data.data.result;}
const click=selector=>{b("snapshot","-i");b("click",selector);};
const saved=()=>b("wait","--fn","document.querySelector('[data-save-status]').hidden");
const snapshot=()=>evaluate("JSON.parse(document.querySelector('[data-studio-appearance-value]').dataset.studioAppearanceValue)");
function login(){b("snapshot","-i");b("fill","#email_address",credentials.email);evaluate('document.querySelector("#password").value='+JSON.stringify(credentials.password)+';document.querySelector("#password").dispatchEvent(new Event("input",{bubbles:true}));true');click("input[type=submit]");b("wait","[data-controller=studio][data-ready=true]");}
try {
 b("--args","--no-sandbox","open","http://127.0.0.1:3122");
 b("cookies","set","accio_appearance",other.value,"--url","http://127.0.0.1:3122","--httpOnly","--sameSite","Strict");b("reload");login();
 b("wait","[data-recovery=keep]:not([hidden])");
 const before=snapshot();assert.notEqual(before.accent,"#aa3399");
 b("screenshot",resolve(evidence,"legacy-browser-conflict.png"));
 click("[data-recovery=keep]");saved();b("reload");b("wait","[data-ready=true]");saved();assert.deepEqual(snapshot(),before);
 results.push({name:"Outro navegador mantém SQLite e preserva cookie diferente para recuperação",result:"PASS"});
 session="accio-p12c-bootstrap-draft";
 b("--args","--no-sandbox","open","http://127.0.0.1:3122");
 b("cookies","set","accio_appearance",credentials.legacy,"--url","http://127.0.0.1:3122","--httpOnly","--sameSite","Strict");
 b("network","route","**/appearance/bootstrap","--abort");b("reload");login();
 b("wait","[data-retry]:not([hidden])");click("[data-open=customize]");b("wait","#customize[open]");
 const draftTheme=evaluate("document.documentElement.dataset.theme === 'light' ? 'dark' : 'light'");
 b("select","#drawer-theme",draftTheme);
 b("network","unroute","**/appearance/bootstrap");click("[data-retry]");saved();b("press","Escape");b("reload");b("wait","[data-ready=true]");saved();
 assert.equal(evaluate("document.documentElement.dataset.theme"),draftTheme);
 results.push({name:"Falha de bootstrap preserva edição feita antes da retentativa e a salva depois",result:"PASS"});
 session="accio-p12c-empty-recovery";
 b("--args","--no-sandbox","open","http://127.0.0.1:3123");
 b("cookies","set","accio_appearance","synthetic-invalid-ciphertext","--url","http://127.0.0.1:3123","--httpOnly","--sameSite","Strict");b("reload");login();
 b("wait","[data-recovery=defaults]:not([hidden])");assert.match(evaluate("document.querySelector('[data-save-message]').textContent"),/inválido ou incompatível/);
 b("set","viewport","320","1000");
 b("screenshot",resolve(evidence,"invalid-cookie-mobile.png"));
 assert.ok(evaluate("document.querySelector('[data-save-status]').getBoundingClientRect().right <= innerWidth"));
 writeFileSync(resolve(evidence,"axe-recovery.json"),JSON.stringify(b("a11y","--json"),null,2));
 click("[data-recovery=defaults]");saved();b("reload");b("wait","[data-ready=true]");saved();
 assert.equal(evaluate("document.documentElement.dataset.theme"),"dark");
 results.push({name:"Cookie inválido exige escolha explícita e preserva cópia antes de inicializar",result:"PASS"});
 b("snapshot","-i");click("[data-open=customize]");b("wait","#customize[open]");
 evaluate('window.__realFetch=window.fetch;window.fetch=()=>Promise.resolve(new Response(JSON.stringify({error:"database_busy",message:"O armazenamento está ocupado. Sua edição foi mantida; tente novamente."}),{status:503,headers:{"Content-Type":"application/json"}}));true');
 b("select","#drawer-theme","light");b("wait","[data-retry]:not([hidden])");
 assert.equal(evaluate("document.documentElement.dataset.theme"),"light");
 b("screenshot",resolve(evidence,"busy-retry-mobile.png"));
 evaluate("window.fetch=window.__realFetch;true");click("[data-retry]");saved();b("press","Escape");b("reload");b("wait","[data-ready=true]");saved();assert.equal(evaluate("document.documentElement.dataset.theme"),"light");
 results.push({name:"Feedback HTTP 503 mantém edição e permite retentativa",result:"PASS"});
 writeFileSync(resolve(evidence,"browser-recovery-results.json"),JSON.stringify(results,null,2)+"\n");
 console.log(JSON.stringify(results,null,2));
} finally {
 for(const name of ["accio-p12c-browser-b","accio-p12c-bootstrap-draft","accio-p12c-empty-recovery"]){session=name;b("close");}
}
