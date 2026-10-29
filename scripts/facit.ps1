# Facitloggen (Tradingbibeln, "Facitlogg – så utvecklas Jarvis"): varje analys med besked loggas och följs upp
# efter en och fyra veckor mot Yahoo Finance dagsdata. Källan är JSON-blocket i references\facitlogg.md;
# tabellen överst skrivs om från det vid varje körning.
# Lägen:
#   -Add <fil.json>                      lägger till en analys (fält: date, asset, ysym, shift, besked, price,
#                                        zone [lo,hi], zoneText, inval, invalText, targets [t1,t2], targetText)
#   -Check                               fyller i utfall 1 v och 4 v där tiden har gått
#   -Judge <id> -Verdict Rätt|Fel|Delvis -Lesson "..."   sätter omdöme och lärdom
# Körs: powershell -ExecutionPolicy Bypass -File facit.ps1 -Check
param([string]$Add, [switch]$Check, [string]$Judge, [string]$Verdict, [string]$Lesson)
$ErrorActionPreference = 'Stop'
# Facitloggen ligger i data/ (privata repot jarvis-data) sedan 29 okt, så att molnkörningarna sparar den; references/ är reserv
$File = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data/facitlogg.md'))
if (-not (Test-Path $File) -and (Test-Path (Join-Path $PSScriptRoot '../references/facitlogg.md'))) { $File = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../references/facitlogg.md')) }
$sv = [Globalization.CultureInfo]::GetCultureInfo('sv-SE')
function F($v, $d = 0) { if ($null -eq $v) { return '–' }; ([double]$v).ToString("N$d", $sv) }
function Load {
  $t = [IO.File]::ReadAllText($File, [Text.Encoding]::UTF8)
  $m = [regex]::Match($t, '(?s)<!-- facit-data -->\s*```json\s*(.*?)```')
  if (-not $m.Success) { throw 'JSON-blocket saknas i facitlogg.md' }
  foreach ($x in (ConvertFrom-Json -InputObject $m.Groups[1].Value)) { Entry $x }
}
$FIELDS = 'id', 'date', 'asset', 'ysym', 'shift', 'price', 'besked', 'zone', 'zoneText', 'inval', 'invalText', 'targets', 'targetText', 'o1', 'o4', 'verdict', 'lesson'
function Entry($x) {
  $o = [ordered]@{}; foreach ($k in $FIELDS) { $o[$k] = $x.$k }
  if ($null -eq $o.shift) { $o.shift = 0 }
  if (-not $o.id) { $o.id = "$($o.date)-" + (($o.asset -replace '[^A-Za-z0-9]', '').ToLower()) }
  $o.zone = @($o.zone | Where-Object { $null -ne $_ }); $o.targets = @($o.targets | Where-Object { $null -ne $_ })
  [pscustomobject]$o
}
function Outcome($e, $days) {
  $from = [DateTimeOffset]::new($(if ($e.date -is [datetime]) { [datetime]::SpecifyKind($e.date.Date, 'Unspecified') } else { [datetime]::ParseExact($e.date, 'yyyy-MM-dd', $null) })).ToUnixTimeSeconds()
  $to = $from + ($days + 1) * 86400
  $res = (Invoke-RestMethod -Uri "https://query2.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($e.ysym))?period1=$from&period2=$to&interval=1d" -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30).chart.result[0]
  $q = $res.indicators.quote[0]; $sh = [double]$e.shift; $hs = @(); $ls = @(); $cs = @()
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) {
    if ($res.timestamp[$i] -le $from -or $null -eq $q.close[$i]) { continue }
    $hs += [double]$q.high[$i] - $sh; $ls += [double]$q.low[$i] - $sh; $cs += [double]$q.close[$i] - $sh
  }
  if (-not $cs.Count) { return $null }
  $hi = ($hs | Measure-Object -Maximum).Maximum; $lo = ($ls | Measure-Object -Minimum).Minimum; $last = $cs[-1]; $minClose = ($cs | Measure-Object -Minimum).Minimum
  $z = @($e.zone); $tg = @($e.targets)
  $o = [ordered]@{
    high = [math]::Round($hi, 2); low = [math]::Round($lo, 2); close = [math]::Round($last, 2); chgPct = [math]::Round(($last / [double]$e.price - 1) * 100, 2)
    zone = $(if ($z.Count -ge 2) { $lo -le [double]$z[1] -and $hi -ge [double]$z[0] } else { $null })
    inval = $(if ($null -ne $e.inval) { $minClose -lt [double]$e.inval } else { $null })
    target = $(if ($tg.Count) { $hi -ge [double]$tg[0] } else { $null })
  }
  $parts = @("$(if ($o.chgPct -ge 0) { '+' })$(F $o.chgPct 1) % (högst $(F $o.high), lägst $(F $o.low))")
  if ($null -ne $o.zone) { $parts += $(if ($o.zone) { 'köpzonen nåddes' } else { 'köpzonen nåddes inte' }) }
  if ($null -ne $o.inval) { $parts += $(if ($o.inval) { 'stängde under invalideringen' } else { 'invalideringen höll' }) }
  if ($null -ne $o.target) { $parts += $(if ($o.target) { 'mål 1 nåddes' } else { 'mål 1 nåddes inte' }) }
  $o.text = $parts -join '; '
  [pscustomobject]$o
}
function Save($List) {
  $cell = { param($s) if ($null -eq $s -or "$s" -eq '') { '' } else { ("$s" -replace '\|', '/' -replace "`r?`n", ' ') } }
  $rows = foreach ($e in $List) { '| ' + ((@($e.date, $e.asset, $e.besked, $e.zoneText, $e.invalText, $e.targetText, $e.o1.text, $e.o4.text, $e.verdict, $e.lesson) | ForEach-Object { & $cell $_ }) -join ' | ') + ' |' }
  $List = @($List); $done = @($List | Where-Object { $_.verdict }).Count; $right = @($List | Where-Object { $_.verdict -eq 'Rätt' }).Count
  $md = @(
    '# Facitlogg'
    ''
    'Varje analys med besked loggas här och följs upp efter en och fyra veckor (Tradingbibeln, avsnittet Facitlogg). Utfallen fylls i av `scripts\facit.ps1 -Check` mot Yahoo Finance dagsdata; omdöme och lärdom sätter Claude med `-Judge`. Var 20:e bedömda analys: gå igenom vilka verktyg och nivåer som träffade och vilka som missade, och skriv ändringen i strategier.md eller kalibrering.md.'
    ''
    "Bedömda: $done av $($List.Count)$(if ($done) { ", rätt $right ($([math]::Round($right / $done * 100)) %)" })."
    ''
    '| Datum | Tillgång | Besked | Köpzon | Invalidering | Mål | Utfall 1 v | Utfall 4 v | Rätt/fel | Lärdom |'
    '|---|---|---|---|---|---|---|---|---|---|'
  ) + $rows + @('', '<!-- facit-data -->', '```json', (ConvertTo-Json -InputObject @($List) -Depth 6), '```', '')
  [IO.File]::WriteAllText($File, ($md -join "`n"), [Text.UTF8Encoding]::new($false))
}

