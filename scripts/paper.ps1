# Jarvis testportfölj (pappershandel). Inga riktiga pengar och inga riktiga order.
# Reglerna står i references\handelsplan.md (beslutade med Devin 2026-10-23). Ingen trade öppnas utan handelsplan.
# Lägen:
#   -Update                              följer upp alla väntande och öppna testtrades mot timdata (Yahoo) och räknar statistik
#   -Open us-tgt,se-aq -Plan <fil.json>  lägger köp- eller blankningsorder (vid BOS) enligt handelsplanen; swing från data\scan-latest.json,
#                                        daytrades och egna setups med entry/stopp/mål och ysym i planen
#   -Lesson <id> -Text "..."             sparar en lärdom på en trade
#   -AllowB                              tillåter B-betyg för swing (skälet ska stå i planen)
#   -Notis                               skriver ut händelser som inte skickats som notis än (rader "NOTIS: ...") och markerar dem som skickade
# Skriver data\paper\ledger.json (källan) och data\paper\db-state.json + db-trades.json (till Jarvis-databasen).
# Varje köporder, köp, mål 1, stängning och förfall loggas i ledger.events; körningens nya händelser i data\paper\events-new.json.
# Fel i uppföljningen skrivs till data\paper\update-errors.json (hälsokontrollen läser den).
# Test (scripts\test-paper.ps1): -DataDir <mapp> -BarsDir <mapp med <ysym>.json> -NowT <unixtid> -ScanFile <fil> kör motorn på påhittad data.
param([switch]$Update, [string[]]$Open, [string]$Plan, [string]$Lesson, [string]$Text, [switch]$AllowB, [switch]$Notis,
  [string]$DataDir, [string]$BarsDir, [int64]$NowT = 0, [string]$ScanFile)
