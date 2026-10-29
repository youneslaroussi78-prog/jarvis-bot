# Tester för testportföljens motor (paper.ps1) med påhittade timcandles. Rör aldrig den riktiga testportföljen.
# Kör före varje ändring i paper.ps1:  powershell -ExecutionPolicy Bypass -File test-paper.ps1
# Skriver "OK"/"FEL" per test och "Tester: x av y godkända". Avslutar med kod 1 om något test fallerar.
$ErrorActionPreference = 'Stop'
$paper = Join-Path $PSScriptRoot 'paper.ps1'
$PSEXE = (Get-Process -Id $PID).Path; $root = Join-Path ([IO.Path]::GetTempPath()) "jarvis-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$enc = [Text.UTF8Encoding]::new($false)
$T0 = 1792800000   # en hel timme i oktober 2026
$script:pass = 0; $script:fail = 0
function W($f, $o) { [IO.File]::WriteAllText($f, ($o | ConvertTo-Json -Depth 12 -Compress), $enc) }
function Trade($o) {
  $t = [ordered]@{ id = 'pt-test'; side = 'long'; createdT = $T0; symbol = 'TST'; name = 'Test'; ysym = 'TST'; market = 'USA'; sector = 'Test'; horizon = 'swing'
    productType = 'underliggande'; product = @{ type = 'underliggande'; lev = 1 }; dayEnd = $null; plan = @{ entry = 100; stop = 95; t1 = 110; t2 = 120 }
    currency = 'USD'; fx = 10; qty = 100; riskPct = 1; riskKr = 5000; dec = 2; status = 'väntar'; fill = $null; exits = @(); stopNow = 95; t1done = $false
    lastPrice = 99; lastT = $T0; mfeR = $null; maeR = $null; resultKr = $null; r = $null; closed = $null; reasonClosed = $null; daysHeld = $null; lesson = $null; scanT = $null
    tplan = @{ thesis = 'test' } }
  foreach ($k in $o.Keys) { $t[$k] = $o[$k] }; $t
}
# bars: lista med [o,h,l,c], en per timme från T0
function Run($name, $trade, $bars, [int]$times = 1, [scriptblock]$check) {
  $d = Join-Path $root $name; New-Item -ItemType Directory -Force $d | Out-Null
  $i = 0; $B = @($bars | ForEach-Object { , @(($T0 + 3600 * $i++), $_[0], $_[1], $_[2], $_[3]) })
  W (Join-Path $d "$($trade.ysym).json") @{ bars = $B; last = $bars[-1][3] }
  W (Join-Path $d 'ledger.json') @{ v = 1; created = 'test'; start = 100000; currency = 'SEK'; trades = @($trade); equity = @(); lessons = @(); events = @() }
  $nowT = $T0 + 3600 * ($B.Count + 1)
  for ($k = 0; $k -lt $times; $k++) { $null = & $PSEXE -NoProfile -ExecutionPolicy Bypass -File $paper -Update -DataDir $d -BarsDir $d -NowT $nowT }
  $t = (Get-Content (Join-Path $d 'ledger.json') -Raw -Encoding UTF8 | ConvertFrom-Json).trades[0]
  try { $msg = & $check $t; if ($msg) { throw $msg }; "OK  $name"; $script:pass++ } catch { "FEL $($name): $($_.Exception.Message) (status $($t.status), skäl $($t.reasonClosed), r $($t.r), utgångar $(@($t.exits).Count))"; $script:fail++ }
}
function Between($v, $lo, $hi, $what) { if ($null -eq $v -or [double]$v -lt $lo -or [double]$v -gt $hi) { "$what $v ligger inte mellan $lo och $hi" } }

# 1. Köp vid BOS, mål 1 (en tredjedel) och resten på break-even
Run 'kop-mal1-breakeven' (Trade @{}) @(@(99, 99.5, 98, 99), @(99.5, 101, 99, 100.5), @(101, 111, 100.5, 110.5), @(109, 109, 99.5, 100)) 1 {
  param($t) if ($t.status -ne 'stängd' -or $t.reasonClosed -ne 'break-even') { 'ska stängas på break-even' } elseif (@($t.exits).Count -ne 2) { 'ska ha två utgångar' } else { Between $t.r 0.5 0.7 'R' } }
