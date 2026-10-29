# Jarvis hälsokontroll. Körs sist i varje schemalagd körning (och när som helst för hand).
#   kontroll.ps1 -Run jarvis-testtrade-vakt          registrerar att körningen gick klart och kontrollerar allt
#   kontroll.ps1 -Run jarvis-morgonscan -Fail -Note "TradingView svarade inte"   registrerar en körning som misslyckades
#   kontroll.ps1                                      bara kontrollen
# Kontrollerar priser och datakontroll, scannern, att alla schemalagda körningar har gått, bevakningslistans besked mot nivåerna,
# dagens besked, testportföljen, makrokalendern, inkorgen och sidans fellogg. Skriver data\health.json (till meta/health i Jarvis)
# och raderna "HÄLSA: ..." och "PROBLEM: ...". Kontrollen ändrar aldrig nivåer, besked eller trades.
param([string]$Run, [switch]$Fail, [string]$Note, [string]$DbDir = (Join-Path $PSScriptRoot '../data/db-export'))
$ErrorActionPreference = 'Stop'
$data = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data'))
$enc = [Text.UTF8Encoding]::new($false)
$now = Get-Date; $nowU = $now.ToUniversalTime()
$sv = [Globalization.CultureInfo]::GetCultureInfo('sv-SE')
function J($f) { if (-not (Test-Path $f)) { return $null }; try { $o = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json; if ($o.PSObject.Properties.Name -contains 'data' -and $o.PSObject.Properties.Name -contains 'version') { $o.data } else { $o } } catch { $null } }
function Db($col, $id) { J (Join-Path $DbDir "$col/$id.json") }
function DbAll($col) { $d = Join-Path $DbDir $col; if (-not (Test-Path $d)) { return @() }; @(Get-ChildItem $d -Filter *.json | ForEach-Object { $o = J $_.FullName; if ($o) { $o | Add-Member -NotePropertyName _id -NotePropertyValue $_.BaseName -Force; $o } }) }
function T($s) { if (-not $s) { return $null }; if ($s -is [datetime]) { return $s.ToLocalTime() }; try { [DateTimeOffset]::Parse([string]$s, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime } catch { $null } }
function Age($dt) { if (-not $dt) { return [double]::PositiveInfinity }; ($now - $dt).TotalHours }
function Hm($h) { if ([double]::IsInfinity($h)) { 'aldrig' } elseif ($h -lt 1) { "$([math]::Round($h * 60)) min" } elseif ($h -lt 48) { "$([math]::Round($h, 1).ToString($sv)) h" } else { "$([math]::Round($h / 24)) dagar" } }
function N($v) { if ($null -eq $v -or "$v" -eq '') { return [double]::NaN }; try { [double]$v } catch { [double]::NaN } }
function Ok([double]$v) { -not ([double]::IsNaN($v) -or [double]::IsInfinity($v)) }
function F($v, $d = 2) { (N $v).ToString("N$d", $sv) }
$checks = [Collections.Generic.List[object]]::new()
function Add($k, $name, $level, $text, $items) { $checks.Add([ordered]@{ k = $k; name = $name; level = $level; text = $text; items = @($items | Where-Object { $_ }) }) }

# ---------- körningslogg ----------
$runsFile = Join-Path $data 'runs.json'
# since: körningar före loggens start räknas inte som missade. Saknas eller går loggen inte att läsa börjar den två dygn bakåt,
# så att en missad körning ändå syns (26 okt hade loggen börjat om och dolde att söndagens körning fastnat); en trasig logg sparas som runs-trasig.json
$runs = J $runsFile
if (-not $runs) { if (Test-Path $runsFile) { Copy-Item $runsFile (Join-Path $data 'runs-trasig.json') -Force }
  $runs = [pscustomobject]@{ since = $nowU.AddDays(-2).ToString('yyyy-MM-ddTHH:mm:ssZ'); tasks = [pscustomobject]@{} } }
if ($Run) {
  $prevRun = $runs.tasks.$Run; $stamp = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ')
  $entry = [pscustomobject]@{ at = $stamp; ok = (-not $Fail); note = $Note; lastOk = $(if (-not $Fail) { $stamp } elseif ($prevRun) { $prevRun.lastOk } else { $null }) }
  $runs.tasks | Add-Member -NotePropertyName $Run -NotePropertyValue $entry -Force
  [IO.File]::WriteAllText($runsFile, ($runs | ConvertTo-Json -Depth 5 -Compress), $enc)
}

# ---------- schemat: när borde varje körning senast ha gått klart ----------
$TASKS = @(
  @{ id = 'jarvis-morgonscan'; name = 'Morgonscan'; cron = '45 7 * * 1-5' }
  @{ id = 'jarvis-testtrade-vakt'; name = 'Testtrade-vakten'; cron = '0 10-21 * * 1-5' }
  @{ id = 'jarvis-kvallsscan'; name = 'Kvällsscan'; cron = '20 22 * * 1-5' }
  @{ id = 'jarvis-krypto-helg-auto'; name = 'Krypto helg'; cron = '0 10,20 * * 0,6' }   # ersatte jarvis-krypto-helg 25 okt (den gamla är pausad)
)
$GRACE = 50   # minuter: slumpad start (upp till ~11 min) plus själva körningen
function CronSet($f, $lo, $hi) {
  $out = @(); foreach ($part in $f -split ',') {
    $step = 1; if ($part -match '/(\d+)$') { $step = [int]$Matches[1]; $part = $part -replace '/\d+$', '' }
    if ($part -eq '*') { $a = $lo; $b = $hi } elseif ($part -match '^(\d+)-(\d+)$') { $a = [int]$Matches[1]; $b = [int]$Matches[2] } else { $a = [int]$part; $b = $a }
    for ($x = $a; $x -le $b; $x += $step) { $out += $x }
  }; $out
}
function LastFire($cron, $before) {
  $p = $cron -split '\s+'; $M = CronSet $p[0] 0 59; $H = CronSet $p[1] 0 23; $D = CronSet $p[4] 0 6
  for ($i = 0; $i -le 8; $i++) { $day = $before.Date.AddDays(-$i); if ([int]$day.DayOfWeek -notin $D) { continue }
    foreach ($h in ($H | Sort-Object -Descending)) { foreach ($m in ($M | Sort-Object -Descending)) { $t = $day.AddHours($h).AddMinutes($m); if ($t -le $before) { return $t } } } }
  $null
}
$since = T $runs.since; $runItems = @(); $runLevel = 'ok'; $runOut = @()
foreach ($tk in $TASKS) {
  $fire = LastFire $tk.cron $now.AddMinutes(-$GRACE)
  $hb = $runs.tasks.($tk.id); $last = if ($hb) { T $hb.at } else { $null }; $lastOk = if ($hb -and $hb.lastOk) { T $hb.lastOk } else { $null }
  $lvl = 'ok'; $txt = if ($last) { "senast $($last.ToString('ddd d MMM HH:mm', $sv))" } else { 'ingen kontroll registrerad än' }
  if ($hb -and $hb.ok -eq $false) { $lvl = 'fel'; $txt = "misslyckades $($last.ToString('ddd HH:mm', $sv))$(if ($hb.note) { ": $($hb.note)" })" }
  elseif ($fire -and $since -and $fire -gt $since -and (-not $lastOk -or $lastOk -lt $fire)) { $lvl = 'fel'; $txt = "körningen $($fire.ToString('ddd HH:mm', $sv)) har inte gått klart (fastnat på ett godkännande eller inte startat)" }
  if ($lvl -ne 'ok') { $runLevel = 'fel'; $runItems += "$($tk.name): $txt" }
  $runOut += [ordered]@{ id = $tk.id; name = $tk.name; last = $(if ($last) { $last.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }); ok = $(if ($hb) { $hb.ok } else { $null }); expected = $(if ($fire) { $fire.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }); level = $lvl; text = $txt }
}
Add 'runs' 'Schemalagda körningar' $runLevel $(if ($runLevel -eq 'ok') { 'Alla körningar har gått enligt schemat.' } else { 'En körning har missats. Öppna den i Claude-appen och godkänn eller stoppa den; ställ in uppgiften på Auto.' }) $runItems

# ---------- marknadstider ----------
$wd = [int]$now.DayOfWeek -in 1..5; $dayHours = $wd -and $now.Hour -ge 9 -and $now.Hour -lt 22

# ---------- priser och datakontroll ----------
try {
  $pLocal = J (Join-Path $data 'watch/prices.json'); $pDb = Db 'meta' 'prices'
  $pAt = @((T $pLocal.at), (T $pDb.at)) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
  $maxH = if ($dayHours) { 2.5 } else { 14.5 }; $h = Age $pAt
  $q = J (Join-Path $data 'watch/quality.json'); $qe = @($q.err | Where-Object { $_ }); $qw = @($q.warn | Where-Object { $_ }); $qo = @($q.ok | Where-Object { $_ })
  $items = @($qe | ForEach-Object { "Fel: $_" }) + @($qw | ForEach-Object { "Varning: $_" })
  $lvl = if ($h -gt 2 * $maxH -or $qe.Count) { 'fel' } elseif ($h -gt $maxH -or $qw.Count) { 'varning' } else { 'ok' }
  Add 'prices' 'Priser' $lvl "Senast uppdaterade för $(Hm $h) sedan$(if ($h -gt $maxH) { " (ska vara högst $(Hm $maxH) $(if ($dayHours) { 'när börserna är öppna' } else { 'utanför börstid' }))" }). $(if ($q) { "$($qo.Count) av $($qo.Count + $qe.Count) kontrollerade mot två källor." })" $items
} catch { Add 'prices' 'Priser' 'fel' "Kontrollen kunde inte läsa priserna: $($_.Exception.Message)" @() }

# ---------- scannern ----------
try {
  $sc = J (Join-Path $data 'scan-latest.json'); $h = Age (T $sc.at); $maxH = if ($dayHours) { 3 } else { 15 }; $items = @()
  # sedan 25 okt: 16 aktiemarknader plus krypto, cirka 4 500 instrument
  $u = $sc.universe; if ($u) { if ([int]$u.us -lt 1500) { $items += "Bara $($u.us) amerikanska aktier (brukar vara cirka 2 200)" }; if ([int]$u.se -lt 300) { $items += "Bara $($u.se) svenska aktier (brukar vara cirka 480)" }; if ([int]$u.crypto -lt 150) { $items += "Bara $($u.crypto) kryptovalutor (brukar vara cirka 280)" }
    foreach ($p in @($u.markets.PSObject.Properties)) { if ([int]$p.Value -eq 0) { $items += "Marknaden $($p.Name) saknas i scanningen (TradingView svarade inte)" } } } else { $items += 'Scanningen saknar universum' }
  foreach ($c in @($sc.candidates | Where-Object { $_ })) { $g = if ($c.side -eq 'short') { -1 } else { 1 }
    if (-not ((N $c.price) -gt 0) -or $g * ((N $c.entry) - (N $c.stop)) -le 0 -or $g * ((N $c.t1) - (N $c.entry)) -le 0) { $items += "$($c.symbol): entry, stopp och mål går inte ihop" } }
  $lvl = if ($h -gt 2 * $maxH -or $items.Count) { 'fel' } elseif ($h -gt $maxH) { 'varning' } else { 'ok' }
  Add 'scan' 'Scannern' $lvl "Senaste scanning för $(Hm $h) sedan: $(if ($u.total) { "$($u.total) instrument i $(@($u.markets.PSObject.Properties).Count) marknader" } else { "$($u.us) USA, $($u.se) Sverige, $($u.crypto) krypto" }), $($u.deep) djupanalyserade, $(@($sc.candidates).Count) utvalda." $items
} catch { Add 'scan' 'Scannern' 'fel' "Kunde inte läsa scanningen: $($_.Exception.Message)" @() }

# ---------- bevakningslistan: besked mot nivåer ----------
try {
  $items = @(); $lvl = 'ok'
  foreach ($a in (DbAll 'assets')) {
    $id = $a._id; $u = J (Join-Path $data "watch/upd-$id.json"); $p = if ($u -and (Ok (N $u.price))) { N $u.price } else { N $a.price }
    $inv = N $a.inval; $bos = N $a.bos; $nm = if ($a.name) { $a.name } else { $id }
    if ($u.dataWarn -or $a.dataWarn) { $items += "$($nm): $(if ($u.dataWarn) { $u.dataWarn } else { $a.dataWarn })"; $lvl = 'fel' }
    if ((Ok $inv) -and $p -lt $inv -and $a.status -ne 'kopinte') { $items += "$nm $(F $p ($a.dec)) är under fel om-nivån $(F $inv ($a.dec)) men beskedet är '$($a.status)': nivåerna behöver ses över"; if ($lvl -eq 'ok') { $lvl = 'varning' } }
    elseif ((Ok $bos) -and $p -gt $bos -and $a.status -in 'vanta', 'bevaka') { $items += "$nm $(F $p ($a.dec)) är över BOS $(F $bos ($a.dec)): kräver stängning och ny analys"; if ($lvl -eq 'ok') { $lvl = 'varning' } }
  }
  Add 'levels' 'Bevakningslistan' $lvl $(if ($items.Count) { 'Ett eller flera besked stämmer inte med priset. Jarvis visar det i korten tills nästa analys.' } else { 'Alla besked stämmer med priset och nivåerna.' }) $items
} catch { Add 'levels' 'Bevakningslistan' 'varning' "Kunde inte jämföra: $($_.Exception.Message)" @() }

# ---------- dagens besked ----------
try {
  $b = Db 'meta' 'brief'; $bd = if ($b.date) { $(if ($b.date -is [datetime]) { $b.date.Date } else { [datetime]::ParseExact($b.date, 'yyyy-MM-dd', $null) }) } else { $null }
  $lvl = 'ok'; $txt = "Skrivet $($b.date) $($b.time)."
  if ($wd -and ($now.Hour -gt 8 -or ($now.Hour -eq 8 -and $now.Minute -ge 30)) -and (-not $bd -or $bd.Date -lt $now.Date)) { $lvl = 'varning'; $txt += ' Morgonens besked saknas, så texten kan ha gamla priser.' }
  Add 'brief' 'Dagens besked' $lvl $txt @()
} catch { Add 'brief' 'Dagens besked' 'varning' "Kunde inte läsa beskedet: $($_.Exception.Message)" @() }

# ---------- testportföljen ----------
try {
  $L = J (Join-Path $data 'paper/ledger.json'); $items = @(); $lvl = 'ok'
  if (-not $L) { throw 'ledger.json saknas' }
  $ids = @($L.trades | ForEach-Object { $_.id }); $dup = @($ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }); if ($dup.Count) { $items += "Dubbla trade-id: $($dup -join ', ')"; $lvl = 'fel' }
  $act = @($L.trades | Where-Object { $_.status -in 'väntar', 'öppen' }); $nowT = [DateTimeOffset]::new($nowU).ToUnixTimeSeconds()
  $eq = [double]$L.start; $openRisk = 0.0
  foreach ($t in $act) { $g = if ($t.side -eq 'short') { -1 } else { 1 }; $pl = $t.plan; $openRisk += N $t.riskKr
    if ($g * ((N $pl.entry) - (N $pl.stop)) -le 0 -or $g * ((N $pl.t1) - (N $pl.entry)) -le 0) { $items += "$($t.symbol): entry, stopp och mål går inte ihop"; $lvl = 'fel' }
    if (-not $t.tplan) { $items += "$($t.symbol): handelsplan saknas"; $lvl = 'fel' }
    if (-not ((N $t.riskKr) -gt 0)) { $items += "$($t.symbol): risken saknas"; $lvl = 'fel' }
    if ($t.status -eq 'väntar' -and $t.horizon -ne 'day' -and $nowT - [double]$t.createdT -gt 7.5 * 86400) { $items += "$($t.symbol): ordern borde ha förfallit (äldre än 7 dagar)"; $lvl = 'fel' }
    $lh = ($nowT - (N $t.lastT)) / 3600; $mx = if ($dayHours) { 3 } else { 16 }
    if ($t.market -eq 'Krypto' -or $wd) { if ($lh -gt $mx) { $items += "$($t.symbol): inte uppföljd på $(Hm $lh)"; if ($lvl -eq 'ok') { $lvl = 'varning' } } }
  }
  $eqLast = if (@($L.equity).Count) { N (@($L.equity)[-1][1]) } else { $eq }
  if (-not (Ok $eqLast) -or $eqLast -le 0) { $items += 'Portföljvärdet går inte att räkna'; $lvl = 'fel' }
  # gränsen kommer från motorn: 10 % under lärfasen (de första 30 avslutade), annars 5 %
  $ds = J (Join-Path $data 'paper/db-state.json'); $maxR = if ($ds -and (N $ds.stats.maxOpenRiskPct) -gt 0) { N $ds.stats.maxOpenRiskPct } else { 5 }
  if ((Ok $eqLast) -and $eqLast -gt 0 -and $openRisk / $eqLast * 100 -gt $maxR + 0.05) { $items += "Total risk $(F ($openRisk / $eqLast * 100) 1) % (högst $(F $maxR 0) %)"; $lvl = 'fel' }
  $uns = @($L.events | Where-Object { $_.sent -eq $false -and $nowT - [double]$_.t -gt 3 * 3600 }); if ($uns.Count) { $items += "$($uns.Count) händelser har inte skickats som notis"; if ($lvl -eq 'ok') { $lvl = 'varning' } }
  $ue = J (Join-Path $data 'paper/update-errors.json'); foreach ($e in @($ue.errors)) { if ($e) { $items += "Uppföljningen: $e"; $lvl = 'fel' } }
  Add 'paper' 'Testportföljen' $lvl "$($act.Count) aktiva, total risk $(F ($openRisk / [math]::Max(1, $eqLast) * 100) 1) %, värde $(F $eqLast 0) kr." $items
} catch { Add 'paper' 'Testportföljen' 'fel' "Kunde inte kontrollera: $($_.Exception.Message)" @() }

