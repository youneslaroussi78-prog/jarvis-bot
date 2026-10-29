# Gemensam daytrade-analys (Devin 26 okt: "bygg backtest och facit för daytradelägena"). Används av daytrade.ps1 (nu) och
# daytrade-facit.ps1 (backtest på 60 dagars 15m-data och uppföljning av varje läge), så att lägen, betyg och utfall räknas exakt
# likadant i båda. Allt räknas "vid tidpunkten": bara candlar som fanns då, gårdagens nivåer ur förra sessionen och dagstrenden ur
# dagsdata före i dag plus dagens pris. Snabbt (index och binärsökning) eftersom backtestet kör ca 11 000 analyser.
$script:svC = [Globalization.CultureInfo]::GetCultureInfo('sv-SE')
# y = Yahoo, tv = TradingView, mk = marknad (styr dagens slut i paper.ps1), open = huvudsessionens öppning (tid, tidszon), dec = decimaler
$DT_INSTR = @(
  @{ id = 'cl'; y = 'CL=F'; tv = 'NYMEX:CL1!'; name = 'Olja WTI'; mk = 'Råvaror'; sector = 'Energi'; open = @('09:00', 'Eastern Standard Time'); dec = 2; eia = $true }
  @{ id = 'bz'; y = 'BZ=F'; tv = 'ICEEUR:BRN1!'; name = 'Olja Brent'; mk = 'Råvaror'; sector = 'Energi'; open = @('09:00', 'Eastern Standard Time'); dec = 2; eia = $true }
  @{ id = 'gc'; y = 'GC=F'; tv = 'COMEX:GC1!'; name = 'Guld (termin)'; mk = 'Råvaror'; sector = 'Metaller'; open = @('08:20', 'Eastern Standard Time'); dec = 1 }
  @{ id = 'si'; y = 'SI=F'; tv = 'COMEX:SI1!'; name = 'Silver (termin)'; mk = 'Råvaror'; sector = 'Metaller'; open = @('08:25', 'Eastern Standard Time'); dec = 3 }
  @{ id = 'hg'; y = 'HG=F'; tv = 'COMEX:HG1!'; name = 'Koppar (termin)'; mk = 'Råvaror'; sector = 'Metaller'; open = @('08:10', 'Eastern Standard Time'); dec = 4 }
  @{ id = 'nq'; y = 'NQ=F'; tv = 'CME_MINI:NQ1!'; name = 'Nasdaq 100 (termin)'; mk = 'USA'; sector = 'Index'; open = @('09:30', 'Eastern Standard Time'); dec = 2 }
  @{ id = 'es'; y = 'ES=F'; tv = 'CME_MINI:ES1!'; name = 'S&P 500 (termin)'; mk = 'USA'; sector = 'Index'; open = @('09:30', 'Eastern Standard Time'); dec = 2 }
  @{ id = 'dax'; y = '^GDAXI'; tv = 'XETR:DAX'; name = 'DAX'; mk = 'Tyskland'; sector = 'Index'; open = @('09:00', 'W. Europe Standard Time'); dec = 1 }
  @{ id = 'omx'; y = '^OMX'; tv = 'OMXSTO:OMXS30'; name = 'OMXS30'; mk = 'Sverige'; sector = 'Index'; open = @('09:00', 'W. Europe Standard Time'); dec = 2 }
  @{ id = 'btc'; y = 'BTC-USD'; tv = 'BINANCE:BTCUSD'; name = 'Bitcoin'; mk = 'Krypto'; sector = 'Krypto'; open = @('09:00', 'W. Europe Standard Time'); dec = 0 }
  @{ id = 'eth'; y = 'ETH-USD'; tv = 'COINBASE:ETHUSD'; name = 'Ethereum'; mk = 'Krypto'; sector = 'Krypto'; open = @('09:00', 'W. Europe Standard Time'); dec = 1 }
  @{ id = 'sol'; y = 'SOL-USD'; tv = 'COINBASE:SOLUSD'; name = 'Solana'; mk = 'Krypto'; sector = 'Krypto'; open = @('09:00', 'W. Europe Standard Time'); dec = 2 }
  @{ id = 'nvda'; y = 'NVDA'; tv = 'NASDAQ:NVDA'; name = 'NVIDIA'; mk = 'USA'; sector = 'Halvledare'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true }
  @{ id = 'tsla'; y = 'TSLA'; tv = 'NASDAQ:TSLA'; name = 'Tesla'; mk = 'USA'; sector = 'Bil'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true }
  @{ id = 'amd'; y = 'AMD'; tv = 'NASDAQ:AMD'; name = 'AMD'; mk = 'USA'; sector = 'Halvledare'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true }
  @{ id = 'mu'; y = 'MU'; tv = 'NASDAQ:MU'; name = 'Micron'; mk = 'USA'; sector = 'Halvledare'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true }
  @{ id = 'meta'; y = 'META'; tv = 'NASDAQ:META'; name = 'Meta'; mk = 'USA'; sector = 'Mjukvara'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true }
  @{ id = 'aapl'; y = 'AAPL'; tv = 'NASDAQ:AAPL'; name = 'Apple'; mk = 'USA'; sector = 'Teknik'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true }
)
# Inställningar som backtestet prövar (daytrade-facit.ps1 -Backtest -Cfg "costFloorR=0.15;noOrb=1;lateHour=19"). 0 = av.
#   costFloorR: stoppet minst så brett att kostnaden tur och retur blir högst så många R; noOrb: inga ORB-lägen; lateHour: inga redo lägen från den timmen (svensk tid)
# Standard sedan backtestet 26 okt (4 aug–23 okt, 18 instrument, 2 696 lägen): stopp så breda att kostnaden blir högst 0,1R, inga ORB-lägen
# (sämst i båda halvorna) och inga redo lägen efter 19. Det tog snittet från −0,36R till −0,10R netto per trade; inget läge har ännu en fördel.
#   trial: nya setups som prövas, kommaseparerat (gapgo = nyhetsgap som håller, gapfade = nyhetsgap som inte håller, trend = trenddag,
#   orb60 = utbrott ur första timmen). Live använder bara de som hållit i båda halvorna av backtestet.
# YL 29 okt ("trada mer, shorta när det ska ner, 2 % per dag"): B-lägen räknas också som redo och gränsen är kl 21 i stället för 19.
$DT_CFG = @{ costFloorR = 0.1; noOrb = 1; lateHour = 21; trial = ''; gapMin = 0.5 }   # gapMin: minsta gap i dags-ATR för nyhetsgap
# Bredare lista bara för backtestet (-Universe bred, Devin 26 okt: pröva nyhetsgap): aktier som ofta gappar på nyheter, i USA och Europa.
# Urvalet är gjort i dag, så bolag som försvunnit saknas (överlevnadsfel); det är en grov kontroll, inte ett bevis.
$DT_EXTRA = @(
  foreach ($t in 'PLTR', 'COIN', 'MSTR', 'SMCI', 'AMZN', 'GOOGL', 'NFLX', 'AVGO', 'ORCL', 'UBER', 'SHOP', 'CRWD', 'BA', 'INTC', 'LLY', 'XOM', 'JPM', 'HOOD') {
    @{ id = "x-$($t.ToLower())"; y = $t; tv = "NASDAQ:$t"; name = $t; mk = 'USA'; sector = 'Aktie USA'; open = @('09:30', 'Eastern Standard Time'); dec = 2; stock = $true } }
  @{ id = 'x-asml'; y = 'ASML.AS'; tv = 'EURONEXT:ASML'; name = 'ASML'; mk = 'Nederländerna'; sector = 'Aktie Europa'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
  @{ id = 'x-sap'; y = 'SAP.DE'; tv = 'XETR:SAP'; name = 'SAP'; mk = 'Tyskland'; sector = 'Aktie Europa'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
  @{ id = 'x-rhm'; y = 'RHM.DE'; tv = 'XETR:RHM'; name = 'Rheinmetall'; mk = 'Tyskland'; sector = 'Aktie Europa'; open = @('09:00', 'W. Europe Standard Time'); dec = 1; stock = $true }
  @{ id = 'x-novo'; y = 'NOVO-B.CO'; tv = 'OMXCOP:NOVO_B'; name = 'Novo Nordisk'; mk = 'Danmark'; sector = 'Aktie Europa'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
  @{ id = 'x-eric'; y = 'ERIC-B.ST'; tv = 'OMXSTO:ERIC_B'; name = 'Ericsson'; mk = 'Sverige'; sector = 'Aktie Sverige'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
  @{ id = 'x-volv'; y = 'VOLV-B.ST'; tv = 'OMXSTO:VOLV_B'; name = 'Volvo'; mk = 'Sverige'; sector = 'Aktie Sverige'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
  @{ id = 'x-evo'; y = 'EVO.ST'; tv = 'OMXSTO:EVO'; name = 'Evolution'; mk = 'Sverige'; sector = 'Aktie Sverige'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
  @{ id = 'x-saab'; y = 'SAAB-B.ST'; tv = 'OMXSTO:SAAB_B'; name = 'Saab'; mk = 'Sverige'; sector = 'Aktie Sverige'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
  @{ id = 'x-nokia'; y = 'NOKIA.HE'; tv = 'OMXHEX:NOKIA'; name = 'Nokia'; mk = 'Finland'; sector = 'Aktie Europa'; open = @('10:00', 'GTB Standard Time'); dec = 3; stock = $true }   # GTB har samma tid som Helsingfors; FLE blir Europe/Kiev, som saknas i molnets Linux
  @{ id = 'x-eqnr'; y = 'EQNR.OL'; tv = 'OSL:EQNR'; name = 'Equinor'; mk = 'Norge'; sector = 'Aktie Europa'; open = @('09:00', 'W. Europe Standard Time'); dec = 2; stock = $true }
)
$DT_CLOSE = @{ 'USA' = @('Eastern Standard Time', '16:00'); 'Råvaror' = @('Eastern Standard Time', '16:00'); 'Tyskland' = @('W. Europe Standard Time', '17:30'); 'Sverige' = @('W. Europe Standard Time', '17:30'); 'Krypto' = @('W. Europe Standard Time', '23:00')
  'Kanada' = @('Eastern Standard Time', '16:00'); 'Storbritannien' = @('GMT Standard Time', '16:30'); 'Norge' = @('W. Europe Standard Time', '16:20'); 'Danmark' = @('W. Europe Standard Time', '17:00'); 'Finland' = @('GTB Standard Time', '18:30')
  'Frankrike' = @('W. Europe Standard Time', '17:30'); 'Nederländerna' = @('W. Europe Standard Time', '17:30'); 'Schweiz' = @('W. Europe Standard Time', '17:30'); 'Italien' = @('W. Europe Standard Time', '17:30'); 'Spanien' = @('W. Europe Standard Time', '17:30') }

function Get15($y, $range = '5d') {
  $u = "https://query2.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($y))?range=$range&interval=15m"
  $res = (Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 60).chart.result[0]; $q = $res.indicators.quote[0]; $o = [Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) { if ($null -eq $q.close[$i] -or $null -eq $q.high[$i] -or $null -eq $q.low[$i] -or $null -eq $q.open[$i]) { continue }
    $o.Add([double[]]@([double]$res.timestamp[$i], [double]$q.open[$i], [double]$q.high[$i], [double]$q.low[$i], [double]$q.close[$i], $(if ($null -ne $q.volume[$i]) { [double]$q.volume[$i] } else { 0.0 }))) }
  , $o.ToArray()
}
function GetD($y, $range = '3mo') {
  $u = "https://query2.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($y))?range=$range&interval=1d"
  $res = (Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 60).chart.result[0]; $q = $res.indicators.quote[0]; $o = [Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) { if ($null -eq $q.close[$i] -or $null -eq $q.high[$i]) { continue }; $o.Add([double[]]@([double]$res.timestamp[$i], [double]$q.open[$i], [double]$q.high[$i], [double]$q.low[$i], [double]$q.close[$i])) }
  , $o.ToArray()
}
# candlar som kolumner (snabbare än listor av listor)
function ToArrays($B) { $n = $B.Count; $X = @{ tA = [double[]]::new($n); oA = [double[]]::new($n); hA = [double[]]::new($n); lA = [double[]]::new($n); cA = [double[]]::new($n); vA = [double[]]::new($n) }
  for ($i = 0; $i -lt $n; $i++) { $b0 = $B[$i]; $X.tA[$i] = $b0[0]; $X.oA[$i] = $b0[1]; $X.hA[$i] = $b0[2]; $X.lA[$i] = $b0[3]; $X.cA[$i] = $b0[4]; $X.vA[$i] = $b0[5] }; $X }
# sista index med värde <= v (-1 om inget), första index med värde >= v
function LastLE([double[]]$a, [double]$v) { $lo = 0; $hi = $a.Length - 1; $r = -1; while ($lo -le $hi) { $mid = [int][math]::Floor(($lo + $hi) / 2); if ($a[$mid] -le $v) { $r = $mid; $lo = $mid + 1 } else { $hi = $mid - 1 } }; $r }
function FirstGE([double[]]$a, [double]$v) { $lo = 0; $hi = $a.Length - 1; $r = $a.Length; while ($lo -le $hi) { $mid = [int][math]::Floor(($lo + $hi) / 2); if ($a[$mid] -ge $v) { $r = $mid; $hi = $mid - 1 } else { $lo = $mid + 1 } }; $r }
function EmaR([double[]]$v, [int]$from, [int]$to, $n) { $k = 2 / ($n + 1); $e = $v[$from]; for ($i = $from; $i -le $to; $i++) { $e = $v[$i] * $k + $e * (1 - $k) }; $e }
function Fm($v, $d) { ([double]$v).ToString("N$d", $script:svC) }
function Rn($v, $d) { [math]::Round([double]$v, $d) }
# mål 1 räknas från avrundade entry och stopp och avrundas utåt, så att R/R aldrig blir under 1:2 (WTI 26 okt blev 1:1,96 och nekades)
function T1R($s, $d) { $g = if ($s.side -eq 'short') { -1 } else { 1 }; $e = Rn $s.entry $d; $st = Rn $s.stop $d; $m = [math]::Pow(10, $d); $v = [math]::Max($g * $s.t1, $g * ($e + $g * 2 * [math]::Abs($e - $st))) * $g; if ($g -gt 0) { [math]::Ceiling($v * $m - 1e-9) / $m } else { [math]::Floor($v * $m + 1e-9) / $m } }
# öppning och dagens slut (unix) för dagen som tidpunkten atU (UTC) ligger i, i instrumentets tidszon
function SessionOpenAt($open, [datetime]$atU) { $tz = [TimeZoneInfo]::FindSystemTimeZoneById($open[1]); $loc = [TimeZoneInfo]::ConvertTimeFromUtc($atU, $tz)
  [DateTimeOffset]::new([TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($loc.Date + [timespan]$open[0], 'Unspecified'), $tz)).ToUnixTimeSeconds() }
function SessionEndAt($mk, [datetime]$atU) { $c0 = $DT_CLOSE[$mk]; if (-not $c0) { $c0 = @('W. Europe Standard Time', '23:00') }; SessionOpenAt @($c0[1], $c0[0]) $atU }
function EiaAt([datetime]$atU) { $etz = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time'); $eloc = [TimeZoneInfo]::ConvertTimeFromUtc($atU, $etz)
  if ($eloc.DayOfWeek -ne 'Wednesday') { return 0 }; [DateTimeOffset]::new([TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($eloc.Date + [timespan]'10:30', 'Unspecified'), $etz)).ToUnixTimeSeconds() }
# kostnad tur och retur i andel av underliggande: aktier 0,2 %, krypto 0,3 %, index och råvaror via turbo 9,5x (courtage 0,1 % och spread 0,4 % på produktens värde, två gånger)
function DayCostPct($ins) { if ($ins.stock) { 0.002 } elseif ($ins.mk -eq 'Krypto') { 0.003 } else { 2 * (0.001 + 0.004) / 9.5 } }

function DtMk($key, $name, $side, $entry, $stop, $why, $conf, $lv) {
  $g = if ($side -eq 'short') { -1 } else { 1 }; $risk = $g * ($entry - $stop); if ($risk -lt $lv.minRisk) { $stop = $entry - $g * $lv.minRisk; $risk = $lv.minRisk }
  $t1 = $entry + $g * 2 * $risk; $t2 = $entry + $g * 3 * $risk
  # mål 2 vid en nivå om den ligger längre bort än 2R (gårdagens high/low, dagens high/low)
  $far = if ($g -gt 0) { @($lv.PDH, $lv.HOD) | Where-Object { $_ -gt $t1 } | Sort-Object } else { @($lv.PDL, $lv.LOD) | Where-Object { $_ -lt $t1 } | Sort-Object -Descending }
  if (@($far).Count) { $t2 = [math]::Max($g * $t2, $g * @($far)[0]) * $g }
  [ordered]@{ key = $key; name = $name; side = $side; entry = $entry; stop = $stop; t1 = $t1; t2 = $t2; riskPct = $risk / $entry * 100; why = $why; conf = @($conf | Where-Object { $_ }) }
}

# Analys vid tidpunkten atT (unix): $X = ToArrays av 15m-candlar, $D = dagsdata, $ctx = @{ cal = @(@{ t; label }); earn = [datetime] eller $null }
function Analyze($ins, $X, $D, [double]$atT, $ctx) {
  $tA = $X.tA; $oA = $X.oA; $hA = $X.hA; $lA = $X.lA; $cA = $X.cA; $vA = $X.vA
  $atU = [DateTimeOffset]::FromUnixTimeSeconds([int64]$atT).UtcDateTime
  $iL = LastLE $tA ($atT - 1); $iC = LastLE $tA ($atT - 900); if ($iC -lt 60 -or $iL -lt 0) { return $null }
  $px = $cA[$iL]
  $sOpen = SessionOpenAt $ins.open $atU; $sEnd = SessionEndAt $ins.mk $atU
  # dagens candlar från sessionens början (krypto: midnatt UTC; terminer: 18.00 New York dagen före = Globex; övrigt: öppningen)
  $dayStart = if ($ins.mk -eq 'Krypto') { [DateTimeOffset]::new($atU.Date).ToUnixTimeSeconds() } elseif (($ins.mk -eq 'Råvaror') -or ($ins.sector -eq 'Index' -and $ins.mk -eq 'USA')) { $sOpen - 15.5 * 3600 } else { $sOpen }
  $i0 = FirstGE $tA $dayStart; if ($iC - $i0 + 1 -lt 2) { return $null }
  $atr15 = 0.0; for ($i = $iC - 13; $i -le $iC; $i++) { $atr15 += [math]::Max($hA[$i] - $lA[$i], [math]::Max([math]::Abs($hA[$i] - $cA[$i - 1]), [math]::Abs($lA[$i] - $cA[$i - 1]))) }; $atr15 /= 14
  $HOD = $hA[$i0]; $LOD = $lA[$i0]; $pv = 0.0; $vv = 0.0
  for ($i = $i0; $i -le $iC; $i++) { if ($hA[$i] -gt $HOD) { $HOD = $hA[$i] }; if ($lA[$i] -lt $LOD) { $LOD = $lA[$i] }; $w = if ($vA[$i] -gt 0) { $vA[$i] } else { 1 }; $pv += ($hA[$i] + $lA[$i] + $cA[$i]) / 3 * $w; $vv += $w }
  $vwap = $pv / $vv
  # gårdagens high/low ur förra sessionens 15m-candlar (Yahoos dagsdata för terminer kan vara trasig), annars sista dagen före i dag
  $PDH = $null; $PDL = $null; $nPrev = 0; $roll = $false
  if ($i0 -gt 0) { $pEnd = $tA[$i0 - 1]; $j0 = FirstGE $tA ($pEnd - 23.75 * 3600); $nPrev = $i0 - $j0
    if ($nPrev -ge 8) { $PDH = $hA[$j0]; $PDL = $lA[$j0]; for ($i = $j0; $i -lt $i0; $i++) { if ($hA[$i] -gt $PDH) { $PDH = $hA[$i] }; if ($lA[$i] -lt $PDL) { $PDL = $lA[$i] } } }
    # terminer: glapp över 3 % mot förra stängningen är ofta ett kontraktsbyte (Brent rullar i slutet av månaden), då gäller inte gårdagens nivåer
    if ($ins.mk -eq 'Råvaror') { $roll = [math]::Abs($oA[$i0] / $cA[$i0 - 1] - 1) -gt 0.03 } }
  # dagsdata före i dag (UTC-datum) plus dagens candle av 15m-datan
  $dT = [double]([DateTimeOffset]::new($atU.Date).ToUnixTimeSeconds()); $jD = -1; for ($i = $D.Count - 1; $i -ge 0; $i--) { if ($D[$i][0] -lt $dT) { $jD = $i; break } }
  if ($jD -lt 20) { return $null }
  if ($null -eq $PDH) { $PDH = $D[$jD][2]; $PDL = $D[$jD][3] }
  $sum = $px; for ($i = $jD - 18; $i -le $jD; $i++) { $sum += $D[$i][4] }; $sma20 = $sum / 20
  $c4 = $D[$jD - 3][4]   # stängningen fyra dagar före dagens
  $trendD = if ($px -gt $sma20 -and $px -gt $c4) { 1 } elseif ($px -lt $sma20 -and $px -lt $c4) { -1 } else { 0 }
  $atrD = [math]::Max($HOD - $LOD, [math]::Max([math]::Abs($HOD - $D[$jD][4]), [math]::Abs($LOD - $D[$jD][4])))
  for ($i = $jD - 12; $i -le $jD; $i++) { $atrD += [math]::Max($D[$i][2] - $D[$i][3], [math]::Max([math]::Abs($D[$i][2] - $D[$i - 1][4]), [math]::Abs($D[$i][3] - $D[$i - 1][4]))) }; $atrD /= 14
  $e20 = EmaR $cA ([math]::Max(0, $iC - 119)) $iC 20; $e50 = EmaR $cA ([math]::Max(0, $iC - 199)) $iC 50
  $sv0 = 0.0; $nv = 0; for ($i = [math]::Max(0, $iC - 40); $i -lt $iC; $i++) { $sv0 += $vA[$i]; $nv++ }; $rv = if ($nv -and $sv0 -gt 0) { $vA[$iC] / ($sv0 / $nv) } else { 1 }
  # öppningsrangen: de två första 15m-candlarna efter öppningen
  $o0 = FirstGE $tA $sOpen; $orH = $null; $orL = $null
  if ($o0 + 1 -lt $tA.Length -and $tA[$o0 + 1] -lt $sOpen + 1800 -and $o0 + 1 -le $iC) { $orH = [math]::Max($hA[$o0], $hA[$o0 + 1]); $orL = [math]::Min($lA[$o0], $lA[$o0 + 1]) }
  # minsta stopp: det större av en 15m-ATR och 12 % av dags-ATR, så att vanligt brus inte tar stoppet
  $costP = DayCostPct $ins; $minR = [math]::Max($atr15, 0.12 * $atrD); if ($DT_CFG.costFloorR -gt 0) { $minR = [math]::Max($minR, $costP * $px / $DT_CFG.costFloorR) }
  $lv = @{ minRisk = $minR; PDH = $PDH; PDL = $PDL; HOD = $HOD; LOD = $LOD }; $buf = 0.05 * $atr15; $dec = $ins.dec
  $cbH = $hA[$iC]; $cbL = $lA[$iC]; $cbC = $cA[$iC]; $setups = @()
  # 1. ORB: utbrott ur öppningsrangen, stopp i mitten av rangen
  if (-not $DT_CFG.noOrb -and $null -ne $orH -and $tA[$iC] -ge $sOpen + 1800) { $mid = ($orH + $orL) / 2
    if ($px -le $orH + 0.3 * $atr15 -and $px -ge $mid) { $setups += DtMk 'orb' 'ORB: utbrott över öppningsrangen' 'long' ($orH + $buf) $mid "Öppningsrangen $(Fm $orL $dec)–$(Fm $orH $dec); köp vid 15m-utbrott över $(Fm $orH $dec), stopp i rangens mitt" @('Öppningsrange', $(if ($px -gt $vwap) { 'Över VWAP' }), $(if ([math]::Abs($orH - $PDH) -lt 0.5 * $atr15) { 'Gårdagens high' })) $lv }
    if ($px -ge $orL - 0.3 * $atr15 -and $px -le $mid) { $setups += DtMk 'orb' 'ORB: utbrott under öppningsrangen' 'short' ($orL - $buf) $mid "Öppningsrangen $(Fm $orL $dec)–$(Fm $orH $dec); blanka vid 15m-utbrott under $(Fm $orL $dec), stopp i rangens mitt" @('Öppningsrange', $(if ($px -lt $vwap) { 'Under VWAP' }), $(if ([math]::Abs($orL - $PDL) -lt 0.5 * $atr15) { 'Gårdagens low' })) $lv } }
  # 2. Sweep av gårdagens low/high och återtagning (likviditetsjakt, turtle soup)
  if (-not $roll -and $LOD -lt $PDL -and $cbC -gt $PDL) { $setups += DtMk 'sweep' 'Sweep av gårdagens low och återtagning' 'long' ($cbH + $buf) ($LOD - 0.1 * $atr15) "Dagens low $(Fm $LOD $dec) svepte gårdagens low $(Fm $PDL $dec) och 15m stängde tillbaka över; köp vid BOS över $(Fm $cbH $dec)" @('Gårdagens low (likviditet)', 'Sweep och återtagning', $(if ($px -lt $vwap) { 'Mål VWAP' })) $lv }
  if (-not $roll -and $HOD -gt $PDH -and $cbC -lt $PDH) { $setups += DtMk 'sweep' 'Sweep av gårdagens high och avvisning' 'short' ($cbL - $buf) ($HOD + 0.1 * $atr15) "Dagens high $(Fm $HOD $dec) svepte gårdagens high $(Fm $PDH $dec) och 15m stängde tillbaka under; blanka vid BOS under $(Fm $cbL $dec)" @('Gårdagens high (likviditet)', 'Sweep och avvisning', $(if ($px -gt $vwap) { 'Mål VWAP' })) $lv }
  # 3. VWAP-trend med rekyl: trend på 15m (EMA20 mot EMA50 och pris mot VWAP), rekyl mot VWAP/EMA20, BOS över/under senaste candlen
  $plo = [math]::Min($lA[$iC - 2], [math]::Min($lA[$iC - 1], $lA[$iC])); $phi = [math]::Max($hA[$iC - 2], [math]::Max($hA[$iC - 1], $hA[$iC]))
  if ($e20 -gt $e50 -and $cbC -gt $vwap -and $plo -le [math]::Max($vwap, $e20) + 0.25 * $atr15 -and $cbC -gt $e20) { $setups += DtMk 'vwap' 'VWAP-trend: rekyl i upptrend' 'long' ($cbH + $buf) ($plo - 0.1 * $atr15) "Upptrend på 15m (EMA20 över EMA50) med rekyl till VWAP $(Fm $vwap $dec)/EMA20 och stängning över; köp vid BOS över $(Fm $cbH $dec)" @('VWAP', 'EMA20 15m', $(if ($trendD -gt 0) { 'Dagstrend upp' })) $lv }
  if ($e20 -lt $e50 -and $cbC -lt $vwap -and $phi -ge [math]::Min($vwap, $e20) - 0.25 * $atr15 -and $cbC -lt $e20) { $setups += DtMk 'vwap' 'VWAP-trend: rekyl i nedtrend' 'short' ($cbL - $buf) ($phi + 0.1 * $atr15) "Nedtrend på 15m (EMA20 under EMA50) med rekyl till VWAP $(Fm $vwap $dec)/EMA20 och stängning under; blanka vid BOS under $(Fm $cbL $dec)" @('VWAP', 'EMA20 15m', $(if ($trendD -lt 0) { 'Dagstrend ned' })) $lv }
  # Nya setups som prövas i backtestet (DT_CFG.trial). Nyhetsgap räknas bara där det finns ett riktigt gap (aktier och index med
  # öppning, inte terminer och krypto som handlas dygnet runt): öppningen minst 0,5 dags-ATR från gårdagens stängning.
  $trial = @("$($DT_CFG.trial)" -split ',' | Where-Object { $_ })
  if ($trial.Count) {
    $oS = FirstGE $tA $sOpen; $sinceOpen = $atT - $sOpen; $pc = if ($i0 -gt 0) { $cA[$i0 - 1] } else { $null }
    $gapAtr = if ($pc -and $atrD -gt 0) { ($oA[$i0] - $pc) / $atrD } else { 0 }
    $gapOk = ($ins.stock -or ($ins.sector -eq 'Index' -and $ins.mk -ne 'USA')) -and [math]::Abs($gapAtr) -ge $(if ($DT_CFG.gapMin) { $DT_CFG.gapMin } else { 0.5 })
    $orDone = $null -ne $orH -and $tA[$iC] -ge $sOpen + 1800
    if ($orDone -and $gapOk -and $sinceOpen -le 3 * 3600) { $mid = ($orH + $orL) / 2
      # nyhetsgap som håller (gap and go): köp vid utbrott över öppningsrangen när gapet upp håller över VWAP, blanka spegelvänt
      if ($trial -contains 'gapgo') {
        if ($gapAtr -gt 0 -and $px -gt $vwap -and $px -ge $mid -and $px -le $orH + 0.3 * $atr15) { $setups += DtMk 'gapgo' 'Nyhetsgap som håller: utbrott uppåt' 'long' ($orH + $buf) ([math]::Min($vwap, $mid) - 0.1 * $atr15) "Gap upp $(Fm $gapAtr 1) dags-ATR som håller över VWAP $(Fm $vwap $dec); köp vid utbrott över öppningsrangen $(Fm $orH $dec)" @('Gap', 'Öppningsrange', 'Över VWAP') $lv }
        if ($gapAtr -lt 0 -and $px -lt $vwap -and $px -le $mid -and $px -ge $orL - 0.3 * $atr15) { $setups += DtMk 'gapgo' 'Nyhetsgap som håller: utbrott nedåt' 'short' ($orL - $buf) ([math]::Max($vwap, $mid) + 0.1 * $atr15) "Gap ned $(Fm (-$gapAtr) 1) dags-ATR som håller under VWAP $(Fm $vwap $dec); blanka vid utbrott under öppningsrangen $(Fm $orL $dec)" @('Gap', 'Öppningsrange', 'Under VWAP') $lv } }
      # nyhetsgap som inte håller (gap fill): gap upp som faller under VWAP och öppningsrangen, blanka mot gårdagens stängning, och spegelvänt
      if ($trial -contains 'gapfade') {
        if ($gapAtr -gt 0 -and $px -lt $vwap -and [math]::Abs($px - $orL) -le 0.3 * $atr15) { $m0 = DtMk 'gapfade' 'Nyhetsgap som inte håller: blanka mot gårdagens stängning' 'short' ($orL - $buf) ($vwap + 0.1 * $atr15) "Gap upp $(Fm $gapAtr 1) dags-ATR som fallit under VWAP $(Fm $vwap $dec); blanka under öppningsrangen $(Fm $orL $dec), mål gårdagens stängning $(Fm $pc $dec)" @('Gap', 'Under VWAP', 'Gårdagens stängning') $lv; if ($pc -lt $m0.t2) { $m0.t2 = $pc }; $setups += $m0 }
        if ($gapAtr -lt 0 -and $px -gt $vwap -and [math]::Abs($px - $orH) -le 0.3 * $atr15) { $m0 = DtMk 'gapfade' 'Nyhetsgap som inte håller: köp mot gårdagens stängning' 'long' ($orH + $buf) ($vwap - 0.1 * $atr15) "Gap ned $(Fm (-$gapAtr) 1) dags-ATR som tagits tillbaka över VWAP $(Fm $vwap $dec); köp över öppningsrangen $(Fm $orH $dec), mål gårdagens stängning $(Fm $pc $dec)" @('Gap', 'Över VWAP', 'Gårdagens stängning') $lv; if ($pc -gt $m0.t2) { $m0.t2 = $pc }; $setups += $m0 } }
    }
    # trenddag: minst 0,6 dags-ATR från öppningen, rätt sida om VWAP, 15m-trend och nytt dagshögsta/-lägsta de senaste fyra candlarna; köp vid nytt high
    if ($trial -contains 'trend' -and $oS -le $iC -and $sinceOpen -ge 5400) { $mv = ($px - $oA[$oS]) / $atrD
      $rh = [math]::Max([math]::Max($hA[$iC - 3], $hA[$iC - 2]), [math]::Max($hA[$iC - 1], $hA[$iC])); $rl = [math]::Min([math]::Min($lA[$iC - 3], $lA[$iC - 2]), [math]::Min($lA[$iC - 1], $lA[$iC]))
      if ($mv -ge 0.6 -and $px -gt $vwap -and $e20 -gt $e50 -and $rh -ge $HOD - 0.05 * $atr15) { $setups += DtMk 'trend' 'Trenddag: köp på nytt dagshögsta' 'long' ($HOD + $buf) ($rl - 0.1 * $atr15) "Trenddag: upp $(Fm $mv 1) dags-ATR sedan öppningen, över VWAP och vid dagens high; köp över $(Fm $HOD $dec)" @('Trenddag', 'Över VWAP', 'EMA20 15m') $lv }
      if ($mv -le -0.6 -and $px -lt $vwap -and $e20 -lt $e50 -and $rl -le $LOD + 0.05 * $atr15) { $setups += DtMk 'trend' 'Trenddag: blanka på nytt dagslägsta' 'short' ($LOD - $buf) ($rh + 0.1 * $atr15) "Trenddag: ned $(Fm (-$mv) 1) dags-ATR sedan öppningen, under VWAP och vid dagens low; blanka under $(Fm $LOD $dec)" @('Trenddag', 'Under VWAP', 'EMA20 15m') $lv } }
    # ORB på första timmen (fyra 15m-candlar) i stället för första halvtimmen, högst fyra timmar efter öppningen, stopp i rangens mitt
    if ($trial -contains 'orb60' -and $oS + 3 -le $iC -and $tA[$oS + 3] -lt $sOpen + 3600 -and $sinceOpen -le 4 * 3600) {
      $h60 = [math]::Max([math]::Max($hA[$oS], $hA[$oS + 1]), [math]::Max($hA[$oS + 2], $hA[$oS + 3])); $l60 = [math]::Min([math]::Min($lA[$oS], $lA[$oS + 1]), [math]::Min($lA[$oS + 2], $lA[$oS + 3])); $m60 = ($h60 + $l60) / 2
      if ($px -le $h60 + 0.3 * $atr15 -and $px -ge $m60) { $setups += DtMk 'orb60' 'ORB 60 min: utbrott över första timmen' 'long' ($h60 + $buf) $m60 "Första timmen $(Fm $l60 $dec)–$(Fm $h60 $dec); köp vid utbrott över $(Fm $h60 $dec), stopp i rangens mitt" @('Öppningsrange 60 min', $(if ($px -gt $vwap) { 'Över VWAP' })) $lv }
      if ($px -ge $l60 - 0.3 * $atr15 -and $px -le $m60) { $setups += DtMk 'orb60' 'ORB 60 min: utbrott under första timmen' 'short' ($l60 - $buf) $m60 "Första timmen $(Fm $l60 $dec)–$(Fm $h60 $dec); blanka vid utbrott under $(Fm $l60 $dec), stopp i rangens mitt" @('Öppningsrange 60 min', $(if ($px -lt $vwap) { 'Under VWAP' })) $lv } }
  } $hourSe = [TimeZoneInfo]::ConvertTimeFromUtc($atU, [TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time')).Hour
  foreach ($s in $setups) {
    $g = if ($s.side -eq 'short') { -1 } else { 1 }; $dist = $g * ($s.entry - $px) / $atr15
    $flags = @(); $score = 50
    if (($g -gt 0 -and $trendD -gt 0) -or ($g -lt 0 -and $trendD -lt 0)) { $score += 12 } elseif ($trendD -ne 0) { $score -= 12; $flags += 'Mot dagstrenden' }
    if (($g -gt 0 -and $px -gt $vwap) -or ($g -lt 0 -and $px -lt $vwap)) { $score += 8 } elseif ($s.key -ne 'sweep') { $score -= 8; $flags += "$(if ($g -gt 0) { 'Under' } else { 'Över' }) VWAP" }
    if ($rv -ge 1.3) { $score += 6 } elseif ($rv -lt 0.6) { $score -= 4; $flags += 'Låg volym' }
    $score += 4 * [math]::Min(3, @($s.conf).Count)
    if ($s.key -eq 'sweep') { $score += 5 }
    if ($dist -le 0.5) { $score += 6 } elseif ($dist -gt 1.5) { $score -= 10; $flags += 'Långt till entry' }
    if ($s.riskPct -gt 4) { $score -= 30; $flags += "Stopp $(Fm $s.riskPct 1) % bort (högst 4 %)" }
    if (($sEnd - $atT) / 3600 -lt 1.5) { $score -= 30; $flags += 'Under 1,5 timme kvar av dagen' }
    if ($atT -lt $sOpen + 1800 -and $s.key -eq 'orb') { $flags += 'Öppningsrangen är inte klar' }
    if ($eiaT -and $atT -gt $eiaT - 1800 -and $atT -lt $eiaT + 900) { $score -= 30; $flags += 'EIA-oljelagret inom 30 minuter' }
    # Fed och KPI pausar inte sedan 27 okt (Devin: "fortsätta köra dina trades och lära dig"); flaggan är bara information
    $ev = @($ctx.cal | Where-Object { $_.t -gt $atT -and $_.t -lt $atT + 24 * 3600 }); if ($ev.Count) { $flags += "Besked: $($ev[0].label) inom 24 timmar" }
    if ($DT_CFG.lateHour -gt 0 -and $hourSe -ge $DT_CFG.lateHour) { $flags += "Efter kl $($DT_CFG.lateHour) (backtest: sämst)" }
    $s.costR = $costP * $s.entry / [math]::Abs($s.entry - $s.stop)
    if ($ins.stock -and $ctx.earn) { $ed = ($ctx.earn - $atU).TotalDays; if ($ed -ge -0.5 -and $ed -le 1.5) { $score -= 40; $flags += 'Rapport i dag eller i morgon' } }
    $score = [math]::Max(0, [math]::Min(100, $score)); $grade = if ($score -ge 70) { 'A' } elseif ($score -ge 58) { 'B' } elseif ($score -ge 45) { 'C' } else { 'D' }
    $s.dist = $dist; $s.score = [int]$score; $s.grade = $grade; $s.flags = $flags
    $s.ready = [bool]($grade -in @('A', 'B') -and $dist -le 0.8 -and $dist -ge -0.2 -and -not ($flags | Where-Object { $_ -match 'Paus|Rapport|EIA|Under 1,5|Stopp|inte klar|Efter kl' }))
  }
  @{ px = $px; vwap = $vwap; PDH = $PDH; PDL = $PDL; HOD = $HOD; LOD = $LOD; orH = $orH; orL = $orL; atr15 = $atr15; atrD = $atrD; trendD = $trendD; rv = $rv; roll = $roll; sOpen = $sOpen; sEnd = $sEnd; gap = $(if ($i0 -gt 0) { $oA[$i0] / $cA[$i0 - 1] - 1 } else { 0 }); setups = @($setups) }
}

# Utfall för ett läge, räknat som testportföljen: stopporder vid BOS efter tidpunkten, förfaller om stoppet nås först, en tredjedel
# vid mål 1 och stoppet till break-even, resten vid mål 2 eller vid dagens slut. Gap förbi entry eller stopp ger öppningskursen.
# Når en candle både stopp och mål räknas stoppet först (försiktigt). R räknas på planerad risk; rNet drar kostnaden tur och retur.
function Outcome($X, $s, [double]$atT, [double]$endT, [double]$costPct) {
  $tA = $X.tA; $oA = $X.oA; $hA = $X.hA; $lA = $X.lA; $cA = $X.cA
  $g = if ($s.side -eq 'short') { -1 } else { 1 }; $entry = [double]$s.entry; $stop = [double]$s.stop; $t1 = [double]$s.t1; $t2 = [double]$s.t2; $risk = [math]::Abs($entry - $stop)
  if (-not ($risk -gt 0)) { return $null }
  $k = FirstGE $tA $atT; $state = 0; $fill = 0.0; $rem = 1.0; $acc = 0.0; $stopNow = $stop; $t1done = $false; $reason = 'ej utlöst'; $fillT = $null; $lastC = $null; $mfe = 0.0
  for (; $k -lt $tA.Length -and $tA[$k] -lt $endT; $k++) {
    $op = $oA[$k]; $lastC = $cA[$k]; $fav = if ($g -gt 0) { $hA[$k] } else { $lA[$k] }; $adv = if ($g -gt 0) { $lA[$k] } else { $hA[$k] }
    if ($state -eq 0) {
      if ($g * ($fav - $entry) -ge 0) { $fill = if ($g * ($op - $entry) -gt 0) { $op } else { $entry }; $state = 1; $fillT = $tA[$k]
        if ($g * ($adv - $stopNow) -le 0) { $acc = $g * ($stopNow - $fill); $rem = 0; $reason = 'stopp'; break }; continue }
      if ($g * ($adv - $stop) -le 0) { $reason = 'förföll'; break }
      continue
    }
    $mfe = [math]::Max($mfe, $g * ($fav - $fill) / $risk)
    if ($g * ($adv - $stopNow) -le 0) { $ex = if ($g * ($op - $stopNow) -lt 0) { $op } else { $stopNow }; $acc += $rem * $g * ($ex - $fill); $rem = 0; $reason = $(if ($t1done) { 'break-even' } else { 'stopp' }); break }
    if (-not $t1done -and $g * ($fav - $t1) -ge 0) { $acc += (1 / 3) * $g * ($t1 - $fill); $rem = 2 / 3; $t1done = $true; $stopNow = $fill
      if ($g * ($fav - $t2) -ge 0) { $acc += $rem * $g * ($t2 - $fill); $rem = 0; $reason = 'mål 2'; break }; continue }
    if ($t1done -and $g * ($fav - $t2) -ge 0) { $acc += $rem * $g * ($t2 - $fill); $rem = 0; $reason = 'mål 2'; break }
  }
  if ($state -eq 0) { return @{ status = $(if ($reason -eq 'förföll') { 'förföll' } else { 'ej utlöst' }); r = 0.0; rNet = 0.0; reason = $reason; t1 = $false } }
  if ($rem -gt 0) { $acc += $rem * $g * ($lastC - $fill); $reason = $(if ($t1done) { 'dagsslut efter mål 1' } else { 'dagsslut' }) }
  $r = $acc / $risk; $cost = $costPct * $entry / $risk
  @{ status = 'utlöst'; r = [math]::Round($r, 3); rNet = [math]::Round($r - $cost, 3); costR = [math]::Round($cost, 3); reason = $reason; t1 = $t1done; fillT = $fillT; mfe = [math]::Round($mfe, 2) }
}

# Statistik över utfall: antal lägen, utlösta, träff (netto över 0), snitt-R brutto och netto, summa, vinstfaktor och andel som nådde mål 1
function DtStats($recs) {
  $all = @($recs); $tr = @($all | Where-Object { $_.out.status -eq 'utlöst' })
  $o = [ordered]@{ n = $all.Count; triggered = $tr.Count; expired = @($all | Where-Object { $_.out.status -eq 'förföll' }).Count }
  if ($tr.Count) { $rs = @($tr | ForEach-Object { [double]$_.out.rNet }); $rg = @($tr | ForEach-Object { [double]$_.out.r }); $pos = ($rs | Where-Object { $_ -gt 0 } | Measure-Object -Sum).Sum; $neg = ($rs | Where-Object { $_ -lt 0 } | Measure-Object -Sum).Sum
    $o.wins = @($rs | Where-Object { $_ -gt 0 }).Count; $o.winRate = [math]::Round($o.wins / $tr.Count * 100); $o.t1Rate = [math]::Round(@($tr | Where-Object { $_.out.t1 }).Count / $tr.Count * 100)
    $o.avgR = [math]::Round(($rg | Measure-Object -Average).Average, 3); $o.avgRNet = [math]::Round(($rs | Measure-Object -Average).Average, 3); $o.sumRNet = [math]::Round(($rs | Measure-Object -Sum).Sum, 2)
    $o.avgCostR = [math]::Round((@($tr | ForEach-Object { [double]$_.out.costR }) | Measure-Object -Average).Average, 3); $o.pf = if ($neg -lt 0) { [math]::Round($pos / - $neg, 2) } else { $null } }
  $o
}
function DtGroup($recs, [scriptblock]$by) { $m = [ordered]@{}; foreach ($g0 in @($recs) | Group-Object $by | Sort-Object Name) { $m[[string]$g0.Name] = DtStats $g0.Group }; $m }
function DtClass($ins) { if ($ins.stock) { 'Aktier' } elseif ($ins.mk -eq 'Krypto') { 'Krypto' } elseif ($ins.sector -eq 'Index') { 'Index' } elseif ($ins.sector -eq 'Energi') { 'Olja' } else { 'Metaller' } }
