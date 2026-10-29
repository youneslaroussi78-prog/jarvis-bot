# Daytrade på 5 minuter med flera tidsramar (Devin 26 okt: "du ska göra det man ska göra på daytrading, försök att samla så mycket
# data som möjligt för att lyckas, kan du inte det så får vi strunta i det"). Motorn ligger i daytrade5-engine.ps1 (C#, snabb nog för
# hundratusentals 5m-candlar) och används både här och live.
#   daytrade5.ps1 -Backtest   hämtar 5m-data (Yahoo, 60 dagar) för ca 65 instrument, sparar den i data\bars5 (arkivet växer för varje körning,
#                             så att historiken blir längre än Yahoos 60 dagar), och testar setupsen två gånger: var 5:e minut (som en daytrader
#                             vid skärmen) och varje hel timme (som vakten), med två kostnader: Avanza (turbo, aktier) och billig mäklare
#                             (terminer/CFD, aktier hos lågprismäklare). Skriver data\daytrade5-backtest.json och daytrade5-lagen.json.
param([switch]$Backtest, [string]$Only, [string]$Setups = 'sweep5,fvg5,vwap5,orbr', [switch]$NoFetch, [switch]$InPlay)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'daytrade-lib.ps1')
. (Join-Path $PSScriptRoot 'daytrade5-engine.ps1')
$data = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data')); $arch = Join-Path $data 'bars5'; New-Item -ItemType Directory -Force $arch | Out-Null
$nowU = (Get-Date).ToUniversalTime(); $enc = [Text.UTF8Encoding]::new($false); $se = [TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time')
# fler instrument för 5m-testet: ETF:er, europeiska index och fler aktier som rör sig mycket (urvalet gjort i dag, överlevnadsfel finns)
$DT5_MORE = @(
  foreach ($t in 'SPY', 'QQQ', 'IWM', 'GLD', 'SLV', 'USO', 'SMH', 'TLT') { @{ id = "e-$($t.ToLower())"; y = $t; tv = "AMEX:$t"; name = $t; mk = 'USA'; sector = 'ETF'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true } }
  foreach ($t in 'MSFT', 'TSM', 'ARM', 'MRVL', 'PYPL', 'SOFI', 'DKNG', 'AFRM', 'UPST', 'RBLX') { @{ id = "x-$($t.ToLower())"; y = $t; tv = "NASDAQ:$t"; name = $t; mk = 'USA'; sector = 'Aktie USA'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true } }
  @{ id = 'ftse'; y = '^FTSE'; tv = 'TVC:UKX'; name = 'FTSE 100'; mk = 'Storbritannien'; sector = 'Index'; open = @('08:00', 'GMT Standard Time'); dec = 1 }
  @{ id = 'sx5e'; y = '^STOXX50E'; tv = 'TVC:SX5E'; name = 'Euro Stoxx 50'; mk = 'Tyskland'; sector = 'Index'; open = @('09:00', 'W. Europe Standard Time'); dec = 1 }
  @{ id = 'cac'; y = '^FCHI'; tv = 'TVC:CAC40'; name = 'CAC 40'; mk = 'Frankrike'; sector = 'Index'; open = @('09:00', 'W. Europe Standard Time'); dec = 1 }
)
function Get5($y) {
  $u = "https://query2.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($y))?range=60d&interval=5m"
  $res = (Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 90).chart.result[0]; $q = $res.indicators.quote[0]; $o = [Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) { $t0 = [double]$res.timestamp[$i]; if ($t0 % 300 -ne 0 -or $null -eq $q.close[$i] -or $null -eq $q.high[$i] -or $null -eq $q.low[$i] -or $null -eq $q.open[$i]) { continue }
    $o.Add([double[]]@($t0, [double]$q.open[$i], [double]$q.high[$i], [double]$q.low[$i], [double]$q.close[$i], $(if ($null -ne $q.volume[$i]) { [double]$q.volume[$i] } else { 0.0 }))) }
  , $o.ToArray()
}
# arkivet: nya candlar läggs till de sparade, så att historiken växer (en fil per instrument)
function Archive($ins, $new) {
  $f = Join-Path $arch "$($ins.id).json"; $m = [Collections.Generic.SortedDictionary[double, double[]]]::new()
  if (Test-Path $f) { foreach ($b in (Get-Content $f -Raw | ConvertFrom-Json).bars) { $m[[double]$b[0]] = [double[]]@($b) } }
  foreach ($b in $new) { $m[$b[0]] = $b }
  $arr = @($m.Values); $sb = [Text.StringBuilder]::new(); [void]$sb.Append('{"id":"' + $ins.id + '","y":"' + $ins.y + '","bars":[')
  for ($i = 0; $i -lt $arr.Count; $i++) { $b = $arr[$i]; if ($i) { [void]$sb.Append(',') }; [void]$sb.Append('[' + (($b | ForEach-Object { ([double]$_).ToString('R', [Globalization.CultureInfo]::InvariantCulture) }) -join ',') + ']') }
  [void]$sb.Append(']}'); [IO.File]::WriteAllText($f, $sb.ToString(), $enc); , $arr
}
# sessioner per handelsdag: öppning, slut, dagens början (terminer 18.00 New York dagen före, krypto midnatt UTC) och UTC-midnatt för dagsdatan
function Sessions5($ins, [double[]]$tA) {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById($ins.open[1]); $dates = [Collections.Generic.SortedSet[datetime]]::new()
  foreach ($t0 in $tA) { [void]$dates.Add([TimeZoneInfo]::ConvertTimeFromUtc([DateTimeOffset]::FromUnixTimeSeconds([int64]$t0).UtcDateTime, $tz).Date) }
  $S = @{ ds = [Collections.Generic.List[double]]::new(); so = [Collections.Generic.List[double]]::new(); se = [Collections.Generic.List[double]]::new(); dm = [Collections.Generic.List[double]]::new() }
  foreach ($dt in $dates) { if ([int]$dt.DayOfWeek -in 0, 6) { continue }
    $noon = [TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($dt.AddHours(12), 'Unspecified'), $tz); $so = [double](SessionOpenAt $ins.open $noon); $sEnd = [double](SessionEndAt $ins.mk $noon)
    $soU = [DateTimeOffset]::FromUnixTimeSeconds([int64]$so).UtcDateTime; $mid = [double][DateTimeOffset]::new($soU.Date).ToUnixTimeSeconds()
    $ds = if ($ins.mk -eq 'Krypto') { $mid } elseif ($ins.mk -eq 'Råvaror' -or ($ins.sector -eq 'Index' -and $ins.mk -eq 'USA')) { $so - 15.5 * 3600 } else { $so }
    $S.ds.Add($ds); $S.so.Add($so); $S.se.Add($sEnd); $S.dm.Add($mid) }
  $S
}
function HasOn($ins) { $ins.mk -eq 'Krypto' -or $ins.mk -eq 'Råvaror' -or ($ins.sector -eq 'Index' -and $ins.mk -eq 'USA') }
# kostnad tur och retur i andel av underliggande. A = Avanza som i testportföljen; B = billig mäklare (terminer eller CFD på index och råvaror,
# lågprismäklare för aktier, kryptobörs med låg avgift). B är en uppskattning.
function CostA($ins) { DayCostPct $ins }
function CostB($ins) { if ($ins.stock) { 0.0005 } elseif ($ins.mk -eq 'Krypto') { 0.001 } elseif ($ins.sector -eq 'Index') { 0.0001 } else { 0.0002 } }
$NAMES5 = @{ sweep5 = 'Likviditetssvep + CHoCH'; fvg5 = 'FVG-retest i trenden'; vwap5 = 'VWAP-återtagning i trenden'; orbr = 'ORB med retest'; orb15 = 'ORB 15 min' }

if ($Backtest) {
  $list = @($DT_INSTR) + @($DT_EXTRA) + @($DT5_MORE); if ($Only) { $list = @($list | Where-Object { $_.id -in ($Only -split ',') }) }
  $REC = [Collections.Generic.List[object]]::new(); $sw = [Diagnostics.Stopwatch]::StartNew(); $nBars = 0
  foreach ($ins in $list) {
    try {
      $B = if ($NoFetch) { @((Get-Content (Join-Path $arch "$($ins.id).json") -Raw | ConvertFrom-Json).bars | ForEach-Object { , [double[]]@($_) }) } else { Archive $ins (Get5 $ins.y) }
      # dagsdatan sparas också, så att -NoFetch går helt utan Yahoo (som ibland spärrar efter många anrop)
      $dF = Join-Path $arch "$($ins.id)-dag.json"; $D = $null
      try { $D = GetD $ins.y '1y'; if ($D.Count -ge 40) { [IO.File]::WriteAllText($dF, (ConvertTo-Json -InputObject @($D) -Depth 3 -Compress), $enc) } } catch { if (Test-Path $dF) { $D = @((Get-Content $dF -Raw | ConvertFrom-Json) | ForEach-Object { , [double[]]@($_) }) } else { throw } }
      if ($B.Count -lt 500 -or $D.Count -lt 40) { "$($ins.name): för lite data"; continue }
      $X = ToArrays $B; $nBars += $B.Count; $SES = Sessions5 $ins $X.tA
      $dT = [double[]]@($D | ForEach-Object { $_[0] }); $dH = [double[]]@($D | ForEach-Object { $_[2] }); $dL = [double[]]@($D | ForEach-Object { $_[3] }); $dC = [double[]]@($D | ForEach-Object { $_[4] })
      $cls = DtClass $ins; $cA = CostA $ins; $cB = CostB $ins; $n0 = $REC.Count
      foreach ($cad in 300, 3600) { $valid = if ($cad -eq 300) { 1800 } else { 3600 }
        $res = [Dt5]::Run($X.tA, $X.oA, $X.hA, $X.lA, $X.cA, $X.vA, $SES.ds.ToArray(), $SES.so.ToArray(), $SES.se.ToArray(), $SES.dm.ToArray(), $dT, $dH, $dL, $dC, [bool](HasOn $ins), $cad, $valid, $Setups, 1800, 5400, $false, 0, $null)
        foreach ($s in $res) { $costRA = $cA * $s.Entry / $s.Risk; $costRB = $cB * $s.Entry / $s.Risk
          $REC.Add([pscustomobject]@{ ins = $ins.id; symbol = $ins.name; class = $cls; cad = $cad; setup = $s.Key; side = $(if ($s.Side -gt 0) { 'long' } else { 'short' }); level = $s.Level; atT = $s.AtT
            hour = [TimeZoneInfo]::ConvertTimeFromUtc([DateTimeOffset]::FromUnixTimeSeconds([int64]$s.AtT).UtcDateTime, $se).Hour; bias = $s.Bias; trendD = $s.TrendD; riskPct = [math]::Round($s.Risk / $s.Entry * 100, 3)
            status = $s.Status; reason = $s.Reason; r = [math]::Round($s.R, 3); costA = [math]::Round($costRA, 3); costB = [math]::Round($costRB, 3); t1 = $s.T1Hit; ambig = $s.Ambig; mfe = [math]::Round($s.Mfe, 2) }) } }
      "{0,-22} {1,6} candlar · {2,4} lägen ({3:N0} s)" -f $ins.name, $B.Count, ($REC.Count - $n0), $sw.Elapsed.TotalSeconds
    } catch { "$($ins.name): misslyckades ($($_.Exception.Message))" }
  }
  [IO.File]::WriteAllText((Join-Path $data 'daytrade5-lagen.json'), (ConvertTo-Json -InputObject @($REC) -Depth 4 -Compress), $enc)
  "--- $($list.Count) instrument, $nBars candlar à 5 min, $($REC.Count) lägen ($([math]::Round($sw.Elapsed.TotalMinutes, 1)) min) ---"
  # sammanfattning per setup, riktning och tempo, i tre lika långa delar. Godkänt = plus netto med billig mäklare (B) i alla tre delarna och
  # minst 50 utlösta i varje (hårdare än två halvor: 26 okt klarade "svep blanka" två halvor men inte tre). Avanza (A) visas bredvid.
  $all = @($REC); $mn = ($all | Measure-Object atT -Minimum).Minimum; $mx = ($all | Measure-Object atT -Maximum).Maximum; $cut = @($mn, ($mn + ($mx - $mn) / 3), ($mn + 2 * ($mx - $mn) / 3), ($mx + 1))
  function S5($set) { $tr = @($set | Where-Object { $_.status -eq 'utlöst' }); if (-not $tr.Count) { return [ordered]@{ n = 0 } }
    [ordered]@{ n = $tr.Count; winB = [math]::Round(@($tr | Where-Object { $_.r - $_.costB -gt 0 }).Count / $tr.Count * 100); gross = [math]::Round(($tr | Measure-Object r -Average).Average, 3)
      netB = [math]::Round(($tr | ForEach-Object { $_.r - $_.costB } | Measure-Object -Average).Average, 3); netA = [math]::Round(($tr | ForEach-Object { $_.r - $_.costA } | Measure-Object -Average).Average, 3) } }
  $rows = foreach ($cad in 300, 3600) { foreach ($k in 'sweep5', 'fvg5', 'vwap5', 'orbr') { foreach ($sd in 'long', 'short') { $set = @($all | Where-Object { $_.cad -eq $cad -and $_.setup -eq $k -and $_.side -eq $sd })
    $th = @(for ($i = 0; $i -lt 3; $i++) { S5 @($set | Where-Object { $_.atT -ge $cut[$i] -and $_.atT -lt $cut[$i + 1] }) })
    $ok = @($th | Where-Object { $_.n -ge 50 -and $_.netB -gt 0 }).Count -eq 3
    [ordered]@{ setup = $k; side = $sd; name = "$($NAMES5[$k]) $(if ($sd -eq 'short') { 'blanka' } else { 'köp' })"; cad = $cad; all = (S5 $set); thirds = $th; holds = $ok
      verdict = $(if ($ok) { 'håller i alla tre delarna' } elseif (@($th | Where-Object { $_.n -lt 50 }).Count) { 'för få lägen' } else { 'håller inte' }) } } } }
  $sum = [ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ'); from = [DateTimeOffset]::FromUnixTimeSeconds([int64]$mn).UtcDateTime.ToString('yyyy-MM-dd'); to = [DateTimeOffset]::FromUnixTimeSeconds([int64]$mx).UtcDateTime.ToString('yyyy-MM-dd')
    instruments = $list.Count; candles = $nBars; signals = $all.Count; overall = [ordered]@{ min5 = (S5 @($all | Where-Object { $_.cad -eq 300 })); hour = (S5 @($all | Where-Object { $_.cad -eq 3600 })) }
    rule = 'Godkänt: plus netto med billig mäklare i alla tre delarna av perioden och minst 50 utlösta i varje.'
    costs = 'A = Avanza (turbo 9,5x på index och råvaror, aktier 0,2 % tur och retur); B = billig mäklare (terminer eller CFD 0,01–0,02 %, aktier 0,05 %, krypto 0,1 %).'
    rows = @($rows) }
  [IO.File]::WriteAllText((Join-Path $data 'daytrade5-backtest.json'), ($sum | ConvertTo-Json -Depth 7 -Compress), $enc)
  foreach ($r0 in $rows) { "{0,-40} {1,-6} {2,5} st brutto {3,6} B {4,6} A {5,6} · delar B {6} · {7}" -f $r0.name, $(if ($r0.cad -eq 300) { '5 min' } else { 'timme' }), $r0.all.n, $r0.all.gross, $r0.all.netB, $r0.all.netA, (($r0.thirds | ForEach-Object { $_.netB }) -join ' / '), $r0.verdict }
}

# -InPlay (Devin 26 okt: "kör testet med aktier i rörelse"): cirka 300 USA-aktier (data\inplay-universe.json: de 200 med störst omsättning
# och de 100 mest volatila av resten), och bara dagar då aktien är i rörelse: gap minst 3 % mot gårdagens stängning och volymen de första
# 15 minuterna minst dubbelt så stor som snittet för samma 15 minuter de 20 dagarna före (båda kända efter 15 minuter, ingen framtidsdata).
# Setups på 5m var 5:e minut, plus ORB 15 min i gapets riktning. Regeln bestämdes före testet: godkänt = plus netto med billig mäklare i alla
# tre delarna och minst 50 utlösta i varje. Skriver data\daytrade5-inplay.json och daytrade5-inplay-lagen.json.
if ($InPlay) {
  $U = @((Get-Content (Join-Path $data 'inplay-universe.json') -Raw -Encoding UTF8 | ConvertFrom-Json).stocks); if ($Only) { $U = @($U | Where-Object { $_.ticker -in ($Only -split ',') }) }
  $REC = [Collections.Generic.List[object]]::new(); $sw = [Diagnostics.Stopwatch]::StartNew(); $nBars = 0; $nDays = 0; $nPlay = 0; $fail = @()
  $nU = 0
  foreach ($stk in $U) { $nU++   # inte $u: PowerShell skiljer inte på $u och $U
    $ins = @{ id = "ip-$(([string]$stk.ticker).ToLower() -replace '[^a-z0-9]', '')"; y = ([string]$stk.ticker -replace '[_\.]', '-'); tv = $stk.tv; name = [string]$stk.ticker; mk = 'USA'; sector = 'Aktie USA'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true }
    try {
      if ($NoFetch) { $B = @((Get-Content (Join-Path $arch "$($ins.id).json") -Raw | ConvertFrom-Json).bars | ForEach-Object { , [double[]]@($_) }) }
      else { $new = $null; for ($try = 0; $try -lt 3 -and $null -eq $new; $try++) { try { $new = Get5 $ins.y } catch { Start-Sleep -Seconds (4 * ($try + 1)) } }; if ($null -eq $new) { throw 'Yahoo svarade inte' }; $B = Archive $ins $new; Start-Sleep -Milliseconds 200 }
      if ($B.Count -lt 1500) { $fail += "$($ins.name) (för lite data)"; continue }
      $dF = Join-Path $arch "$($ins.id)-dag.json"; $D = $null
      if ($NoFetch -and (Test-Path $dF)) { $D = @((Get-Content $dF -Raw | ConvertFrom-Json) | ForEach-Object { , [double[]]@($_) }) } else { $D = GetD $ins.y '1y'; [IO.File]::WriteAllText($dF, (ConvertTo-Json -InputObject @($D) -Depth 3 -Compress), $enc) }
      if ($D.Count -lt 40) { $fail += "$($ins.name) (för lite dagsdata)"; continue }
      $X = ToArrays $B; $nBars += $B.Count; $SES = Sessions5 $ins $X.tA; $so = $SES.so.ToArray(); $sEnd0 = $SES.se.ToArray(); $nd = $so.Length
      $gapA = [double[]]::new($nd); $v15 = [double[]]::new($nd); $gapRaw = [double[]]::new($nd)
      for ($di = 0; $di -lt $nd; $di++) { $gapA[$di] = [double]::NaN; $v15[$di] = [double]::NaN; $gapRaw[$di] = [double]::NaN   # inte $d: den skulle skriva över dagsdatan $D
        $oS = FirstGE $X.tA $so[$di]; if ($oS + 2 -ge $X.tA.Length -or $X.tA[$oS] -ge $so[$di] + 300 -or $X.tA[$oS + 2] -ge $so[$di] + 900) { continue }
        $v15[$di] = $X.vA[$oS] + $X.vA[$oS + 1] + $X.vA[$oS + 2]
        if ($di -gt 0) { $pE = LastLE $X.tA ($sEnd0[$di - 1] - 1); if ($pE -ge 0 -and $pE -lt $oS) { $gapRaw[$di] = $X.oA[$oS] / $X.cA[$pE] - 1 } } }
      for ($di = 20; $di -lt $nd; $di++) { if ([double]::IsNaN($gapRaw[$di]) -or [double]::IsNaN($v15[$di])) { continue }; $nDays++
        $pv0 = @(for ($q = $di - 20; $q -lt $di; $q++) { if (-not [double]::IsNaN($v15[$q])) { $v15[$q] } }); if ($pv0.Count -lt 10) { continue }
        $avg = ($pv0 | Measure-Object -Average).Average; if ($avg -gt 0 -and [math]::Abs($gapRaw[$di]) -ge 0.03 -and $v15[$di] / $avg -ge 2) { $gapA[$di] = $gapRaw[$di]; $nPlay++ } }
      $dT = [double[]]@($D | ForEach-Object { $_[0] }); $dH = [double[]]@($D | ForEach-Object { $_[2] }); $dL = [double[]]@($D | ForEach-Object { $_[3] }); $dC = [double[]]@($D | ForEach-Object { $_[4] })
      $res = [Dt5]::Run($X.tA, $X.oA, $X.hA, $X.lA, $X.cA, $X.vA, $SES.ds.ToArray(), $so, $sEnd0, $SES.dm.ToArray(), $dT, $dH, $dL, $dC, $false, 300, 1800, 'sweep5,fvg5,vwap5,orbr,orb15', 900, 5400, $false, 0, $gapA)
      foreach ($s in $res) { $sd0 = if ($s.Side -gt 0) { 1 } else { -1 }
        $REC.Add([pscustomobject]@{ ins = $ins.id; symbol = $ins.name; setup = $s.Key; side = $(if ($sd0 -gt 0) { 'long' } else { 'short' }); level = $s.Level; atT = $s.AtT; gap = [math]::Round($s.Gap * 100, 2); gapWith = ([math]::Sign($s.Gap) -eq $sd0)
          minutes = [math]::Round(($s.AtT - $so[$s.Day]) / 60); bias = $s.Bias; trendD = $s.TrendD; riskPct = [math]::Round($s.Risk / $s.Entry * 100, 3)
          status = $s.Status; reason = $s.Reason; r = [math]::Round($s.R, 3); costA = [math]::Round(0.002 * $s.Entry / $s.Risk, 3); costB = [math]::Round(0.0005 * $s.Entry / $s.Risk, 3); t1 = $s.T1Hit; ambig = $s.Ambig; mfe = [math]::Round($s.Mfe, 2) }) }
    } catch { $fail += "$($ins.name) ($($_.Exception.Message))" }
    if ($nU % 50 -eq 0) { "{0} av {1} aktier klara · {2} dagar i rörelse · {3} lägen ({4:N0} s)" -f $nU, $U.Count, $nPlay, $REC.Count, $sw.Elapsed.TotalSeconds }
  }
  $all = @($REC); [IO.File]::WriteAllText((Join-Path $data 'daytrade5-inplay-lagen.json'), (ConvertTo-Json -InputObject $all -Depth 4 -Compress), $enc)
  function S5($set) { $tr = @($set | Where-Object { $_.status -eq 'utlöst' }); if (-not $tr.Count) { return [ordered]@{ n = 0 } }
    [ordered]@{ n = $tr.Count; winB = [math]::Round(@($tr | Where-Object { $_.r - $_.costB -gt 0 }).Count / $tr.Count * 100); gross = [math]::Round(($tr | Measure-Object r -Average).Average, 3)
      netB = [math]::Round(($tr | ForEach-Object { $_.r - $_.costB } | Measure-Object -Average).Average, 3); netA = [math]::Round(($tr | ForEach-Object { $_.r - $_.costA } | Measure-Object -Average).Average, 3) } }
  $mn = ($all | Measure-Object atT -Minimum).Minimum; $mx = ($all | Measure-Object atT -Maximum).Maximum; $cut = @($mn, ($mn + ($mx - $mn) / 3), ($mn + 2 * ($mx - $mn) / 3), ($mx + 1))
  $groups = foreach ($k in 'sweep5', 'fvg5', 'vwap5', 'orbr', 'orb15') { foreach ($sd in 'long', 'short') { @{ name = "$($NAMES5[$k]) $(if ($sd -eq 'short') { 'blanka' } else { 'köp' })"; f = [scriptblock]::Create("`$_.setup -eq '$k' -and `$_.side -eq '$sd'") } } }
  $groups += @{ name = 'Alla lägen i gapets riktning'; f = { $_.gapWith } }; $groups += @{ name = 'Alla lägen mot gapet'; f = { -not $_.gapWith } }; $groups += @{ name = 'Första timmen, i gapets riktning'; f = { $_.gapWith -and $_.minutes -le 60 } }
  $rows = foreach ($gr in $groups) { $set = @($all | Where-Object $gr.f); $th = @(for ($i = 0; $i -lt 3; $i++) { S5 @($set | Where-Object { $_.atT -ge $cut[$i] -and $_.atT -lt $cut[$i + 1] }) })
    $ok = @($th | Where-Object { $_.n -ge 50 -and $_.netB -gt 0 }).Count -eq 3
    [ordered]@{ name = $gr.name; all = (S5 $set); thirds = $th; holds = $ok; verdict = $(if ($ok) { 'håller i alla tre delarna' } elseif (@($th | Where-Object { $_.n -lt 50 }).Count) { 'för få lägen' } else { 'håller inte' }) } }
  $sum = [ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ'); from = [DateTimeOffset]::FromUnixTimeSeconds([int64]$mn).UtcDateTime.ToString('yyyy-MM-dd'); to = [DateTimeOffset]::FromUnixTimeSeconds([int64]$mx).UtcDateTime.ToString('yyyy-MM-dd')
    stocks = $U.Count; failed = $fail.Count; candles = $nBars; stockDays = $nDays; inPlayDays = $nPlay; signals = $all.Count; overall = (S5 $all)
    filter = 'Gap minst 3 % och volym de första 15 minuterna minst 2 gånger snittet för samma 15 minuter de 20 dagarna före.'
    rule = 'Bestämt före testet: godkänt = plus netto med billig mäklare i alla tre delarna och minst 50 utlösta i varje.'
    costs = 'Billig mäklare 0,05 % tur och retur; Avanza 0,2 % (utan växlingsavgiften på 0,25 % åt varje håll för USA-aktier, så i verkligheten ännu dyrare).'; rows = @($rows) }
  [IO.File]::WriteAllText((Join-Path $data 'daytrade5-inplay.json'), ($sum | ConvertTo-Json -Depth 6 -Compress), $enc)
  "--- $($U.Count) aktier ($($fail.Count) utan data), $nBars candlar, $nDays handelsdagar varav $nPlay i rörelse, $($all.Count) lägen ($([math]::Round($sw.Elapsed.TotalMinutes, 1)) min) ---"
  if ($fail.Count) { "utan data: $(($fail | Select-Object -First 10) -join ', ')" }
  foreach ($r0 in $rows) { "{0,-40} {1,5} st brutto {2,6} billig {3,6} Avanza {4,6} · delar billig {5} · {6}" -f $r0.name, $r0.all.n, $r0.all.gross, $r0.all.netB, $r0.all.netA, (($r0.thirds | ForEach-Object { $_.netB }) -join ' / '), $r0.verdict }
}