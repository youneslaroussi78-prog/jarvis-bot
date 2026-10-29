# Jarvis marknadsscanner. Hämtar från TradingViews scanner (börsvärdet är i marknadens egen valuta): USA (över 1 mdr USD),
# Sverige (över 1 mdr SEK, även First North), Norden (Norge, Danmark, Finland), Europa (Tyskland, Frankrike, Nederländerna,
# Belgien, Storbritannien, Schweiz, Italien, Spanien, Portugal, Österrike), Kanada och krypto (topp 300, utan stablecoins).
# Devin 25 okt: "utöka så mycket som möjligt". Kör strategibiblioteket, räknar plan (BOS/entry, stopp, mål, R/R), relativ
# styrka mot S&P 500 / OMXS30 / BTC / snittet på marknaden, betygsätter, kör djupanalysen på de attraktiva, hämtar
# kurshistorik för de bästa, följer upp tidigare scanningar och tar fram sektorrotation och rapportkalender.
# Körs: powershell -ExecutionPolicy Bypass -File scan.ps1 [-Out <mapp>] [-TopUS 12] [-TopSE 6] [-TopNO 5] [-TopEU 8] [-TopCA 3] [-TopCR 4]
# Skriver i <Out>: scan-latest.json, scan-stats.json, market-us.json, market-se.json, market-eu.json, market-crypto.json,
# market-sectors.json, market-earnings.json, hist-<id>.json, scans\<tid>.json
param([string]$Out = (Join-Path $PSScriptRoot '../data'), [int]$TopUS = 12, [int]$TopSE = 6, [int]$TopNO = 5, [int]$TopEU = 8, [int]$TopCA = 3, [int]$TopCR = 4, [int]$DeepN = 50)
$ErrorActionPreference = 'Stop'
$Out = [IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force $Out, (Join-Path $Out 'scans') | Out-Null
$TVH = @{ 'User-Agent' = 'Mozilla/5.0'; 'Origin' = 'https://www.tradingview.com' }
$TECH = @('RSI','RSI[1]','RSI2','MACD.macd','MACD.signal','SMA20','SMA50','SMA50[1]','SMA150','SMA200','SMA200[1]','EMA9','EMA20','EMA21','ATR','ADX','ADX[1]','ADX+DI','ADX-DI','BB.upper','BB.lower',
  'Perf.W','Perf.1M','Perf.3M','Perf.6M','Perf.YTD','High.1M','Low.1M','High.3M','Low.3M','price_52_week_high','price_52_week_low','Recommend.All','high','low','open','high[1]','low[1]')
$COLS = @('name','description','close','change','volume','relative_volume_10d_calc','market_cap_basic','sector','industry','gap','earnings_release_next_date','earnings_release_date','average_volume_10d_calc','currency') + $TECH
$CCOLS = @('name','description','close','change','volume','relative_volume_10d_calc','market_cap_calc','24h_vol_cmc','crypto_total_rank','base_currency') + $TECH
$now = (Get-Date).ToUniversalTime()
$stamp = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
$SV = @{ 'Electronic Technology' = 'Elektronik och halvledare'; 'Technology Services' = 'Mjukvara och IT-tjänster'; 'Finance' = 'Finans'; 'Health Technology' = 'Läkemedel och medicinteknik'
  'Retail Trade' = 'Detaljhandel'; 'Consumer Non-Durables' = 'Dagligvaror'; 'Consumer Durables' = 'Sällanköpsvaror'; 'Producer Manufacturing' = 'Verkstad och tillverkning'; 'Energy Minerals' = 'Olja och gas'
  'Utilities' = 'Kraft och el'; 'Communications' = 'Telekom'; 'Transportation' = 'Transport'; 'Process Industries' = 'Processindustri'; 'Non-Energy Minerals' = 'Gruvor och metaller'
  'Industrial Services' = 'Industritjänster'; 'Commercial Services' = 'Företagstjänster'; 'Health Services' = 'Vård'; 'Consumer Services' = 'Konsumenttjänster'; 'Distribution Services' = 'Distribution'; 'Miscellaneous' = 'Övrigt'; 'Krypto' = 'Krypto' }
$STABLE = @('USDT', 'USDC', 'DAI', 'FDUSD', 'USDE', 'TUSD', 'PYUSD', 'USD1', 'USDS', 'BUSD', 'USDD', 'FRAX', 'USDP', 'GUSD', 'EURC', 'RLUSD', 'USD0', 'USDTB', 'BUIDL', 'USYC', 'XAUT', 'PAXG', 'WBTC', 'WETH', 'STETH', 'WSTETH', 'WEETH', 'CBBTC', 'WBETH', 'RETH', 'LBTC', 'SOLVBTC', 'BSC-USD', 'SUSDE', 'SUSDS')

function N($v) { if ($null -eq $v -or $v -is [string]) { return [double]::NaN }; [double]$v }
function Ok([double]$v) { -not ([double]::IsNaN($v) -or [double]::IsInfinity($v)) }
function Rnd($v) { $v = N $v; if (-not (Ok $v)) { return $null }; $a = [math]::Abs($v); $p = if ($a -ge 1000) { 1 } elseif ($a -ge 100) { 2 } elseif ($a -ge 1) { 3 } elseif ($a -ge 0.01) { 5 } else { 8 }; [math]::Round($v, $p) }
function Dec($p) { if ($p -ge 1000) { 0 } elseif ($p -ge 10) { 2 } elseif ($p -ge 1) { 3 } elseif ($p -ge 0.01) { 4 } else { 6 } }
function F($v, $d) { (N $v).ToString("N$d", [Globalization.CultureInfo]::GetCultureInfo('sv-SE')) }
function Median($a) { $s = @($a | Where-Object { Ok (N $_) } | Sort-Object); if (-not $s.Count) { return $null }; if ($s.Count % 2) { $s[[int][math]::Floor($s.Count / 2)] } else { ($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2 } }
# TradingView svarar ibland 400 när många frågor kommer tätt: försök tre gånger
function Post($market, $body) { $j = $body | ConvertTo-Json -Depth 8 -Compress
  for ($try = 1; $try -le 3; $try++) { try { return Invoke-RestMethod -Method Post -Uri "https://scanner.tradingview.com/$market/scan" -Body $j -ContentType 'application/json' -Headers $TVH -TimeoutSec 90 } catch { if ($try -eq 3) { throw }; Start-Sleep -Seconds (4 * $try) } } }
function Rows($r, $cols) { foreach ($d in $r.data) { $o = [ordered]@{ tv = $d.s }; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $d.d[$i] }; [pscustomobject]$o } }
$stock = @(@{ left = 'type'; operation = 'equal'; right = 'stock' }, @{ left = 'is_primary'; operation = 'equal'; right = $true })
$US = @(Rows (Post 'america' @{ markets = @('america'); symbols = @{ query = @{ types = @() }; tickers = @() }; columns = $COLS; sort = @{ sortBy = 'market_cap_basic'; sortOrder = 'desc' }; range = @(0, 2800)
      filter = ($stock + @(@{ left = 'market_cap_basic'; operation = 'greater'; right = 1e9 }, @{ left = 'exchange'; operation = 'in_range'; right = @('NASDAQ', 'NYSE', 'AMEX') })) }) $COLS)
$SE = @(Rows (Post 'sweden' @{ markets = @('sweden'); symbols = @{ query = @{ types = @() }; tickers = @() }; columns = $COLS; sort = @{ sortBy = 'market_cap_basic'; sortOrder = 'desc' }; range = @(0, 800)
      filter = ($stock + @(@{ left = 'market_cap_basic'; operation = 'greater'; right = 1e9 }, @{ left = 'exchange'; operation = 'in_range'; right = @('OMXSTO') })) }) $COLS)
$CRall = @(Rows (Post 'coin' @{ markets = @('coin'); symbols = @{ query = @{ types = @() }; tickers = @() }; columns = $CCOLS; sort = @{ sortBy = 'crypto_total_rank'; sortOrder = 'asc' }; range = @(0, 320)
      filter = @(@{ left = 'crypto_total_rank'; operation = 'less'; right = 321 }) }) $CCOLS)
# Norden, Europa och Kanada (Devin 25 okt: "utöka så mycket som möjligt"). cap = lägsta börsvärde i marknadens valuta, ex = börser, y = Yahoo-suffix per börs.
$MKS = @(
  @{ tv = 'norway'; name = 'Norge'; region = 'Norden'; pre = 'no-'; cap = 1e9; ex = @('OSL'); y = @{ OSL = '.OL' } }
  @{ tv = 'denmark'; name = 'Danmark'; region = 'Norden'; pre = 'dk-'; cap = 1e9; ex = @('OMXCOP'); y = @{ OMXCOP = '.CO' } }
  @{ tv = 'finland'; name = 'Finland'; region = 'Norden'; pre = 'fi-'; cap = 1e8; ex = @('OMXHEX'); y = @{ OMXHEX = '.HE' } }
  @{ tv = 'germany'; name = 'Tyskland'; region = 'Europa'; pre = 'de-'; cap = 1e9; ex = @('XETR'); y = @{ XETR = '.DE' } }
  @{ tv = 'france'; name = 'Frankrike'; region = 'Europa'; pre = 'fr-'; cap = 1e9; ex = @('EURONEXT'); y = @{ EURONEXT = '.PA' } }
  @{ tv = 'netherlands'; name = 'Nederländerna'; region = 'Europa'; pre = 'nl-'; cap = 1e9; ex = @('EURONEXT'); y = @{ EURONEXT = '.AS' } }
  @{ tv = 'belgium'; name = 'Belgien'; region = 'Europa'; pre = 'be-'; cap = 1e9; ex = @('EURONEXT'); y = @{ EURONEXT = '.BR' } }
  @{ tv = 'uk'; name = 'Storbritannien'; region = 'Europa'; pre = 'uk-'; cap = 1e9; ex = @('LSE'); y = @{ LSE = '.L' } }
  @{ tv = 'switzerland'; name = 'Schweiz'; region = 'Europa'; pre = 'ch-'; cap = 1e9; ex = @('SIX'); y = @{ SIX = '.SW' } }
  @{ tv = 'italy'; name = 'Italien'; region = 'Europa'; pre = 'it-'; cap = 1e9; ex = @('MIL'); y = @{ MIL = '.MI' } }
  @{ tv = 'spain'; name = 'Spanien'; region = 'Europa'; pre = 'es-'; cap = 1e9; ex = @('BME'); y = @{ BME = '.MC' } }
  @{ tv = 'portugal'; name = 'Portugal'; region = 'Europa'; pre = 'pt-'; cap = 5e8; ex = @('EURONEXT'); y = @{ EURONEXT = '.LS' } }
  @{ tv = 'austria'; name = 'Österrike'; region = 'Europa'; pre = 'at-'; cap = 5e8; ex = @('VIE'); y = @{ VIE = '.VI' } }
  @{ tv = 'canada'; name = 'Kanada'; region = 'Kanada'; pre = 'ca-'; cap = 1e9; ex = @('TSX', 'TSXV'); y = @{ TSX = '.TO'; TSXV = '.V' } }
)
$XM = [ordered]@{}
foreach ($m in $MKS) {
  try { $XM[$m.name] = @(Rows (Post $m.tv @{ markets = @($m.tv); symbols = @{ query = @{ types = @() }; tickers = @() }; columns = $COLS; sort = @{ sortBy = 'market_cap_basic'; sortOrder = 'desc' }; range = @(0, 700)
        filter = ($stock + @(@{ left = 'market_cap_basic'; operation = 'greater'; right = $m.cap }, @{ left = 'exchange'; operation = 'in_range'; right = $m.ex })) }) $COLS) }
  catch { "Marknaden $($m.name) kunde inte hämtas: $($_.Exception.Message)"; $XM[$m.name] = @() }
  foreach ($r in $XM[$m.name]) { $r | Add-Member market $m.name -Force }
}
foreach ($r in $US) { $r | Add-Member market 'USA' -Force }; foreach ($r in $SE) { $r | Add-Member market 'Sverige' -Force }
$REGION = @{ 'USA' = 'USA'; 'Sverige' = 'Sverige'; 'Krypto' = 'Krypto' }; $IDPRE = @{ 'USA' = 'us-'; 'Sverige' = 'se-'; 'Krypto' = 'cr-' }; $YSUF = @{ 'USA' = @{}; 'Sverige' = @{ OMXSTO = '.ST' } }
foreach ($m in $MKS) { $REGION[$m.name] = $m.region; $IDPRE[$m.name] = $m.pre; $YSUF[$m.name] = $m.y }
# växelkurser till USD för likviditetskravet (GBX = pence); reservvärden om Yahoo inte svarar
$FX = @{ USD = 1.0; SEK = 0.1; NOK = 0.094; DKK = 0.155; EUR = 1.16; GBP = 1.33; CHF = 1.25; CAD = 0.71 }
foreach ($ccy in 'SEK', 'NOK', 'DKK', 'EUR', 'GBP', 'CHF', 'CAD') { try { $v = [double](Invoke-RestMethod "https://query2.finance.yahoo.com/v8/finance/chart/$($ccy)USD=X?range=1d&interval=1d" -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 20).chart.result[0].meta.regularMarketPrice; if ($v -gt 0) { $FX[$ccy] = $v } } catch { } }
$FX['GBX'] = $FX['GBP'] / 100
# lägsta dagsomsättning i USD per region
$LIQFLOOR = @{ 'USA' = 1e7; 'Sverige' = 3e5; 'Norden' = 5e5; 'Europa' = 2e6; 'Kanada' = 2e6; 'Krypto' = 2e7 }
$CR = @($CRall | Where-Object { $b = [string]$_.base_currency; $b -and $b -notin $STABLE -and -not ((N $_.close) -gt 0.97 -and (N $_.close) -lt 1.03 -and [math]::Abs((N $_.'Perf.3M')) -lt 2) } | ForEach-Object {
    $_ | Add-Member market_cap_basic $_.market_cap_calc -Force; $_ | Add-Member sector 'Krypto' -Force; $_ | Add-Member currency 'USD' -Force
    $_ | Add-Member average_volume_10d_calc ($(if ((N $_.close) -gt 0) { (N $_.'24h_vol_cmc') / (N $_.close) } else { 0 })) -Force; $_ })
$REG = @(Rows (Post 'global' @{ symbols = @{ tickers = @('SP:SPX', 'NASDAQ:NDX', 'TVC:VIX', 'TVC:DXY', 'TVC:US10Y', 'OMXSTO:OMXS30') }; columns = $COLS }) $COLS)
if ($REG.Count -lt 3) { throw 'Indexdata saknas, marknadsläget kan inte bedömas' }
$nXM = 0; foreach ($k in $XM.Keys) { $nXM += $XM[$k].Count }
"Universum: USA $($US.Count), Sverige $($SE.Count), Norden/Europa/Kanada $nXM ($((@($XM.Keys | ForEach-Object { "$_ $($XM[$_].Count)" })) -join ', ')), krypto $($CR.Count)"

# ---------- marknadsläge ----------
function Reg($t) { $REG | Where-Object { $_.tv -eq $t } | Select-Object -First 1 }
$spx = Reg 'SP:SPX'; $vix = Reg 'TVC:VIX'; $omx = Reg 'OMXSTO:OMXS30'; $btc = $CR | Where-Object { $_.base_currency -eq 'BTC' } | Select-Object -First 1
$sc = N $spx.close; $s50 = N $spx.SMA50; $s200 = N $spx.SMA200; $vc = N $vix.close
$regime = if ($sc -lt $s200 -or $vc -gt 25) { 'Risk-off' } elseif ($sc -lt $s50 -or $vc -ge 18) { 'Försiktig' } elseif ($sc -gt $s50 -and $s50 -gt $s200 -and $vc -lt 18) { 'Risk-on' } else { 'Neutral' }
$regimeText = switch ($regime) {
  'Risk-on' { 'S&P 500 över 50- och 200-dagars och VIX under 18. Setups får normal storlek.' }
  'Neutral' { 'S&P 500 över 200-dagars men utan tydlig riktning. Ta bara A- och B-setups.' }
  'Försiktig' { "S&P 500 under 50-dagars eller VIX på $(F $vc 1). Halvera storleken och kräv BOS med volym." }
  'Risk-off' { "S&P 500 under 200-dagars eller VIX över 25. Inga nya långa swingar utom A-setups, och då med halv storlek." }
}
$BENCH = @{ 'USA' = (N $spx.'Perf.3M'); 'Sverige' = (N $omx.'Perf.3M'); 'Krypto' = (N $btc.'Perf.3M') }
$BNAME = @{ 'USA' = 'S&P 500'; 'Sverige' = 'OMXS30'; 'Krypto' = 'BTC' }
# övriga marknader: relativ styrka mot medianen för marknadens egna aktier
foreach ($k in $XM.Keys) { $BENCH[$k] = N (Median @($XM[$k] | ForEach-Object { N $_.'Perf.3M' })); $BNAME[$k] = "snittet i $k" }
$idx = foreach ($t in 'SP:SPX', 'NASDAQ:NDX', 'TVC:VIX', 'TVC:DXY', 'TVC:US10Y', 'OMXSTO:OMXS30') { $x = Reg $t; if ($x) { [ordered]@{ tv = $t; name = @{ 'SP:SPX' = 'S&P 500'; 'NASDAQ:NDX' = 'Nasdaq 100'; 'TVC:VIX' = 'VIX'; 'TVC:DXY' = 'Dollarindex'; 'TVC:US10Y' = 'USA 10 år'; 'OMXSTO:OMXS30' = 'OMXS30' }[$t]; price = Rnd $x.close; chg = Rnd $x.change; rsi = Rnd $x.RSI; perf1m = Rnd $x.'Perf.1M'; perf3m = Rnd $x.'Perf.3M'; above50 = ((N $x.close) -gt (N $x.SMA50)); above200 = ((N $x.close) -gt (N $x.SMA200)) } } }

# ---------- strategier ----------
$STRAT = [ordered]@{
  pullback = 'Rekyl + absorption (BOS-metoden)'
  trend    = 'Trendledare nära toppen'
  breakout = 'Utbrott ur konsolidering'
  swing    = 'Swing-screener 1–2 veckor'
  accum    = 'Ackumulation (köpvolym)'
  gapgo    = 'Gap upp som håller'
  gcross   = 'Golden cross'
  oversold = 'Översåld i upptrend (RSI 2)'
  holygrail = 'Holy Grail (rekyl i stark trend)'
  # blankning (short), Devin 23 okt: "det är lika viktigt som att kunna köpa"
  sbounce = 'Blanka rekyl i nedtrend (BOS nedåt)'
  strend = 'Blanka svag trend (steg 4)'
  sbreak = 'Blanka utbrott nedåt'
  sgapdown = 'Blanka gap ned som håller'
  soverbought = 'Blanka överköpt i nedtrend (RSI 2)'
  sdcross = 'Blanka death cross'
}
$SHORTS = @('sbounce', 'strend', 'sbreak', 'sgapdown', 'soverbought', 'sdcross')
function Levels($entry, [double[]]$cands) { @($cands | Where-Object { (Ok $_) -and $_ -gt $entry * 1.006 } | Sort-Object -Unique) }
function MakePlan($key, $entry, $stop, $res, $why, $atr, $minAtr = 1.0) {
  if (-not ((Ok $entry) -and (Ok $stop) -and $entry -gt $stop)) { return $null }
  $res = @($res); if ((Ok $atr) -and ($entry - $stop) -lt $minAtr * $atr) { $stop = $entry - $minAtr * $atr }; $risk = $entry - $stop
  $t1Kind = 'nivå'; $t1 = $res[0]; $t2 = $res[1]
  if (-not (Ok (N $t1))) { $t1 = $entry + 2 * $risk; $t1Kind = '2R' }
  if (-not (Ok (N $t2)) -or $t2 -lt $t1 + 0.5 * $risk) { $t2 = [math]::Max($t1 + $risk, $entry + 3 * $risk) }
  [ordered]@{ key = $key; side = 'long'; entry = $entry; stop = $stop; t1 = [double]$t1; t2 = [double]$t2; t1Kind = $t1Kind; rr1 = ($t1 - $entry) / $risk; rr2 = ($t2 - $entry) / $risk; riskPct = $risk / $entry * 100; why = $why }
}
# blankning: stöd under entry som mål (närmast först), stopp ovanför
function LevelsS($entry, [double[]]$cands) { @($cands | Where-Object { (Ok $_) -and $_ -gt 0 -and $_ -lt $entry * 0.994 } | Sort-Object -Unique -Descending) }
function MakePlanS($key, $entry, $stop, $sup, $why, $atr, $minAtr = 1.0) {
  if (-not ((Ok $entry) -and (Ok $stop) -and $stop -gt $entry -and $entry -gt 0)) { return $null }
  $sup = @($sup); if ((Ok $atr) -and ($stop - $entry) -lt $minAtr * $atr) { $stop = $entry + $minAtr * $atr }; $risk = $stop - $entry
  $t1Kind = 'nivå'; $t1 = $sup[0]; $t2 = $sup[1]
  if (-not (Ok (N $t1))) { $t1 = $entry - 2 * $risk; $t1Kind = '2R' }
  if (-not (Ok (N $t2)) -or $t2 -gt $t1 - 0.5 * $risk) { $t2 = [math]::Min($t1 - $risk, $entry - 3 * $risk) }
  if ($t1 -le 0 -or $t2 -le 0) { return $null }
  [ordered]@{ key = $key; side = 'short'; entry = $entry; stop = $stop; t1 = [double]$t1; t2 = [double]$t2; t1Kind = $t1Kind; rr1 = ($entry - $t1) / $risk; rr2 = ($entry - $t2) / $risk; riskPct = $risk / $entry * 100; why = $why }
}
function Evaluate($x, $mkt, $p6rank) {
  $c = N $x.close; $hi = N $x.high; $lo = N $x.low; $op = N $x.open; $h1 = N $x.'high[1]'; $l1 = N $x.'low[1]'; $atr = N $x.ATR
  $e21 = N $x.EMA21; $s20 = N $x.SMA20; $s50 = N $x.SMA50; $s50p = N $x.'SMA50[1]'; $s150 = N $x.SMA150; $s200 = N $x.SMA200; $s200p = N $x.'SMA200[1]'
  $wH = N $x.price_52_week_high; $wL = N $x.price_52_week_low; $H1M = N $x.'High.1M'; $H3M = N $x.'High.3M'
  $rsi = N $x.RSI; $rsi2 = N $x.RSI2; $macd = N $x.'MACD.macd'; $sig = N $x.'MACD.signal'; $p3 = N $x.'Perf.3M'; $rv = N $x.relative_volume_10d_calc; $chg = N $x.change; $gap = N $x.gap
  $bbU = N $x.'BB.upper'; $bbL = N $x.'BB.lower'
  if (-not ((Ok $c) -and (Ok $atr) -and (Ok $s200) -and $atr -gt 0)) { return $null }
  # dagsomsättning i USD (lokal valuta gånger växelkurs; krypto är redan i USD)
  $fxu = $FX[[string]$x.currency]; if (-not $fxu) { return $null }
  $liq = (N $x.average_volume_10d_calc) * $c * $fxu
  $minLiq = $LIQFLOOR[$REGION[$mkt]]
  if (-not (Ok $liq) -or -not $minLiq -or $liq -lt $minLiq) { return $null }
  $up = $c -gt $s200 -and $s50 -gt $s200
  $stage2 = $c -gt $s50 -and $s50 -gt $s150 -and $s150 -gt $s200 -and $s200 -ge $s200p -and $c -ge 0.75 * $wH -and $c -ge 1.3 * $wL
  $pos = if ($hi -gt $lo) { ($c - $lo) / ($hi - $lo) } else { 0.5 }
  $supLo = [math]::Min($e21, $s50); $supHi = [math]::Max($e21, $s50)
  $ed = $null; $eDays = 999; $lastE = 999
  if ($x.earnings_release_next_date) { $ed = [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.earnings_release_next_date).UtcDateTime; $eDays = [math]::Floor(($ed - $now).TotalDays) }
  if ($x.earnings_release_date) { $lastE = [math]::Floor(($now - [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.earnings_release_date).UtcDateTime).TotalDays) }
  $rs3 = $p3 - $BENCH[$mkt]
  $d = Dec $c
  $plans = @()
  if ($up -and $lo -le $supHi * 1.01 -and $c -ge $supLo * 0.985 -and $pos -ge 0.5 -and $rsi -ge 38 -and $rsi -le 56) {
    $entry = [math]::Max($hi, $h1) + 0.05 * $atr; $stop = [math]::Min($lo, $l1) - 0.25 * $atr
    $plans += MakePlan 'pullback' $entry $stop (Levels $entry @($H1M, $H3M, $wH)) -atr $atr -why "Rekylerade till EMA21/SMA50 ($(F $supLo $d)–$(F $supHi $d)) och stängde i övre $([math]::Round($pos*100)) % av dagens spann. Upptrend över 200-dagars. BOS = stängning över de två senaste dagarnas topp."
  }
  if ($stage2 -and $rsi -ge 55 -and $rsi -le 72 -and (($wH - $c) / $c) -le 0.08 -and $p3 -ge 15) {
    $trig = if ((($H1M - $c) / $c) -le 0.04 -and $H1M -gt $c) { $H1M } else { [math]::Max($hi, $h1) }
    $entry = $trig + 0.05 * $atr; $stop = [math]::Max($e21 - 0.5 * $atr, $entry - 3 * $atr); if ($stop -ge $entry - 0.8 * $atr) { $stop = $entry - 1.5 * $atr }
    $plans += MakePlan 'trend' $entry $stop (Levels $entry @($wH)) -atr $atr -why "Steg 2-trend (över 50 > 150 > 200-dagars, 200-dagars stiger), +$(F $p3 0) % på 3 mån och $(F ((($wH - $c) / $c) * 100) 1) % från årshögsta. Stopp under EMA21."
  }
  if ($up -and $H3M -ge $c -and (($H3M - $c) / $c) -le 0.035 -and $s20 -gt 0 -and (($bbU - $bbL) / $s20) -le 0.09 -and $rsi -ge 50 -and $rsi -le 70) {
    $entry = $H3M + 0.05 * $atr; $stop = [math]::Max($bbL, $entry - 2.5 * $atr); if ($stop -ge $entry - 0.8 * $atr) { $stop = $entry - 1.5 * $atr }
    $plans += MakePlan 'breakout' $entry $stop (Levels $entry @($wH)) -atr $atr -why "Tight konsolidering (Bollingerbredd $(F ((($bbU - $bbL) / $s20) * 100) 1) %) $(F ((($H3M - $c) / $c) * 100) 1) % under 3-månadershögsta $(F $H3M $d). Utbrott med volym är signalen."
  }
  if ($up -and $rsi -ge 40 -and $rsi -le 62 -and $p3 -ge 10 -and ([math]::Abs($c - $s50) / $s50) -le 0.03 -and $macd -gt $sig -and $eDays -gt 10) {
    $entry = [math]::Max($hi, $h1) + 0.05 * $atr; $stop = $s50 - 0.5 * $atr
    $plans += MakePlan 'swing' $entry $stop (Levels $entry @($H3M, $wH)) -atr $atr -why "Uppfyller swing-screenern: över 200-dagars, 50 > 200, RSI $(F $rsi 0), +$(F $p3 0) % på 3 mån, nära 50-dagars, MACD över signal och ingen rapport inom 10 dagar."
  }
  if ($c -gt $s50 -and $s50 -gt $s200 -and $rv -ge 2 -and $chg -ge 2 -and $pos -ge 0.75 -and $rsi -le 74) {
    $entry = $hi + 0.05 * $atr; $stop = $lo - 0.25 * $atr
    $plans += MakePlan 'accum' $entry $stop (Levels $entry @($H1M, $H3M, $wH)) -atr $atr -why "Stark dag (+$(F $chg 1) %) på $(F $rv 1) gånger normal volym och stängning nära dagens topp i en upptrend: tecken på att stora köpare går in. Fortsättning bekräftas över dagens topp."
  }
  if ((Ok $gap) -and $gap -ge 3 -and $c -ge $op -and $pos -ge 0.6 -and $rv -ge 1.5 -and $c -gt $s50) {
    $after = if ($lastE -le 3) { 'efter rapporten ' } else { '' }
    $entry = $hi + 0.05 * $atr; $stop = [math]::Min($op, $lo) - 0.25 * $atr
    $plans += MakePlan 'gapgo' $entry $stop (Levels $entry @($H3M, $wH)) -atr $atr -why "Gap upp $(F $gap 1) % $($after)som höll: stängde över öppningen på $(F $rv 1) gånger normal volym. Sådana gap fortsätter ofta i dagar till veckor (drift). Stopp under gapets botten."
  }
  if ((Ok $s50p) -and $s50p -le $s200p -and $s50 -gt $s200 -and $c -gt $s50) {
    $entry = [math]::Max($hi, $h1) + 0.05 * $atr; $stop = [math]::Min($s50, $s200) - 0.5 * $atr
    $plans += MakePlan 'gcross' $entry $stop (Levels $entry @($H3M, $wH)) -atr $atr -why "Golden cross i dag: 50-dagars korsade över 200-dagars och kursen ligger över båda. Långsam men bred trendsignal."
  }
  if ($c -gt $s200 -and $s50 -gt $s200 -and $rsi2 -le 10 -and $p3 -gt 0) {
    $entry = $hi + 0.05 * $atr; $stop = $lo - 0.5 * $atr
    $plans += MakePlan 'oversold' $entry $stop (Levels $entry @($s20, $H1M)) -atr $atr -minAtr 0.6 -why "RSI(2) på $(F $rsi2 0) i en upptrend: kortsiktigt översåld. Studs-trade, inte swing. Entry först när kursen tar sig över dagens topp."
  }
  # Holy Grail (Linda Raschke, Tradingbibeln): ADX(14) över 30 och stigande, rekyl till 20 EMA, köpstopp över rekyldagens topp
  $e20 = N $x.EMA20; $adx = N $x.ADX; $adxp = N $x.'ADX[1]'; $pdi = N $x.'ADX+DI'; $mdi = N $x.'ADX-DI'
  if ($up -and (Ok $e20) -and $adx -ge 30 -and $adx -ge $adxp -and $pdi -gt $mdi -and $lo -le $e20 * 1.005 -and $c -ge $e20 * 0.99) {
    $entry = $hi + 0.05 * $atr; $stop = $lo - 0.25 * $atr
    $plans += MakePlan 'holygrail' $entry $stop (Levels $entry @($H1M, $H3M, $wH)) -atr $atr -why "Stark trend (ADX $(F $adx 0) och stigande, +DI över −DI) som rekylerat till 20 EMA ($(F $e20 $d)). Raschkes Holy Grail: köp först över rekyldagens topp, stopp under dess lägsta, mål senaste toppen."
  }
  # ---------- blankning: spegelbilden av köpstrategierna, BOS nedåt = stängning under senaste lägsta ----------
  $L1M = N $x.'Low.1M'; $L3M = N $x.'Low.3M'
  $down = $c -lt $s200 -and $s50 -lt $s200
  $stage4 = $c -lt $s50 -and $s50 -lt $s150 -and $s150 -lt $s200 -and $s200 -le $s200p -and $c -le 0.75 * $wH -and $c -le 1.3 * $wL
  $resLo = [math]::Min($e21, $s50); $resHi = [math]::Max($e21, $s50)
  if ($down -and $hi -ge $resLo * 0.99 -and $c -le $resHi * 1.015 -and $pos -le 0.5 -and $rsi -ge 44 -and $rsi -le 62) {
    $entry = [math]::Min($lo, $l1) - 0.05 * $atr; $stop = [math]::Max($hi, $h1) + 0.25 * $atr
    $plans += MakePlanS 'sbounce' $entry $stop (LevelsS $entry @($L1M, $L3M, $wL)) -atr $atr -why "Rekylerade upp till motståndet EMA21/SMA50 ($(F $resLo $d)–$(F $resHi $d)) i en nedtrend och stängde i nedre $([math]::Round($pos*100)) % av dagens spann (säljare försvarar nivån). BOS nedåt = stängning under de två senaste dagarnas lägsta."
  }
  if ($stage4 -and $rsi -ge 28 -and $rsi -le 45 -and (($c - $wL) / $c) -le 0.08 -and $p3 -le -15) {
    $trig = if ((($c - $L1M) / $c) -le 0.04 -and $L1M -lt $c) { $L1M } else { [math]::Min($lo, $l1) }
    $entry = $trig - 0.05 * $atr; $stop = [math]::Min($e21 + 0.5 * $atr, $entry + 3 * $atr); if ($stop -le $entry + 0.8 * $atr) { $stop = $entry + 1.5 * $atr }
    $plans += MakePlanS 'strend' $entry $stop (LevelsS $entry @($wL)) -atr $atr -why "Steg 4-trend (under 50 < 150 < 200-dagars, 200-dagars faller), $(F $p3 0) % på 3 mån och $(F ((($c - $wL) / $c) * 100) 1) % från årslägsta. Stopp över EMA21."
  }
  if ($down -and $L3M -le $c -and (($c - $L3M) / $c) -le 0.035 -and $s20 -gt 0 -and (($bbU - $bbL) / $s20) -le 0.09 -and $rsi -ge 30 -and $rsi -le 50) {
    $entry = $L3M - 0.05 * $atr; $stop = [math]::Min($bbU, $entry + 2.5 * $atr); if ($stop -le $entry + 0.8 * $atr) { $stop = $entry + 1.5 * $atr }
    $plans += MakePlanS 'sbreak' $entry $stop (LevelsS $entry @($wL)) -atr $atr -why "Tight konsolidering (Bollingerbredd $(F ((($bbU - $bbL) / $s20) * 100) 1) %) $(F ((($c - $L3M) / $c) * 100) 1) % över 3-månaderslägsta $(F $L3M $d) i en nedtrend. Brott nedåt med volym är signalen."
  }
  if ((Ok $gap) -and $gap -le -3 -and $c -le $op -and $pos -le 0.4 -and $rv -ge 1.5 -and $c -lt $s50) {
    $after = if ($lastE -le 3) { 'efter rapporten ' } else { '' }
    $entry = $lo - 0.05 * $atr; $stop = [math]::Max($op, $hi) + 0.25 * $atr
    $plans += MakePlanS 'sgapdown' $entry $stop (LevelsS $entry @($L3M, $wL)) -atr $atr -why "Gap ned $(F ([math]::Abs($gap)) 1) % $($after)som höll: stängde under öppningen på $(F $rv 1) gånger normal volym. Sådana gap fortsätter ofta nedåt i dagar (negativ drift). Stopp över gapets topp."
  }
  if ($c -lt $s200 -and $s50 -lt $s200 -and $rsi2 -ge 90 -and $p3 -lt 0) {
    $entry = $lo - 0.05 * $atr; $stop = $hi + 0.5 * $atr
    $plans += MakePlanS 'soverbought' $entry $stop (LevelsS $entry @($s20, $L1M)) -atr $atr -minAtr 0.6 -why "RSI(2) på $(F $rsi2 0) i en nedtrend: kortsiktigt överköpt. Blankning på studsen, inte swing. Entry först när kursen bryter under dagens lägsta."
  }
  if ((Ok $s50p) -and $s50p -ge $s200p -and $s50 -lt $s200 -and $c -lt $s50) {
    $entry = [math]::Min($lo, $l1) - 0.05 * $atr; $stop = [math]::Max($s50, $s200) + 0.5 * $atr
    $plans += MakePlanS 'sdcross' $entry $stop (LevelsS $entry @($L3M, $wL)) -atr $atr -why "Death cross i dag: 50-dagars korsade under 200-dagars och kursen ligger under båda. Långsam men bred trendsignal nedåt."
  }
  $plans = @($plans | Where-Object { $_ -and ($_.t1Kind -eq '2R' -or $_.rr1 -ge 1.5) -and $_.riskPct -le 15 })
  if (-not $plans.Count) { return $null }
  $best = $null; $bestScore = -999
  foreach ($p in $plans) {
    $s = 0; $sh = $p.side -eq 'short'
    if ($p.t1Kind -eq 'nivå') { $s += if ($p.rr1 -ge 3) { 25 } elseif ($p.rr1 -ge 2) { 18 } else { 8 } } else { $s += 10 }
    $dist = if ($sh) { ($c - $p.entry) / $c * 100 } else { ($p.entry - $c) / $c * 100 }
    if ($dist -le 1.5) { $s += 10 } elseif ($dist -le 3) { $s += 5 }
    if ($eDays -le 7) { $s -= 20 } elseif ($eDays -le 14) { $s -= 10 }
    if ($p.riskPct -gt 8) { $s -= 8 }
    if ($mkt -eq 'Krypto') { $s -= 3 }
    if (-not $sh) {
      if ($stage2) { $s += 15 } elseif ($up) { $s += 8 }
      $s += [math]::Round(15 * $p6rank)
      if (Ok $rs3) { if ($rs3 -ge 10) { $s += 5 } elseif ($rs3 -le -10) { $s -= 3 } }
      if ($rv -ge 1.2 -and $chg -gt 0) { $s += 5 }
      if ($pos -ge 0.65) { $s += 5 }
      if ((N $x.'Recommend.All') -gt 0.1) { $s += 5 } elseif ((N $x.'Recommend.All') -lt -0.3) { $s -= 5 }
      if ($rsi -gt 72) { $s -= 10 }
      if ($regime -eq 'Risk-off' -and $p.key -ne 'oversold') { $s -= 8 } elseif ($regime -eq 'Försiktig' -and $p.key -in 'trend', 'breakout', 'gcross', 'holygrail') { $s -= 4 }
      if ($p.key -eq 'pullback') { $s += 5 } elseif ($p.key -in 'accum', 'gapgo') { $s += 3 }
    } else {
      # spegelbild: svag trend, relativ svaghet, säljvolym, stängning nära botten; aldrig blanka in i översålt
      if ($stage4) { $s += 15 } elseif ($down) { $s += 8 }
      $s += [math]::Round(15 * (1 - $p6rank))
      if (Ok $rs3) { if ($rs3 -le -10) { $s += 5 } elseif ($rs3 -ge 10) { $s -= 3 } }
      if ($rv -ge 1.2 -and $chg -lt 0) { $s += 5 }
      if ($pos -le 0.35) { $s += 5 }
      if ((N $x.'Recommend.All') -lt -0.1) { $s += 5 } elseif ((N $x.'Recommend.All') -gt 0.3) { $s -= 5 }
      if ($rsi -lt 28) { $s -= 10 }
      if ($regime -eq 'Risk-on') { $s -= 8 } elseif ($regime -eq 'Neutral') { $s -= 4 } elseif ($regime -eq 'Risk-off') { $s += 4 }
      if ($p.key -eq 'sbounce') { $s += 5 } elseif ($p.key -eq 'sgapdown') { $s += 3 }
    }
    $p.score = [math]::Max(0, [math]::Min(100, $s))
    if ($p.score -gt $bestScore) { $best = $p; $bestScore = $p.score }
  }
  $flags = @(); $isShort = $best.side -eq 'short'
  if ($isShort) { $flags += 'Blankning: risk för short squeeze vid goda nyheter' }
  if ($eDays -le 14) { $flags += "Rapport om $eDays dagar" }
  if ($best.t1Kind -eq 'nivå' -and $best.rr1 -lt 1.995) { $flags += 'Under 1:2 till första mål' }
  if (-not $isShort -and $rsi -gt 70) { $flags += 'RSI över 70' }
  if ($isShort -and $rsi -lt 30) { $flags += 'RSI under 30: översåld' }
  if ($best.riskPct -gt 8) { $flags += "Brett stopp ($(F $best.riskPct 1) %)" }
  if ($best.t1Kind -eq '2R') { $flags += $(if ($isShort) { 'Inget stöd under, mål = 2R' } else { 'Inget motstånd ovanför, mål = 2R' }) }
  if (-not $isShort -and (Ok $rs3) -and $rs3 -le -10) { $flags += "Svagare än $($BNAME[$mkt])" }
  if ($isShort -and (Ok $rs3) -and $rs3 -ge 10) { $flags += "Starkare än $($BNAME[$mkt])" }
  if ($regime -in 'Risk-off', 'Försiktig' -and $mkt -ne 'Krypto') { $flags += "Marknaden: $regime" }
  if ($mkt -eq 'Krypto') { $flags += 'Krypto: dygnet runt, större svängningar' }
  $tick = if ($mkt -eq 'Krypto') { [string]$x.base_currency } else { ($x.tv -split ':')[1] }
  $pre = $IDPRE[$mkt]
  $id = (($pre + $tick).ToLower() -replace '[^a-z0-9\-]', '-')
  # Yahoo-symbol: aktieklass och punkt blir bindestreck (HEXA_B → HEXA-B.ST, BT.A → BT-A.L, BRK.B → BRK-B) plus börsens suffix
  $ysym = if ($mkt -eq 'Krypto') { "$tick-USD" } else { ($tick -replace '[_\.]', '-') + [string]$YSUF[$mkt][($x.tv -split ':')[0]] }
  $grade = if ($best.score -ge 65) { 'A' } elseif ($best.score -ge 50) { 'B' } elseif ($best.score -ge 38) { 'C' } else { 'D' }
  # betyget följer Devins regler: under 1:2, rapport inom 14 dagar eller RSI över 72 ger högst B, rapport inom 7 dagar högst C
  if ($grade -eq 'A' -and (($best.t1Kind -eq 'nivå' -and $best.rr1 -lt 1.995) -or $eDays -le 14 -or (-not $isShort -and $rsi -gt 72) -or ($isShort -and $rsi -lt 28))) { $grade = 'B' }
  if ($grade -in 'A', 'B' -and $eDays -le 7) { $grade = 'C' }
  [ordered]@{
    id = $id; tv = $x.tv; ysym = $ysym; symbol = $tick; name = $x.description; market = $mkt; region = $REGION[$mkt]; sector = $x.sector; sectorSv = $SV[[string]$x.sector]; industry = $x.industry; currency = $x.currency; dec = $d
    price = Rnd $c; chg = Rnd $chg; low = Rnd $lo; high = Rnd $hi
    side = $best.side; strategy = $best.key; strategyName = $STRAT[$best.key]; strategies = @($plans | ForEach-Object { $_.key })
    score = [int]$best.score; grade = $grade
    entry = Rnd $best.entry; stop = Rnd $best.stop; t1 = Rnd $best.t1; t2 = Rnd $best.t2; t1Kind = $best.t1Kind
    rr1 = [math]::Round($best.rr1, 2); rr2 = [math]::Round($best.rr2, 2); riskPct = [math]::Round($best.riskPct, 2); distPct = [math]::Round($(if ($isShort) { ($c - $best.entry) / $c * 100 } else { ($best.entry - $c) / $c * 100 }), 2)
    why = $best.why; flags = $flags
    earnings = $(if ($ed) { $ed.ToString('yyyy-MM-dd') } else { $null }); earningsDays = $(if ($ed) { [int]$eDays } else { $null })
    rsi = Rnd $rsi; rsi2 = Rnd $rsi2; macd = Rnd $macd; macdSig = Rnd $sig; sma20 = Rnd $s20; sma50 = Rnd $s50; sma200 = Rnd $s200; ema21 = Rnd $e21; atr = Rnd $atr
    relVol = Rnd $rv; perf3m = Rnd $p3; perf6m = Rnd $x.'Perf.6M'; rs3 = Rnd $rs3; bench = $BNAME[$mkt]; d52 = [math]::Round(($wH - $c) / $c * 100, 1); rating = Rnd $x.'Recommend.All'
    s1 = $(if ($isShort) { @((Rnd $best.t1)) } else { @((Rnd $supLo), (Rnd $supHi)) }); s2 = $(if ($isShort) { @((Rnd $best.t2)) } else { @((Rnd $s200)) })
    r1 = $(if ($isShort) { @((Rnd $resLo), (Rnd $resHi)) } else { @((Rnd $best.t1)) }); r2 = $(if ($isShort) { @((Rnd $s200)) } else { @((Rnd $best.t2)) }); bos = Rnd $best.entry; inval = Rnd $best.stop
    s1n = $(if ($isShort) { 'mål 1' } else { 'EMA21–SMA50' }); s2n = $(if ($isShort) { 'mål 2' } else { '200-dagars' }); r1n = $(if ($isShort) { 'EMA21–SMA50' } else { 'mål 1' }); r2n = $(if ($isShort) { '200-dagars' } else { 'mål 2' })
    bosText = $(if ($isShort) { "stängning under $(F $best.entry $d)" } else { "stängning över $(F $best.entry $d)" }); invalText = $(if ($isShort) { "över $(F $best.stop $d)" } else { "under $(F $best.stop $d)" })
  }
}
function Rank($rows) { $vals = @($rows | ForEach-Object { N $_.'Perf.6M' } | Where-Object { Ok $_ } | Sort-Object); $map = @{}; foreach ($r in $rows) { $v = N $r.'Perf.6M'; $map[$r.tv] = if ((Ok $v) -and $vals.Count) { ([array]::BinarySearch([double[]]$vals, $v) -as [double]) / $vals.Count } else { 0 }; if ($map[$r.tv] -lt 0) { $map[$r.tv] = 0.5 } }; $map }
$rkUS = Rank $US; $rkSE = Rank $SE; $rkCR = Rank $CR
$cUS = @($US | ForEach-Object { Evaluate $_ 'USA' $rkUS[$_.tv] } | Where-Object { $_ })
$cSE = @($SE | ForEach-Object { Evaluate $_ 'Sverige' $rkSE[$_.tv] } | Where-Object { $_ })
$WATCH = @('BTC', 'ETH', 'SOL', 'XRP')
# De fyra stora i bevakningslistan scannas också (likvidast, bäst för testportföljen); kandidaten märks så att den jämförs med nivåerna
$cCR = @($CR | ForEach-Object { Evaluate $_ 'Krypto' $rkCR[$_.tv] } | Where-Object { $_ })
foreach ($c in $cCR) { if ($c.symbol -in $WATCH) { $c.flags = @($c.flags) + 'Finns i bevakningslistan: jämför med nivåerna där' } }
$cNO = @(); $cEU = @(); $cCA = @()
foreach ($m in $MKS) { $rows = $XM[$m.name]; if (-not $rows.Count) { continue }; $rk = Rank $rows
  $cc = @($rows | ForEach-Object { Evaluate $_ $m.name $rk[$_.tv] } | Where-Object { $_ })
  switch ($m.region) { 'Norden' { $cNO += $cc } 'Europa' { $cEU += $cc } 'Kanada' { $cCA += $cc } } }

# ---------- djupanalys: bibelns verktyg på riktig kurshistorik för de attraktiva lägena (A/B nära sin trigger) ----------
. (Join-Path $PSScriptRoot 'djupanalys.ps1')
$SETUPN = [ordered]@{ fvg = 'FVG eller order block i entryzonen (SMC)'; sweep = 'Likviditetssweep och återtagning'; turtle = 'Turtle-utbrott (Donchian 20/55)'; squeeze = 'TTM Squeeze avfyrad'
  weinstein = 'Weinstein steg 2/4'; ep = 'Episodic pivot'; nr7 = 'NR7 / inside day'; div = 'RSI-divergens' }
function Regrade($c) {
  $s = [int]$c.score; $g = if ($s -ge 65) { 'A' } elseif ($s -ge 50) { 'B' } elseif ($s -ge 38) { 'C' } else { 'D' }
  $ed = if ($null -ne $c.earningsDays) { [int]$c.earningsDays } else { 999 }; $sh = $c.side -eq 'short'; $r = N $c.rsi
  if ($g -eq 'A' -and (($c.t1Kind -eq 'nivå' -and $c.rr1 -lt 1.995) -or $ed -le 14 -or (-not $sh -and $r -gt 72) -or ($sh -and $r -lt 28))) { $g = 'B' }
  if ($g -in 'A', 'B' -and $ed -le 7) { $g = 'C' }
  $g
}
$pool = @($cUS + $cSE + $cNO + $cEU + $cCA + $cCR | Where-Object { $_.grade -in 'A', 'B' -and $_.distPct -ge -2 -and $_.distPct -le 8 } | Sort-Object { -$_.score } | Select-Object -First $DeepN)
$BARS = @{}; $nDeep = 0
foreach ($c in $pool) {
  try {
    $y = $c.ysym; if (-not $BARS.ContainsKey($y)) { $BARS[$y] = DeepBars $y }
    $dp = Deep $BARS[$y].d $BARS[$y].h @{ side = $c.side; entry = [double]$c.entry; stop = [double]$c.stop; t1 = [double]$c.t1 } $c.dec $c.strategy
    if (-not $dp) { continue }
    $nDeep++; $c.deep = $dp; $c.scoreBase = $c.score
  } catch { "Djupanalys saknas för $($c.symbol): $($_.Exception.Message)" }
}
# Justeringen görs relativ (minus medianen för dagens lägen), så att djupanalysen rangordnar men inte blåser upp betygen:
# nästan alla lägen har något verktyg i närheten, så bara de som är bättre än de andra ska lyftas
$medAdj = Median @($pool | Where-Object { $_.deep } | ForEach-Object { $_.deep.adj }); if ($null -eq $medAdj) { $medAdj = 0 }
foreach ($c in @($pool | Where-Object { $_.deep })) {
  try {
    $dp = $c.deep; $dp.adjRaw = $dp.adj; $dp.adj = [int][math]::Round([math]::Max(-10, [math]::Min(10, $dp.adj - $medAdj)))
    $c.score = [int][math]::Max(0, [math]::Min(100, $c.score + $dp.adj)); $c.grade = Regrade $c
    $al = @($dp.setups | Where-Object { $_.side -eq $c.side -or $_.side -eq 'both' })
    $c.setups = @($al | ForEach-Object { $_.k } | Select-Object -Unique)
    $c.strategies = @(@($c.strategies) + $c.setups | Select-Object -Unique)
    if ($dp.confl -ge 3) { $c.flags = @($c.flags) + "Konfluens $($dp.confl): $(($dp.fams) -join ', ')" } elseif ($dp.confl -eq 0) { $c.flags = @($c.flags) + 'Ingen konfluens i entryzonen' }
    if ($dp.obstacle) { $c.flags = @($c.flags) + "Hinder: $($dp.obstacle)" }
    foreach ($w in @($dp.why | Where-Object { $_ -like 'emot:*' -or $_ -like 'veckotrenden*' })) { $c.flags = @($c.flags) + ($w.Substring(0, 1).ToUpper() + $w.Substring(1)) }
  } catch { "Djupanalysen kunde inte räknas in för $($c.symbol): $($_.Exception.Message)" }
}
"Djupanalys: $nDeep av $($pool.Count) attraktiva lägen (median för justeringen $medAdj)"
function Pick($list, $n) { $out = @(); $bySector = @{}; foreach ($c in ($list | Sort-Object { -$_.score }, { -$_.rr1 })) { if ($out.Count -ge $n) { break }; if ($c.grade -eq 'D') { continue }; $k = [string]$c.sector; if ($k -ne 'Krypto' -and $bySector[$k] -ge 3) { continue }; $bySector[$k] = 1 + [int]$bySector[$k]; $out += $c }; $out }
$picks = @(Pick $cUS $TopUS) + @(Pick $cSE $TopSE) + @(Pick $cNO $TopNO) + @(Pick $cEU $TopEU) + @(Pick $cCA $TopCA) + @(Pick $cCR $TopCR)
$all = $cUS + $cSE + $cNO + $cEU + $cCA + $cCR
$counts = [ordered]@{}; foreach ($k in $STRAT.Keys) { $counts[$k] = @($all | Where-Object { $k -in $_.strategies }).Count }
# ---------- snart aktuella: A- och B-lägen nära sin trigger, med vad som saknas innan en testtrade får läggas ----------
$soon = @(foreach ($c in ($all | Where-Object { $_.grade -in 'A', 'B' -and $_.distPct -ge -1 -and $_.distPct -le 4 })) {
    $need = @()
    $sh = $c.side -eq 'short'
    if ($c.distPct -gt 0) { $need += $(if ($sh) { "BOS nedåt: stängning under $(F $c.entry $c.dec) (−$(F $c.distPct 1) %)" } else { "BOS: stängning över $(F $c.entry $c.dec) (+$(F $c.distPct 1) %)" }) }
    else { $need += $(if ($sh) { "Under entry redan ($(F ([math]::Abs($c.distPct)) 1) %): vänta på studs, jaga inte" } else { "Över entry redan ($(F ([math]::Abs($c.distPct)) 1) %): vänta på rekyl, jaga inte" }) }
    if ($sh -and (N $c.rsi) -lt 30) { $need += "RSI $(F $c.rsi 0): översåld, blanka inte in i det" }
    if ($c.grade -ne 'A') { $need += 'betyg B, A krävs för swing' }
    if ($null -ne $c.earningsDays -and $c.earningsDays -le 14) { $need += "rapport om $($c.earningsDays) dagar" }
    if ($c.t1Kind -eq 'nivå' -and $c.rr1 -lt 1.995) { $need += "R/R 1:$(F $c.rr1 1), minst 1:2 krävs" }
    if ($c.riskPct -gt 8) { $need += "stopp $(F $c.riskPct 1) % bort, högst 8 %" }
    if (-not $sh -and (N $c.rsi) -gt 70) { $need += "RSI $(F $c.rsi 0): sträckt" }
    $ready = $c.grade -eq 'A' -and $need.Count -eq 1 -and $c.distPct -gt 0 -and $c.distPct -le 2
    $o = [ordered]@{}; foreach ($k in 'id', 'tv', 'ysym', 'symbol', 'name', 'market', 'sector', 'sectorSv', 'currency', 'dec', 'price', 'chg', 'side', 'strategy', 'strategyName', 'grade', 'score', 'scoreBase', 'entry', 'stop', 't1', 't2', 't1Kind', 'rr1', 'rr2', 'riskPct', 'distPct', 'earnings', 'earningsDays', 'rsi', 'why', 'flags', 'setups', 'deep') { $o[$k] = $c[$k] }
    $o.need = $need; $o.ready = $ready; $o
  }) | Sort-Object { -[int]$_.ready }, { -$_.score }, { $_.distPct } | Select-Object -First 16
"Snart aktuella: $($soon.Count), redo: $(@($soon | Where-Object { $_.ready }).Count)"
"Kandidater: USA $($cUS.Count), Sverige $($cSE.Count), Norden $($cNO.Count), Europa $($cEU.Count), Kanada $($cCA.Count), krypto $($cCR.Count). Utvalda: $($picks.Count)"

# ---------- kurshistorik ----------
function Candles($sym, $range, $interval) {
  $u = "https://query2.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($sym))?range=$range&interval=$interval"
  $res = (Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30).chart.result[0]
  $q = $res.indicators.quote[0]; $rows = @()
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) { if ($null -eq $q.close[$i] -or $null -eq $q.open[$i]) { continue }; $rows += , @([int64]$res.timestamp[$i], (Rnd $q.open[$i]), (Rnd $q.high[$i]), (Rnd $q.low[$i]), (Rnd $q.close[$i])) }
  , $rows
}
function Ysym($c) { if ($c.ysym) { return $c.ysym }; $ex, $t = $c.tv -split ':'; if ($ex -eq 'OMXSTO') { ($t -replace '_', '-') + '.ST' } else { $t -replace '\.', '-' } }
function Trim5($rows) { , @($rows | ForEach-Object { , @([int64]$_[0], (Rnd $_[1]), (Rnd $_[2]), (Rnd $_[3]), (Rnd $_[4])) }) }
foreach ($p in $picks) {
  try { $y = Ysym $p
    # djupanalysens kurshistorik återanvänds (6 månader dag, 5 dagar timme) så att Yahoo inte frågas två gånger
    $hist = if ($BARS.ContainsKey($y)) { $cut = [DateTimeOffset]::new($now.AddDays(-7)).ToUnixTimeSeconds(); @{ d = (Trim5 @($BARS[$y].d | Select-Object -Last 126)); h = (Trim5 @($BARS[$y].h | Where-Object { $_[0] -ge $cut })); at = $stamp; src = "Yahoo Finance $y" } }
      else { @{ d = (Candles $y '6mo' '1d'); h = (Candles $y '5d' '1h'); at = $stamp; src = "Yahoo Finance $y" } }
    if (@($hist.d).Count -lt 20) { throw 'för lite data' }
    [IO.File]::WriteAllText((Join-Path $Out "hist-$($p.id).json"), ($hist | ConvertTo-Json -Depth 5 -Compress)) } catch { "Historik saknas för $($p.symbol): $($_.Exception.Message)" }
}