# 2. Köp och stopp: cirka −1R inklusive courtage
Run 'kop-stopp' (Trade @{}) @(@(99, 99.5, 98, 99), @(99.5, 101, 99, 100.5), @(99, 99.5, 94, 94.5)) 1 {
  param($t) if ($t.reasonClosed -ne 'stopp') { 'ska stängas på stoppet' } else { Between $t.r -1.1 -1.0 'R' } }
# 3. Kursen går under stoppet före BOS: ordern förfaller utan köp
Run 'forfall-stopp-fore-bos' (Trade @{}) @(, @(99, 99.5, 94.5, 95)) 1 {
  param($t) if ($t.status -ne 'förföll' -or $t.fill) { 'ordern ska förfalla utan köp' } }
# 4. Ingen BOS på sju dagar: ordern förfaller
Run 'forfall-7-dagar' (Trade @{}) @(1..(8 * 24) | ForEach-Object { , @(98, 99, 97, 98) }) 1 {
  param($t) if ($t.status -ne 'förföll' -or $t.reasonClosed -notmatch '7 dagar') { 'ordern ska förfalla efter 7 dagar' } }
# 5. Blankning: BOS nedåt, mål 1 och mål 2, med lånekostnad
Run 'blankning-mal2' (Trade @{ side = 'short'; plan = @{ entry = 50; stop = 52; t1 = 46; t2 = 43 }; stopNow = 52; qty = 1000; riskKr = 20000; lastPrice = 50.5 }) @(@(50.5, 50.8, 49.8, 50), @(49, 49.2, 45.5, 46), @(45.8, 46, 42.5, 43)) 1 {
  param($t) if ($t.reasonClosed -ne 'mål 2') { 'ska stängas vid mål 2' } else { Between $t.r 2.8 3.1 'R' } }
# 6. Blankning och stopp ovanför
Run 'blankning-stopp' (Trade @{ side = 'short'; plan = @{ entry = 50; stop = 52; t1 = 46; t2 = 43 }; stopNow = 52; qty = 1000; riskKr = 20000; lastPrice = 50.5 }) @(@(50.5, 50.8, 49.8, 50), @(50.2, 52.5, 50, 52.2)) 1 {
  param($t) if ($t.reasonClosed -ne 'stopp') { 'ska stängas på stoppet' } else { Between $t.r -1.1 -1.0 'R' } }
# 7. Turbo: gap förbi knockout ger förlust större än 1R
Run 'turbo-knockout' (Trade @{ productType = 'turbo'; product = @{ type = 'turbo'; ko = 90; lev = 10 } }) @(@(99, 99.5, 98, 99), @(99.5, 101, 99, 100.5), @(89, 89.5, 88, 89)) 1 {
  param($t) if ($t.reasonClosed -ne 'knockout') { 'ska slås ut (knockout)' } elseif ([double]$t.r -gt -1.5) { "förlusten $($t.r) R ska vara större än 1,5R" } }
# 7b. Turbo: courtage och spread på produktens värde (100 − 90 = 10), inte på hela underliggande (rättat 26 okt)
Run 'turbo-courtage' (Trade @{ productType = 'turbo'; product = @{ type = 'turbo'; ko = 90; lev = 10 } }) @(@(99, 99.5, 98, 99), @(99.5, 101, 99, 100.5)) 1 {
  param($t) if ($t.status -ne 'öppen') { 'ska vara köpt' } else { Between $t.fill.price 100.04 100.06 'köpkurs med kostnader' } }
# 8. Samma timmar räknas bara en gång (två körningar i rad ger inte två delförsäljningar)
Run 'dubbelkorning' (Trade @{}) @(@(99, 99.5, 98, 99), @(99.5, 101, 99, 100.5), @(101, 111, 100.5, 110.5)) 2 {
  param($t) if ($t.status -ne 'öppen' -or @($t.exits).Count -ne 1 -or -not $t.t1done) { 'ska vara öppen med exakt en delförsäljning' } }
