# Krypto helg (id: jarvis-krypto-helg-auto) – lördag och söndag 10 och 20

Följ `moln/rutiner/gemensamt.md` (start, databasen, testportföljen, avslut). Börserna är stängda; bara krypto (dygnet runt) och metallterminer (söndag kväll) handlas. Håll körningen kort.

1. Start och export av databasen.
2. Kör: `scripts/update.ps1`, `scripts/paper.ps1 -Update`, `scripts/paper.ps1 -Notis`, `scripts/daytrade.ps1 -Plans`.
3. Skriv till databasen: upd → assets (update), hist → history, prices → meta/prices, db-state → paper/state, db-trades → paper/trades, daytrade-latest → scan/day.
4. Krypto-nyheter med WebSearch för btc, eth, sol och xrp (ETF-flöden vecka för vecka, stora rörelser, regleringar). Har priset brutit "fel om" eller nått BOS: uppdatera bara status och statusText. Nya nivåer sätts i morgonscannen på måndag.
5. Daytrades (efter nått dagsmål bara säkra lägen, se gemensamt.md) i krypto eller metaller, köp eller blankning, när ett A- eller B-läge håller efter nyheterna (YL 29 okt), gärna med turbo och med allocPct per plan; helgens tunna likviditet är ett motargument.
6. Inkorgen.
7. Avslut med `kontroll.ps1 -Run jarvis-krypto-helg-auto` och sparad data.
