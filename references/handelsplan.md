# Jarvis handelsplan – regler för testportföljen

Beslutad med Devin 2026-10-23. Gäller Jarvis testportfölj (virtuella 100 000 kr, inga riktiga order). Bygger på Devins regler och Tradingbibeln. Motorn `scripts\paper.ps1` stoppar själv det som bryter mot reglerna; det som står som förslag kan Devin ändra. Reglerna ändras bara när Devin säger till, och ändringen skrivs in här med datum.

## 1. Ingen trade utan plan

Jarvis går in själv (Devins val: "Själv, med plan"), men bara med en nedskriven handelsplan. Planen skrivs före köpordern som JSON och skickas med `paper.ps1 -Open <id> -Plan <fil.json>`. Saknas planen, eller är någon grind inte uppfylld, öppnas ingen trade. Devin får en notis när ordern läggs och planen syns på traden i Jarvis.

Planen innehåller:

| Fält | Innehåll |
|---|---|
| `horizon` | `swing` (dagar till 3 veckor) eller `day` (stängs samma handelsdag) |
| `side` | `long` (köp) eller `short` (blankning); för scannerlägen följer den kandidatens riktning |
| `product` | `{"type":"underliggande"}`, `{"type":"turbo","ko":<knockout>}` eller `{"type":"mini","financing":<F>,"stopLoss":<SL>}` |
| `thesis` | Varför traden ska fungera, 1–2 meningar |
| `htf` | Trend och regim på högre tidsram (dag/vecka; för daytrade dag/4h) |
| `level`, `confluence` | Nivån och minst två verktyg som bildar den (S/R, fib, glidande medel, volymprofil, pivå, VWAP) |
| `trigger` | Exakt BOS-villkor (tidsram och stängning) |
| `invalidation` | Var tesen är fel, i ord |
| `against` | Minst två konkreta motargument |
| `events` | Händelser fram till exit (rapport, Fed, KPI) |
| `correlation` | Vad i portföljen som rör sig likadant |
| `exit` | Plan för mål 1, break-even, mål 2 och tidsstopp |
| `gates` | De nio grindarna nedan, alla `true` |
| `entry`, `stop`, `t1`, `t2` | Krävs för daytrades och egna setups; för swing från scannern används scannerns plan om de saknas |

## 2. De nio grindarna (Tradingbibeln, ett nej = ingen trade)

1. `htf` – HTF-trend och regim noterad. 2. `events` – händelserna fram till exit (rapport, Fed, KPI) är kända och står i planen med vad de kan göra med traden (se 5). 3. `confluence` – nivån syns på HTF och har minst två verktyg. 4. `discount` – köp i discount (under mitten av rangen). 5. `bos` – sweep/absorption vid nivån och BOS; entry på rekylen. 6. `stop` – strukturellt stopp, storlek uträknad, risk högst 1 %. 7. `rr` – minst 1:2 till första målet. 8. `invalidation` – invalidering och två motargument nedskrivna. 9. `risk` – total öppen risk och korrelation kontrollerad.

## 3. Risk och storlek

- 1 % av portföljen per trade, 0,5 % i försiktig marknad, inga nya trades i risk-off.
- Högst 5 aktiva trades, högst 5 % total öppen risk, högst 2 per sektor. Korrelerade innehav räknas som ett.
- Högst 3 nya trades per dag (motverkar overtrading).
- Ingen ny trade samma dag efter en förlust. Paus ett dygn efter två förluster i rad. Ingen ny trade när veckans stängda trades summerar till −6R eller sämre.
- Antal = risk i kr / (entry − stopp). Positionen (eller produktens insats) högst 25 % av portföljen.
- **Lärfas (ändrat 2026-10-27**, Devin: "nej du kan fortsätta tradea, jag tycker fram tills du har gjort ett bra antal trades så tycker jag att du kan köra hur många du vill så länge de är bra och godkända"): tills 30 trades är avslutade gäller inte pausen efter förlust, pausen efter två förluster i rad, stoppet vid −6R på en vecka, taket på 5 aktiva och 3 nya swingtrades per dag eller taket på 3 blankningar. Varje trade ska fortfarande ha plan, klara de nio grindarna och följa risken: 1 % per trade (0,5 % i försiktig marknad) och högst 2 per sektor. Total öppen risk högst 10 % under lärfasen i stället för 5 % (ändrat samma dag, Devin: "Höj taket på total risk till 10 % under lärfasen"; `maxOpenRiskPctLearn`). Efter 30 avslutade gäller reglerna ovan och 5 % igen av sig själva (`learnTrades` i `paper.ps1`), och då går Jarvis igenom statistiken med Devin.

