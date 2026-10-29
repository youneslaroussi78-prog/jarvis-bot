# Nivåtrappa för bevakningslistan med bibelns verktyg (Devin 26 okt: "djupa analyser och rita och visa i min tradingview").
# Stöd och motstånd blir kluster av verktyg (FVG, order block, fib, volymprofil, AVWAP, likviditet, pivåer, glidande medel) inom 0,6 ATR;
# S1/S2 = de två närmaste klustren med minst två verktyg under priset, R1/R2 över. BOS = senaste 4h-swingtoppen över priset
# (Devins entry: BOS på 1h/4h), fel om = under S1 med en femtedels ATR. Priserna räknas om till symbolerna i
# TradingView-listan (Yahoo-historiken förskjuts till diagrammets pris).
#   nivaer.ps1                 skriver data\nivaer.json och visar trappan
#   nivaer.ps1 -Pine           skriver också data\jarvis-nivaer.pine (indikatorn som ritar nivåerna i TradingView)
param([switch]$Pine)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'djupanalys.ps1')
$data = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data'))
$sv = [Globalization.CultureInfo]::GetCultureInfo('sv-SE')
# id, Yahoo-symbol, symbolen i TradingView, decimaler
$ASSETS = @(
  @{ id = 'guld'; y = 'GC=F'; tv = 'PEPPERSTONE:XAUUSD'; dec = 0 }
  @{ id = 'silver'; y = 'SI=F'; tv = 'TVC:SILVER'; dec = 2 }
  @{ id = 'koppar'; y = 'HG=F'; tv = 'CAPITALCOM:XCUUSD'; dec = 3 }
  @{ id = 'btc'; y = 'BTC-USD'; tv = 'BINANCE:BTCUSD'; dec = 0 }
  @{ id = 'eth'; y = 'ETH-USD'; tv = 'COINBASE:ETHUSD'; dec = 0 }
  @{ id = 'sol'; y = 'SOL-USD'; tv = 'COINBASE:SOLUSD'; dec = 2 }
  @{ id = 'xrp'; y = 'XRP-USD'; tv = 'BINANCE:XRPUSD'; dec = 4 }
  @{ id = 'mu'; y = 'MU'; tv = 'BATS:MU'; dec = 2 }
  @{ id = 'googl'; y = 'GOOGL'; tv = 'BATS:GOOGL'; dec = 2 }
  @{ id = 'ndx'; y = '^NDX'; tv = 'NASDAQ_DLY:NDX'; dec = 0 }
)
# diagrammets aktuella pris (TradingView), för att förskjuta Yahoo-historiken (terminer mot spot och CFD)
$body = @{ symbols = @{ tickers = @($ASSETS | ForEach-Object { $_.tv }) }; columns = @('close') } | ConvertTo-Json -Depth 5 -Compress
$TVP = @{}; try { $r = Invoke-RestMethod -Method Post -Uri 'https://scanner.tradingview.com/global/scan' -Body $body -ContentType 'application/json' -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Origin' = 'https://www.tradingview.com' } -TimeoutSec 30; foreach ($x in $r.data) { $TVP[$x.s] = [double]$x.d[0] } } catch { "TradingView svarade inte: $($_.Exception.Message)" }
function RoundTo($v, $d) { [math]::Round([double]$v, $d) }
function Fm($v, $d) { ([double]$v).ToString("N$d", $sv) }
# kluster av zoner (mitten inom 0,6 ATR), sorterade efter avstånd till priset
function Clusters($Z, $atr, $px, [int]$dir, [int]$minN = 2) {
  $c = @($Z | Where-Object { $m = ($_.lo + $_.hi) / 2; $dir * ($m - $px) -gt 0 -and [math]::Abs($m - $px) -le 8 * $atr } | Sort-Object { [math]::Abs(($_.lo + $_.hi) / 2 - $px) })
  $out = @(); $used = @{}
  foreach ($a in $c) {
    $k = "$($a.tool)|$($a.lo)"; if ($used[$k]) { continue }
    $m0 = ($a.lo + $a.hi) / 2
    $mem = @($c | Where-Object { $mm = ($_.lo + $_.hi) / 2; -not $used["$($_.tool)|$($_.lo)"] -and [math]::Abs($mm - $m0) -le 0.6 * $atr })
    foreach ($x in $mem) { $used["$($x.tool)|$($x.lo)"] = 1 }
    $fams = @($mem | ForEach-Object { $_.fam } | Sort-Object -Unique)
    $mids = @($mem | ForEach-Object { ($_.lo + $_.hi) / 2 })
    $out += [pscustomobject]@{ lo = ($mids | Measure-Object -Minimum).Minimum; hi = ($mids | Measure-Object -Maximum).Maximum; n = $fams.Count; fams = $fams; tools = @($mem | ForEach-Object { $_.tool } | Select-Object -Unique) }
  }
  $ok = @($out | Where-Object { $_.n -ge $minN }); if ($ok.Count -lt 2 -and $minN -gt 1) { $ok = @($out | Where-Object { $_.n -ge 2 }) + @($out | Where-Object { $_.n -lt 2 } | Select-Object -First (2 - $ok.Count)); $ok = @($ok | Sort-Object { [math]::Abs($_.lo - $px) }) }; $ok
}
$RES = [ordered]@{}
foreach ($a in $ASSETS) {
  try {
    $B = DeepBars $a.y; $n = $B.d.Count; $yl = $B.d[$n - 1][4]
    $chartPx = $TVP[$a.tv]; $shift = if ($chartPx -gt 0) { $yl - $chartPx } else { 0 }
    if ([math]::Abs($shift) / $yl -gt 0.05) { $shift = 0 }   # orimlig skillnad: använd Yahoo som det är
    if ($shift) { foreach ($set in $B.d, $B.h) { foreach ($row in $set) { for ($k = 1; $k -le 4; $k++) { $row[$k] -= $shift } } } }
    $dp = Deep $B.d $B.h $null $a.dec 'bevakning'
    $px = $B.d[$n - 1][4]; $atr = DAtr $B.d
    # alla zoner (Deep() returnerar bara toppen, så räkna om hela listan här med samma verktyg)
    $Z = @(); $H4 = Agg $B.h 14400; $atr4 = DAtr $H4
    $Z += Fvgs $B.d $atr 'dag'; $Z += Fvgs $H4 $atr4 '4h' 90; $Z += Obs $B.d $atr 'dag'; $Z += Obs $H4 $atr4 '4h' 90
    $sw = SwingPts $B.d; foreach ($s in $sw.l | Select-Object -Last 8) { $Z += Zone 'Swingbotten' 'Likviditet' 'stöd' $s[1] $s[1] '' }; foreach ($s in $sw.h | Select-Object -Last 8) { $Z += Zone 'Swingtopp' 'Likviditet' 'motstånd' $s[1] $s[1] '' }
    # ett år bakåt: swingar (3 candles på var sida), makro-fib över årets range (bibeln: dra en makro-fib över den stora rörelsen) och månadspivåer
    $sy = SwingPts $B.d 3 250; foreach ($s in $sy.l) { $Z += Zone 'Swingbotten (år)' 'Likviditet' 'stöd' $s[1] $s[1] '' }; foreach ($s in $sy.h) { $Z += Zone 'Swingtopp (år)' 'Likviditet' 'motstånd' $s[1] $s[1] '' }
    $yh = ($B.d | ForEach-Object { $_[2] } | Measure-Object -Maximum).Maximum; $yl0 = ($B.d | ForEach-Object { $_[3] } | Measure-Object -Minimum).Minimum
    foreach ($fr in 0.236, 0.382, 0.5, 0.618, 0.786) { $v = $yh - $fr * ($yh - $yl0); $Z += Zone "Fib år $([math]::Round($fr * 100, 1)) %" 'Fib' '' $v $v '' }
    $mo = @($B.d | Group-Object { [DateTimeOffset]::FromUnixTimeSeconds([int64]$_[0]).UtcDateTime.ToString('yyyy-MM') }); if ($mo.Count -ge 2) { $pm = @($mo[$mo.Count - 2].Group); $mh = ($pm | ForEach-Object { $_[2] } | Measure-Object -Maximum).Maximum; $ml = ($pm | ForEach-Object { $_[3] } | Measure-Object -Minimum).Minimum
      $mp = ($mh + $ml + $pm[-1][4]) / 3; foreach ($q in @(@('Månadspivå P', $mp), @('Månadspivå S1', (2 * $mp - $mh)), @('Månadspivå R1', (2 * $mp - $ml)), @('Månadspivå S2', ($mp - ($mh - $ml))), @('Månadspivå R2', ($mp + ($mh - $ml))))) { $Z += Zone $q[0] 'Pivå' '' $q[1] $q[1] '' } }
    $wk = Agg $B.d 604800 345600; $pw = $wk[$wk.Count - 2]; $Z += Zone 'PWL' 'Likviditet' 'stöd' $pw[3] $pw[3] ''; $Z += Zone 'PWH' 'Likviditet' 'motstånd' $pw[2] $pw[2] ''
    $piv = ($pw[2] + $pw[3] + $pw[4]) / 3; $rg = $pw[2] - $pw[3]; foreach ($q in @(@('Veckopivå P', $piv), @('Veckopivå S1', (2 * $piv - $pw[2])), @('Veckopivå R1', (2 * $piv - $pw[3])), @('Veckopivå S2', ($piv - $rg)), @('Veckopivå R2', ($piv + $rg)))) { $Z += Zone $q[0] 'Pivå' '' $q[1] $q[1] '' }
    foreach ($t in $dp.levels) { $Z += Zone $t.tool $(if ($t.tool -like 'FVG*') { 'FVG' } elseif ($t.tool -like 'Order*') { 'OB' } elseif ($t.tool -like 'Fib*') { 'Fib' } elseif ($t.tool -in 'POC', 'VAH', 'VAL') { 'Volymprofil' } else { 'AVWAP' }) $t.kind $t.lo $t.hi $t.note }
    foreach ($m in @(@('SMA50', 50), @('SMA200', 200))) { $v = DSma $B.d $m[1]; if ($v -gt 0) { $Z += Zone $m[0] 'Glidande medel' '' $v $v '' } }
    $suppt = @(Clusters $Z $atr $px -1); $resist = @(Clusters $Z $atr $px 1)
    # BOS: senaste 4h-swingtoppen över priset (inom 3 ATR); annars närmaste motståndskluster
    $s4 = SwingPts $H4 2 60; $bosC = @($s4.h | Where-Object { $_[1] -gt $px -and $_[1] -le $px + 3 * $atr } | Sort-Object { - $_[0] } | Select-Object -First 1)
    $bos = if ($bosC.Count) { $bosC[0][1] } elseif ($resist.Count) { $resist[0].lo } else { $px + $atr }
    $s1 = $suppt[0]; $s2 = $suppt[1]; $r1 = $resist[0]; $r2 = $resist[1]
    $inval = if ($s1) { $s1.lo - 0.2 * $atr } else { $px - 1.5 * $atr }
    $d = $a.dec
    $RES[$a.id] = [ordered]@{ id = $a.id; tv = $a.tv; dec = $d; price = (RoundTo $px $d); atr = (RoundTo $atr ($d + 1)); shift = (RoundTo $shift ($d + 1)); weekly = $dp.weekly; premium = $dp.premium
      s1 = $(if ($s1) { @((RoundTo $s1.lo $d), (RoundTo $s1.hi $d)) }); s1t = $(if ($s1) { $s1.tools -join ', ' }); s2 = $(if ($s2) { @((RoundTo $s2.lo $d), (RoundTo $s2.hi $d)) }); s2t = $(if ($s2) { $s2.tools -join ', ' })
      r1 = $(if ($r1) { @((RoundTo $r1.lo $d), (RoundTo $r1.hi $d)) }); r1t = $(if ($r1) { $r1.tools -join ', ' }); r2 = $(if ($r2) { @((RoundTo $r2.lo $d), (RoundTo $r2.hi $d)) }); r2t = $(if ($r2) { $r2.tools -join ', ' })
      bos = (RoundTo $bos $d); inval = (RoundTo $inval $d); setups = @($dp.setups | ForEach-Object { "$($_.k)/$($_.side): $($_.t)" }); text = $dp.text
      zones = @($Z | Where-Object { $_.fam -in 'FVG', 'OB' -and [math]::Abs(($_.lo + $_.hi) / 2 - $px) -le 4 * $atr } | Sort-Object { [math]::Abs(($_.lo + $_.hi) / 2 - $px) } | Select-Object -First 6 | ForEach-Object { [ordered]@{ tool = $_.tool; kind = $_.kind; lo = (RoundTo $_.lo $d); hi = (RoundTo $_.hi $d) } })
      poc = $(($Z | Where-Object { $_.tool -eq 'POC' } | Select-Object -First 1).lo | ForEach-Object { RoundTo $_ $d }); val = $(($Z | Where-Object { $_.tool -eq 'VAL' } | Select-Object -First 1).lo | ForEach-Object { RoundTo $_ $d }); vah = $(($Z | Where-Object { $_.tool -eq 'VAH' } | Select-Object -First 1).lo | ForEach-Object { RoundTo $_ $d })
      at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $x = $RES[$a.id]
    "{0,-7} {1,-20} pris {2} (ATR {3}, förskjutning {4}) vecka {5} | S2 {6} [{7}] | S1 {8} [{9}] | R1 {10} [{11}] | R2 {12} [{13}] | BOS {14} | fel om {15}" -f $a.id, $a.tv, (Fm $x.price $d), (Fm $x.atr ($d)), $x.shift, $x.weekly, ($x.s2 -join '–'), $x.s2t, ($x.s1 -join '–'), $x.s1t, ($x.r1 -join '–'), $x.r1t, ($x.r2 -join '–'), $x.r2t, (Fm $x.bos $d), (Fm $x.inval $d)
    if ($x.setups.Count) { "        setups: " + ($x.setups -join ' · ') }
  } catch { "$($a.id): kunde inte analyseras ($($_.Exception.Message)) rad $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim().Substring(0, [math]::Min(140, $_.InvocationInfo.Line.Trim().Length)))" }
}
[IO.File]::WriteAllText((Join-Path $data 'nivaer.json'), ($RES | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($true))
"klart -> $data\nivaer.json"