# 9. Daytrade: allt säljs vid dagens slut
Run 'daytrade-dagsslut' (Trade @{ horizon = 'day'; dayEnd = $T0 + 4 * 3600 }) @(@(99.5, 101, 99, 100.5), @(100.5, 102, 100, 101), @(101, 102, 100.5, 101.5), @(101.5, 102, 101, 101.8)) 1 {
  param($t) if ($t.reasonClosed -ne 'dagsslut') { 'ska stängas vid dagens slut' } }
# 10. Mini: knockoutnivån ger restvärdet, inte noll
Run 'mini-stoploss' (Trade @{ productType = 'mini'; product = @{ type = 'mini'; financing = 80; stopLoss = 88; lev = 5 } }) @(@(99.5, 101, 99, 100.5), @(87, 87.5, 86, 87)) 1 {
  param($t) if ($t.reasonClosed -ne 'knockout') { 'ska avvecklas vid stop loss-nivån' } elseif (-not ([double]$t.exits[0].price -gt 80)) { "restvärdet $($t.exits[0].price) ska ligga över finansieringsnivån 80" } }

# ---------- reglerna när en order läggs (-Open) ----------
function OpenTest($name, $cand, $plan, $regime, $events, [scriptblock]$check, $trades = @()) {
  $d = Join-Path $root $name; New-Item -ItemType Directory -Force $d | Out-Null
  $c = [ordered]@{ id = 'us-tst'; symbol = 'TST'; name = 'Test'; tv = 'X:TST'; ysym = 'TST'; market = 'USA'; sector = 'Test'; sectorSv = 'Test'; side = 'long'; strategy = 'pullback'; strategyName = 'Rekyl'
    grade = 'A'; score = 70; why = 'test'; dec = 2; price = 99; entry = 100; stop = 96; t1 = 110; t2 = 115; t1Kind = 'nivå'; earningsDays = 30; rsi = 55 }
  foreach ($k in $cand.Keys) { $c[$k] = $cand[$k] }
  $p = [ordered]@{ id = 'us-tst'; horizon = 'swing'; product = @{ type = 'underliggande' }; thesis = 't'; htf = 'h'; level = 'l'; trigger = 'tr'; invalidation = 'i'; events = 'e'; correlation = 'c'; exit = 'x'
    confluence = @('a', 'b'); against = @('a', 'b'); gates = @{ htf = $true; events = $true; confluence = $true; discount = $true; bos = $true; stop = $true; rr = $true; invalidation = $true; risk = $true } }
  foreach ($k in $plan.Keys) { $p[$k] = $plan[$k] }
  W (Join-Path $d 'scan.json') @{ regime = $regime; candidates = @($c); soon = @() }
  W (Join-Path $d 'plan.json') @(, $p)
  W (Join-Path $d 'TST.json') @{ bars = @(); last = 99 }
  W (Join-Path $d 'makrokalender.json') @{ events = @($events) }
  W (Join-Path $d 'ledger.json') @{ v = 1; created = 'test'; start = 100000; currency = 'SEK'; trades = @($trades); equity = @(); lessons = @(); events = @() }
  foreach ($x in @($trades | Where-Object { $_.status -in 'väntar', 'öppen' })) { W (Join-Path $d "$($x.ysym).json") @{ bars = @(); last = 99 } }
  $out = (& $PSEXE -NoProfile -ExecutionPolicy Bypass -File $paper -Open us-tst -Plan (Join-Path $d 'plan.json') -DataDir $d -BarsDir $d -NowT ($T0 + 7200) -ScanFile (Join-Path $d 'scan.json')) -join "`n"
  $L = Get-Content (Join-Path $d 'ledger.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  try { $msg = & $check $out $L; if ($msg) { throw $msg }; "OK  $name"; $script:pass++ } catch { "FEL $($name): $($_.Exception.Message) | utskrift: $($out -replace "`n", ' / ')"; $script:fail++ }
}
$iso = { param($h) [DateTimeOffset]::FromUnixTimeSeconds($T0 + 7200 + $h * 3600).ToString('yyyy-MM-ddTHH:mm:ssZ') }
OpenTest 'open-giltig' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'JA') { 'planen ska godkännas' } elseif ([double]$L.trades[0].riskKr -ne 1000 -or [double]$L.trades[0].qty -ne 25) { "risk $($L.trades[0].riskKr) kr och antal $($L.trades[0].qty) ska vara 1 000 kr och 25 st" } }
OpenTest 'open-forsiktig-halv-risk' @{} @{} 'Försiktig' @() { param($o, $L) if ([double]$L.trades[0].riskPct -ne 0.5 -or [double]$L.trades[0].riskKr -gt 500) { "risken $($L.trades[0].riskPct) % / $($L.trades[0].riskKr) kr ska vara 0,5 % och högst 500 kr" } }
OpenTest 'open-plan-saknas' @{} @{ against = @('bara ett') } 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*motargument' -or @($L.trades).Count) { 'ska nekas: färre än två motargument' } }
OpenTest 'open-riskoff-kop' @{} @{} 'Risk-off' @() { param($o, $L) if ($o -notmatch 'NEJ.*risk-off') { 'köp ska nekas i risk-off' } }
# Devin 27 okt: ingen paus före Fed ("fortsätta köra dina trades och lära dig"); traden läggs och märks med beskedet
OpenTest 'open-fore-fed' @{} @{} 'Neutral' @(@{ t = (& $iso 30); kind = 'kpi'; label = 'KPI senare' }, @{ t = (& $iso 10); kind = 'fed'; label = 'Fed test' }) { param($o, $L) if ($o -notmatch 'JA') { 'ska läggas trots Fed inom 24 timmar' } elseif ($L.trades[0].nearEvent -ne 'Fed test') { "nearEvent är '$($L.trades[0].nearEvent)', ska vara 'Fed test' (närmaste beskedet)" } elseif ($L.events[0].text -notmatch 'Läggs före Fed test') { 'händelsen ska nämna beskedet' } }
OpenTest 'open-inget-besked' @{} @{} 'Neutral' @(@{ t = (& $iso 30); kind = 'kpi'; label = 'KPI senare' }) { param($o, $L) if ($o -notmatch 'JA' -or $null -ne $L.trades[0].nearEvent) { "nearEvent ska vara tomt när beskedet är mer än 24 timmar bort, är '$($L.trades[0].nearEvent)'" } }
# lärfas (Devin 27 okt): tills 30 trades är avslutade ingen förlustpaus och inget tak för antalet; efter det gäller reglerna igen
$lossToday = { param($n) @(1..$n | ForEach-Object { Trade @{ id = "pt-l$_"; symbol = "L$_"; ysym = "L$_"; status = 'stängd'; closed = $T0 + 3000 + $_; resultKr = -500; r = -0.5; strategy = 'pullback'; grade = 'A' } }) }
$wins = { param($n) @(1..$n | ForEach-Object { Trade @{ id = "pt-w$_"; symbol = "W$_"; ysym = "W$_"; status = 'stängd'; closed = $T0 - 10 * 86400 + $_; resultKr = 1000; r = 1; strategy = 'pullback'; grade = 'A' } }) }
$active5 = @(1..5 | ForEach-Object { Trade @{ id = "pt-a$_"; symbol = "A$_"; ysym = "A$_"; sector = "Sektor$_"; status = 'öppen'; createdT = $T0 + 3600; riskKr = 500; fill = @{ t = $T0 + 3600; price = 99 } } })
OpenTest 'open-larfas-efter-forlust' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'JA') { 'i lärfasen ska två förluster i dag inte stoppa en ny trade' } } (& $lossToday 2)
OpenTest 'open-larfas-utan-tak' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'JA') { 'i lärfasen ska fem aktiva och fem nya i dag inte stoppa en ny trade' } } $active5
OpenTest 'open-efter-larfas-forlust' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'Förlust i dag' -or $o -match 'JA') { 'efter 30 avslutade ska en förlust i dag stoppa nya trades' } } (@(& $wins 29) + @(& $lossToday 1))
OpenTest 'open-efter-larfas-tak' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*redan 5 aktiva') { 'efter 30 avslutade ska taket på 5 aktiva swingtrades gälla' } } (@(& $wins 30) + $active5)
# lärfasen: högst 10 % total risk i stället för 5 % (Devin 27 okt); efter 30 avslutade gäller 5 % igen
# fill = senaste priset, så att öppna trades inte blåser upp portföljvärdet (då skulle risken räknas mot fel värde)
$activeN = { param($n) @(1..$n | ForEach-Object { Trade @{ id = "pt-r$_"; symbol = "R$_"; ysym = "R$_"; sector = "Risk$_"; status = 'öppen'; createdT = $T0 - 86400; riskKr = 1000; fill = @{ t = $T0 - 86400; price = 99 } } }) }
OpenTest 'open-larfas-risk-7' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'JA') { 'i lärfasen ska 7 % total risk gå (högst 10 %)' } } (& $activeN 6)
OpenTest 'open-larfas-risk-over-10' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*total risk över 10 %') { 'i lärfasen ska över 10 % total risk nekas' } } (& $activeN 10)
OpenTest 'open-efter-larfas-risk-5' @{} @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*total risk över 5 %') { 'efter 30 avslutade ska över 5 % total risk nekas' } } (@(& $wins 30) + @(& $activeN 6))
OpenTest 'open-blanka-oversalt' @{ side = 'short'; entry = 50; stop = 52; t1 = 46; t2 = 43; rsi = 25 } @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*översålt') { 'blankning i översålt ska nekas' } }
OpenTest 'open-rr-for-lag' @{ t1 = 105 } @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*R/R') { 'R/R under 1:2 ska nekas' } }
OpenTest 'open-rapport-nara' @{ earningsDays = 5 } @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*rapport') { 'rapport inom 14 dagar ska nekas' } }
OpenTest 'open-turbo-ko-nara-stopp' @{} @{ product = @{ type = 'turbo'; ko = 95.5 } } 'Neutral' @() { param($o, $L) if ($o -notmatch 'NEJ.*knockout') { 'knockout för nära stoppet ska nekas' } }

