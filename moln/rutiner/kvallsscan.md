# Kvällsscan (id: jarvis-kvallsscan) – vardagar 22.20, efter USA-stängningen

Följ `moln/rutiner/gemensamt.md` (start, databasen, testportföljen, avslut). Steg:

1. Start och export av databasen. Läs meta/brief, paper/state, paper/trades och inkorgen.
2. Kör i ordning: `scripts/scan.ps1` (kör i bakgrunden och vänta), `scripts/update.ps1`, `scripts/nivaer.ps1`, `scripts/paper.ps1 -Update`, `scripts/paper.ps1 -Notis`, `scripts/daytrade-facit.ps1 -Check` (skriver `data/daytrade-stats.json`), `scripts/facit.ps1 -Check`. Analyser som väntar på omdöme bedömer du med `facit.ps1 -Judge <id> -Verdict Rätt|Fel|Delvis -Lesson "..."`.
3. Lärdomar: `paper.ps1 -Lesson` för varje testtrade som stängts i dag.
4. Nyheter med WebSearch: dagens stängning i USA, rapporter i kväll och i morgon, Asien, de tio bevakningstillgångarna och A-lägen nära entry (long och short). Uppdatera meta/calendar, makrokalendern och meta/macro.
5. Nivåer och besked för de tio tillgångarna (assets/<id> update).
6. Morgondagens besked: meta/brief med MORGONDAGENS datum (date) och nuvarande klockslag (time); sidan vet att kvällens besked har morgondagens datum. Ta med hur dagen gick mot dagsmålet.
7. Swinglägen: gå igenom A- och B-lägen nära entry (B med `paper.ps1 -Open ... -AllowB` och skälet i planen), köp och blankning lika gärna, i aktier, metaller och krypto, mot handelsplanen (0,5 % risk i försiktig marknad, inga nya köp i risk-off, rapport inom 14 dagar stoppar). Planer bara för lägen som håller, `paper.ps1 -Open`, takes-filen, `paper.ps1 -Notis`.
8. Fredagar: `scripts/daytrade-facit.ps1 -Trials`, sedan `scripts/daytrade5.ps1 -Backtest` och `scripts/daytrade5.ps1 -InPlay` (tar lång tid: i bakgrunden, upp till tio minuter var). En setup godkänns bara om den är plus netto med billig mäklare i alla tre delarna och har minst 50 utlösta lägen per del, och inget tas i bruk utan att YL sagt ja. Resultatet i sammanfattningen.
9. Inkorgen: kvällen är rätt tillfälle för större önskemål; beskriv förslaget i svaret (koden ändras inte från molnet).
10. Avslut med `kontroll.ps1 -Run jarvis-kvallsscan` och sparad data.
