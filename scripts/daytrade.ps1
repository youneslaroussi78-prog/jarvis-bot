# Daytrade-scanner (Devin 26 okt: "du gör knappt några daytrades, det vill jag att du gör! kolla oljan tillexempel").
# Letar intradagslägen på 15-minutersdata (Yahoo) i likvida marknader: olja (WTI, Brent), guld, silver, koppar, Nasdaq- och
# S&P-terminer, DAX, OMXS30, BTC, ETH, SOL och de största amerikanska techbolagen. Bibelns daytrade-verktyg:
#   ORB (opening range breakout, första 30 minuterna av huvudsessionen), sweep av gårdagens high/low med återtagning (PDH/PDL,
#   turtle soup), VWAP-trend med rekyl (first pullback, VWAP reclaim/rejection). Plus filter: dagstrend, VWAP-sida, relativ
#   volym, EIA för olja, rapport i dag eller i morgon för aktier, sessionstider.
# Varje läge får entry (stop-order vid BOS på 15m), stopp, mål 1 och 2 (minst 1:2), betyg och om det är redo.
#   daytrade.ps1           skriver data\daytrade-latest.json (till scan/day i Jarvis) och visar lägena
#   daytrade.ps1 -Plans    skriver också planutkast för redo lägen i data\paper\plan-day-<tid>.json (granska innan -Open)
param([switch]$Plans, [string]$Only)
$ErrorActionPreference = 'Stop'
$data = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data'))
$nowU = (Get-Date).ToUniversalTime(); $nowT = [DateTimeOffset]::new($nowU).ToUnixTimeSeconds()
# Analysen (lägen, betyg, utfall) ligger i daytrade-lib.ps1, som backtestet och facit (daytrade-facit.ps1) också använder.
. (Join-Path $PSScriptRoot 'daytrade-lib.ps1')
$INSTR = @($DT_INSTR)
if ($Only) { $INSTR = @($INSTR | Where-Object { $_.id -in ($Only -split ',') }) }
# rapportdatum för aktierna (TradingView)
$EARN = @{}; try { $tk = @($INSTR | Where-Object { $_.stock } | ForEach-Object { $_.tv }); if ($tk.Count) { $tvb = @{ symbols = @{ tickers = $tk }; columns = @('earnings_release_next_date') } | ConvertTo-Json -Depth 5 -Compress
  $r = Invoke-RestMethod -Method Post -Uri 'https://scanner.tradingview.com/global/scan' -Body $tvb -ContentType 'application/json' -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Origin' = 'https://www.tradingview.com' } -TimeoutSec 30
  foreach ($x in $r.data) { if ($x.d[0]) { $EARN[$x.s] = [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.d[0]).UtcDateTime } } } } catch { }
