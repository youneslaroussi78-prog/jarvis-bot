# Jarvis i molnet

Så körs Jarvis utan att Younes dator är på: som schemalagda molnkörningar (routines) i Claude Code på claude.ai/code. Varje körning startar en ny Linux-maskin hos Anthropic, checkar ut två repon och följer instruktionerna i `moln/rutiner/`.

| Del | Var |
|---|---|
| Koden (skript, regler, sidan) | `youneslaroussi78-prog/jarvis-bot`, gren `ylkopia` |
| Datan (testportföljen, scanningar, facit) | `youneslaroussi78-prog/jarvis-data` (privat), länkas in som `data/` |
| Sidan och dess databas | https://claude.ai/artifact/PVnPWS7n5PEnq4S8mExFHU |
| Instruktioner per körning | `moln/rutiner/*.md` (gemensamt.md + en fil per körning) |

## Det här gör Younes en gång

1. **Ge Claudes GitHub-app åtkomst till jarvis-data.** GitHub → Settings → Applications → Installed GitHub Apps → Claude → Configure → Repository access → lägg till `jarvis-data` (och `jarvis-bot` om den inte redan är med) → Save.
2. **Skapa miljön "Jarvis"** på claude.ai/code: klicka på molnikonen med miljöns namn i raden ovanför meddelanderutan → lägg till miljö.
   - **Namn:** Jarvis
   - **Nätverk:** egen lista (Custom), behåll standardlistan och lägg till:
     ```
     query1.finance.yahoo.com
     query2.finance.yahoo.com
     scanner.tradingview.com
     ```
   - **Miljövariabler:**
     ```
     TZ=Europe/Stockholm
     ```
   - **Startskript (setup script):**
     ```bash
     bash /home/user/jarvis-bot/moln/setup.sh || (curl -sSL https://raw.githubusercontent.com/youneslaroussi78-prog/jarvis-bot/ylkopia/moln/setup.sh | bash)
     ```

## Schemat

Molnkörningarnas tider anges i UTC. Svensk vintertid är UTC+1 (sommartid UTC+2), så tiderna nedan gäller vintertid; i slutet av mars flyttas de en timme (en rad i varje körning).

| Körning | Svensk tid | Cron (UTC) | Per dag |
|---|---|---|---|
| jarvis-morgonscan | 07.45 vardagar | `45 6 * * 1-5` | 1 |
| jarvis-testtrade-vakt | varje hel timme 10–21 vardagar | `0 9-20 * * 1-5` | 12 |
| jarvis-kvallsscan | 22.20 vardagar | `20 21 * * 1-5` | 1 |
| jarvis-krypto-helg-auto | 10 och 20 lör–sön | `0 9,19 * * 0,6` | 2 |

Max-abonnemanget tillåter 15 molnkörningar per dag. Vardagar blir det 14, så en extra körning för hand ryms. Timvakten börjar 10 i stället för 09 av det skälet. Körningarna räknas också mot abonnemangets vanliga användning.

## Läget (29 okt 2026)

Molnet är påslaget sedan 29 okt 11.00. Miljön heter Jarvis (`env_01DWhEkhTkmiNXmEbzWb5AgY`) och har nätverkslistan, `TZ=Europe/Stockholm` och ett startskript som installerar PowerShell 7. Provkörningen i miljön gav 200 från Yahoo och TradingView, nivaer.ps1, update.ps1 och paper.ps1 fungerade, och testerna gav 36 av 36. Datorns fem uppgifter under Schemalagt är pausade.

| Molnkörning | Id | Modell |
|---|---|---|
| Jarvis morgonscan | `trig_01K8m3iDtamLN21cHfuMfnf6` | Opus 5.5 |
| Jarvis testtrade-vakt | `trig_015wTTyi5MVzSUutrVZVhVGo` | Sonnet 5.5 |
| Jarvis kvällsscan | `trig_01WHw6sGi8oxqXiCBBej5dui` | Opus 5.5 |
| Jarvis krypto helg | `trig_01V3cHXzALdUJKH4EJUbes5g` | Sonnet 5.5 |

Körningarna har bara kopplingarna Twelve Data och Crypto.com. En ny molnkörning får automatiskt alla kopplingar i kontot (Gmail, Fortnox med flera), så begränsa dem direkt efter att den skapats. Claudes GitHub-app har bara åtkomst till jarvis-bot och jarvis-data. Se körningarna på claude.ai/code/routines.

## Byte från datorn till molnet

1. Spara datan från datorn: `cd data && git add -A && git commit -m "Sista körningen på datorn" && git push`.
2. Pausa uppgifterna under Schemalagt i Claude-appen (jarvis-morgonscan, jarvis-testtrade-vakt, jarvis-kvallsscan, jarvis-krypto-helg-auto).
3. Ändra testtrade-vaktens rad i `scripts/kontroll.ps1` till `cron = '0 10-21 * * 1-5'`, så att hälsokontrollen väntar på samma tider som molnet.
4. Slå på molnkörningarna på claude.ai/code/routines.

Datorn och molnet får aldrig köra samtidigt, eftersom båda skriver till testportföljen.

## Ändringar för Linux (29 okt)

Skripten fungerar i både Windows PowerShell 5.1 och PowerShell 7 på Linux: sökvägar med snedstreck, datum från JSON tolkas likadant i båda versionerna, och testerna startar samma PowerShell som kör dem. Facitloggen ligger i `data/facitlogg.md`. `scripts/test-paper.ps1` gav 36 av 36 godkända i båda versionerna.