# ---------- makrokalendern ----------
try {
  $mk = J (Join-Path $data 'paper/makrokalender.json'); $fut = @($mk.events | Where-Object { (T $_.t) -gt $now } | Sort-Object { T $_.t })
  $lvl = if (-not $fut.Count) { 'fel' } elseif ((T $fut[-1].t) -lt $now.AddDays(30)) { 'varning' } else { 'ok' }
  Add 'macro' 'Makrokalendern' $lvl $(if ($fut.Count) { "Nästa: $($fut[0].label). $($fut.Count) kommande besked inlagda$(if ($lvl -eq 'varning') { '; fyll på med fler än en månad framåt' })." } else { 'Inga kommande Fed- eller KPI-datum: testtrades före besked märks inte och rutan Nästa händelse blir tom.' }) @()
} catch { Add 'macro' 'Makrokalendern' 'fel' "Kunde inte läsa: $($_.Exception.Message)" @() }

# ---------- inkorgen och sidans fellogg ----------
try {
  $old = @(DbAll 'inbox' | Where-Object { $_.status -eq 'ny' -and (Age (T $_.t)) -gt 3 })
  Add 'inbox' 'Inkorgen' $(if ($old.Count) { 'varning' } else { 'ok' }) $(if ($old.Count) { "$($old.Count) meddelanden väntar på svar sedan över 3 timmar." } else { 'Inga obesvarade meddelanden.' }) @()
  # fel som är åtgärdade (resolved: true, med resolvedNote) räknas inte
  $logs = @(DbAll 'logs' | Where-Object { (Age (T $_.t)) -lt 24 -and $_.resolved -ne $true })
  Add 'logs' 'Sidans fellogg' $(if ($logs.Count) { 'varning' } else { 'ok' }) $(if ($logs.Count) { "$($logs.Count) fel i sidan senaste dygnet." } else { 'Inga fel från sidan senaste dygnet.' }) @($logs | Select-Object -First 5 | ForEach-Object { "$($_.where): $($_.msg)" })
} catch { Add 'inbox' 'Inkorgen' 'varning' "Kunde inte läsa: $($_.Exception.Message)" @() }

# ---------- sammanfattning ----------
$nF = @($checks | Where-Object { $_.level -eq 'fel' }).Count; $nW = @($checks | Where-Object { $_.level -eq 'varning' }).Count
$level = if ($nF) { 'fel' } elseif ($nW) { 'varning' } else { 'ok' }
$summary = if ($level -eq 'ok') { 'Allt fungerar.' } else { (@($checks | Where-Object { $_.level -ne 'ok' } | ForEach-Object { $_.name }) -join ', ') + $(if ($nF) { ' behöver åtgärdas.' } else { ' har varningar.' }) }
$health = [ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ'); by = $(if ($Run) { $Run } else { 'hand' }); level = $level; summary = $summary; checks = $checks; runs = $runOut }
[IO.File]::WriteAllText((Join-Path $data 'health.json'), ($health | ConvertTo-Json -Depth 6 -Compress), $enc)
"HÄLSA: $level – $summary"
foreach ($c in $checks | Where-Object { $_.level -ne 'ok' }) { "PROBLEM ($($c.level)) $($c.name): $($c.text)"; foreach ($i in $c.items) { "    - $i" } }