## 4. Setups per horisont

- **Swing:** bara A-betyg från scannern (B bara med `-AllowB` och skäl i planen), ingen rapport inom 14 dagar, minst 1:2, stopp högst 8 % bort. Köporder vid BOS som förfaller efter 7 dagar eller om kursen går under stoppet först. Mål 1: sälj en tredjedel och flytta stoppet till break-even; resten vid mål 2, på stoppet eller efter 21 dagar.
- **Daytrade:** egen setup från intradagsanalys (1h/15m) med entry, stopp och mål i planen. Minst 1:2, stopp högst 4 % bort, ingen rapport i dag eller i morgon. Ordern gäller bara samma handelsdag, och allt som är kvar säljs vid dagens stängning (respektive börs stängning, t.ex. USA 22.00, Tyskland och Sverige 17.30, krypto 23.00 svensk tid). Motorn följer upp daytrades på 15-minutersdata (sedan 26 okt), så utfallet är en uppskattning.
- **Daytrade, så hittas lägena (Devin 26 okt: "du gör knappt några daytrades, det vill jag att du gör", och scannern ska gälla alla aktier):** `scripts\daytrade.ps1` söker varje timme igenom alla aktier på de börser som är öppna (relativ volym, rörelse, gap, ATR, likviditet) och analyserar de ca 45 som rör sig mest plus olja, index, metaller och krypto på 15m: ORB (utbrott ur första halvtimmen), sweep av gårdagens high/low med återtagning och VWAP-trend med rekyl. Bara A-lägen nära entry blir planutkast, och planen granskas mot dagens nyheter innan ordern läggs (paper.ps1 vägrar ogranskade utkast).
- **Daytrade, gränser (Devin 26 okt: "du får göra hur många du vill, det finns ingen gräns, men om det inte är bra setup behöver du inte göra några alls, men jag vill ändå att du ska ta lite risk"):** inget tak för antalet daytrades, men bara lägen som verkligen håller (A, nära entry, granskade mot nyheterna). Risken är 1 % per daytrade även i försiktig marknad, eftersom de stängs samma dag (halv risk gäller bara blankningar i risk-on). Daytrades räknas för sig från swing; högst 2 samtidigt i samma sektor, och den totala risken på 5 % (10 % under lärfasen, se 3) gäller allt. Index och råvaror handlas via turbo med högst 9,5x hävstång och knockout långt bortom stoppet, i delar av underliggande (certifikat motsvarar t.ex. 0,01 DAX), så att 0,5–1 % risk ryms inom 25 % av portföljen.

## 5. Händelser (Devins val)

- **Ändrat 2026-10-27** (Devin: "jag tycker inte du ska vänta 24 timmar innan fed, jag tycker att du kan fortsätta köra dina trades och lära dig"): ingen paus före Feds räntebesked eller amerikansk KPI. Tidigare regel (23 okt): inga nya trades 24 timmar före. KPI togs bort samtidigt eftersom det var samma regel.
- Trades som läggs inom 24 timmar före ett besked märks (`nearEvent`) och räknas för sig i statistiken (`byEvent`: före besked mot övriga), så att Jarvis lär sig om lägen före besked fungerar. Planens `events` ska nämna beskedet. Alla andra regler gäller som vanligt (1 % risk, stopp, BOS).
- Tiderna står i `data\paper\makrokalender.json`, som scanningarna håller uppdaterad.
- Swing: ingen rapport inom 14 dagar. Daytrade: ingen rapport i dag eller i morgon.

