# Jarvis – tradingassistent med testportfölj

Jarvis är en tradingassistent som Devin bygger tillsammans med Claude (Anthropic). Den scannar marknaden, räknar fram nivåer och lägen och testhandlar de bästa lägena i en **testportfölj med låtsaspengar** (100 000 kr). Syftet är att mäta hur ofta strategierna faktiskt fungerar innan någon lägger riktiga pengar.

> **Viktigt:** Det här är pappershandel. Inga riktiga order läggs, och inget här är finansiell rådgivning.
> Resultat per 27 oktober 2026: testportföljen ligger på −0,3 % med 2 avslutade affärer, båda med förlust. Backtestet av de mekaniska daytradelägena gav cirka −0,1 R per affär efter avgifter. Det är ett pågående test, inte ett bevisat sätt att tjäna pengar.

## Så fungerar det

```
TradingView-screener ─┐
Yahoo Finance ────────┼─> PowerShell-skripten ─> lägen, nivåer, planutkast ─> Claude granskar mot nyheter ─> testportföljen
Webbsök (nyheter) ────┘        (scripts/)                                       och handelsplanen            (paper.ps1)
                                                                                                                  │
                                                       Jarvis-sidan (app/jarvis.html) <── databas <──────────────┘
```

1. **Scanning** (`scripts/scan.ps1`): cirka 4 200 aktier i 16 marknader (USA, Sverige, Norden, Europa, Kanada) plus de 300 största kryptona. Åtta strategier för köp och sex för blankning (rekyl, utbrott, trend, översåld studs med flera), relativ styrka, marknadsläge (risk-on, försiktig, risk-off), sektorrotation och rapportkalender. Varje läge får entry vid BOS (break of structure), stopp, mål, R/R och betyg A–D.
2. **Djupanalys** (`scripts/djupanalys.ps1`, `scripts/nivaer.ps1`): FVG, order block, likviditet och sweep, Fibonacci, pivåer, volymprofil, AVWAP, TTM Squeeze, Weinstein-stadier och divergens på kurshistoriken. Nivåer där flera verktyg möts väger tyngst.
3. **Granskning:** Claude läser lägena, webbsöker nyheter och rapportdatum och skriver en handelsplan för de lägen som håller. Det körs schemalagt i Claude-appen: morgon (före Stockholmsbörsen), kväll (efter USA-stängningen) och varje timme under börsdagen.
4. **Testportföljen** (`scripts/paper.ps1`): lägger köp- eller blankningsorder vid BOS, säljer en tredjedel vid mål 1 och flyttar stoppet till break-even, säljer resten vid mål 2, på stoppet eller efter 21 dagar. Simulerar courtage, spread, finansiering och knockout för turbo och mini. Ingen affär läggs utan nedskriven plan och nio uppfyllda grindar (`references/handelsplan.md`).
5. **Daytrade** (`scripts/daytrade.ps1`, `daytrade-lib.ps1`): söker varje timme igenom aktierna på de börser som är öppna plus olja, index, metaller och krypto på 15-minutersdata (ORB, sweep av gårdagens high/low, VWAP-trend). `daytrade-facit.ps1` och `daytrade5.ps1` backtestar lägena.
6. **Uppföljning:** `scripts/facit.ps1` följer upp varje analys efter 1 och 4 veckor, och statistiken visas per strategi, betyg, marknad och typ. `scripts/kontroll.ps1` är en hälsokontroll av hela kedjan.
7. **Sidan** (`app/jarvis.html`): en Claude-artifact (webbsida på claude.ai) som läser en databas och visar läget, testportföljen, bevakningen, scannern och statistiken.

## Datakällor

| Vad | Källa | Kostnad |
|---|---|---|
| Kurser och historik (dag, timme, 15 och 5 minuter) | Yahoo Finance (öppet kursdiagram-API) | Gratis |
| Scanning av marknaden med indikatorer | TradingViews screener (scanner.tradingview.com) | Gratis |
| Livepriser i sidan | Twelve Data och Crypto.com via claude.ai-kopplingar (bara symbolnamn skickas) | Gratis nivå |
| Nyheter, rapportdatum, Fed och KPI | Webbsökning av Claude vid varje scanning | – |
| Analys och beslut | Claude, efter reglerna i `references/` | – |

Det finns inga API-nycklar i koden. Yahoos och TradingViews öppna gränssnitt är inofficiella och kan ändras utan förvarning. De fungerar för eget bruk, men den som vill bygga en tjänst bör använda en betald datakälla med licens.

## Köra skripten

Kräver Windows PowerShell 5.1 och internet. Skripten skriver sina resultat i mappen `data/` (skapas vid första körningen).

```powershell
powershell -ExecutionPolicy Bypass -File scripts\scan.ps1        # scanna marknaden -> data\scan-latest.json
powershell -ExecutionPolicy Bypass -File scripts\update.ps1      # priser och historik för bevakningslistan
powershell -ExecutionPolicy Bypass -File scripts\daytrade.ps1    # daytradelägen just nu
powershell -ExecutionPolicy Bypass -File scripts\paper.ps1 -Update   # följ upp testportföljen
powershell -ExecutionPolicy Bypass -File scripts\test-paper.ps1  # tester för testportföljens motor
```

Själva granskningen (nyheter, handelsplaner, beslut om nya testaffärer) görs av Claude, så helheten kräver Claude-appen med schemalagda körningar. Bevakningslistan i `update.ps1` och `nivaer.ps1` är ett exempel och kan bytas.

## Mappar

- `scripts/` – scanning, djupanalys, nivåer, testportfölj, daytrade, backtest, uppföljning och hälsokontroll
- `references/` – handelsplanen (reglerna för testportföljen), strategibiblioteket, kunskapsbanken och kalibreringsloggen
- `app/` – Jarvis-sidan (koden, utan data)

Inte med i den här kopian: databasen, journalen, positioner, scanningsarkivet, testportföljens logg, personliga anteckningar och Tradingbibeln (Devins eget dokument).

## Licens

Ingen licens är vald. Koden får läsas, men inte kopieras eller användas vidare utan lov från ägaren.

## Younes kopia (sedan 2026-10-28)

Den här forken är Younes egen Jarvis, byggd av Claude i Claude-appen på Younes Windows-dator.

- Sidan: https://claude.ai/artifact/PVnPWS7n5PEnq4S8mExFHU (privat artifact med egen databas), publicerad från `app/jarvis.html`.
- Testportföljen startade tom 2026-10-28 med 100 000 låtsaskronor.
- Schemalagda körningar i Claude-appen (Schemalagt): `jarvis-morgonscan` 07.45 vardagar, `jarvis-testtrade-vakt` varje hel timme 09–21 vardagar, `jarvis-kvallsscan` 22.20 vardagar, `jarvis-krypto-helg-auto` 10 och 20 lör–sön och `jarvis-uppdatera-nu` (manuell). De går bara när appen är öppen.
- Egna regler utöver Devins: `references/handelsplan.md` avsnitt 9 (dagsmål +2 %, lägen åt båda håll i aktier, ädelmetaller och krypto).
- Mappen `data/` (ledger, scanningar, databasexport) är lokal och ligger aldrig i git.
