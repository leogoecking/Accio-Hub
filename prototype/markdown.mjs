// Renderizador de subconjunto Markdown por lista de permissões. HTML bruto é texto.
export const escapeHTML=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function safeLink(value){try{if(/[\u0000-\u0020\u007f]/.test(value))return null;const u=new URL(value);return ['https:','http:'].includes(u.protocol)&&!u.username&&!u.password?u.href:null;}catch{return null;}}
function inline(text,links){
  // Escapar por token: nenhum texto do usuário é recolocado como HTML confiável.
  const pattern=/(`+)([^`\n]*?)\1|\[\[([^\]\n]+)\]\]|\[([^\]\n]+)\]\(([^\s)]*)\)|\*\*([^*\n]+)\*\*|\*([^*\n]+)\*/g;let out='',start=0;
  for(const m of text.matchAll(pattern)){out+=escapeHTML(text.slice(start,m.index));if(m[1])out+='<code>'+escapeHTML(m[2])+'</code>';else if(m[3]){const label=m[3].trim(),l=links.find(l=>l.label===label);out+=l?`<a class="knowledge-wikilink" href="#/knowledge/${encodeURIComponent(l.targetId)}">${escapeHTML(label)}</a>`:`<span class="knowledge-unresolved" title="Nota ausente ou título ambíguo">[[${escapeHTML(label)}]]</span>`;}else if(m[4]){const url=safeLink(m[5]);out+=url?`<a href="${escapeHTML(url)}" target="_blank" rel="noopener noreferrer">${escapeHTML(m[4])}</a>`:escapeHTML(m[0]);}else out+=(m[6]?'<strong>'+escapeHTML(m[6])+'</strong>':'<em>'+escapeHTML(m[7])+'</em>');start=m.index+m[0].length;}return out+escapeHTML(text.slice(start));
}
export function renderMarkdown(body,links=[],depth=0){
  const lines=body.replace(/\r\n?/g,'\n').split('\n');let out='',i=0;
  while(i<lines.length){const line=lines[i];if(!line.trim()){i++;continue;}
    const fence=line.match(/^\s*(`{3,}|~{3,})(.*)$/);if(fence){const content=[],mark=fence[1][0],length=fence[1].length;i++;while(i<lines.length&&!new RegExp('^\\s*'+mark+'{'+length+',}\\s*$').test(lines[i]))content.push(lines[i++]);if(i<lines.length)i++;out+=`<pre><code>${escapeHTML(content.join('\n'))}</code></pre>`;continue;}
    const heading=line.match(/^(#{1,6})\s+(.+)$/);if(heading){out+=`<h${heading[1].length}>${inline(heading[2],links)}</h${heading[1].length}>`;i++;continue;}
    if(depth<16&&/^>\s?/.test(line)){const quote=[];while(i<lines.length&&/^>\s?/.test(lines[i]))quote.push(lines[i++].replace(/^>\s?/,''));out+='<blockquote>'+renderMarkdown(quote.join('\n'),links,depth+1)+'</blockquote>';continue;}
    const list=line.match(/^\s*(?:([-+*])|\d+[.)])\s+(.+)$/);if(list){const ordered=!list[1],tag=ordered?'ol':'ul';out+='<'+tag+'>';while(i<lines.length){const item=lines[i].match(/^\s*(?:([-+*])|\d+[.)])\s+(.+)$/);if(!item||!item[1]!==ordered)break;out+='<li>'+inline(item[2],links)+'</li>';i++;}out+='</'+tag+'>';continue;}
    const paragraph=[line];i++;while(i<lines.length&&lines[i].trim()&&!/^(#{1,6}\s|>\s?|\s*(`{3,}|~{3,}|[-+*]\s|\d+[.)]\s))/.test(lines[i]))paragraph.push(lines[i++]);out+='<p>'+paragraph.map(l=>inline(l,links)).join('<br>')+'</p>';
  }return out||'<p class="muted">Esta página espera suas ideias.</p>';
}
