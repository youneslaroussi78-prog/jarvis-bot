# Facitlogg

Varje analys med besked loggas här och följs upp efter en och fyra veckor (Tradingbibeln, avsnittet Facitlogg). Utfallen fylls i av `scripts\facit.ps1 -Check` mot Yahoo Finance dagsdata; omdöme och lärdom sätter Claude med `-Judge`. Var 20:e bedömda analys: gå igenom vilka verktyg och nivåer som träffade och vilka som missade, och skriv ändringen i strategier.md eller kalibrering.md.

Bedömda: 0 av 10.

| Datum | Tillgång | Besked | Köpzon | Invalidering | Mål | Utfall 1 v | Utfall 4 v | Rätt/fel | Lärdom |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-29 | mu | Vänta: vid 50-dagars, BOS 1 089 | S1 964.28–981.51 | Under 954.67 | R1 1017.38, R2 1042.4 |  |  |  |  |
| 2026-10-29 | koppar | Bevaka: upptrend, köp vid BOS över 6,726 eller rekyl till S2 | S1 6.59–6.633 | Under 6.573 | R1 6.686, R2 6.738 |  |  |  |  |
| 2026-10-29 | btc | Vänta: vid stöd, köp först vid BOS över 81 712 | S1 78959–79830 | Under 78584 | R1 81359, R2 82919 |  |  |  |  |
| 2026-10-29 | ndx | Vänta: terminerna −1 %, BOS över 29 928 | S1 29499–29753 | Under 29400 | R1 30086, R2 30365 |  |  |  |  |
| 2026-10-29 | silver | Köp inte: fallande kniv (steg 4) | S1 52.41–52.41 | Under 52.18 | R1 54, R2 54.66 |  |  |  |  |
| 2026-10-29 | guld | Vänta: nedtrend, köp först vid BOS över 4 088 | S1 4015–4029 | Under 4002 | R1 4077, R2 4120 |  |  |  |  |
| 2026-10-29 | xrp | Bevaka: positiv divergens vid 200-dagars, BOS över 1,3441 | S1 1.2695–1.2903 | Under 1.2602 | R1 1.3299, R2 1.3567 |  |  |  |  |
| 2026-10-29 | sol | Vänta: vid stöd, BOS över 103,74 | S1 98.27–99.84 | Under 97.56 | R1 101.55, R2 104.81 |  |  |  |  |
| 2026-10-29 | googl | Köp inte: rapportfall −10 % | Efterhandsnivå 285–290 | Under 285 | Gapfyllnad 311,42 och 323,16 |  |  |  |  |
| 2026-10-29 | eth | Vänta: svag, BOS över 2 387 | S1 2230–2280 | Under 2213 | R1 2358, R2 2424 |  |  |  |  |