# fler marknader (25 okt): valutan följer aktien och daytrades stängs vid börsens egen stängning
OpenTest 'open-norge-nok' @{ market = 'Norge'; currency = 'NOK' } @{} 'Neutral' @() { param($o, $L) if ($o -notmatch 'JA' -or $L.trades[0].currency -ne 'NOK') { "valutan $($L.trades[0].currency) ska vara NOK" } }
# T0 + 2 h = lördag 24 okt 02.00 UTC; Xetra stänger 17.30 i Frankfurt = 15.30 UTC (sommartid)
OpenTest 'open-daytrade-tyskland' @{ market = 'Tyskland'; currency = 'EUR' } @{ horizon = 'day' } 'Neutral' @() { param($o, $L) if ([int64]$L.trades[0].dayEnd -ne ($T0 + 15.5 * 3600)) { "dagens slut $($L.trades[0].dayEnd) ska vara $($T0 + 15.5 * 3600) (17.30 i Frankfurt)" } }
OpenTest 'open-daytrade-london' @{ market = 'Storbritannien'; currency = 'GBX' } @{ horizon = 'day' } 'Neutral' @() { param($o, $L) if ([int64]$L.trades[0].dayEnd -ne ($T0 + 15.5 * 3600)) { "dagens slut $($L.trades[0].dayEnd) ska vara 16.30 i London" } }

