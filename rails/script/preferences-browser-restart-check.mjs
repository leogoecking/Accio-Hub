import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import assert from "node:assert/strict";
const root=resolve(import.meta.dirname,"../..");
const workspace=readFileSync(resolve(root,"rails/tmp/p12c-workspace"),"utf8").trim();
const credentials=JSON.parse(readFileSync(resolve(workspace,"credentials.json"),"utf8"));
const session="accio-p12c-restart";
const args=["--session",session,"--json"];
const env={...process.env,XDG_RUNTIME_DIR:"/tmp"};
const b=(...cmd)=>{const r=JSON.parse(execFileSync("agent-browser",[...args,...cmd],{env,encoding:"utf8",timeout:45000}));assert.equal(r.success,true);return r.data;};
const evaluate=source=>{const r=JSON.parse(execFileSync("agent-browser",[...args,"eval","--stdin"],{env,input:source,encoding:"utf8",timeout:45000}));assert.equal(r.success,true);return r.data.result;};
const click=selector=>{b("snapshot","-i");b("click",selector);};
const ready=()=>{b("wait","[data-ready=true]");b("wait","--fn","document.querySelector('[data-save-status]').hidden");};
const state=()=>evaluate("({appearance:JSON.parse(document.querySelector('[data-controller=studio]').dataset.studioAppearanceValue),version:Number(document.querySelector('[data-controller=studio]').dataset.studioVersionValue)})");
if(process.argv[2]==="capture") {
 b("--args","--no-sandbox","open","http://127.0.0.1:3122");b("snapshot","-i");b("fill","#email_address",credentials.email);
 evaluate('document.querySelector("#password").value='+JSON.stringify(credentials.password)+';document.querySelector("#password").dispatchEvent(new Event("input",{bubbles:true}));true');click("input[type=submit]");ready();
 const first=b("tab","list").tabs.find(t=>t.active).tabId;
 b("tab","new","http://127.0.0.1:3122");ready();const second=b("tab","list").tabs.find(t=>t.active).tabId;
 b("tab",first);click("[data-open=customize]");b("wait","#customize[open]");b("select","#drawer-theme",evaluate("document.documentElement.dataset.theme==='dark'?'light':'dark'"));b("wait","--fn","document.querySelector('[data-save-status]').hidden");b("press","Escape");
 b("tab",second);click("[data-open=customize]");b("wait","#customize[open]");b("select","#drawer-theme",evaluate("document.documentElement.dataset.theme==='dark'?'light':'dark'"));b("wait","[data-recovery=apply]:not([hidden])");click("[data-recovery=apply]");b("wait","--fn","document.querySelector('[data-save-status]').hidden");
 assert.equal(evaluate("document.querySelector('#customize').contains(document.activeElement)"),true);b("press","Escape");assert.equal(evaluate("document.activeElement.dataset.open"),"customize");b("tab","close",first);
 b("reload");ready();writeFileSync(resolve(workspace,"before-restart.json"),JSON.stringify(state()));
 b("screenshot",resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root,"docs/assets/p1.2c"),"before-restart.png"));
 console.log("PASS recuperação mantém foco no diálogo e Escape retorna ao acionador; estado pré-reinício capturado");
} else {
 b("reload");ready();assert.deepEqual(state(),JSON.parse(readFileSync(resolve(workspace,"before-restart.json"),"utf8")));
 b("screenshot",resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root,"docs/assets/p1.2c"),"after-restart.png"));
 writeFileSync(resolve(process.env.ACCIO_QA_EVIDENCE || resolve(root,"docs/assets/p1.2c"),"browser-restart-results.json"),JSON.stringify({real_rails_server_restart:true,appearance_and_version_preserved:true,authenticated_session_preserved:true,recovery_focus_and_escape:true},null,2)+"\n");
 b("close");console.log("PASS servidor Rails reiniciado conserva aparência, versão e sessão autenticada");
}