# ---------- uppföljning av tidigare scanningar ----------
$results = @(); $prev = Get-ChildItem (Join-Path $Out 'scans') -Filter '*.json' | Sort-Object Name | Select-Object -Last 40
$cache = @{}
foreach ($f in $prev) {
  $old = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $t0 = $(if ($old.at -is [datetime]) { $old.at.ToUniversalTime() } else { [DateTime]::Parse($old.at, [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime() })
  if (($now - $t0).TotalHours -lt 20 -or [int]$old.v -lt 2) { continue }
  foreach ($c in $old.candidates) {
    $y = Ysym $c
    if (-not $cache.ContainsKey($y)) { try { $cache[$y] = Candles $y '6mo' '1d' } catch { $cache[$y] = @() } }
    $fb = @($cache[$y] | Where-Object { [DateTimeOffset]::FromUnixTimeSeconds($_[0]).UtcDateTime.Date -gt $t0.Date })
    $status = 'ej utlöst'; $r = $null; $trig = $false; $sh = $c.side -eq 'short'
    foreach ($b in $fb) {
      if (-not $trig) { if (($sh -and $b[3] -le $c.entry) -or (-not $sh -and $b[2] -ge $c.entry)) { $trig = $true; $status = 'öppen' } else { continue } }
      if (($sh -and $b[2] -ge $c.stop) -or (-not $sh -and $b[3] -le $c.stop)) { $status = 'stopp'; $r = -1; break }
      if (($sh -and $b[3] -le $c.t1) -or (-not $sh -and $b[2] -ge $c.t1)) { $status = 'mål 1'; $r = [double]$c.rr1; break }
    }
    if ($status -eq 'ej utlöst' -and $fb.Count -ge 10) { $status = 'förföll' }
    $results += [ordered]@{ scan = $old.at; id = $c.id; symbol = $c.symbol; name = $c.name; market = $c.market; side = $(if ($sh) { 'short' } else { 'long' }); strategy = $c.strategy; grade = $c.grade; entry = $c.entry; stop = $c.stop; t1 = $c.t1; status = $status; r = $r
      setups = @($c.setups | Where-Object { $_ }); confl = $(if ($c.deep) { [int]$c.deep.confl } else { $null }) }
  }
}
# samma kandidat i flera scanningar räknas en gång (den första)
$seen = @{}; $results = @($results | Where-Object { $k = "$($_.id)|$($_.entry)"; if ($seen[$k]) { $false } else { $seen[$k] = 1; $true } })
$stats = [ordered]@{}
foreach ($k in $STRAT.Keys) {
  $rs = @($results | Where-Object { $_.strategy -eq $k }); $done = @($rs | Where-Object { $_.status -in 'stopp', 'mål 1' }); $w = @($done | Where-Object { $_.status -eq 'mål 1' }).Count
  $stats[$k] = [ordered]@{ name = $STRAT[$k]; signals = $rs.Count; triggered = @($rs | Where-Object { $_.status -in 'öppen', 'stopp', 'mål 1' }).Count; wins = $w; losses = $done.Count - $w; open = @($rs | Where-Object { $_.status -eq 'öppen' }).Count; hitRate = $(if ($done.Count) { [math]::Round($w / $done.Count * 100) } else { $null }); avgR = $(if ($done.Count) { [math]::Round((($done | ForEach-Object { $_.r } | Measure-Object -Sum).Sum) / $done.Count, 2) } else { $null }) }
}
# facit för djupanalysen: per setup och per antal verktyg i konfluens (bibeln om SMC: "Testa själv")
function Facit($rs) { $done = @($rs | Where-Object { $_.status -in 'stopp', 'mål 1' }); $w = @($done | Where-Object { $_.status -eq 'mål 1' }).Count
  [ordered]@{ signals = @($rs).Count; done = $done.Count; wins = $w; hitRate = $(if ($done.Count) { [math]::Round($w / $done.Count * 100) } else { $null }); avgR = $(if ($done.Count) { [math]::Round((($done | ForEach-Object { $_.r } | Measure-Object -Sum).Sum) / $done.Count, 2) } else { $null }) } }
$bySetup = [ordered]@{}; foreach ($k in $SETUPN.Keys) { $bySetup[$k] = Facit @($results | Where-Object { $k -in @($_.setups) }); $bySetup[$k].name = $SETUPN[$k] }
$byConfl = [ordered]@{ 'utan djupanalys' = (Facit @($results | Where-Object { $null -eq $_.confl })); '0–1 verktyg' = (Facit @($results | Where-Object { $null -ne $_.confl -and $_.confl -le 1 })); '2 verktyg' = (Facit @($results | Where-Object { $_.confl -eq 2 })); '3 eller fler' = (Facit @($results | Where-Object { $_.confl -ge 3 })) }
$byGrade = [ordered]@{}; foreach ($g in 'A', 'B', 'C') { $done = @($results | Where-Object { $_.grade -eq $g -and $_.status -in 'stopp', 'mål 1' }); $w = @($done | Where-Object { $_.status -eq 'mål 1' }).Count; $byGrade[$g] = [ordered]@{ done = $done.Count; wins = $w; hitRate = $(if ($done.Count) { [math]::Round($w / $done.Count * 100) } else { $null }) } }

# ---------- marknadslistor, sektorer, rapporter ----------
function Row($x) { $c = N $x.close; $sym = if ($x.base_currency) { [string]$x.base_currency } else { ($x.tv -split ':')[1] }
  [ordered]@{ tv = $x.tv; symbol = $sym; name = $x.description; sector = $x.sector; sectorSv = $SV[[string]$x.sector]; price = Rnd $c; chg = Rnd $x.change; rsi = Rnd $x.RSI; perfW = Rnd $x.'Perf.W'; perf1m = Rnd $x.'Perf.1M'; perf3m = Rnd $x.'Perf.3M'; perfYtd = Rnd $x.'Perf.YTD'
    d52 = $(if ((N $x.price_52_week_high) -gt 0) { [math]::Round(((N $x.price_52_week_high) - $c) / $c * 100, 1) } else { $null }); above50 = ($c -gt (N $x.SMA50)); above200 = ($c -gt (N $x.SMA200)); mcap = Rnd $x.market_cap_basic
    earnings = $(if ($x.earnings_release_next_date) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.earnings_release_next_date).UtcDateTime.ToString('yyyy-MM-dd') } else { $null }); rating = Rnd $x.'Recommend.All'; currency = $x.currency; market = $x.market; mcapUsd = (McapUsd $x) } }