## 6. Produkter (Devins val: även turbo och mini)

Simuleras med underliggande kurs, så att knockout-risken syns:

- **Turbo L:** knockout = finansieringsnivå. Nås knockout på ett gap förbi stoppet blir produkten värdelös (förlusten större än 1R).
- **Mini L:** finansieringsnivå F och stop loss-nivå SL. Bryts SL avvecklas produkten och restvärdet (kurs − F) betalas ut.
- Knockout/SL ska ligga under stoppet med minst halva stoppavståndet som marginal, och under S2 när nivåtrappan finns (lärdom från en tidigare affär).
- Hävstång vid entry (entry / (entry − F)): högst 5 gånger för swing och 10 gånger för daytrade (förslag). Bull/bear-certifikat (daglig omviktning) används inte.
- Kostnad utöver courtage: spread 0,4 % av produktens värde per affär och finansiering cirka 7 % per år på exponeringen.

## 7. Blankning (short) – Devin 2026-10-23: "det är lika viktigt som att kunna köpa"

Samma plan, grindar och risk som för köp, spegelvänt:

- **Bara i nedtrend:** pris under 200-dagars och 50-dagars under 200-dagars (eller ett misslyckat utbrott). Sälj i premium, på en lägre topp eller en rekyl upp mot motstånd (bibeln: "leta sälj/blankning på LH").
- **BOS nedåt:** blankningsordern ligger under senaste lägsta och löses ut först när kursen bryter dit. Stoppet ligger ovanför senaste toppen (minst 1 ATR). Mål vid stöd under (1-månaders, 3-månaders och 52-veckors lägsta).
- **Aldrig in i översålt:** ingen blankning när RSI(14) är under 30. Rapport inom 14 dagar stoppar som för köp, och på goda nyheter finns risk för short squeeze.
- **Marknadsläget:** risk-off stoppar nya köp men inte blankningar. I risk-on blankas med halv risk (förslag).
- **Högst 3 blankningar samtidigt** (förslag), inom samma tak på 5 aktiva och 5 % total risk (under lärfasen inget tak för antalet och 10 % total risk, se 3).
- **Produkter:** underliggande (blankning), Mini S (finansieringsnivå ovanför kursen, stop loss-nivån mellan kursen och finansieringsnivån) eller Turbo S (knockout ovanför). Knockout ska ligga ovanför stoppet med minst halva stoppavståndet som marginal. Bear-certifikat används inte.
- **Kostnader:** lånekostnad cirka 2 % per år för aktier och 10 % för krypto (finansiering på perps), plus vanliga courtage.
- I planen betyder grinden `discount` för en blankning att kursen ligger i premium (övre halvan av rangen).

## 8. Efter varje trade

- Ärlig lärdom med `paper.ps1 -Lesson` (vad som fungerade, vad som inte gjorde det, vad som ska ändras).
- Statistik per strategi, betyg, marknad, horisont och produkt. Inga slutsatser före 20–30 avslutade trades per grupp; först då ändras reglerna, och bara med Devin.

## 9. Dagsmål och lägen åt båda håll (YL 2026-10-28)

YL kopia av Jarvis sedan 2026-10-28: här ändras reglerna när YL säger till, med datum. YL 2026-10-28: "Jag vill göra 2 % i avkastning per dag. Du ska trada upp till 2 % sen är du klar. Du ska inte bara gå på något som ska upp, vi ska även jobba med att shorta och trada värdepapper, ädelmetaller och krypto."