# ---------- steg 1: alla aktier på börser som är öppna just nu (Devin 26 okt: "det kan väll vara för alla möjliga aktier") ----------
# TradingView sorterar på relativ volym; de som rör sig mest i dag ("in play": hög relativ volym, stor rörelse eller gap, hög ATR och god
# likviditet) går vidare till 15-minutersanalysen. cap = lägsta börsvärde i marknadens valuta, liq = lägsta dagsomsättning i USD.
$MKT = @(
  @{ tv = 'america'; name = 'USA'; pre = 'us'; ex = @('NASDAQ', 'NYSE', 'AMEX'); y = @{}; open = @('09:30', 'Eastern Standard Time'); cap = 2e9; liq = 2e7; top = 25 }
  @{ tv = 'sweden'; name = 'Sverige'; pre = 'se'; ex = @('OMXSTO'); y = @{ OMXSTO = '.ST' }; open = @('09:00', 'W. Europe Standard Time'); cap = 1e9; liq = 1e6; top = 8 }
  @{ tv = 'norway'; name = 'Norge'; pre = 'no'; ex = @('OSL'); y = @{ OSL = '.OL' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 1e6; top = 4 }
  @{ tv = 'denmark'; name = 'Danmark'; pre = 'dk'; ex = @('OMXCOP'); y = @{ OMXCOP = '.CO' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 1e6; top = 3 }
  @{ tv = 'finland'; name = 'Finland'; pre = 'fi'; ex = @('OMXHEX'); y = @{ OMXHEX = '.HE' }; open = @('10:00', 'GTB Standard Time'); cap = 3e8; liq = 1e6; top = 3 }
  @{ tv = 'germany'; name = 'Tyskland'; pre = 'de'; ex = @('XETR'); y = @{ XETR = '.DE' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 3e6; top = 6 }
  @{ tv = 'france'; name = 'Frankrike'; pre = 'fr'; ex = @('EURONEXT'); y = @{ EURONEXT = '.PA' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 3e6; top = 5 }
  @{ tv = 'netherlands'; name = 'Nederländerna'; pre = 'nl'; ex = @('EURONEXT'); y = @{ EURONEXT = '.AS' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 3e6; top = 3 }
  @{ tv = 'uk'; name = 'Storbritannien'; pre = 'uk'; ex = @('LSE'); y = @{ LSE = '.L' }; open = @('08:00', 'GMT Standard Time'); cap = 2e9; liq = 3e6; top = 5 }
  @{ tv = 'switzerland'; name = 'Schweiz'; pre = 'ch'; ex = @('SIX'); y = @{ SIX = '.SW' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 3e6; top = 3 }
  @{ tv = 'italy'; name = 'Italien'; pre = 'it'; ex = @('MIL'); y = @{ MIL = '.MI' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 3e6; top = 3 }
  @{ tv = 'spain'; name = 'Spanien'; pre = 'es'; ex = @('BME'); y = @{ BME = '.MC' }; open = @('09:00', 'W. Europe Standard Time'); cap = 2e9; liq = 3e6; top = 3 }
  @{ tv = 'canada'; name = 'Kanada'; pre = 'ca'; ex = @('TSX'); y = @{ TSX = '.TO' }; open = @('09:30', 'Eastern Standard Time'); cap = 2e9; liq = 5e6; top = 4 }
)
$FXU = @{ USD = 1.0; SEK = 0.1; NOK = 0.094; DKK = 0.155; EUR = 1.16; GBP = 1.33; GBX = 0.0133; CHF = 1.25; CAD = 0.71 }
$scanned = 0; $picked = @(); $openMk = @()
if (-not $Only) {
  foreach ($m in $MKT) {
    $op = SessionOpenAt $m.open $nowU; $cl = SessionEndAt $m.name $nowU
    if ($nowT -lt $op + 1800 -or $nowT -gt $cl - 5400 -or [int]$nowU.DayOfWeek -in 0, 6) { continue }   # bara öppna börser, efter öppningsrangen och mer än 1,5 timme före stängning
    try {
      $body = @{ markets = @($m.tv); symbols = @{ query = @{ types = @() }; tickers = @() }; columns = @('name', 'description', 'close', 'change', 'gap', 'average_volume_10d_calc', 'relative_volume_10d_calc', 'ATR', 'currency', 'earnings_release_next_date', 'sector')
        sort = @{ sortBy = 'relative_volume_10d_calc'; sortOrder = 'desc' }; range = @(0, 120)
        filter = @(@{ left = 'type'; operation = 'equal'; right = 'stock' }, @{ left = 'is_primary'; operation = 'equal'; right = $true }, @{ left = 'market_cap_basic'; operation = 'greater'; right = $m.cap }, @{ left = 'exchange'; operation = 'in_range'; right = $m.ex }) } | ConvertTo-Json -Depth 8 -Compress
      $rows = (Invoke-RestMethod -Method Post -Uri "https://scanner.tradingview.com/$($m.tv)/scan" -Body $body -ContentType 'application/json' -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Origin' = 'https://www.tradingview.com' } -TimeoutSec 60).data
      $scanned += @($rows).Count; $openMk += $m.name
      $cand = foreach ($x in $rows) { $px0 = [double]$x.d[2]; if (-not ($px0 -gt 0)) { continue }; $ccy = [string]$x.d[8]; $usdRate = $FXU[$ccy]; if (-not $usdRate) { continue }
        $liq = [double]$x.d[5] * $px0 * $usdRate; $atrP = [double]$x.d[7] / $px0 * 100; $chg = [double]$x.d[3]; $gap = [double]$x.d[4]; $rvol = [double]$x.d[6]
        if ($liq -lt $m.liq -or $atrP -lt 1.2) { continue }
        if (-not ($rvol -ge 1.3 -or [math]::Abs($chg) -ge 2 -or [math]::Abs($gap) -ge 1.5)) { continue }
        [pscustomobject]@{ x = $x; ip = $rvol * (1 + [math]::Abs($chg) / 2) * $(if ($atrP -ge 2) { 1.2 } else { 1 }); chg = $chg; rvol = $rvol; atrP = $atrP } }
      foreach ($c in @($cand | Sort-Object { - $_.ip } | Select-Object -First $m.top)) { $x = $c.x; $tk = ($x.s -split ':')[1].TrimEnd('.')   # LSE: "RR." är RR.L hos Yahoo
        if ($picked | Where-Object { $_.name -eq [string]$x.d[1] }) { continue }   # samma bolag på två börser (Stellantis i Paris och Milano)
        $picked += @{ id = "$($m.pre)-$(($tk -replace '[^A-Za-z0-9]', '').ToLower())"; y = ($tk -replace '[_\.]', '-') + [string]$m.y[($x.s -split ':')[0]]; tv = $x.s; name = [string]$x.d[1]; mk = $m.name; sector = [string]$x.d[10]; open = $m.open
          dec = $(if ([double]$x.d[2] -ge 1000) { 1 } elseif ([double]$x.d[2] -ge 10) { 2 } else { 3 }); stock = $true; ccy = [string]$x.d[8]; inplay = "relativ volym $([math]::Round($c.rvol, 1)), $([math]::Round($c.chg, 1)) % i dag, ATR $([math]::Round($c.atrP, 1)) %" }
        if ($x.d[9]) { $EARN[$x.s] = [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.d[9]).UtcDateTime } }
    } catch { "Marknaden $($m.name) kunde inte scannas: $($_.Exception.Message)" }
  }
  $have = @{}; foreach ($i0 in $INSTR) { $have[$i0.tv] = 1 }
  $INSTR = @($INSTR) + @($picked | Where-Object { -not $have[$_.tv] })
  "Steg 1: $scanned aktier på öppna börser, $($picked.Count) rör sig mest i dag och går vidare (plus olja, index, metaller och krypto)"
}
# makrokalendern (Fed, KPI) styr pausen; EIA-oljelagret (onsdagar 10.30 New York) räknas i biblioteket
$cal = @(); try { $cal = @((Get-Content (Join-Path $data 'paper/makrokalender.json') -Raw -Encoding UTF8 | ConvertFrom-Json).events) } catch { }
$calT = @(foreach ($e in $cal) { try { @{ t = [double]$(if ($e.t -is [datetime]) { [DateTimeOffset]$e.t.ToUniversalTime() } else { [DateTimeOffset]::Parse($e.t, [Globalization.CultureInfo]::InvariantCulture) }).ToUnixTimeSeconds(); label = $e.label } } catch { } })

$OUT = @()
foreach ($ins in $INSTR) {
  try {
    $B = Get15 $ins.y; $D = GetD $ins.y
    if ($B.Count -lt 60 -or $D.Count -lt 25) { "$($ins.name): för lite data"; continue }
    $A = Analyze $ins (ToArrays $B) $D $nowT @{ cal = $calT; earn = $EARN[$ins.tv] }
    if (-not $A) { continue }
    if ($A.roll) { "$($ins.name): glapp på $(Fm ($A.gap * 100) 1) % mot förra stängningen (troligen kontraktsbyte), inga sweeplägen mot gårdagens nivåer" }
    $dc = $ins.dec
    foreach ($s in $A.setups) { $g = if ($s.side -eq 'short') { -1 } else { 1 }
      $OUT += [ordered]@{ id = "dt-$($ins.id)-$($s.key)-$(if ($g -lt 0) { 's' } else { 'l' })"; ins = $ins.id; symbol = $ins.name; name = $ins.name; tv = $ins.tv; ysym = $ins.y; market = $ins.mk; sector = $ins.sector; currency = $(if ($ins.ccy) { $ins.ccy } elseif ($ins.mk -eq 'Sverige') { 'SEK' } elseif ($ins.mk -eq 'Tyskland') { 'EUR' } else { 'USD' }); dec = $dc; inplay = $ins.inplay; stock = [bool]$ins.stock; class = (DtClass $ins)
        setup = $s.key; setupName = $s.name; side = $s.side; price = (Rn $A.px $dc); entry = (Rn $s.entry $dc); stop = (Rn $s.stop $dc); t1 = (T1R $s $dc); t2 = (Rn $s.t2 $dc); rr1 = 2.0; riskPct = (Rn $s.riskPct 2); distAtr = (Rn $s.dist 2)
        score = $s.score; grade = $s.grade; ready = $s.ready; why = $s.why; conf = @($s.conf); flags = @($s.flags)
        vwap = (Rn $A.vwap $dc); pdh = (Rn $A.PDH $dc); pdl = (Rn $A.PDL $dc); hod = (Rn $A.HOD $dc); lod = (Rn $A.LOD $dc); orh = $(if ($null -ne $A.orH) { Rn $A.orH $dc }); orl = $(if ($null -ne $A.orL) { Rn $A.orL $dc }); atr15 = (Rn $A.atr15 ($dc + 1)); atrD = (Rn $A.atrD ($dc + 1)); trendD = $A.trendD; relVol = (Rn $A.rv 2)
        sessionEnd = $A.sEnd; at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
    "{0,-20} pris {1} · VWAP {2} · gårdagens H/L {3}/{4} · dagens H/L {5}/{6} · OR {7}–{8} · ATR15 {9} · dagstrend {10} · lägen {11}" -f $ins.name, (Fm $A.px $dc), (Fm $A.vwap $dc), (Fm $A.PDH $dc), (Fm $A.PDL $dc), (Fm $A.HOD $dc), (Fm $A.LOD $dc), $(if ($null -ne $A.orL) { Fm $A.orL $dc } else { '–' }), $(if ($null -ne $A.orH) { Fm $A.orH $dc } else { '–' }), (Fm $A.atr15 ($dc + 1)), $A.trendD, $A.setups.Count
  } catch { "$($ins.name): kunde inte scannas ($($_.Exception.Message))" }
}$OUT = @($OUT | Sort-Object { - [int]$_.ready }, { - $_.score })
$latest = [ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ'); scanned = $scanned; openMarkets = @($openMk); analysed = $INSTR.Count; count = $OUT.Count; ready = @($OUT | Where-Object { $_.ready }).Count; setups = @($OUT | Select-Object -First 20) }
[IO.File]::WriteAllText((Join-Path $data 'daytrade-latest.json'), ($latest | ConvertTo-Json -Depth 6 -Compress), [Text.UTF8Encoding]::new($false))
# facit (Devin 26 okt): varje läge sparas första gången det syns per dag, och en gång till första gången det är redo, i
# data\daytrade-signals.json (45 dagar). daytrade-facit.ps1 -Check räknar utfallet efter dagens slut på samma sätt som backtestet.
if (-not $Only) {
  $sigFile = Join-Path $data 'daytrade-signals.json'; $SIG = @(); try { $SIG = @((Get-Content $sigFile -Raw -Encoding UTF8 | ConvertFrom-Json).signals | Where-Object { [double]$_.atT -ge $nowT - 45 * 86400 }) } catch { }
  $seenSig = @{}; foreach ($x in $SIG) { $seenSig[[string]$x.sid] = 1 }; $dayKey = $nowU.ToString('yyyy-MM-dd'); $nNew = 0
  foreach ($o in $OUT) { $sid = "$dayKey-$($o.id)"; foreach ($k in @($sid) + @(if ($o.ready) { "$sid-r" })) { if ($seenSig[$k]) { continue }; $seenSig[$k] = 1; $nNew++
    $SIG += [pscustomobject][ordered]@{ sid = $k; first = ($k -notlike '*-r'); id = $o.id; ins = $o.ins; symbol = $o.symbol; ysym = $o.ysym; market = $o.market; sector = $o.sector; stock = $o.stock; class = $o.class; setup = $o.setup; side = $o.side
      grade = $o.grade; score = $o.score; ready = $o.ready; entry = $o.entry; stop = $o.stop; t1 = $o.t1; t2 = $o.t2; riskPct = $o.riskPct; distAtr = $o.distAtr; relVol = $o.relVol; flags = @($o.flags); atT = $nowT; sessionEnd = $o.sessionEnd; out = $null } } }
  [IO.File]::WriteAllText($sigFile, ([ordered]@{ at = $nowU.ToString('yyyy-MM-ddTHH:mm:ssZ'); signals = @($SIG) } | ConvertTo-Json -Depth 6 -Compress), [Text.UTF8Encoding]::new($false)); "facit: $nNew nya lägen sparade ($($SIG.Count) totalt)"
}"--- lägen: $($OUT.Count), redo: $($latest.ready) ---"
foreach ($o in $OUT | Select-Object -First 12) { "{0} {1,3} {2}{3,-20} {4,-38} {5,-5} entry {6} stopp {7} ({8} %) mål {9}/{10} · {11} ATR bort | {12}" -f $o.grade, $o.score, $(if ($o.ready) { '* ' } else { '  ' }), $o.symbol, $o.setupName, $o.side, (Fm $o.entry $o.dec), (Fm $o.stop $o.dec), $o.riskPct, (Fm $o.t1 $o.dec), (Fm $o.t2 $o.dec), $o.distAtr, (($o.flags) -join '; ') }
if ($Plans) {
  $rd = @($OUT | Where-Object { $_.ready }); if (-not $rd.Count) { 'Inga redo lägen, inga planutkast.'; return }
  $pl = foreach ($o in $rd) { $sh = $o.side -eq 'short'
    # index, råvaror och krypto med tajt stopp: turbo med högst 9,5x hävstång (knockout långt bortom stoppet). Aktier handlas som aktier.
    $isStock = [bool]$o.stock
    # YL 29 okt: certifikat med hävstång även för krypto (turbo lång eller kort)
    $prodD = if (-not $isStock) { $lev = 9.5; $ko = [math]::Round($o.entry * $(if ($sh) { 1 + 1 / $lev } else { 1 - 1 / $lev }), $o.dec); @{ type = 'turbo'; ko = $ko } } else { $lev = 1; @{ type = 'underliggande' } }
    # förslag på andel av kapitalet (allocPct): stoppet kostar cirka 2 % av portföljen för A och 1,5 % för B, högst hela kapitalet; Jarvis justerar efter läget
    $stopP = [math]::Abs($o.entry - $o.stop) / $o.entry * 100; $allocD = [math]::Max(1, [math]::Min(100, [math]::Round($(if ($o.grade -eq 'A') { 2 } else { 1.5 }) / ($stopP * $lev) * 100, 0)))
    [ordered]@{ id = $o.id; horizon = 'day'; side = $o.side; product = $prodD; fractional = (-not $isStock); symbol = $o.symbol; name = $o.name; ysym = $o.ysym; tv = $o.tv; market = $o.market; sector = $o.sector; currency = $o.currency; dec = $o.dec
      entry = $o.entry; stop = $o.stop; t1 = $o.t1; t2 = $o.t2; allocPct = $allocD; grade = $o.grade
      thesis = "$($o.setupName). $($o.why). UTKAST: granska nyheterna innan ordern läggs."
      htf = "Dagstrend $(@{ 1 = 'upp'; 0 = 'sidled'; -1 = 'ned' }[[int]$o.trendD]) (pris mot 20-dagars), VWAP $(Fm $o.vwap $o.dec), relativ volym $($o.relVol)."
      level = "Gårdagens high/low $(Fm $o.pdh $o.dec)/$(Fm $o.pdl $o.dec), dagens high/low $(Fm $o.hod $o.dec)/$(Fm $o.lod $o.dec)$(if ($o.orh) { ", öppningsrange $(Fm $o.orl $o.dec)–$(Fm $o.orh $o.dec)" })"
      confluence = @($o.conf); trigger = "$(if ($sh) { 'Sälj' } else { 'Köp' }) vid BOS på 15m: $(if ($sh) { 'under' } else { 'över' }) $(Fm $o.entry $o.dec)"
      invalidation = "$(if ($sh) { 'Över' } else { 'Under' }) $(Fm $o.stop $o.dec) är läget fel"
      against = @('Intradag är brus: falska utbrott är vanliga', $(if ($o.flags.Count) { $o.flags -join '; ' } else { 'Nyheter kan vända rörelsen snabbt' }))
      events = 'Kontrollera rubriker och kalender (EIA onsdagar 16.30, Fed, KPI) innan ordern läggs.'; correlation = 'Kontrollera mot öppna testtrades i samma sektor.'
      exit = 'En tredjedel vid mål 1 (2R) och stoppet till break-even, resten vid mål 2 eller vid dagens stängning.'
      gates = [ordered]@{ htf = $true; events = $true; confluence = (@($o.conf).Count -ge 2); discount = $true; bos = $true; stop = ($o.riskPct -le 4); rr = $true; invalidation = $true; risk = $true } } }
  $pf = Join-Path $data "paper/plan-day-$((Get-Date).ToString('yyyyMMdd-HHmm')).json"; [IO.File]::WriteAllText($pf, (ConvertTo-Json -InputObject @($pl) -Depth 6), [Text.UTF8Encoding]::new($true)); "planutkast -> $pf"
}