$ErrorActionPreference = 'Stop'
$Dir = if ($DataDir) { [IO.Path]::GetFullPath($DataDir) } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data/paper')) }
New-Item -ItemType Directory -Force $Dir | Out-Null
$LedgerFile = Join-Path $Dir 'ledger.json'
$now = if ($NowT) { [DateTimeOffset]::FromUnixTimeSeconds($NowT).UtcDateTime } else { (Get-Date).ToUniversalTime() }; $nowT = [DateTimeOffset]::new($now).ToUnixTimeSeconds()
$enc = [Text.UTF8Encoding]::new($false)
$RULES = [ordered]@{
  start = 100000; currency = 'SEK'
  riskPct = 1.0; riskPctCautious = 0.5; maxActive = 5; maxOpenRiskPct = 5; maxPerSector = 2; maxPositionPct = 25; maxNewPerDay = 3; weeklyLossR = -6
  # daytrades räknas för sig från swing och har inget tak för antalet (Devin 26 okt: "du får göra hur många du vill ... men om det inte är bra setup
  # behöver du inte göra några alls, men jag vill ändå att du ska ta lite risk"); 0 = ingen gräns. Full risk även i försiktig marknad, eftersom de stängs samma dag.
  maxNewDayPerDay = 0; maxActiveDay = 0; riskPctDay = 1.0
  costStock = 0.001; costCrypto = 0.0015; prodSpread = 0.004; finRate = 0.07; pendingDays = 7; timeStopDays = 21; partialAtT1 = 0.3333
  swingMaxStopPct = 8; dayMaxStopPct = 4; maxLevSwing = 5; maxLevDay = 10; eventNearH = 24
  borrowStock = 0.02; borrowCrypto = 0.10; maxShorts = 3
  # lärfas (Devin 27 okt: "fram tills du har gjort ett bra antal trades så tycker jag att du kan köra hur många du vill så länge de är bra och godkända"):
  # tills så här många trades är avslutade gäller ingen paus efter förluster och inget tak för antalet; planen, grindarna och risken gäller som vanligt
  learnTrades = 30
  # under lärfasen högst 10 % total öppen risk i stället för 5 % (Devin 27 okt: "Höj taket på total risk till 10 % under lärfasen")
  maxOpenRiskPctLearn = 10
  # dagsmål (Younes 2026-10-28: "jag vill göra 2 % i avkastning per dag ... trada upp till 2 %, sen är du klar"): när dagens stängda trades
  # gett så här många procent av portföljvärdet vid dagens början läggs inga nya testtrades den dagen; öppna positioner följer sin plan
  dailyTargetPct = 2
  text = @(
    'Ingen trade utan nedskriven handelsplan: tes, HTF och regim, nivå med minst två verktyg, BOS-villkor, invalidering, två motargument, händelser, korrelation, exitplan och alla nio grindar (references\handelsplan.md).',
    'Swing: bara A-betyg, minst 1:2, ingen rapport inom 14 dagar, stopp högst 8 % bort. Köp vid BOS; ordern förfaller efter 7 dagar eller om kursen går under stoppet först.',
    'Daytrade: läge från daytrade-scannern (ORB, sweep av gårdagens high/low, VWAP-trend på 15 minuter) eller egen setup, minst 1:2 och stopp högst 4 % bort. Ordern gäller samma dag och allt säljs vid börsens stängning (till exempel USA 22.00, Stockholm 17.30, London 17.30, krypto 23.00 svensk tid). Följs upp på 15-minutersdata.',
    'Risk 1 % per trade (0,5 % i försiktig marknad, inga nya i risk-off), högst 5 % total risk. Swing: högst 5 aktiva, 2 per sektor och 3 nya per dag. Daytrade, utöver swing: inget tak för antalet, bara bra lägen, högst 2 samtidigt per sektor och 1 % risk även i försiktig marknad.',
    'Vid mål 1 säljs en tredjedel och stoppet flyttas till break-even. Resten vid mål 2, på stoppet, efter 21 dagar (swing) eller vid dagens slut (daytrade).',
    'Lärfas: tills 30 trades är avslutade finns ingen paus efter förluster och inget tak för antalet trades, så länge varje trade är bra och klarar planen, grindarna och risken (1 % per trade, högst 2 per sektor). Total risk högst 10 % under lärfasen i stället för 5 %. Sedan gäller pausreglerna, taken och 5 % igen.',
    'Ingen paus före Feds räntebesked eller amerikansk KPI (fortsätt handla och lär dig). Trades som läggs inom 24 timmar före ett besked märks och räknas för sig i statistiken. Efter en förlust inga nya trades samma dag, paus ett dygn efter två förluster i rad och stopp vid −6R på en vecka.',
    'Turbo och mini simuleras med knockout: under stoppet med marginal och under S2, högst 5 gångers hävstång för swing och 10 för daytrade. Gap förbi knockout ger förlust över 1R.',
    'Kostnader: 0,1 % per affär för aktier, 0,15 % för krypto, plus 0,4 % spread på produktens värde och cirka 7 % finansiering per år för turbo och mini. Resultat i kronor med dollarkursen vid köpet.',
    'Blankning (short) med samma regler spegelvänt: BOS nedåt, stopp ovanför, mål vid stöd under. Bara i nedtrend, aldrig in i översålt (RSI under 30), högst 3 blankningar samtidigt, halv risk i risk-on. Lånekostnad cirka 2 % per år för aktier och 10 % för krypto; Mini S och Turbo S har knockout ovanför stoppet.',
    'Dagsmål (YL 28 okt 2026): +2 % av portföljvärdet per handelsdag, räknat på stängda trades sedan midnatt mot värdet vid dagens början. När målet är nått läggs inga nya testtrades den dagen; öppna positioner följer sin plan. Lägen tas både för köp och blankning i aktier, index, ädelmetaller och krypto, alltid enligt reglerna ovan. YL 29 okt: daytrades med betyg A eller B, swing B med -AllowB, inga nya daytrades från kl 21, blankning lika gärna som köp.')
}
function N($v) { if ($null -eq $v -or $v -is [string]) { return [double]::NaN }; [double]$v }
function Ok([double]$v) { -not ([double]::IsNaN($v) -or [double]::IsInfinity($v)) }
function R6($v) { if (-not (Ok (N $v))) { return $null }; [math]::Round([double]$v, 6) }
function F($v, $d = 2) { (N $v).ToString("N$d", [Globalization.CultureInfo]::GetCultureInfo('sv-SE')) }
$script:NEW = @()
# antal: hela aktier utan decimaler, delar (certifikat på index, krypto) med två eller fler
function QtyDec($q) { if ([double]$q -eq [math]::Floor([double]$q)) { 0 } elseif ([double]$q -ge 10) { 1 } elseif ([double]$q -ge 0.1) { 2 } else { 4 } }
function Ev($t, $type, $time, $text) { $e = [pscustomobject]@{ t = $time; id = $t.id; symbol = $t.symbol; type = $type; text = $text; sent = $false }; $script:NEW += $e; $script:L.events = @($script:L.events) + @($e) }
function Load {
  if (Test-Path $LedgerFile) { return (Get-Content $LedgerFile -Raw -Encoding UTF8 | ConvertFrom-Json) }
  [pscustomobject]@{ v = 1; created = $now.ToString('yyyy-MM-ddTHH:mm:ssZ'); start = $RULES.start; currency = 'SEK'; trades = @(); equity = @(); lessons = @() }
}
function Save($L) { [IO.File]::WriteAllText($LedgerFile, ($L | ConvertTo-Json -Depth 10 -Compress), $enc) }
# Daytrades följs upp på 15-minutersdata (sedan 26 okt), swing på timdata
function Bars($ysym, $since, $interval = '60m') {
  if ($BarsDir) { $o = Get-Content (Join-Path $BarsDir "$($ysym -replace '[^\w\.\-]', '_').json") -Raw -Encoding UTF8 | ConvertFrom-Json; return @{ bars = @($o.bars | ForEach-Object { , @([int64]$_[0], [double]$_[1], [double]$_[2], [double]$_[3], [double]$_[4]) }); last = [double]$o.last } }
  $age = ($nowT - $since) / 86400
  $range = if ($interval -eq '15m') { if ($age -lt 4) { '5d' } else { '1mo' } } elseif ($age -lt 25) { '1mo' } elseif ($age -lt 80) { '3mo' } else { '6mo' }
  $res = (Invoke-RestMethod -Uri "https://query2.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($ysym))?range=$range&interval=$interval" -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30).chart.result[0]
  $q = $res.indicators.quote[0]; $out = @()
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) { if ($null -eq $q.close[$i] -or $null -eq $q.high[$i]) { continue }; $out += , @([int64]$res.timestamp[$i], [double]$q.open[$i], [double]$q.high[$i], [double]$q.low[$i], [double]$q.close[$i]) }
  @{ bars = $out; last = [double]$res.meta.regularMarketPrice }
}
# Växelkurs till SEK (Yahoo <valuta>SEK=X). Londonbörsen noteras i pence (GBX), alltså pundkursen delat med 100.
function Fx($ccy) { if ($ccy -eq 'SEK') { return 1.0 }; if ($BarsDir) { return 10.0 }
  $div = 1.0; if ($ccy -in 'GBX', 'GBp') { $ccy = 'GBP'; $div = 100.0 }
  [double](Invoke-RestMethod -Uri "https://query2.finance.yahoo.com/v8/finance/chart/$($ccy)SEK=X?range=1d&interval=1h" -Headers @{ 'User-Agent' = 'Mozilla/5.0' }).chart.result[0].meta.regularMarketPrice / $div }
# Handelsdagens slut för en tidpunkt, i börsens egen tidszon (USA och Kanada 16.00 New York, London och Lissabon 16.30,
# Oslo 16.20, Köpenhamn 17.00, Helsingfors 18.30, Stockholm och övriga Europa 17.30), krypto 23.00 svensk tid
$BOURSE = @{ 'USA' = @('Eastern Standard Time', '16:00'); 'Kanada' = @('Eastern Standard Time', '16:00'); 'Råvaror' = @('Eastern Standard Time', '16:00'); 'Storbritannien' = @('GMT Standard Time', '16:30'); 'Portugal' = @('GMT Standard Time', '16:30')
  'Norge' = @('W. Europe Standard Time', '16:20'); 'Danmark' = @('W. Europe Standard Time', '17:00'); 'Finland' = @('GTB Standard Time', '18:30'); 'Sverige' = @('W. Europe Standard Time', '17:30')
  'Tyskland' = @('W. Europe Standard Time', '17:30'); 'Frankrike' = @('W. Europe Standard Time', '17:30'); 'Nederländerna' = @('W. Europe Standard Time', '17:30'); 'Belgien' = @('W. Europe Standard Time', '17:30')
  'Schweiz' = @('W. Europe Standard Time', '17:30'); 'Italien' = @('W. Europe Standard Time', '17:30'); 'Spanien' = @('W. Europe Standard Time', '17:30'); 'Österrike' = @('W. Europe Standard Time', '17:30') }
