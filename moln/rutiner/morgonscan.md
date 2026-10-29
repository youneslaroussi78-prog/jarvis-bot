# Morgonscan (id: jarvis-morgonscan) – vardagar 07.45, före Stockholmsbörsen

Följ `moln/rutiner/gemensamt.md` (start, databasen, testportföljen, avslut). Steg:

1. Start och export av databasen. Läs meta/brief (kvällens besked), paper/state och inkorgen.
2. Kör i ordning: `scripts/scan.ps1` (hela marknaden plus djupanalys, kan ta flera minuter: kör i bakgrunden och vänta), `scripts/update.ps1`, `scripts/nivaer.ps1`, `scripts/paper.ps1 -Update`, `scripts/paper.ps1 -Notis`. Före USA-öppning (15.30, 14.30 de veckor tidsskillnaden är en timme mindre) är scannerns USA-priser gårdagens stängning – säg det i beskedet.
3. Nyheter med WebSearch: de tio bevakningstillgångarna, A-lägen nära köpnivån (scan-latest: listan soon och candidates med litet distPct, både long och short) och dagens makro (Fed, KPI, rapporter i dag och i morgon, olja, dollar, VIX, räntor). Uppdatera meta/calendar, `data/paper/makrokalender.json` och meta/macro.
4. Nivåer och besked för de tio tillgångarna (assets/<id> update). Lämna aldrig ett gammalt besked kvar när strukturen ändrats.
5. Dagens besked: meta/brief med dagens datum och tid, rubrik, sammanfattning, punkter och prioritering.
6. Testportföljen: gå igenom A- och B-lägen nära entry (B med `paper.ps1 -Open ... -AllowB` och skälet i planen), köp och blankning lika gärna, med allocPct per plan (se gemensamt.md, "Hela kapitalet"), i aktier, metaller och krypto, mot handelsplanen. Skriv planer bara för lägen som verkligen håller, kör `paper.ps1 -Open`, takes-filen, `paper.ps1 -Notis`.
7. Facit: `scripts/facit.ps1 -Check`, och logga varje bevakningstillgång som fått ett nytt besked med `facit.ps1 -Add <fil.json>` (fält: date, asset, ysym, shift, besked, price, zone [lo,hi], zoneText, inval, invalText, targets [t1,t2], targetText). Loggen ligger i `data/facitlogg.md`.
8. Inkorgen.
9. Avslut med `kontroll.ps1 -Run jarvis-morgonscan` och sparad data.