function McapUsd($x) { $cc = [string]$x.currency; if ($cc -eq 'GBX') { $cc = 'GBP' }; $r = $FX[$cc]; if ($r) { [math]::Round((N $x.market_cap_basic) * $r) } else { $null } }
$XALL = @(foreach ($k in $XM.Keys) { $XM[$k] })
$mUS = [ordered]@{ at = $stamp; rows = @($US | Select-Object -First 40 | ForEach-Object { Row $_ }) }
$mSE = [ordered]@{ at = $stamp; rows = @($SE | Select-Object -First 30 | ForEach-Object { Row $_ }) }
$mEU = [ordered]@{ at = $stamp; rows = @($XALL | Sort-Object { - (N (McapUsd $_)) } | Select-Object -First 50 | ForEach-Object { Row $_ }) }
$mCR = [ordered]@{ at = $stamp; rows = @($CR | Select-Object -First 30 | ForEach-Object { Row $_ }) }
$sectors = @($US | Where-Object { $_.sector } | Group-Object sector | Where-Object { $_.Count -ge 5 } | ForEach-Object {
    $g = $_.Group; [ordered]@{ sector = $_.Name; sectorSv = $SV[$_.Name]; n = $_.Count; perfW = Rnd (Median ($g | ForEach-Object { N $_.'Perf.W' })); perf1m = Rnd (Median ($g | ForEach-Object { N $_.'Perf.1M' })); perf3m = Rnd (Median ($g | ForEach-Object { N $_.'Perf.3M' }))
      above50 = [math]::Round(@($g | Where-Object { (N $_.close) -gt (N $_.SMA50) }).Count / $g.Count * 100); above200 = [math]::Round(@($g | Where-Object { (N $_.close) -gt (N $_.SMA200) }).Count / $g.Count * 100) } } | Sort-Object { - (N $_.perf1m) })