<!-- facit-data -->
```json
[
    {
        "id":  "2026-10-29-mu",
        "date":  "2026-10-29",
        "asset":  "mu",
        "ysym":  "MU",
        "shift":  0,
        "price":  983.23,
        "besked":  "Vänta: vid 50-dagars, BOS 1 089",
        "zone":  [
                     964.28,
                     981.51
                 ],
        "zoneText":  "S1 964.28–981.51",
        "inval":  954.67,
        "invalText":  "Under 954.67",
        "targets":  [
                        1017.38,
                        1042.4
                    ],
        "targetText":  "R1 1017.38, R2 1042.4",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-koppar",
        "date":  "2026-10-29",
        "asset":  "koppar",
        "ysym":  "HG=F",
        "shift":  0,
        "price":  6.638,
        "besked":  "Bevaka: upptrend, köp vid BOS över 6,726 eller rekyl till S2",
        "zone":  [
                     6.59,
                     6.633
                 ],
        "zoneText":  "S1 6.59–6.633",
        "inval":  6.573,
        "invalText":  "Under 6.573",
        "targets":  [
                        6.686,
                        6.738
                    ],
        "targetText":  "R1 6.686, R2 6.738",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-btc",
        "date":  "2026-10-29",
        "asset":  "btc",
        "ysym":  "BTC-USD",
        "shift":  -12.1,
        "price":  79843,
        "besked":  "Vänta: vid stöd, köp först vid BOS över 81 712",
        "zone":  [
                     78959,
                     79830
                 ],
        "zoneText":  "S1 78959–79830",
        "inval":  78584,
        "invalText":  "Under 78584",
        "targets":  [
                        81359,
                        82919
                    ],
        "targetText":  "R1 81359, R2 82919",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-ndx",
        "date":  "2026-10-29",
        "asset":  "ndx",
        "ysym":  "^NDX",
        "shift":  0,
        "price":  29813,
        "besked":  "Vänta: terminerna −1 %, BOS över 29 928",
        "zone":  [
                     29499,
                     29753
                 ],
        "zoneText":  "S1 29499–29753",
        "inval":  29400,
        "invalText":  "Under 29400",
        "targets":  [
                        30086,
                        30365
                    ],
        "targetText":  "R1 30086, R2 30365",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-silver",
        "date":  "2026-10-29",
        "asset":  "silver",
        "ysym":  "SI=F",
        "shift":  -0.028,
        "price":  52.88,
        "besked":  "Köp inte: fallande kniv (steg 4)",
        "zone":  [
                     52.41,
                     52.41
                 ],
        "zoneText":  "S1 52.41–52.41",
        "inval":  52.18,
        "invalText":  "Under 52.18",
        "targets":  [
                        54,
                        54.66
                    ],
        "targetText":  "R1 54, R2 54.66",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-guld",
        "date":  "2026-10-29",
        "asset":  "guld",
        "ysym":  "GC=F",
        "shift":  9.2,
        "price":  4036,
        "besked":  "Vänta: nedtrend, köp först vid BOS över 4 088",
        "zone":  [
                     4015,
                     4029
                 ],
        "zoneText":  "S1 4015–4029",
        "inval":  4002,
        "invalText":  "Under 4002",
        "targets":  [
                        4077,
                        4120
                    ],
        "targetText":  "R1 4077, R2 4120",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-xrp",
        "date":  "2026-10-29",
        "asset":  "xrp",
        "ysym":  "XRP-USD",
        "shift":  -0.001,
        "price":  1.2931,
        "besked":  "Bevaka: positiv divergens vid 200-dagars, BOS över 1,3441",
        "zone":  [
                     1.2695,
                     1.2903
                 ],
        "zoneText":  "S1 1.2695–1.2903",
        "inval":  1.2602,
        "invalText":  "Under 1.2602",
        "targets":  [
                        1.3299,
                        1.3567
                    ],
        "targetText":  "R1 1.3299, R2 1.3567",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-sol",
        "date":  "2026-10-29",
        "asset":  "sol",
        "ysym":  "SOL-USD",
        "shift":  0,
        "price":  99.87,
        "besked":  "Vänta: vid stöd, BOS över 103,74",
        "zone":  [
                     98.27,
                     99.84
                 ],
        "zoneText":  "S1 98.27–99.84",
        "inval":  97.56,
        "invalText":  "Under 97.56",
        "targets":  [
                        101.55,
                        104.81
                    ],
        "targetText":  "R1 101.55, R2 104.81",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-googl",
        "date":  "2026-10-29",
        "asset":  "googl",
        "ysym":  "GOOGL",
        "shift":  0,
        "price":  288,
        "besked":  "Köp inte: rapportfall −10 %",
        "zone":  [
                     285,
                     290
                 ],
        "zoneText":  "Efterhandsnivå 285–290",
        "inval":  285,
        "invalText":  "Under 285",
        "targets":  [
                        311.42,
                        323.16
                    ],
        "targetText":  "Gapfyllnad 311,42 och 323,16",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    },
    {
        "id":  "2026-10-29-eth",
        "date":  "2026-10-29",
        "asset":  "eth",
        "ysym":  "ETH-USD",
        "shift":  0.4,
        "price":  2309,
        "besked":  "Vänta: svag, BOS över 2 387",
        "zone":  [
                     2230,
                     2280
                 ],
        "zoneText":  "S1 2230–2280",
        "inval":  2213,
        "invalText":  "Under 2213",
        "targets":  [
                        2358,
                        2424
                    ],
        "targetText":  "R1 2358, R2 2424",
        "o1":  null,
        "o4":  null,
        "verdict":  null,
        "lesson":  null
    }
]
```
