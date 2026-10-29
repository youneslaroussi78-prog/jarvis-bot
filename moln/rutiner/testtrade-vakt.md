# Testtrade-vakten (id: jarvis-testtrade-vakt) – varje hel timme 10–21 vardagar

Följ `moln/rutiner/gemensamt.md` (start, databasen, testportföljen, avslut). Körningen ska vara kort (under tio minuter): ingen hel marknadsscanning, inga nya nivåer.

1. Start och export av databasen.
2. Kör: `scripts/update.ps1`, `scripts/paper.ps1 -Update`, `scripts/paper.ps1 -Notis`, `scripts/daytrade.ps1 -Plans` (daytradelägen på de börser som är öppna, både köp och blankning).
3. Skriv till databasen: `data/watch/upd-<id>.json` → assets/<id> (update) · `data/watch/hist-<id>.json` → history/<id> · `data/watch/prices.json` → meta/prices · `data/paper/db-state.json` → paper/state · `data/paper/db-trades.json` → paper/trades · `data/daytrade-latest.json` → scan/day.
4. Daytrades (bara om dagsmålet inte är nått): finns redo A-lägen i planutkasten från den här körningen: sök nyheter för just de symbolerna med WebSearch, kontrollera makrokalendern och meta/calendar (EIA onsdagar 16.30, Fed, KPI, rapport i dag eller i morgon stoppar). Skriv om utkasten bara för lägen som verkligen håller (ta bort UTKAST, fyll thesis, events och against, gates true bara när uppfyllda). Kör `paper.ps1 -Open <id> -Plan <fil>`, läs JA/NEJ, kör `paper.ps1 -Notis`. Regler: bara A, nära entry, minst 1:2, stopp högst 4 % bort, 1 % risk, högst 2 samtidigt per sektor, total öppen risk högst 10 % under lärfasen, blankning aldrig in i översålt (RSI under 30), inga nya daytrades efter kl 19.
5. Bevakningslistan: har priset brutit "fel om" eller nått BOS för någon tillgång: uppdatera bara status och statusText (update). Nya nivåer sätts bara i morgon- och kvällsscannen.
6. Inkorgen (korta svar; större önskemål skjuts till kvällsscannen).
7. Avslut med `kontroll.ps1 -Run jarvis-testtrade-vakt` och sparad data.