$breadth = [ordered]@{ us50 = [math]::Round(@($US | Where-Object { (N $_.close) -gt (N $_.SMA50) }).Count / [math]::Max(1, $US.Count) * 100); us200 = [math]::Round(@($US | Where-Object { (N $_.close) -gt (N $_.SMA200) }).Count / [math]::Max(1, $US.Count) * 100)
  se50 = [math]::Round(@($SE | Where-Object { (N $_.close) -gt (N $_.SMA50) }).Count / [math]::Max(1, $SE.Count) * 100); se200 = [math]::Round(@($SE | Where-Object { (N $_.close) -gt (N $_.SMA200) }).Count / [math]::Max(1, $SE.Count) * 100)
  eu50 = [math]::Round(@($XALL | Where-Object { (N $_.close) -gt (N $_.SMA50) }).Count / [math]::Max(1, $XALL.Count) * 100); eu200 = [math]::Round(@($XALL | Where-Object { (N $_.close) -gt (N $_.SMA200) }).Count / [math]::Max(1, $XALL.Count) * 100) }
$mSec = [ordered]@{ at = $stamp; rows = $sectors; breadth = $breadth }
$erows = @(@($US | Select-Object -First 150) + @($SE | Select-Object -First 60) + @($XALL | Sort-Object { - (N (McapUsd $_)) } | Select-Object -First 80) | Where-Object { $_.earnings_release_next_date } | ForEach-Object {
    $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$_.earnings_release_next_date).UtcDateTime; $days = ($dt - $now).TotalDays
    if ($days -ge -0.5 -and $days -le 14) { [ordered]@{ date = $dt.ToString('yyyy-MM-dd'); symbol = ($_.tv -split ':')[1]; tv = $_.tv; name = $_.description; market = $_.market; sector = $_.sector; mcap = Rnd $_.market_cap_basic; currency = $_.currency } } } | Sort-Object { $_.date }, { - (N $_.mcap) })
