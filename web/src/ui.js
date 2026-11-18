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
export const eventText = line => line.replace(/#\d+/g, '')
export function cardFace(card, action, value, options = {}) {
  const {strength = card.strength, hp = card.health, selected, status, suppressed} = options
  const labels = [card.bridge && !suppressed && status !== 'Bridge chain' && 'Bridge', status].filter(Boolean)
  const stats = card.type === 'Unit'
    ? `<span class="card-stats"><span aria-label="Strength ${strength}">${strength} STR</span>
       <b class="unit-hp${hp < card.health ? ' wounded' : ''}" aria-label="Health ${hp} of ${card.health}">${hp}/${card.health} HP</b></span>`
    : '<small class="type">Effect</small>'
  return `<button class="card-face f-${esc(card.faction)} ${selected?'selected':''}" data-action="${esc(action)}" data-value="${esc(value)}">
    <span class="card-image">${art(card)}</span><span class="card-caption"><strong>${esc(name(card))}</strong>${stats}
    ${labels.length ? '<small class="flag">'+esc(labels.join(' · '))+'</small>' : ''}</span></button>`
}
export function inspect(card, unit, metrics) {
  const state = unit && metrics?.units[unit.u]
  const tags = [state?.cross ? 'Bridge chain' : state?.chain && 'Chain '+state.chain, unit?.ch && 'Chain used',
    unit?.g && 'Guard '+unit.g, unit?.dis && 'Suppressed', unit?.nd && 'Barrier', unit?.recovered && 'Discard recovery used this round'].filter(Boolean)
  const strength = state?.strength ?? card.strength
  return `<div class="inspection f-${esc(card.faction)}"><div class="portrait">${art(card)}</div>
    <h2 id="dialog-title">${esc(name(card))}</h2>
    ${card.type==='Unit' ? `<dl class="numbers"><div><dt>Strength</dt><dd>${strength}${strength!==card.strength ? ' <small>(base '+card.strength+')</small>' : ''}</dd></div><div><dt>Health</dt><dd>${unit?.hp ?? card.health}/${card.health}</dd></div></dl>` : '<small>Effect</small>'}
    ${!unit && card.strength>=5 && !card.replaces ? '<p class="hint">Heavy · Field an ally with base Strength 1–3 to deploy at full Health. Otherwise this unit enters at 2 Strength and 2/'+card.health+' HP.</p>' : ''}
    <p class="rules">${esc(card.text)}</p>${tags.length ? '<p>'+esc(tags.join(' · '))+'</p>' : ''}</div>`
}
