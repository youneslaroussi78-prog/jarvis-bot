# Hämtar pris och indikatorer (TradingView-scannern) plus kurshistorik (Yahoo Finance) för Jarvis.
# Skriver upd-<id>.json (fält att slå ihop i assets/<id>) och hist-<id>.json (history/<id>) i data\watch\.
# Datakontroll: priset jämförs med Yahoo (två källor) och med förra körningen. Ett pris som källorna inte är överens om skrivs inte; då får
# tillgången bara fältet dataWarn (syns i Jarvis) och raden "KONTROLL:" skrivs ut. Resultatet i data\watch\quality.json.
$ErrorActionPreference = 'Stop'
$out = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '../data/watch'
New-Item -ItemType Directory -Force $out | Out-Null
$assets = @(
  @{id='guld';   mkt='cfd';     tv='PEPPERSTONE:XAUUSD'; y='GC=F';    adj=$true}
  @{id='koppar'; mkt='futures'; tv='COMEX:HG1!';         y='HG=F'}
  @{id='btc';    mkt='crypto';  tv='BINANCE:BTCUSD';     y='BTC-USD'}
  @{id='eth';    mkt='crypto';  tv='COINBASE:ETHUSD';    y='ETH-USD'}
  @{id='sol';    mkt='crypto';  tv='COINBASE:SOLUSD';    y='SOL-USD'}
  @{id='xrp';    mkt='crypto';  tv='BINANCE:XRPUSD';     y='XRP-USD'}
  @{id='mu';     mkt='america'; tv='NASDAQ:MU';          y='MU'}
  @{id='googl';  mkt='america'; tv='NASDAQ:GOOGL';       y='GOOGL'}
  @{id='ndx';    mkt='global';  tv='NASDAQ:NDX';         y='^NDX'}
  @{id='silver'; mkt='cfd';     tv='TVC:SILVER';         y='SI=F';    adj=$true}
)
# Gränser för datakontrollen: skillnad mot Yahoo, hopp sedan förra körningen (krypto rör sig mer), terminspremie för guld/silver
$LIM = @{ srcPct = 3.0; jumpPct = 15.0; jumpPctCrypto = 25.0; shiftPct = 4.0 }
# Djupanalys med bibelns verktyg (FVG, order block, likviditet, fib, pivåer, volymprofil m.fl.) mot nivåerna i Jarvis (från databasexporten)
. (Join-Path $PSScriptRoot 'djupanalys.ps1')
$EXP = Join-Path $PSScriptRoot '../data/db-export/assets'
$cols = @('close','change','high','low','RSI','RSI|240','MACD.macd','MACD.signal','SMA50','SMA200','ATR')
$keys = @('price','chg','high','low','rsi','rsi4h','macd','macdSig','sma50','sma200','atr')
$scan = @{}; $Q = [ordered]@{ ok = @(); warn = @(); err = @() }
foreach ($g in ($assets | Group-Object { $_.mkt })) {
  $body = @{ symbols = @{ tickers = @($g.Group | ForEach-Object { $_.tv }) }; columns = $cols } | ConvertTo-Json -Depth 5 -Compress
  try {
    $r = Invoke-RestMethod -Method Post -Uri "https://scanner.tradingview.com/$($g.Name)/scan" -Body $body -ContentType 'application/json' -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Origin' = 'https://www.tradingview.com' } -TimeoutSec 25
    foreach ($d in $r.data) { $scan[$d.s] = $d.d }
  } catch { $Q.err += "TradingView ($($g.Name)) svarade inte: $($_.Exception.Message)" }
}
function Rnd($v) { if ($null -eq $v) { return $null }; $a = [math]::Abs([double]$v); $p = if ($a -ge 1000) { 2 } elseif ($a -ge 10) { 3 } elseif ($a -ge 1) { 4 } else { 6 }; [math]::Round([double]$v, $p) }
function Candles($sym, $range, $interval, $shift) {
  $u = "https://query2.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($sym))?range=$range&interval=$interval"
  $res = (Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 25).chart.result[0]
  $q = $res.indicators.quote[0]; $rows = @()
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) {
    if ($null -eq $q.close[$i] -or $null -eq $q.open[$i]) { continue }
    $rows += ,@([int64]$res.timestamp[$i], (Rnd ($q.open[$i] - $shift)), (Rnd ($q.high[$i] - $shift)), (Rnd ($q.low[$i] - $shift)), (Rnd ($q.close[$i] - $shift)))
  }
  @{ rows = $rows; last = $res.meta.regularMarketPrice }
}
function Prev($id) { $f = Join-Path $out "upd-$id.json"; if (-not (Test-Path $f)) { return $null }; try { $p = (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).price; if ($p) { [double]$p } else { $null } } catch { $null } }
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
foreach ($a in $assets) {
  $d = $scan[$a.tv]; $upd = [ordered]@{}; $bad = $null
  try {
    if ($null -eq $d -or $null -eq $d[0] -or [double]$d[0] -le 0) { throw 'TradingView gav inget pris' }
    for ($i = 0; $i -lt $keys.Count; $i++) { if ($null -ne $d[$i]) { $upd[$keys[$i]] = if ($keys[$i] -eq 'chg') { [math]::Round([double]$d[$i], 2) } else { Rnd $d[$i] } } }
    $px = [double]$d[0]
    $shift = 0
    if ($a.adj) {
      $probe = Candles $a.y '1d' '1h' 0; $shift = [double]$probe.last - $px
      if ([math]::Abs($shift) / $px * 100 -gt $LIM.shiftPct) { $bad = "terminen $($a.y) ligger $([math]::Round($shift / $px * 100, 1)) % från spotpriset $(Rnd $px)" }
    }
    $day = Candles $a.y '6mo' '1d' $shift
    $hour = Candles $a.y '5d' '1h' $shift
    if (-not $a.adj -and $day.last) { $diff = ([double]$day.last - $px) / $px * 100; if ([math]::Abs($diff) -gt $LIM.srcPct) { $bad = "TradingView $(Rnd $px) och Yahoo $(Rnd $day.last) skiljer $([math]::Round($diff, 1)) %" } }
    $prev = Prev $a.id; $jl = if ($a.mkt -eq 'crypto') { $LIM.jumpPctCrypto } else { $LIM.jumpPct }
    # stort hopp: priset skrivs ändå när två källor är överens, men varningen syns
    if (-not $bad -and $prev) { $j = ($px - $prev) / $prev * 100; if ([math]::Abs($j) -gt $jl) { $Q.warn += "$($a.id): priset $(Rnd $px) har ändrats $([math]::Round($j, 1)) % sedan förra körningen ($(Rnd $prev)), bekräftat av Yahoo" } }
    if ($day.rows.Count -lt 60) { $Q.warn += "$($a.id): bara $($day.rows.Count) dagar kurshistorik" }
    foreach ($k in 'rsi', 'sma50', 'sma200', 'atr') { if (-not $upd.Contains($k)) { $Q.warn += "$($a.id): $k saknas från TradingView" } }
    if ($bad) { throw $bad }
    $upd.pxAt = $now; $upd.dataWarn = $null
    try {
      $B = DeepBars $a.y
      if ($shift) { foreach ($set in $B.d, $B.h) { foreach ($row in $set) { for ($k = 1; $k -le 4; $k++) { $row[$k] -= $shift } } } }
      $lv = if (Test-Path "$EXP/$($a.id).json") { Get-Content "$EXP/$($a.id).json" -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
      $tgt = @(@($lv.r2) + @($lv.r1) | Where-Object { [double]$_ -gt [double]$lv.bos })
      $plan = if ($lv -and [double]$lv.bos -gt [double]$lv.inval -and [double]$lv.inval -gt 0) { @{ side = 'long'; entry = [double]$lv.bos; stop = [double]$lv.inval; t1 = $(if ($tgt.Count) { [double]($tgt | Measure-Object -Minimum).Minimum } else { 0 }) } } else { $null }
      $dp = Deep $B.d $B.h $plan $(if ($null -ne $lv.dec) { [int]$lv.dec } else { 2 }) 'bevakning'
      if ($dp) { $dp.Remove('adj'); $upd.deep = $dp }
    } catch { $Q.warn += "$($a.id): djupanalysen gick inte ($($_.Exception.Message))" }
    $hist = @{ d = $day.rows; h = $hour.rows; at = $now; src = "Yahoo Finance $($a.y)" + $(if ($a.adj) { ", förskjuten $([math]::Round($shift,2)) till spotpris" } else { '' }) }
    [IO.File]::WriteAllText((Join-Path $out "upd-$($a.id).json"), ($upd | ConvertTo-Json -Depth 8 -Compress))   # djup 8: djupanalysens verktyg och setups (blev "System.Collections…" med standarddjupet 2, rättat 26 okt)
    [IO.File]::WriteAllText((Join-Path $out "hist-$($a.id).json"), ($hist | ConvertTo-Json -Depth 5 -Compress))
    $Q.ok += $a.id
    "{0,-7} pris {1,-10} dagar {2,4} timmar {3,4}" -f $a.id, $upd.price, $day.rows.Count, $hour.rows.Count
  } catch {
    # priset skrivs inte; förra priset ligger kvar och Jarvis visar varningen. Historikfilen lämnas orörd.
    $msg = "$($a.id): $($_.Exception.Message)"; $Q.err += $msg; "KONTROLL: $msg (priset skrevs inte)"
    [IO.File]::WriteAllText((Join-Path $out "upd-$($a.id).json"), (@{ dataWarn = "Priset kunde inte kontrolleras: $($_.Exception.Message)"; dataWarnAt = $now } | ConvertTo-Json -Compress))
    if (-not (Test-Path (Join-Path $out "hist-$($a.id).json"))) { [IO.File]::WriteAllText((Join-Path $out "hist-$($a.id).json"), (@{ d = @(); h = @(); at = $now; src = 'saknas' } | ConvertTo-Json -Compress)) }
  }
}
foreach ($w in $Q.warn) { "KONTROLL (varning): $w" }
[IO.File]::WriteAllText((Join-Path $out 'quality.json'), ([ordered]@{ at = $now; ok = $Q.ok; warn = $Q.warn; err = $Q.err } | ConvertTo-Json -Compress))
[IO.File]::WriteAllText((Join-Path $out 'prices.json'), (@{ at = $now; source = 'TradingView-scannern'; checked = $Q.ok.Count; failed = $Q.err.Count } | ConvertTo-Json -Compress))
"klart $now ($($Q.ok.Count) kontrollerade, $($Q.err.Count) fel, $($Q.warn.Count) varningar)"