$mEarn = [ordered]@{ at = $stamp; rows = $erows }

$latest = [ordered]@{ v = 3; at = $stamp; regime = $regime; regimeText = $regimeText; indices = @($idx); breadth = $breadth
  universe = [ordered]@{ us = $US.Count; se = $SE.Count; crypto = $CR.Count; nordic = (@($MKS | Where-Object { $_.region -eq 'Norden' } | ForEach-Object { $XM[$_.name].Count }) | Measure-Object -Sum).Sum
    europe = (@($MKS | Where-Object { $_.region -eq 'Europa' } | ForEach-Object { $XM[$_.name].Count }) | Measure-Object -Sum).Sum; canada = $XM['Kanada'].Count
    total = $US.Count + $SE.Count + $nXM + $CR.Count; markets = [ordered]@{ USA = $US.Count; Sverige = $SE.Count; Krypto = $CR.Count }; candidates = $all.Count; deep = $nDeep }; counts = $counts; strategies = $STRAT; setupNames = $SETUPN; candidates = $picks; soon = @($soon) }
foreach ($k in $XM.Keys) { $latest.universe.markets[$k] = $XM[$k].Count }
$enc = [Text.UTF8Encoding]::new($false)
function Save($name, $obj, $depth = 8) { [IO.File]::WriteAllText((Join-Path $Out $name), ($obj | ConvertTo-Json -Depth $depth -Compress), $enc) }
Save 'scan-latest.json' $latest
Save ('scans\' + $now.ToString('yyyy-MM-dd-HHmm') + '.json') $latest
Save 'scan-stats.json' ([ordered]@{ at = $stamp; byStrategy = $stats; byGrade = $byGrade; bySetup = $bySetup; byConfluence = $byConfl; results = @($results | Select-Object -Last 80) })
Save 'market-us.json' $mUS; Save 'market-se.json' $mSE; Save 'market-eu.json' $mEU; Save 'market-crypto.json' $mCR; Save 'market-sectors.json' $mSec; Save 'market-earnings.json' $mEarn
"Läge: $regime · bredd USA $($breadth.us50) % över 50d, $($breadth.us200) % över 200d · rapporter 14 d: $($erows.Count)"
"Sektorer (1 mån): " + (($sectors | Select-Object -First 4 | ForEach-Object { "$($_.sectorSv) $($_.perf1m)" }) -join ', ') + ' … ' + (($sectors | Select-Object -Last 3 | ForEach-Object { "$($_.sectorSv) $($_.perf1m)" }) -join ', ')
$picks | ForEach-Object { "{0} {1,-3} {2,-8} {3,-10} {4,-30} pris {5,-10} entry {6,-10} stopp {7,-10} mål {8,-10} RR {9,-5} {10}" -f $_.grade, $_.score, $_.market, $_.symbol, ($_.name.Substring(0, [math]::Min(30, $_.name.Length))), $_.price, $_.entry, $_.stop, $_.t1, $_.rr1, ($_.strategy + ' ' + ($_.flags -join '; ')) }
"klart $stamp -> $Out"