function DayEnd($market, [int64]$t) {
  $cl = $BOURSE[[string]$market]; if (-not $cl) { $cl = @('W. Europe Standard Time', '23:00') }
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById($cl[0])
  $local = [TimeZoneInfo]::ConvertTimeFromUtc([DateTimeOffset]::FromUnixTimeSeconds($t).UtcDateTime, $tz)
  $close = [timespan]$cl[1]
  $end = [DateTimeOffset]::new([TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($local.Date + $close, 'Unspecified'), $tz)).ToUnixTimeSeconds()
  if ($end -le $t) { $end += 86400 }
  $end
}
function Cost($t) { if ($t.market -eq 'Krypto') { $RULES.costCrypto } else { $RULES.costStock } }
# Turbo och mini: finansieringsnivå F och knockout/stop loss-nivå
function ProdF($t) { switch ($t.product.type) { 'turbo' { [double]$t.product.ko } 'mini' { [double]$t.product.financing } default { $null } } }
function KoLevel($t) { switch ($t.product.type) { 'turbo' { [double]$t.product.ko } 'mini' { [double]$t.product.stopLoss } default { $null } } }
# Riktning: +1 för köp (long), −1 för blankning (short). Gamla trades utan side är köp.
function Sg($t) { if ($t.side -eq 'short') { -1 } else { 1 } }
# courtage per enhet: på produktens värde (kurs − F) för turbo och mini, annars på kursen (rättat 26 okt: räknades på hela underliggande värdet)
function CostPx($t, $px) { $f = ProdF $t; if ($null -eq $f) { return (Cost $t) * [double]$px }; (Cost $t) * [math]::Max(0, (Sg $t) * ([double]$px - $f)) }
function ProdCost($t, $px) { $f = ProdF $t; if ($null -eq $f) { return 0.0 }; $RULES.prodSpread * [math]::Max(0, (Sg $t) * ([double]$px - $f)) }
# finansiering för turbo/mini, lånekostnad för blankning av underliggande
function FinCost($t, $time) {
  if (-not $t.fill) { return 0.0 }
  $rate = if ($null -ne (ProdF $t)) { $RULES.finRate } elseif ($t.side -eq 'short') { if ($t.market -eq 'Krypto') { $RULES.borrowCrypto } else { $RULES.borrowStock } } else { 0 }
  [double]$t.fill.price * $rate * (([double]$time - [double]$t.fill.t) / 86400) / 365
}
function Remaining($t) { $q = [double]$t.qty; foreach ($e in @($t.exits)) { $q -= [double]$e.qty }; [math]::Max(0, $q) }
function Realized($t) { $g = Sg $t; $s = 0.0; foreach ($e in @($t.exits)) { $s += $g * ([double]$e.price - [double]$t.fill.price) * [double]$e.qty * [double]$t.fx }; $s }
function Unrealized($t) { if ($t.status -ne 'öppen' -or -not (Ok (N $t.lastPrice))) { return 0.0 }; $g = Sg $t; $lp = N $t.lastPrice; $eff = $lp - $g * (CostPx $t $lp) - $g * (ProdCost $t $lp); $g * ($eff - [double]$t.fill.price) * (Remaining $t) * [double]$t.fx }
function Equity($L) { $e = [double]$L.start; foreach ($t in $L.trades) { if ($t.status -in 'öppen', 'stängd') { $e += (Realized $t) + (Unrealized $t) } }; $e }
function AddExit($t, $time, $price, $qty, $reason) {
  $g = Sg $t; $p = [double]$price - $g * ((CostPx $t $price) + (ProdCost $t $price) + (FinCost $t $time))
  $t.exits = @($t.exits) + @([pscustomobject]@{ t = $time; price = (R6 $p); qty = (R6 $qty); reason = $reason })
}
function Close($t, $time, $reason) {
  $t.status = 'stängd'; $t.closed = $time; $t.reasonClosed = $reason
  $t.resultKr = [math]::Round((Realized $t), 0); $t.r = [math]::Round($t.resultKr / [double]$t.riskKr, 2)
  $t.daysHeld = [math]::Round(($time - [double]$t.fill.t) / 86400, 1)
  Ev $t 'stängd' $time "Stängde $($t.symbol) ($reason): $(if ($t.resultKr -ge 0) { '+' })$(F $t.resultKr 0) kr, $(F $t.r 2) R efter $(F $t.daysHeld 1) dagar."
}
function Expire($t, $time, $reason, $text) { $t.status = 'förföll'; $t.reasonClosed = $reason; $t.closed = $time; Ev $t 'förföll' $time $text }
function Step($t) {
  $B = Bars $t.ysym ([int64]$t.createdT) $(if ($t.horizon -eq 'day') { '15m' } else { '60m' })
  $t.lastPrice = R6 $B.last; $t.lastT = $nowT
  # candlens längd (15 min för daytrades, en timme för swing) räknas fram ur datan
  $bs = @($B.bars); $dur = 3600; if ($bs.Count -ge 2) { $dur = [int64]($bs[1][0] - $bs[0][0]); for ($j = 2; $j -lt [math]::Min(8, $bs.Count); $j++) { $dd = [int64]($bs[$j][0] - $bs[$j - 1][0]); if ($dd -gt 0 -and $dd -lt $dur) { $dur = $dd } } }
  if (-not ($t.PSObject.Properties.Name -contains 'scanT')) { $t | Add-Member scanT $null }
  $day = $t.horizon -eq 'day'; $ko = KoLevel $t; $g = Sg $t; $sh = $g -lt 0
  $ord = if ($sh) { 'Blankningsordern' } else { 'Köpordern' }
  foreach ($b in $B.bars) {
    $bt, $o, $hi, $lo, $c = $b
    if ($bt -lt [int64]$t.createdT) { continue }
    # En stängd timme räknas bara en gång, så att ett flyttat stopp inte testas mot gamla timmar
    if ($null -ne $t.scanT -and $bt -le [int64]$t.scanT) { continue }
    if ($bt + $dur -le $nowT) { $t.scanT = $bt }
    $best = if ($sh) { $lo } else { $hi }; $worst = if ($sh) { $hi } else { $lo }
    if ($t.status -eq 'väntar') {
      if ($day -and $bt -ge [int64]$t.dayEnd) { Expire $t $bt 'Ingen BOS samma dag' "Daytraden i $($t.symbol) förföll: ingen BOS före dagens stängning."; return }
      if (-not $day -and $bt -gt [int64]$t.createdT + $RULES.pendingDays * 86400) { Expire $t $bt 'Ingen BOS inom 7 dagar' "$ord i $($t.symbol) förföll: ingen BOS inom 7 dagar."; return }
      # kursen nådde stoppet innan BOS: setupen är ogiltig
      if ($g * ($worst - [double]$t.plan.stop) -le 0) { Expire $t $bt "Gick $(if ($sh) { 'över' } else { 'under' }) stoppet före BOS, setupen ogiltig" "$ord i $($t.symbol) förföll: kursen gick $(if ($sh) { 'över' } else { 'under' }) stoppet $(F $t.plan.stop $t.dec) före BOS."; return }
      if ($g * ($best - [double]$t.plan.entry) -ge 0) {
        $px0 = if ($sh) { [math]::Min([double]$t.plan.entry, $o) } else { [math]::Max([double]$t.plan.entry, $o) }
        $fp = $px0 + $g * ((CostPx $t $px0) + (ProdCost $t $px0))
        $t.fill = [pscustomobject]@{ t = $bt; price = (R6 $fp) }; $t.status = 'öppen'; $t.stopNow = [double]$t.plan.stop; $t.t1done = $false
        $verb = if ($sh) { 'Blankade' } else { 'Köpte' }
        Ev $t 'köpt' $bt "$verb $(F $t.qty (QtyDec $t.qty)) st $($t.symbol)$(if ($t.product.type -in 'turbo', 'mini') { " via $($t.product.type) $(F $t.product.lev 1)x" }) för $(F $px0 $t.dec) $($t.currency) (BOS $(F $t.plan.entry $t.dec)). Stopp $(F $t.plan.stop $t.dec), mål $(F $t.plan.t1 $t.dec). Risk $(F $t.riskKr 0) kr."
      } else { continue }
    }
    if ($t.status -ne 'öppen') { continue }
    $risk1 = $g * ([double]$t.fill.price - [double]$t.plan.stop)
    if ($risk1 -gt 0) { $mfe = $g * ($best - [double]$t.fill.price) / $risk1; $mae = $g * ($worst - [double]$t.fill.price) / $risk1; if ($mfe -gt (N $t.mfeR) -or -not (Ok (N $t.mfeR))) { $t.mfeR = [math]::Round($mfe, 2) }; if ($mae -lt (N $t.maeR) -or -not (Ok (N $t.maeR))) { $t.maeR = [math]::Round($mae, 2) } }
    $rem = Remaining $t
    # Gap förbi knockout: turbon blir värdelös, minin avvecklas till restvärdet
    if ($null -ne $ko -and $g * ($ko - $o) -ge 0) {
      $fin = ProdF $t; $px = if ($t.product.type -eq 'turbo') { $fin } elseif ($sh) { [math]::Min($fin, $o) } else { [math]::Max($fin, $o) }
      AddExit $t $bt $px $rem 'knockout'; Close $t $bt 'knockout'; return
    }
    $be = [double]$t.fill.price - $g * (CostPx $t ([double]$t.fill.price))
    if ($g * ($worst - [double]$t.stopNow) -le 0) {
      $px = if ($sh) { [math]::Max([double]$t.stopNow, $o) } else { [math]::Min([double]$t.stopNow, $o) }
      $why = if ($g * ([double]$t.stopNow - $be * (1 - $g * 0.001)) -ge 0) { 'break-even' } else { 'stopp' }
      AddExit $t $bt $px $rem $why; Close $t $bt $why; return
    }
    if (-not $t.t1done -and $g * ($best - [double]$t.plan.t1) -ge 0) {
      $part = [double]$t.qty * $RULES.partialAtT1; if ($t.market -ne 'Krypto') { $part = [math]::Floor($part) }; if ($part -le 0) { $part = $rem }
      $px = if ($sh) { [math]::Min([double]$t.plan.t1, $o) } else { [math]::Max([double]$t.plan.t1, $o) }
      AddExit $t $bt $px $part 'mål 1 (1/3)'; $t.t1done = $true; $t.stopNow = $be
      Ev $t 'mål 1' $bt "$(if ($sh) { 'Köpte tillbaka' } else { 'Sålde' }) en tredjedel av $($t.symbol) vid mål 1 ($(F $t.plan.t1 $t.dec)). Stoppet flyttat till break-even."
      $rem = Remaining $t; if ($rem -le 0) { Close $t $bt 'mål 1'; return }
    }
    if ($t.t1done -and $g * ($best - [double]$t.plan.t2) -ge 0) { $px = if ($sh) { [math]::Min([double]$t.plan.t2, $o) } else { [math]::Max([double]$t.plan.t2, $o) }; AddExit $t $bt $px $rem 'mål 2'; Close $t $bt 'mål 2'; return }
    if ($day -and $bt + $dur -ge [int64]$t.dayEnd -and $nowT -ge [int64]$t.dayEnd) { AddExit $t $bt $c $rem 'dagsslut'; Close $t $bt 'dagsslut'; return }
    if (-not $day -and $bt -gt [double]$t.fill.t + $RULES.timeStopDays * 86400) { AddExit $t $bt $c $rem 'tidsstopp'; Close $t $bt 'tidsstopp'; return }
  }
  if ($day -and $t.status -eq 'väntar' -and $nowT -ge [int64]$t.dayEnd) { Expire $t $nowT 'Ingen BOS samma dag' "Daytraden i $($t.symbol) förföll: ingen BOS före dagens stängning." }
}function Wilson($k, $n) { if ($n -le 0) { return $null }; $z = 1.96; $p = $k / $n; $d = 1 + $z * $z / $n; $c = ($p + $z * $z / (2 * $n)) / $d; $h = $z * [math]::Sqrt($p * (1 - $p) / $n + $z * $z / (4 * $n * $n)) / $d; @([math]::Round(($c - $h) * 100), [math]::Round(($c + $h) * 100)) }
function GroupStats($trades, $key) {
  $out = [ordered]@{}
  foreach ($g in ($trades | Group-Object { if ($key -is [scriptblock]) { & $key $_ } else { $_.$key } })) { $cl = @($g.Group); $w = @($cl | Where-Object { $_.r -gt 0 }).Count
    $out[[string]$g.Name] = [ordered]@{ n = $cl.Count; wins = $w; winRate = [math]::Round($w / $cl.Count * 100); avgR = [math]::Round((($cl | Measure-Object r -Average).Average), 2); resultKr = [math]::Round((($cl | Measure-Object resultKr -Sum).Sum), 0) } }
  $out
}
function Stats($L) {
  $closed = @($L.trades | Where-Object { $_.status -eq 'stängd' }); $w = @($closed | Where-Object { $_.r -gt 0 }).Count
  $gw = (($closed | Where-Object { $_.resultKr -gt 0 } | Measure-Object resultKr -Sum).Sum); $gl = - (($closed | Where-Object { $_.resultKr -lt 0 } | Measure-Object resultKr -Sum).Sum)
  $eq = Equity $L; $peak = [double]$L.start; $dd = 0.0; foreach ($p in $L.equity) { if ($p[1] -gt $peak) { $peak = $p[1] }; $x = ($peak - $p[1]) / $peak * 100; if ($x -gt $dd) { $dd = $x } }
  [ordered]@{
    equity = [math]::Round($eq, 0); returnPct = [math]::Round(($eq / [double]$L.start - 1) * 100, 2); maxDrawdownPct = [math]::Round($dd, 2)
    closed = $closed.Count; learnTarget = $RULES.learnTrades; maxOpenRiskPct = $(if ($closed.Count -lt $RULES.learnTrades) { $RULES.maxOpenRiskPctLearn } else { $RULES.maxOpenRiskPct }); wins = $w; losses = $closed.Count - $w; winRate = $(if ($closed.Count) { [math]::Round($w / $closed.Count * 100) } else { $null }); winRateCI = (Wilson $w $closed.Count)
    avgR = $(if ($closed.Count) { [math]::Round((($closed | Measure-Object r -Average).Average), 2) } else { $null }); profitFactor = $(if ($gl -gt 0) { [math]::Round($gw / $gl, 2) } else { $null })
    avgDays = $(if ($closed.Count) { [math]::Round((($closed | Measure-Object daysHeld -Average).Average), 1) } else { $null })
    open = @($L.trades | Where-Object { $_.status -eq 'öppen' }).Count; pending = @($L.trades | Where-Object { $_.status -eq 'väntar' }).Count; expired = @($L.trades | Where-Object { $_.status -eq 'förföll' }).Count
    byStrategy = (GroupStats $closed 'strategy'); byGrade = (GroupStats $closed 'grade'); byMarket = (GroupStats $closed 'market'); byHorizon = (GroupStats $closed 'horizon'); byProduct = (GroupStats $closed 'productType'); bySide = (GroupStats $closed 'side')
    # lagda inom 24 timmar före Fed eller KPI mot övriga (sedan 27 okt), så att Jarvis ser om lägen före besked fungerar
    byEvent = (GroupStats $closed { param($x) if ($x.nearEvent) { 'fore' } else { 'utan' } })
  }
}
function Export($L) {
  $st = Stats $L
  # värdekurvan utan pipeline: Select-Object packar in listorna, och PowerShell 5.1 skriver dem då som {value, Count} (sidan kunde inte rita kurvan, rättat 26 okt)
  $eqAll = if ($L.equity) { [object[]]$L.equity } else { @() }; $eqN = $eqAll.Count; $eqLast = if ($eqN -gt 400) { $eqAll[($eqN - 400)..($eqN - 1)] } else { $eqAll }
  $state = [ordered]@{ at = $now.ToString('yyyy-MM-ddTHH:mm:ssZ'); start = $L.start; currency = 'SEK'; created = $L.created; stats = $st; rules = $RULES.text; equity = $eqLast; lessons = @($L.lessons | Select-Object -Last 40); events = @($L.events | Select-Object -Last 60) }
  [IO.File]::WriteAllText((Join-Path $Dir 'db-state.json'), ($state | ConvertTo-Json -Depth 10 -Compress), $enc)
  [IO.File]::WriteAllText((Join-Path $Dir 'db-trades.json'), ([ordered]@{ at = $state.at; trades = @($L.trades | Select-Object -Last 150) } | ConvertTo-Json -Depth 10 -Compress), $enc)
  $st
}
function Txt($v) { if ($null -eq $v) { '' } else { ([string]$v).Trim() } }

