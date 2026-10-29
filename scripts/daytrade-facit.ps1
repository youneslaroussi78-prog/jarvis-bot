# Facit för daytradelägena (Devin 26 okt: "bygg backtest och facit för daytradelägena").
#   daytrade-facit.ps1 -Backtest   kör daytrade-analysen bakåt på Yahoos 15m-data (60 dagar) för den fasta listan (olja, metaller, index,
#                                  krypto och sex USA-aktier), varje hel timme 10–20 svensk tid som vakten, och räknar utfallet för varje läge
#                                  exakt som testportföljen: stopporder vid BOS, en tredjedel vid mål 1 och break-even, resten vid mål 2 eller
#                                  dagens slut, med kostnader. Skriver data\daytrade-backtest.json.
#   daytrade-facit.ps1 -Check      räknar utfallet för lägena som daytrade.ps1 sparat i data\daytrade-signals.json när deras dag är slut.
# Båda skriver data\daytrade-stats.json (till scan/daystats i Jarvis). Ett läge räknas första gången det syns per dag, och en gång till
# första gången det är redo (A, nära entry, inget hinder), så att samma läge inte räknas varje timme.
param([switch]$Backtest, [switch]$Check, [string]$Only, [string]$Range = '60d', [string]$Cfg, [string]$Tag, [string]$Universe, [switch]$Trials)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'daytrade-lib.ps1')
# -Cfg prövar andra inställningar (till exempel "costFloorR=0.15;noOrb=1"); -Tag skriver resultatet till daytrade-backtest-<tag>.json i stället
if ($Cfg) { foreach ($kv in $Cfg -split ';') { $p2 = $kv -split '='; $DT_CFG[$p2[0].Trim()] = if ($p2[1] -match '^[\d.]+$') { [double]$p2[1] } else { $p2[1].Trim() } } }
$btName = if ($Tag) { "daytrade-backtest-$Tag" } else { 'daytrade-backtest' }
$data = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data'))
$nowU = (Get-Date).ToUniversalTime(); $nowT = [DateTimeOffset]::new($nowU).ToUnixTimeSeconds(); $enc = [Text.UTF8Encoding]::new($false)
$se = TzFind('W. Europe Standard Time')
function CostOf($cls) { switch ($cls) { 'Aktier' { 0.002 } 'Krypto' { 0.003 } default { 2 * (0.001 + 0.004) / 9.5 } } }
function Bucket($sc) { if ($sc -ge 80) { '80+' } elseif ($sc -ge 70) { '70–79' } elseif ($sc -ge 58) { '58–69' } elseif ($sc -ge 45) { '45–57' } else { 'under 45' } }
function Summary($first, $ready) {
  [ordered]@{ all = DtStats $first; ready = DtStats $ready
    readyBySetup = DtGroup $ready { "$($_.setup) $($_.side)" }; allBySetup = DtGroup $first { "$($_.setup) $($_.side)" }
    byGrade = DtGroup $first { $_.grade }; byScore = DtGroup $first { Bucket $_.score }; readyByClass = DtGroup $ready { $_.class }
    readyByHour = DtGroup $ready { '{0:00}' -f [int]$_.hour }; readyByVolume = DtGroup $ready { if (@($_.flags) -contains 'Låg volym') { 'låg volym' } else { 'normal eller hög volym' } }
    readyByTrend = DtGroup $ready { if (@($_.flags) -contains 'Mot dagstrenden') { 'mot dagstrenden' } elseif ($_.trendWith) { 'med dagstrenden' } else { 'dagstrend sidled' } }
    readyByInstr = DtGroup $ready { $_.symbol } }
}