$List = @(Load)
if ($Add) {
  $raw = Get-Content $Add -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($k in 'date', 'asset', 'ysym', 'besked', 'price') { if (-not $raw.$k) { throw "Fältet $k saknas" } }
  $n = Entry $raw; $n.o1 = $null; $n.o4 = $null
  if (@($List | Where-Object { $_.id -eq $n.id }).Count) { throw "Finns redan: $($n.id)" }
  $List = @($List) + @($n); Save $List; "Loggad: $($n.id)"; return
}
if ($Judge) {
  $e = $List | Where-Object { $_.id -eq $Judge } | Select-Object -First 1; if (-not $e) { throw "Ingen analys med id $Judge" }
  $e.verdict = $Verdict; $e.lesson = $Lesson; Save $List; "Bedömd: $Judge = $Verdict"; return
}
if ($Check) {
  $today = (Get-Date).Date; $changed = 0
  foreach ($e in $List) {
    $age = ($today - $(if ($e.date -is [datetime]) { [datetime]::SpecifyKind($e.date.Date, 'Unspecified') } else { [datetime]::ParseExact($e.date, 'yyyy-MM-dd', $null) })).TotalDays
    try {
      if ($null -eq $e.o1 -and $age -ge 7) { $e.o1 = Outcome $e 7; $changed++; "1 v $($e.id): $($e.o1.text)" }
      if ($null -eq $e.o4 -and $age -ge 28) { $e.o4 = Outcome $e 28; $changed++; "4 v $($e.id): $($e.o4.text)" }
    } catch { "Kunde inte följa upp $($e.id): $($_.Exception.Message)" }
  }
  Save $List
  $wait = @($List | Where-Object { $_.o1 -and -not $_.verdict }).Count
  "Facit: $(@($List).Count) analyser, $changed nya utfall, $wait väntar på omdöme."
}