# daytrades på 15-minutersdata stängs vid dagens slut och inte en timme för tidigt
$T15 = $T0
function Run15($name, $trade, $bars, [scriptblock]$check) {
  $d = Join-Path $root $name; New-Item -ItemType Directory -Force $d | Out-Null
  $i = 0; $B = @($bars | ForEach-Object { , @(($T15 + 900 * $i++), $_[0], $_[1], $_[2], $_[3]) })
  W (Join-Path $d "$($trade.ysym).json") @{ bars = $B; last = $bars[-1][3] }
  W (Join-Path $d 'ledger.json') @{ v = 1; created = 'test'; start = 100000; currency = 'SEK'; trades = @($trade); equity = @(); lessons = @(); events = @() }
  $null = & $PSEXE -NoProfile -ExecutionPolicy Bypass -File $paper -Update -DataDir $d -BarsDir $d -NowT ($T15 + 900 * ($B.Count + 1))
  $t = (Get-Content (Join-Path $d 'ledger.json') -Raw -Encoding UTF8 | ConvertFrom-Json).trades[0]
  try { $msg = & $check $t; if ($msg) { throw $msg }; "OK  $name"; $script:pass++ } catch { "FEL $($name): $($_.Exception.Message) (status $($t.status), skäl $($t.reasonClosed), stängd $($t.closed))"; $script:fail++ }
}
# dagens slut efter 8 candles (2 timmar); utgången ska ske på candlen 1.45–2.00, inte en timme tidigare
Run15 'daytrade-15m-dagsslut' (Trade @{ horizon = 'day'; dayEnd = $T0 + 2 * 3600 }) @(@(99.5, 101, 99, 100.5), @(100.5, 101, 100, 100.8), @(100.8, 101.2, 100.4, 101), @(101, 101.5, 100.8, 101.2), @(101.2, 101.6, 101, 101.3), @(101.3, 101.8, 101.1, 101.5), @(101.5, 101.9, 101.2, 101.6), @(101.6, 102, 101.4, 101.7)) {
  param($t) if ($t.reasonClosed -ne 'dagsslut') { 'ska stängas vid dagens slut' } elseif ([int64]$t.closed -ne $T0 + 7 * 900) { "stängdes $(([int64]$t.closed - $T0) / 900) candles in, ska vara 7 (sista candlen före dagens slut)" } }
