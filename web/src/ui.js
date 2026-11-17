export function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
}
export const name = card => card.display_name || card.name
export const rowName = n => n === 1 ? 'Front' : 'Back'
export function btn(label, action, value = '', style = '', disabled = false) {
  return `<button type="button" class="${style}" data-action="${esc(action)}" data-value="${esc(value)}" ${disabled ? 'disabled' : ''}>${esc(label)}</button>`
}
export function art(card) {
  return `<img loading="lazy" decoding="async" src="${esc(card.art)}" alt="">`
}
export function cardFace(card, action, value, stats = '', selected = false, flags = '') {
  return `<button class="card-face f-${esc(card.faction)} ${selected?'selected':''}" data-action="${esc(action)}" data-value="${esc(value)}">
    <span class="card-image">${art(card)}<span class="rank">${esc(card.strength ?? '✦')}</span>${flags ? '<small class="flag">'+esc(flags)+'</small>' : ''}</span>
    <strong>${esc(name(card))}</strong><small>${esc(stats || (card.type === 'Unit' ? card.health+' HP · Unit' : 'Effect'))}</small></button>`
}
export function inspect(card, unit, metrics) {
  const state = unit && metrics?.units[unit.u]
  const tags = [state?.chain && 'Chain '+state.chain, state?.cross && 'Bridge chain', unit?.ch && 'Chain used',
    unit?.g && 'Guard '+unit.g, unit?.dis && 'Suppressed', unit?.nd && 'Barrier'].filter(Boolean)
  return `<div class="inspection f-${esc(card.faction)}"><div class="portrait">${art(card)}</div>
    <p class="eyebrow">${esc(card.id)} · ${esc(card.rarity)} · ${esc(card.type)}</p>
    ${card.type==='Unit' ? `<dl class="numbers"><div><dt>Rank</dt><dd>${card.strength}</dd></div><div><dt>Strength</dt><dd>${state?.strength ?? card.strength}</dd></div><div><dt>Health</dt><dd>${unit?.hp ?? card.health}/${card.health}</dd></div></dl>` : ''}
    <p class="rules">${esc(card.text)}</p>${tags.length ? '<p>'+esc(tags.join(' · '))+'</p>' : ''}</div>`
}