$L = Load
if (-not ($L.PSObject.Properties.Name -contains 'events')) { $L | Add-Member events @() }
if ($Lesson) {
  $t = $L.trades | Where-Object { $_.id -eq $Lesson } | Select-Object -First 1; if (-not $t) { throw "Ingen trade med id $Lesson" }
  $t | Add-Member lesson $Text -Force; $L.lessons = @($L.lessons) + @([pscustomobject]@{ t = $nowT; id = $Lesson; symbol = $t.symbol; text = $Text }); Save $L; Export $L | Out-Null; "Lärdom sparad på $Lesson"; return
}
if ($Notis) {
  $n = 0
  foreach ($e in @($L.events)) {
    if (-not ($e.PSObject.Properties.Name -contains 'sent') -or $e.sent) { continue }
    $m = "Jarvis testtrade: $($e.text)"; if ($m.Length -gt 199) { $m = $m.Substring(0, 196) + '...' }
    "NOTIS: $m"; $e.sent = $true; $n++
  }
  if ($n) { Save $L } else { 'Inga nya notiser.' }
  return
}
if ($Open) {
  $scan = Get-Content $(if ($ScanFile) { $ScanFile } else { Join-Path $PSScriptRoot '../data/scan-latest.json' }) -Raw -Encoding UTF8 | ConvertFrom-Json
  $takesFile = if ($ScanFile) { $null } else { Get-ChildItem (Join-Path $PSScriptRoot '../data') -Filter 'takes-*.json' | Sort-Object Name | Select-Object -Last 1 }
  $takes = if ($takesFile) { (Get-Content $takesFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).takes } else { $null }
  $plans = @{}
  if ($Plan) { foreach ($p in (ConvertFrom-Json -InputObject (Get-Content $Plan -Raw -Encoding UTF8))) { $plans[[string]$p.id] = $p } }
  $regime = $scan.regime
  # risk-off stoppar nya köp men inte blankningar; risken sätts per trade längre ner
  # Ingen hämndtrading: förlust i dag, två förluster i rad senaste dygnet eller −6R på veckan stoppar nya trades
  $closedTr = @($L.trades | Where-Object { $_.status -eq 'stängd' } | Sort-Object { [double]$_.closed })
  $today0 = [DateTimeOffset]::new($now.Date).ToUnixTimeSeconds()
  # Dagsmål (Younes 2026-10-28, handelsplan.md avsnitt 9): dagens stängda trades mot portföljvärdet vid dagens början (sista värdekurvepunkten före midnatt)
  $dayBase = [double]$L.start; foreach ($p in @($L.equity)) { if ([double]$p[0] -lt $today0 -and [double]$p[1] -gt 0) { $dayBase = [double]$p[1] } }
  $dayKr = (($closedTr | Where-Object { [double]$_.closed -ge $today0 } | Measure-Object resultKr -Sum).Sum)
  if ($null -ne $dayKr -and $dayBase -gt 0 -and $dayKr / $dayBase * 100 -ge $RULES.dailyTargetPct) { "Dagsmålet +$($RULES.dailyTargetPct) % är nått ($(F $dayKr 0) kr i dag): inga nya testtrades förrän i morgon."; return }
  # lärfas: pausreglerna och taken för antalet gäller först när learnTrades trades är avslutade
  $learning = $closedTr.Count -lt $RULES.learnTrades
  if ($learning) { "Lärfas: $($closedTr.Count) av $($RULES.learnTrades) trades avslutade. Ingen paus efter förluster och inget tak för antalet." }
  else {
    if (@($closedTr | Where-Object { [double]$_.closed -ge $today0 -and [double]$_.resultKr -lt 0 }).Count) { 'Förlust i dag: inga nya testtrades förrän i morgon.'; return }
    $last2 = @($closedTr | Select-Object -Last 2)
    if ($last2.Count -eq 2 -and @($last2 | Where-Object { [double]$_.resultKr -lt 0 }).Count -eq 2 -and [double]$last2[1].closed -ge $nowT - 86400) { 'Två förluster i rad: paus ett dygn.'; return }
    $weekR = (($closedTr | Where-Object { [double]$_.closed -ge $nowT - 7 * 86400 } | Measure-Object r -Sum).Sum)
    if ($null -ne $weekR -and $weekR -le $RULES.weeklyLossR) { "Veckan står på $(F $weekR 1) R: inga nya testtrades förrän den är bättre än $($RULES.weeklyLossR) R."; return }
  }
  # Fed och amerikansk KPI: ingen paus sedan 27 okt (Devin: "fortsätta köra dina trades och lära dig"); trades inom 24 timmar före märks med nearEvent
  $calFile = Join-Path $Dir 'makrokalender.json'
  $soon = @(); if (Test-Path $calFile) { $soon = @((Get-Content $calFile -Raw -Encoding UTF8 | ConvertFrom-Json).events | Where-Object { $et = $(if ($_.t -is [datetime]) { [DateTimeOffset]$_.t.ToUniversalTime() } else { [DateTimeOffset]::Parse($_.t, [Globalization.CultureInfo]::InvariantCulture) }).ToUnixTimeSeconds(); $et -gt $nowT -and $et -le $nowT + $RULES.eventNearH * 3600 } | Sort-Object { $(if ($_.t -is [datetime]) { [DateTimeOffset]$_.t.ToUniversalTime() } else { [DateTimeOffset]::Parse($_.t, [Globalization.CultureInfo]::InvariantCulture) }).ToUnixTimeSeconds() }) }
  $nearEv = if ($soon.Count) { [string]$soon[0].label } else { $null }
  $GATES = 'htf', 'events', 'confluence', 'discount', 'bos', 'stop', 'rr', 'invalidation', 'risk'
  foreach ($id in ($Open -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $pl = $plans[$id]
    if (-not $pl) { "NEJ $($id): ingen handelsplan. Skriv planen och kör med -Plan <fil.json> (se references\handelsplan.md)."; continue }
    $why = @()
    $hz = [string]$pl.horizon; if ($hz -notin 'swing', 'day') { $why += 'horisont saknas (swing eller day)'; $hz = 'swing' }
    foreach ($k in 'thesis', 'htf', 'level', 'trigger', 'invalidation', 'events', 'correlation', 'exit') { if (-not (Txt $pl.$k)) { $why += "planen saknar $k" } }
    if ((Txt $pl.thesis) -match 'UTKAST') { $why += 'planen är ett ogranskat utkast (skriv om thesis, events och against efter nyheterna)' }
    if (@($pl.confluence | Where-Object { Txt $_ }).Count -lt 2) { $why += 'färre än två verktyg i konfluensen' }
    if (@($pl.against | Where-Object { Txt $_ }).Count -lt 2) { $why += 'färre än två motargument' }
    $no = @($GATES | Where-Object { $pl.gates.$_ -ne $true }); if ($no.Count) { $why += "grind inte uppfylld: $($no -join ', ')" }
    $c = @($scan.candidates) + @($scan.soon) | Where-Object { $_ -and $_.id -eq $id } | Select-Object -First 1
    if (-not $c -and $hz -eq 'day' -and $pl.ysym) {
      $c = [pscustomobject]@{ id = $id; side = $(if ($pl.side -eq 'short') { 'short' } else { 'long' }); symbol = $pl.symbol; name = $pl.name; tv = $pl.tv; ysym = $pl.ysym; market = $pl.market; currency = $pl.currency; sector = $pl.sector; sectorSv = $pl.sectorSv; strategy = 'daytrade'; strategyName = 'Daytrade (egen setup)'; grade = 'egen'; score = $null; why = $pl.thesis; dec = $pl.dec; price = $pl.entry; earningsDays = $pl.earningsDays; entry = $null; stop = $null; t1 = $null; t2 = $null; t1Kind = 'nivå' }
    }
    if (-not $c) { "NEJ $($id): finns inte i senaste scanningen (en egen setup måste vara daytrade med ysym, market, entry, stop, t1 och t2 i planen)"; continue }
    if ($hz -eq 'day' -and $c.strategy -ne 'daytrade') { $c = $c.PSObject.Copy(); $c.strategy = 'daytrade'; $c.strategyName = "Daytrade ($($c.strategyName))" }
    $entry = if (Ok (N $pl.entry)) { [double]$pl.entry } else { N $c.entry }
    $stop = if (Ok (N $pl.stop)) { [double]$pl.stop } else { N $c.stop }
    $t1 = if (Ok (N $pl.t1)) { [double]$pl.t1 } else { N $c.t1 }
    $t2 = if (Ok (N $pl.t2)) { [double]$pl.t2 } else { N $c.t2 }
    $side = if ($c.side -eq 'short') { 'short' } else { 'long' }; $g = if ($side -eq 'short') { -1 } else { 1 }
    if (-not ((Ok $entry) -and (Ok $stop) -and (Ok $t1) -and $g * ($entry - $stop) -gt 0 -and $g * ($t1 - $entry) -gt 0)) { "NEJ $($id): entry, stopp och mål 1 saknas eller går inte ihop för en $(if ($g -lt 0) { 'blankning' } else { 'köp' })"; continue }
    if (-not (Ok $t2) -or $g * ($t2 - $t1) -le 0) { $t2 = $t1 + $g * [math]::Abs($entry - $stop) }
    $rr1 = $g * ($t1 - $entry) / [math]::Abs($entry - $stop); $rr2 = $g * ($t2 - $entry) / [math]::Abs($entry - $stop); $stopPct = [math]::Abs($entry - $stop) / $entry * 100
    # marknadsläget: inga nya köp i risk-off; halv risk i försiktig marknad (swing) och för blankningar i risk-on
    if ($side -eq 'long' -and $regime -eq 'Risk-off') { $why += 'risk-off: inga nya köp' }
    $riskPct = if ($side -eq 'short' -and $regime -eq 'Risk-on') { $RULES.riskPctCautious } elseif ($hz -eq 'day') { $RULES.riskPctDay } elseif ($regime -eq 'Försiktig') { $RULES.riskPctCautious } else { $RULES.riskPct }
    if ($side -eq 'short' -and (N $c.rsi) -lt 30) { $why += "RSI $(F $c.rsi 0): blanka inte in i översålt" }
    if (-not $learning -and $side -eq 'short' -and @($L.trades | Where-Object { $_.status -in 'väntar', 'öppen' -and $_.side -eq 'short' }).Count -ge $RULES.maxShorts) { $why += "redan $($RULES.maxShorts) blankningar" }
    if ($hz -eq 'swing') {
      if ($c.grade -ne 'A' -and -not ($AllowB -and $c.grade -eq 'B')) { $why += "betyg $($c.grade)" }
      if ($null -ne $c.earningsDays -and [int]$c.earningsDays -le 14) { $why += "rapport om $($c.earningsDays) dagar" }
      if ($stopPct -gt $RULES.swingMaxStopPct) { $why += "stopp $(F $stopPct 1) % bort" }
    } else {
      if ($null -ne $c.earningsDays -and [int]$c.earningsDays -le 1) { $why += 'rapport i dag eller i morgon' }
      if ($stopPct -gt $RULES.dayMaxStopPct) { $why += "stopp $(F $stopPct 1) % bort (daytrade högst $($RULES.dayMaxStopPct) %)" }
    }
    if ($rr1 -lt 1.995) { $why += "R/R 1:$(F $rr1 2)" }
    # Produkt: underliggande, turbo eller mini
    $ptype = if ($pl.product.type) { [string]$pl.product.type } else { 'underliggande' }
    $prod = [ordered]@{ type = $ptype; ko = $null; financing = $null; stopLoss = $null; lev = 1.0; capitalKr = $null }
    $fin = $null; $koL = $null
    switch ($ptype) {
      'underliggande' { }
      'turbo' { $fin = N $pl.product.ko; $koL = $fin; $prod.ko = $fin }
      'mini' { $fin = N $pl.product.financing; $koL = N $pl.product.stopLoss; $prod.financing = $fin; $prod.stopLoss = $koL; if ((Ok $fin) -and (Ok $koL) -and $g * ($koL - $fin) -le 0) { $why += $(if ($g -lt 0) { 'Mini S: stop loss-nivån ska ligga under finansieringsnivån' } else { 'minins stop loss-nivå ska ligga över finansieringsnivån' }) } }
      default { $why += "okänd produkt $ptype" }
    }
    if ($ptype -in 'turbo', 'mini') {
      if (-not ((Ok $fin) -and (Ok $koL) -and $g * ($entry - $fin) -gt 0)) { $why += 'knockout eller finansieringsnivå saknas eller ligger på fel sida' }
      else {
        $prod.lev = [math]::Round($entry / [math]::Abs($entry - $fin), 2); $koMax = $stop - $g * 0.5 * [math]::Abs($entry - $stop)
        if ($g * ($koL - $koMax) -gt 0) { $why += "knockout $(F $koL $c.dec) för nära stoppet (ska vara $(if ($g -lt 0) { 'över' } else { 'under' }) $(F $koMax $c.dec))" }
        $maxLev = if ($hz -eq 'day') { $RULES.maxLevDay } else { $RULES.maxLevSwing }
        if ($prod.lev -gt $maxLev) { $why += "hävstång $(F $prod.lev 1)x (högst $($maxLev)x för $hz)" }
      }
    }
    $active = @($L.trades | Where-Object { $_.status -in 'väntar', 'öppen' })
    if (@($active | Where-Object { $_.symbol -eq $c.symbol }).Count) { $why += 'redan aktiv' }
    # swing och daytrade räknas var för sig (antal aktiva, nya per dag och sektor); den totala risken räknas på allt
    $sameHz = @($active | Where-Object { $(if ($_.horizon -eq 'day') { 'day' } else { 'swing' }) -eq $hz })
    $maxAct = if ($hz -eq 'day') { $RULES.maxActiveDay } else { $RULES.maxActive }; $maxNew = if ($hz -eq 'day') { $RULES.maxNewDayPerDay } else { $RULES.maxNewPerDay }
    if (-not $learning -and $maxAct -gt 0 -and $sameHz.Count -ge $maxAct) { $why += "redan $($sameHz.Count) aktiva $(if ($hz -eq 'day') { 'daytrades' } else { 'swingtrades' })" }
    if ($c.sector -and @($sameHz | Where-Object { $_.sector -eq $c.sector }).Count -ge $RULES.maxPerSector) { $why += "redan $($RULES.maxPerSector) i sektorn $($c.sector)" }
    if (-not $learning -and @($L.trades | Where-Object { [double]$_.createdT -ge $today0 -and $(if ($_.horizon -eq 'day') { 'day' } else { 'swing' }) -eq $hz }).Count -ge $maxNew -and $maxNew -gt 0) { $why += "redan $maxNew nya $(if ($hz -eq 'day') { 'daytrades' } else { 'swingtrades' }) i dag" }
    $eq = Equity $L; $openRisk = (($active | Measure-Object riskKr -Sum).Sum)
    $riskKr = [math]::Round($eq * $riskPct / 100, 0)
    $maxRisk = if ($learning) { $RULES.maxOpenRiskPctLearn } else { $RULES.maxOpenRiskPct }
    if (($openRisk + $riskKr) / $eq * 100 -gt $maxRisk) { $why += "total risk över $maxRisk %" }
    if ($why.Count) { "NEJ $id ($($c.symbol)): $($why -join ', ')"; continue }
    $ccy = if ($c.currency) { [string]$c.currency } elseif ($c.market -eq 'Sverige') { 'SEK' } else { 'USD' }; $fx = Fx $ccy
    $perUnit = [math]::Abs($entry - $stop) * $fx
    $qty = $riskKr / $perUnit
    $capPerUnit = if ($null -ne $fin) { [math]::Abs($entry - $fin) * $fx } else { $entry * $fx }
    $maxQty = $eq * $RULES.maxPositionPct / 100 / $capPerUnit; if ($qty -gt $maxQty) { $qty = $maxQty }
    # hela aktier, utom krypto och daytrades i index och råvaror via certifikat (en turbo på DAX motsvarar t.ex. 0,01 index per certifikat)
    if ($c.market -eq 'Krypto' -or $pl.fractional -eq $true) { $qty = [math]::Round($qty, 6) } else { $qty = [math]::Floor($qty) }
    if ($qty -le 0) { "NEJ $($id): för dyr per aktie för risken"; continue }
    $prod.capitalKr = [math]::Round($qty * $capPerUnit, 0)
    $tplan = [ordered]@{}; foreach ($k in 'thesis', 'htf', 'level', 'trigger', 'invalidation', 'events', 'correlation', 'exit') { $tplan[$k] = Txt $pl.$k }
    $tplan.confluence = @($pl.confluence | Where-Object { Txt $_ }); $tplan.against = @($pl.against | Where-Object { Txt $_ }); $tplan.gates = $pl.gates
    $t = [pscustomobject][ordered]@{
      id = "pt-$($now.ToString('yyyyMMdd'))-$($c.id)"; side = $side; createdT = $nowT; created = $now.ToString('yyyy-MM-ddTHH:mm:ssZ'); symbol = $c.symbol; name = $c.name; tv = $c.tv; ysym = $c.ysym; market = $c.market; sector = $c.sector; sectorSv = $c.sectorSv
      strategy = $c.strategy; strategyName = $c.strategyName; grade = $c.grade; score = $c.score; regime = $regime; why = $c.why; take = $(if ($takes -and $c.id) { $takes.($c.id) } else { $null })
      horizon = $hz; productType = $ptype; product = [pscustomobject]$prod; dayEnd = $(if ($hz -eq 'day') { DayEnd $c.market $nowT } else { $null }); tplan = [pscustomobject]$tplan; nearEvent = $nearEv
      plan = [pscustomobject]@{ entry = $entry; stop = $stop; t1 = $t1; t2 = $t2; rr1 = [math]::Round($rr1, 2); rr2 = [math]::Round($rr2, 2); t1Kind = $c.t1Kind }
      currency = $ccy; fx = [math]::Round($fx, 4); qty = $qty; riskPct = $riskPct; riskKr = [math]::Round($qty * $perUnit, 0); dec = $c.dec
      status = 'väntar'; fill = $null; exits = @(); stopNow = $stop; t1done = $false; lastPrice = [double]$c.price; lastT = $nowT; mfeR = $null; maeR = $null; resultKr = $null; r = $null; closed = $null; reasonClosed = $null; daysHeld = $null; lesson = $null; scanT = $null
    }
    $L.trades = @($L.trades) + @($t)
    $kind = if ($hz -eq 'day') { 'daytrade' } else { 'swing' }; if ($side -eq 'short') { $kind = "blankning, $kind" }; if ($ptype -ne 'underliggande') { $kind += ", $(if ($side -eq 'short') { $ptype + ' S' } else { $ptype }) $(F $prod.lev 1)x" }
    Ev $t 'lagd' $nowT "$(if ($side -eq 'short') { 'Blankningsorder' } else { 'Köporder' }) ($($kind -replace '^blankning, ', '')): $(F $qty (QtyDec $qty)) st $($c.symbol) vid BOS $(F $entry $c.dec) $ccy, stopp $(F $stop $c.dec), mål $(F $t1 $c.dec).$(if ($nearEv) { " Läggs före $($nearEv)." }) Plan: $((Txt $pl.thesis).Substring(0, [math]::Min(60, (Txt $pl.thesis).Length)))"
    "JA  $id ($($c.symbol), $kind): $(if ($side -eq 'short') { 'blanka' } else { 'köp' }) $qty st vid BOS $entry $ccy, stopp $stop, mål $t1 / $t2, risk $($t.riskKr) kr ($riskPct %)$(if ($prod.capitalKr) { ", insats $($prod.capitalKr) kr" })$(if ($nearEv) { ", före $nearEv (märks i statistiken)" })"
  }
}
if ($Update -or $Open) {
  $errs = @()
  foreach ($t in @($L.trades | Where-Object { $_.status -in 'väntar', 'öppen' })) { try { Step $t } catch { $errs += "$($t.symbol): $($_.Exception.Message)"; "Kunde inte uppdatera $($t.symbol): $($_.Exception.Message)" } }
  # lärfasen klar: en händelse (som blir en notis) första gången learnTrades trades är avslutade
  if (-not ($L.PSObject.Properties.Name -contains 'learnDone') -and @($L.trades | Where-Object { $_.status -eq 'stängd' }).Count -ge $RULES.learnTrades) {
    $L | Add-Member learnDone $nowT -Force
    Ev ([pscustomobject]@{ id = 'larfas'; symbol = '' }) 'lärfas' $nowT "$($RULES.learnTrades) testtrades avslutade: lärfasen är klar. Pausreglerna, taken och högst 5 % total risk gäller igen. Dags att gå igenom statistiken."
  }
  [IO.File]::WriteAllText((Join-Path $Dir 'update-errors.json'), ([ordered]@{ at = $now.ToString('yyyy-MM-ddTHH:mm:ssZ'); errors = $errs } | ConvertTo-Json -Compress), $enc)
  $L.equity = @($L.equity) + , @($nowT, [math]::Round((Equity $L), 0))
  Save $L
  [IO.File]::WriteAllText((Join-Path $Dir 'events-new.json'), (ConvertTo-Json -InputObject @($script:NEW) -Depth 5 -Compress), $enc)
  $st = Export $L
  foreach ($e in $script:NEW) { "HÄNDELSE $($e.type): $($e.text)" }
  "Testportfölj: {0:N0} kr ({1:+0.00;-0.00} %), {2} öppna, {3} väntande, {4} stängda, träff {5} %" -f $st.equity, $st.returnPct, $st.open, $st.pending, $st.closed, $st.winRate
  foreach ($t in $L.trades | Where-Object { $_.status -in 'väntar', 'öppen' }) { "  {0,-7} {1,-8} {2} pris {3} entry {4} stopp {5} mål {6}" -f $t.status, $t.symbol, $t.strategyName, $t.lastPrice, $t.plan.entry, $t.stopNow, $t.plan.t1 }
}