# egna gränser: tre aktiva swingtrades hindrar inte en daytrade
function OpenMany($name, [scriptblock]$check, $extra = @(), $regime = 'Neutral') {
  $d = Join-Path $root $name; New-Item -ItemType Directory -Force $d | Out-Null
  $sw = @(1..5 | ForEach-Object { $x = Trade @{ id = "pt-s$_"; symbol = "S$_"; sector = "Sektor$_"; createdT = $T0 - 86400; riskKr = 500 }; $x }) + @($extra)
  W (Join-Path $d 'ledger.json') @{ v = 1; created = 'test'; start = 100000; currency = 'SEK'; trades = $sw; equity = @(); lessons = @(); events = @() }
  $p = [ordered]@{ id = 'dt-test'; horizon = 'day'; side = 'long'; product = @{ type = 'underliggande' }; symbol = 'DT'; name = 'Daytest'; ysym = 'DT'; tv = 'X:DT'; market = 'Råvaror'; sector = 'Energi'; currency = 'USD'; dec = 2
    entry = 100.0; stop = 99.0; t1 = 102.0; t2 = 103.0; thesis = 't'; htf = 'h'; level = 'l'; trigger = 'tr'; invalidation = 'i'; events = 'e'; correlation = 'c'; exit = 'x'; confluence = @('a', 'b'); against = @('a', 'b')
    gates = @{ htf = $true; events = $true; confluence = $true; discount = $true; bos = $true; stop = $true; rr = $true; invalidation = $true; risk = $true } }
  W (Join-Path $d 'plan.json') @(, $p); W (Join-Path $d 'scan.json') @{ regime = $regime; candidates = @(); soon = @() }; W (Join-Path $d 'DT.json') @{ bars = @(); last = 99.5 }; W (Join-Path $d 'makrokalender.json') @{ events = @() }
  foreach ($x in $sw) { W (Join-Path $d "$($x.ysym).json") @{ bars = @(); last = 99 } }
  $out = (& $PSEXE -NoProfile -ExecutionPolicy Bypass -File $paper -Open dt-test -Plan (Join-Path $d 'plan.json') -DataDir $d -BarsDir $d -NowT ($T0 + 7200) -ScanFile (Join-Path $d 'scan.json')) -join "`n"
  $L = Get-Content (Join-Path $d 'ledger.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  try { $msg = & $check $out $L; if ($msg) { throw $msg }; "OK  $name"; $script:pass++ } catch { "FEL $($name): $($_.Exception.Message) | $($out -replace "`n", ' / ')"; $script:fail++ }
}
OpenMany 'open-daytrade-utover-swing' { param($o, $L) if ($o -notmatch 'JA' -or -not (@($L.trades | Where-Object { $_.horizon -eq 'day' }).Count)) { 'daytraden ska läggas trots fem aktiva swingtrades' } elseif (@($L.trades | Where-Object { $_.horizon -eq 'day' })[0].dayEnd -ne ($T0 + 20 * 3600)) { "dagens slut ska vara 16.00 New York (20.00 UTC), är $((@($L.trades | Where-Object { $_.horizon -eq 'day' })[0].dayEnd - $T0) / 3600) h" } }

# Devin 26 okt: "du får göra hur många du vill" – inget tak för daytrades, och full risk (1 %) även i försiktig marknad
OpenMany 'open-daytrade-utan-tak' { param($o, $L) $dt = @($L.trades | Where-Object { $_.id -like '*dt-test' }); if ($o -notmatch 'JA' -or -not $dt.Count) { 'en femte daytrade samma dag ska läggas (inget tak)' } elseif ([double]$dt[0].riskPct -ne 1.0) { "daytrade ska ha 1 % risk även i försiktig marknad, har $($dt[0].riskPct)" } } @(1..4 | ForEach-Object { Trade @{ id = "pt-d$_"; symbol = "D$_"; sector = "Dag$_"; horizon = 'day'; createdT = $T0 + 3600; riskKr = 300 } }) 'Försiktig'

# 26 okt: värdekurvan ska sparas som listor [tid, värde]. Med Select-Object blev de {value, Count}, och då kunde Jarvis inte rita kurvan.
$d = Join-Path $root 'db-state-kurva'; New-Item -ItemType Directory -Force $d | Out-Null
W (Join-Path $d 'TST.json') @{ bars = @(, @($T0, 99, 99.5, 98, 99)); last = 99 }
W (Join-Path $d 'ledger.json') @{ v = 1; created = 'test'; start = 100000; currency = 'SEK'; trades = @(Trade @{}); equity = @(@(($T0 - 7200), 100000), @(($T0 - 3600), 100100)); lessons = @(); events = @() }
$null = & $PSEXE -NoProfile -ExecutionPolicy Bypass -File $paper -Update -DataDir $d -BarsDir $d -NowT ($T0 + 7200)
try { $raw = [IO.File]::ReadAllText((Join-Path $d 'db-state.json')); $eq = @(($raw | ConvertFrom-Json).equity)
  if ($raw -match '"Count"') { throw 'equity innehåller {value, Count}' } elseif ($eq.Count -lt 2 -or @($eq[0]).Count -ne 2) { throw "equity ska vara listor [tid, värde], har $($eq.Count) punkter" }
  "OK  db-state-kurva"; $script:pass++ } catch { "FEL db-state-kurva: $($_.Exception.Message)"; $script:fail++ }

# 27 okt: statistiken delar upp avslutade trades i lagda före Fed/KPI och övriga (äldre trades utan nearEvent räknas som övriga)
$d = Join-Path $root 'stats-fore-besked'; New-Item -ItemType Directory -Force $d | Out-Null
$cl = @{ status = 'stängd'; closed = $T0 - 86400 * 2; daysHeld = 2; strategy = 'pullback'; grade = 'A' }
$tr = @((Trade ($cl + @{ id = 'pt-a'; r = 1.5; resultKr = 1500; nearEvent = 'Fed test' })), (Trade ($cl + @{ id = 'pt-b'; r = -1; resultKr = -1000 })), (Trade ($cl + @{ id = 'pt-c'; r = 2; resultKr = 2000; nearEvent = $null })))
W (Join-Path $d 'ledger.json') @{ v = 1; created = 'test'; start = 100000; currency = 'SEK'; trades = $tr; equity = @(); lessons = @(); events = @() }
$null = & $PSEXE -NoProfile -ExecutionPolicy Bypass -File $paper -Update -DataDir $d -BarsDir $d -NowT ($T0 + 7200)
try { $be = ([IO.File]::ReadAllText((Join-Path $d 'db-state.json')) | ConvertFrom-Json).stats.byEvent
  if ($be.fore.n -ne 1 -or $be.fore.avgR -ne 1.5) { throw "före besked ska vara 1 trade med 1,5 R, är n=$($be.fore.n) R=$($be.fore.avgR)" } elseif ($be.utan.n -ne 2) { throw "övriga ska vara 2, är $($be.utan.n)" }
  "OK  stats-fore-besked"; $script:pass++ } catch { "FEL stats-fore-besked: $($_.Exception.Message)"; $script:fail++ }

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
"Tester: $script:pass av $($script:pass + $script:fail) godkända"
if ($script:fail) { exit 1 }
