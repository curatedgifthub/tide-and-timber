// Only an exact, ordered factory list qualifies for an automatic starter update.
export const starterVersion=5
export function upgradeStarters(saved,faction) {
  if ((saved.starterVersion || 0)<3) {
    for (const s of saved.seats) {
      const f=faction(s.faction)
      // Upgrade an untouched starter. Keep deliberately tagged lists and later 20-card choices.
      const old=f.id==='Super' ? f.previousStarter : [f.id==='Water'?43:48,1,2,3,4,21,28,31,32,40,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20,23,25,29,33,39].map(n=>f.id+':'+n)
      const expected=!saved.starterVersion && s.deck.length===20 ? old.slice(0,20) : old
      if (s.deck.length===expected.length && expected.every((id,i)=>s.deck[i]===id)) s.deck=[...f.starter]
    }
    saved.starterVersion=3
  }
  if (saved.starterVersion===3) {
    for (const s of saved.seats) {
      const f=faction(s.faction)
      if (s.deck.length===f.previousStarter.length && f.previousStarter.every((id,i)=>s.deck[i]===id)) s.deck=[...f.starter]
    }
    saved.starterVersion=4
  }
  if (saved.starterVersion===4) {
    const previousComic=[66,61,15,27,32,57,71,72,73,74,75,78,2,11,20,21,62,8,12,14,24,30,47,49,51,61,57,15,27,30].map(n=>'Super:'+n)
    for (const s of saved.seats) {
      if (s.faction==='Super' && s.deck.length===previousComic.length && previousComic.every((id,i)=>s.deck[i]===id)) {
        s.deck=[...faction('Super').starter]
      }
    }
    saved.starterVersion=starterVersion
  }
}