if ($Backtest) {
  # -Universe bred lägger till aktier som ofta gappar på nyheter (DT_EXTRA), för att pröva nyhetsgap
  $list = @($DT_INSTR) + @(if ($Universe -eq 'bred') { $DT_EXTRA }); if ($Only) { $list = @($list | Where-Object { $_.id -in ($Only -split ',') }) }
  $REC = [Collections.Generic.List[object]]::new(); $evals = 0; $from = $null; $to = $null; $sw = [Diagnostics.Stopwatch]::StartNew()
  foreach ($ins in $list) {
    try {
      $B = Get15 $ins.y $Range; $D = GetD $ins.y '1y'; $X = ToArrays $B; $cls = DtClass $ins; $cost = DayCostPct $ins; $seen = @{}; $nI = 0
      if ($B.Count -lt 200) { "$($ins.name): för lite data"; continue }
      $lastT = $X.tA[$X.tA.Length - 1]
      # svenska datum i datan (utom i dag och helger), och varje hel timme 10–20 som vakten
      $dates = @($X.tA | ForEach-Object { [TimeZoneInfo]::ConvertTimeFromUtc([DateTimeOffset]::FromUnixTimeSeconds([int64]$_).UtcDateTime, $se).Date } | Sort-Object -Unique | Where-Object { [int]$_.DayOfWeek -notin 0, 6 -and $_ -lt [TimeZoneInfo]::ConvertTimeFromUtc($nowU, $se).Date })
      foreach ($dt in $dates) {
        foreach ($h in 10..20) {
          $atT = [double][DateTimeOffset]::new([TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($dt.AddHours($h), 'Unspecified'), $se)).ToUnixTimeSeconds()
          if ($atT -gt $lastT) { continue }
          $A = Analyze $ins $X $D $atT @{ cal = @(); earn = $null }; $evals++
          if (-not $A) { continue }
          foreach ($s in $A.setups) { $g = if ($s.side -eq 'short') { -1 } else { 1 }; $id = "dt-$($ins.id)-$($s.key)-$(if ($g -lt 0) { 's' } else { 'l' })"; $sid = "$($dt.ToString('yyyy-MM-dd'))-$id"
            foreach ($k in @($sid) + @(if ($s.ready) { "$sid-r" })) { if ($seen[$k]) { continue }; $seen[$k] = 1
              $sr = @{ side = $s.side; entry = (Rn $s.entry $ins.dec); stop = (Rn $s.stop $ins.dec); t1 = (T1R $s $ins.dec); t2 = (Rn $s.t2 $ins.dec) }
              $out = Outcome $X $sr $atT $A.sEnd $cost; if (-not $out) { continue }
              $REC.Add([pscustomobject]@{ sid = $k; first = ($k -notlike '*-r'); ins = $ins.id; symbol = $ins.name; class = $cls; setup = $s.key; side = $s.side; grade = $s.grade; score = $s.score; ready = $s.ready
                flags = @($s.flags); trendWith = (($g -gt 0 -and $A.trendD -gt 0) -or ($g -lt 0 -and $A.trendD -lt 0)); hour = $h; riskPct = (Rn $s.riskPct 2); dist = (Rn $s.dist 2); relVol = (Rn $A.rv 2); atT = $atT; out = $out }); $nI++
              if ($null -eq $from -or $atT -lt $from) { $from = $atT }; if ($null -eq $to -or $atT -gt $to) { $to = $atT } } }
        }
      }
      "{0,-20} {1,4} lägen ({2:N0} s)" -f $ins.name, $nI, $sw.Elapsed.TotalSeconds
    } catch { "$($ins.name): backtestet misslyckades ($($_.Exception.Message))" }
  }
  $first = @($REC | Where-Object { $_.first }); $ready = @($REC | Where-Object { -not $_.first })
  $bt = [ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ'); range = $Range; from = $(if ($from) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$from).UtcDateTime.ToString('yyyy-MM-dd') }); to = $(if ($to) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$to).UtcDateTime.ToString('yyyy-MM-dd') })
    instruments = $list.Count; universe = $(if ($Universe) { $Universe } else { 'fast lista' }); cfg = $DT_CFG; evals = $evals; signals = $first.Count; readySignals = $ready.Count
    note = 'Fast lista (olja, metaller, index, krypto och sex USA-aktier) varje hel timme 10–20 svensk tid. Utan rapportdagar och dagens urval av aktier som rör sig mest, som inte går att återskapa bakåt. Stopp före mål om båda nås i samma 15m-candle.'
    costs = 'Tur och retur: aktier 0,2 %, krypto 0,3 %, index och råvaror via turbo 9,5x cirka 0,11 % av underliggande (courtage 0,1 % och spread 0,4 % på produktens värde).'
    summary = (Summary $first $ready) }
  [IO.File]::WriteAllText((Join-Path $data "$btName.json"), ($bt | ConvertTo-Json -Depth 8 -Compress), $enc)
  [IO.File]::WriteAllText((Join-Path $data "$btName-lagen.json"), (ConvertTo-Json -InputObject @($REC) -Depth 6 -Compress), $enc)
  "--- backtest: $evals analyser, $($first.Count) lägen, $($ready.Count) redo ($([math]::Round($sw.Elapsed.TotalMinutes, 1)) min) ---"
  # en provad variant ändrar inte Jarvis statistik
  if ($Tag) { foreach ($nm in 'all', 'ready') { $x0 = $bt.summary.$nm; "{0,-6} n {1} utlösta {2} träff {3} % brutto {4} R netto {5} R kostnad {6} R vinstfaktor {7}" -f $nm, $x0.n, $x0.triggered, $x0.winRate, $x0.avgR, $x0.avgRNet, $x0.avgCostR, $x0.pf }; return }
}

