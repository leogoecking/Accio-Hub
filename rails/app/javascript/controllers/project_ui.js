export function studio(element) {
  const shell = element.closest('[data-controller~=studio]')
  return window.Stimulus.getControllerForElementAndIdentifier(shell, 'studio')
}

export async function request(url, body, method = 'POST') {
  const response = await fetch(url, { method, credentials: 'same-origin', headers: {
    Accept: 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content,
    ...(body instanceof FormData ? {} : { 'Content-Type': 'application/json' })
  }, body: body instanceof FormData ? body : JSON.stringify(body) })
  let data
  try { data = await response.json() } catch { throw new Error('Não foi possível confirmar a operação. Seus campos foram mantidos; tente novamente.') }
  if (!response.ok) { const error = new Error(data.message || 'Operação não confirmada.'); error.data = data; throw error }
  return data
}

export async function refresh(url = window.location.href, target = "project-surface", valid = () => true) {
  const response = await fetch(url, { headers: { Accept: 'text/html' }, credentials: 'same-origin' })
  if (!response.ok) throw new Error('Não foi possível atualizar a tela. Recarregue para conferir os dados salvos.')
  const page = new DOMParser().parseFromString(await response.text(), 'text/html')
  const content = page.getElementById(target)
  if (!content) throw new Error('A sessão expirou. Autentique-se novamente para conferir os dados.')
  if (!valid()) return false
  const stream = document.createElement('turbo-stream')
  stream.setAttribute('action', 'update'); stream.setAttribute('target', target)
  const template = document.createElement('template'); template.innerHTML = content.innerHTML
  stream.append(template)
  await new Promise(resolve => {
    const observer = new MutationObserver(() => { observer.disconnect(); requestAnimationFrame(resolve) })
    observer.observe(document.getElementById(target), { childList: true })
    window.Turbo.renderStreamMessage(stream.outerHTML)
  })
  return true
}

export function notice(element, message) {
  const target = element.querySelector('[data-project-notice]') || document.querySelector('#project-surface [data-project-notice]')
  if (target) target.textContent = message
}

export function restoreFocus(id) {
  const target = document.getElementById(id) || document.getElementById('project-new') || document.getElementById('space-title')
  target?.focus()
}