- **Dagsmål +2 %:** målet är +2 % av portföljvärdet per handelsdag. Dagens resultat räknas på stängda trades sedan midnatt mot portföljvärdet vid dagens början (sista punkten i värdekurvan före midnatt, annars startvärdet). När det är +2 % eller mer läggs inga fler testtrades den dagen; motorn (`paper.ps1`, `dailyTargetPct`) stoppar nya order. Öppna positioner följer sin plan (stopp, mål, break-even, dagsslut).
- **Åt båda håll, i alla tre tillgångsslagen:** Jarvis letar aktivt lägen både för köp och blankning (avsnitt 7) i aktier och index, ädelmetaller (guld, silver, koppar) och krypto, och tar de lägen som klarar planen och de nio grindarna tills dagsmålet är nått.
- **Målet ändrar inte reglerna:** 1 % risk per trade, minst 1:2, BOS, de nio grindarna, sektortaken och lärfasen i avsnitt 3 gäller som förut. Ett svagt läge tas aldrig för att nå målet.
- **Att veta:** backtesten (strategier.md) visar ännu ingen fördel per trade, och +2 % per dag motsvarar cirka 2 R netto per dag med 1 % risk. De flesta dagar nås inte målet. Det är ett mål att mäta mot, inte en förväntan; statistiken visar hur ofta det nås.

**YL 2026-10-29:** "varför tradar du inget på någon av marknaderna som är öppna! Du måste också kunna shorta om du får signaler att det ska ner ... om det blir på en trade eller 100 spelar ingen roll."

- **B-lägen tas också:** daytrade-lägen med betyg A eller B räknas som redo (`daytrade-lib.ps1`), och swinglägen med B tas med `paper.ps1 -Open ... -AllowB` och skälet i planen. C och D tas inte.
- **Senare gräns:** inga nya daytrades från kl 21 (förut 19), en timme före USA:s stängning.
- **Blankning lika gärna som köp:** pekar signalerna nedåt (BOS nedåt, under EMA, svag sektor) blankar Jarvis enligt avsnitt 7, med samma risk och stopp.
- **Oförändrat:** 1 % risk per trade, minst 1:2, stopp högst 4 % bort för daytrade, total risk under lärfasen högst 10 %, högst 2 per sektor. Backtestet 26 okt gav −0,10R netto per daytrade, så fler trades betyder fler testade lägen, inte säkert mer vinst.

**YL 2026-10-29, senare:** "du ska lita på dina trades och signaler. 500 kr är inget! Du ska jobba med hela 100 000 kr varje dag ... analysera marknaden och se hur du kan fördela pengarna dag för dag", och "du ska även kunna shorta ... köpa certifikat med hävstång ... du har idag inte köpt en enda ädelmetall eller krypto".

- **Fördelning i stället för fast risk:** varje plan har `allocPct`, andelen av portföljvärdet i traden (upp till 100 %). Jarvis väljer andelen efter hur starkt läget är; en trade kan få hela kapitalet. Alla aktiva trades tillsammans högst hela värdet. Risken blir insatsen × stoppavståndet × hävstången. Total risk högst 10 % under lärfasen ligger kvar som spärr, så att en enda stopp med hävstång inte tar en stor del av portföljen.
- **Hävstång och blankning:** turbo och mini (långa och korta) för index, råvaror, metaller och krypto, högst 10x för daytrade och 5x för swing. Daytrade-utkasten föreslår turbo 9,5x även för krypto.
- **Metaller och krypto i varje körning:** guld, silver, koppar, btc, eth, sol och xrp bedöms varje gång, åt båda håll.

**YL 2026-10-29, kväll:** "2 % är målet men om du har en säker trade efter det så kan du köra igen samma dag. Kör bara säkra."

- **Efter dagsmålet:** nya trades samma dag bara med betyg A och högst 1 % risk (paper.ps1 krymper insatsen). Har dagen nått +2 % och sedan fallit under igen läggs inga fler den dagen. Det ersätter "inga nya när målet är nått" från 28 okt.