# -Trials: prövade setups (daytrade-backtest-nya-lagen.json, från -Backtest -Universe bred -Cfg "trial=gapgo,gapfade,trend,orb60" -Tag nya)
# delas i två halvor per setup och riktning (listan packas upp med ForEach-Object, annars blir den ett enda objekt i PowerShell 5.1). Godkänt = plus netto i båda halvorna och minst 20 utlösta i varje (Devin 26 okt: "behåll bara det som håller i båda halvorna").
if ($Trials) {
  $tf = Join-Path $data 'daytrade-backtest-nya-lagen.json'
  if (Test-Path $tf) { $TR = @((Get-Content $tf -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_.first }); $mn =($TR | Measure-Object atT -Minimum).Minimum; $mx = ($TR | Measure-Object atT -Maximum).Maximum; $mid = $mn + ($mx - $mn) / 2
    $NAMES = @{ gapgo = 'Nyhetsgap som håller'; gapfade = 'Nyhetsgap som inte håller'; trend = 'Trenddag'; orb60 = 'ORB 60 min'; sweep = 'Sweep'; vwap = 'VWAP-trend' }
    $rows = foreach ($grp in $TR | Group-Object { "$($_.setup) $($_.side)" } | Sort-Object Name) { $k0 = $grp.Name -split ' '
      $h1 = DtStats @($grp.Group | Where-Object { $_.atT -lt $mid }); $h2 = DtStats @($grp.Group | Where-Object { $_.atT -ge $mid })
      $ok = $h1.triggered -ge 20 -and $h2.triggered -ge 20 -and $h1.avgRNet -gt 0 -and $h2.avgRNet -gt 0
      [ordered]@{ key = $grp.Name; name = "$($NAMES[$k0[0]]) $(if ($k0[1] -eq 'short') { 'blanka' } else { 'köp' })"; trial = ($k0[0] -in 'gapgo', 'gapfade', 'trend', 'orb60'); all = (DtStats $grp.Group); h1 = $h1; h2 = $h2; holds = $ok
        verdict = $(if ($ok) { 'håller i båda halvorna' } elseif ($h1.triggered -lt 20 -or $h2.triggered -lt 20) { 'för få lägen' } else { 'håller inte' }) } }
    $tri = [ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ'); from = [DateTimeOffset]::FromUnixTimeSeconds([int64]$mn).UtcDateTime.ToString('yyyy-MM-dd'); to = [DateTimeOffset]::FromUnixTimeSeconds([int64]$mx).UtcDateTime.ToString('yyyy-MM-dd')
      universe = 'fasta listan plus 28 aktier som ofta gappar (USA och Europa)'; rule = 'Godkänt: plus netto i båda halvorna och minst 20 utlösta i varje.'; setups = @($rows) }
    [IO.File]::WriteAllText((Join-Path $data 'daytrade-trials.json'), ($tri | ConvertTo-Json -Depth 6 -Compress), $enc)
    foreach ($r0 in $rows) { "{0,-34} första {1,7} R ({2,4} st) · andra {3,7} R ({4,4} st) · {5}" -f $r0.name, $r0.h1.avgRNet, $r0.h1.triggered, $r0.h2.avgRNet, $r0.h2.triggered, $r0.verdict }
  } else { 'Inget provresultat än: kör -Backtest -Universe bred -Cfg "trial=gapgo,gapfade,trend,orb60" -Tag nya först.' }
}
if ($Check) {
  $sigFile = Join-Path $data 'daytrade-signals.json'; $sigDoc = $null; try { $sigDoc = Get-Content $sigFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
  $SIG = @(if ($sigDoc) { $sigDoc.signals }); $todo = @($SIG | Where-Object { $null -eq $_.out -and [double]$_.sessionEnd -lt $nowT })
  $done = 0
  foreach ($grp in $todo | Group-Object ysym) {
    try { $old = ($grp.Group | Measure-Object atT -Minimum).Minimum; $X = ToArrays (Get15 $grp.Name $(if ($nowT - $old -gt 4 * 86400) { '1mo' } else { '5d' }))
      foreach ($sg in $grp.Group) { $o = Outcome $X $sg ([double]$sg.atT) ([double]$sg.sessionEnd) (CostOf $sg.class); if ($o) { $sg.out = [pscustomobject]$o; $done++ } }
    } catch { "$($grp.Name): kunde inte följas upp ($($_.Exception.Message))" }
  }
  if ($sigDoc) { $sigDoc.signals = @($SIG); [IO.File]::WriteAllText($sigFile, ($sigDoc | ConvertTo-Json -Depth 6 -Compress), $enc) }
  "facit: $done lägen följda upp nu, $(@($SIG | Where-Object { $_.out }).Count) av $($SIG.Count) har utfall"
}

# samlad statistik till Jarvis (scan/daystats): live-facit plus backtestets sammanfattning
$SIG = @(); try { $SIG = @((Get-Content (Join-Path $data 'daytrade-signals.json') -Raw -Encoding UTF8 | ConvertFrom-Json).signals | Where-Object { $_.out }) } catch { }
foreach ($sg in $SIG) { if ($null -eq $sg.PSObject.Properties['hour']) { $sg | Add-Member hour ([TimeZoneInfo]::ConvertTimeFromUtc([DateTimeOffset]::FromUnixTimeSeconds([int64]$sg.atT).UtcDateTime, $se).Hour) }
  if ($null -eq $sg.PSObject.Properties['trendWith']) { $sg | Add-Member trendWith ($false) } }
$btS = $null; try { $btS = Get-Content (Join-Path $data "$btName.json") -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
$stats = [ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ')
  live = [ordered]@{ signals = @($SIG | Where-Object { $_.first }).Count; summary = (Summary @($SIG | Where-Object { $_.first }) @($SIG | Where-Object { -not $_.first })) }
  variants = @(foreach ($vf in Get-ChildItem $data -Filter 'daytrade-backtest-v*.json' | Where-Object { $_.Name -notlike '*-lagen.json' } | Sort-Object Name) { try { $v0 = Get-Content $vf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    [ordered]@{ name = ($vf.BaseName -replace '^daytrade-backtest-', ''); cfg = $v0.cfg; all = $v0.summary.all; ready = $v0.summary.ready } } catch { } })
  inplay = $(try { Get-Content (Join-Path $data 'daytrade5-inplay.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null })   # aktier i rörelse (daytrade5.ps1 -InPlay)
  tf5 = $(try { Get-Content (Join-Path $data 'daytrade5-backtest.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null })   # 5m-testet (daytrade5.ps1 -Backtest)
  trials = $(try { Get-Content (Join-Path $data 'daytrade-trials.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null })
  backtest = $(if ($btS) { [ordered]@{ at = $btS.at; from = $btS.from; to = $btS.to; instruments = $btS.instruments; signals = $btS.signals; readySignals = $btS.readySignals; note = $btS.note; costs = $btS.costs; summary = $btS.summary } }) }
[IO.File]::WriteAllText((Join-Path $data 'daytrade-stats.json'), ($stats | ConvertTo-Json -Depth 8 -Compress), $enc)
if ($btS) { $rdy = $btS.summary.ready; $alls = $btS.summary.all
  "Backtest $($btS.from)–$($btS.to): alla lägen $($alls.triggered) utlösta, träff $($alls.winRate) %, snitt $($alls.avgRNet) R netto (brutto $($alls.avgR) R, kostnad $($alls.avgCostR) R) · redo-lägen $($rdy.triggered) utlösta, träff $($rdy.winRate) %, snitt $($rdy.avgRNet) R netto, vinstfaktor $($rdy.pf)" }
