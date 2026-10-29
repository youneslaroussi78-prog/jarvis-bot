# Skriver TradingView-indikatorn "Jarvis nivåer" (Pine Script v5) från Jarvis bevakningslista (S1/S2/R1/R2, BOS, fel om, besked)
# och djupanalysen i data\nivaer.json (FVG, order block, POC/VAL/VAH). Devin 26 okt: "rita och visa i min tradingview".
# Nivåerna läses från databasexporten (data\db-export\assets), så exportera efter en ny analys.
# Körs: powershell -ExecutionPolicy Bypass -File pine.ps1   ->  data\jarvis-nivaer.pine (klistras in i Pine Editor och sparas som "Jarvis nivåer")
param([string]$DbDir = (Join-Path $PSScriptRoot '../data/db-export'))
$ErrorActionPreference = 'Stop'
$data = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../data'))
$inv = [Globalization.CultureInfo]::InvariantCulture; $sv = [Globalization.CultureInfo]::GetCultureInfo('sv-SE')
$NIV = Get-Content (Join-Path $data 'nivaer.json') -Raw -Encoding UTF8 | ConvertFrom-Json
# syminfo.ticker i TradingView-listan (USDT-par räknas som USD i skriptet)
$TICK = [ordered]@{ guld = @('XAUUSD'); silver = @('SILVER', 'XAGUSD'); koppar = @('XCUUSD', 'HG1!', 'COPPER'); btc = @('BTCUSD'); eth = @('ETHUSD'); sol = @('SOLUSD'); xrp = @('XRPUSD'); mu = @('MU'); googl = @('GOOGL'); ndx = @('NDX') }
$STAT = @{ vanta = 'Vänta'; bevaka = 'Bevaka'; kopinte = 'Köp inte'; kop = 'Köpläge'; delvis = 'Delvis' }
# alltid med decimal (3917.0), annars tolkar Pine arrayen som heltal; saknad eller noll blir na
function P($v) { if ($null -eq $v -or "$v" -eq '' -or [double]$v -le 0) { return 'na' }; ([double]$v).ToString('0.0#####', $inv) }
function S($v, $d) { ([double]$v).ToString("N$d", $sv) }
function Q($s) { '"' + (([string]$s) -replace '\\', '\\' -replace '"', "'") + '"' }
$lv = @(); $zn = @(); $bs = @(); $nf = @()
foreach ($id in $TICK.Keys) {
  $f = Join-Path $DbDir "assets/$id.json"; if (-not (Test-Path $f)) { continue }
  $a = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json; $nv = $NIV.$id; $d = if ($null -ne $a.dec) { [int]$a.dec } else { 2 }
  # en nivå med en enda punkt blir en smal ruta (±0,05 %) så att den syns
  $z = foreach ($k in 's2', 's1', 'r1', 'r2') { $r = @($a.$k); $lo = [double]$r[0]; $hi = [double]$r[-1]; if ($hi - $lo -lt $lo * 0.0005) { $m = ($lo + $hi) / 2; $lo = $m * 0.9995; $hi = $m * 1.0005 }; $lo; $hi }
  $vals = @($z) + @($a.bos, $a.inval, $nv.poc, $nv.val, $nv.vah)
  $seen = @{}; $zones = @($nv.zones | Where-Object { $k = "$($_.lo)|$($_.hi)"; if ($seen[$k]) { $false } else { $seen[$k] = 1; $true } } | ForEach-Object { P $_.lo; P $_.hi; $(if ($_.kind -eq 'stöd') { '1.0' } else { '-1.0' }) })
  $txt = "$($STAT[[string]$a.status]): $($a.statusText -replace '^(Vänta|Bevaka|Köp inte|Köpläge|Delvis)[: ]*', '')"
  $info = "BOS $(S $a.bos $d) · fel om $(S $a.inval $d) · nivåer $($a.levelsAt)"
  foreach ($t in $TICK[$id]) {
    $lv += "    $(Q $t) => array.from($(($vals | ForEach-Object { P $_ }) -join ', '))"
    $zn += "    $(Q $t) => $(if ($zones.Count) { "array.from($($zones -join ', '))" } else { 'array.new_float(0)' })"
    $bs += "    $(Q $t) => $(Q $txt)"
    $nf += "    $(Q $t) => $(Q $info)"
  }
}
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$pine = @"
//@version=5
// Jarvis nivåer – genererad av Jarvis $stamp (scripts\pine.ps1). Ersätt hela skriptet när Jarvis gör en ny analys.
// Grönt = stöd S1/S2, rött = motstånd R1/R2, blått = BOS (köp först vid stängning över), orange streckat = fel om (tesen är fel vid stängning under).
// Tunna rutor = FVG och order block från djupanalysen, prickat = POC, VAL och VAH (volymprofil 60 dagar). Analys, inte finansiell rådgivning.
indicator("Jarvis nivåer", shorttitle = "Jarvis", overlay = true, max_boxes_count = 100, max_lines_count = 100, max_labels_count = 100)
visaZoner = input.bool(true, "Visa FVG och order block")
visaVP = input.bool(true, "Visa POC, VAL och VAH")
visaBesked = input.bool(true, "Visa beskedet")
bakat = input.int(120, "Rita från antal staplar bakåt", minval = 10)
cS = #16A34A
cR = #DC2626
cB = #2563EB
cX = #F97316
cV = #7C3AED
t = str.replace_all(syminfo.ticker, "USDT", "USD")
// s2lo, s2hi, s1lo, s1hi, r1lo, r1hi, r2lo, r2hi, bos, fel om, poc, val, vah
lv = switch t
$($lv -join "`n")
    => array.new_float(0)
// FVG och order block: lo, hi, typ (1 = stöd, -1 = motstånd)
zn = switch t
$($zn -join "`n")
    => array.new_float(0)
besked = switch t
$($bs -join "`n")
    => ""
infotext = switch t
$($nf -join "`n")
    => ""
f_box(float lo, float hi, color col, string txt, int tr) =>
    box.new(bar_index - bakat, hi, bar_index + 10, lo, border_color = color.new(col, 30), bgcolor = color.new(col, tr), extend = extend.right, text = txt, text_color = col, text_size = size.small, text_halign = text.align_right)
f_line(float y, color col, string sty, string txt) =>
    line.new(bar_index - bakat, y, bar_index + 10, y, color = col, style = sty, width = 2, extend = extend.right)
    label.new(bar_index + 10, y, txt, style = label.style_label_left, color = color.new(col, 85), textcolor = col, size = size.small)
if barstate.islast and array.size(lv) == 13
    f_box(array.get(lv, 0), array.get(lv, 1), cS, "S2", 88)
    f_box(array.get(lv, 2), array.get(lv, 3), cS, "S1", 80)
    f_box(array.get(lv, 4), array.get(lv, 5), cR, "R1", 80)
    f_box(array.get(lv, 6), array.get(lv, 7), cR, "R2", 88)
    f_line(array.get(lv, 8), cB, line.style_solid, "BOS " + str.tostring(array.get(lv, 8), format.mintick))
    f_line(array.get(lv, 9), cX, line.style_dashed, "Fel om " + str.tostring(array.get(lv, 9), format.mintick))
    if visaVP
        for i = 10 to 12
            y = array.get(lv, i)
            if not na(y)
                line.new(bar_index - bakat, y, bar_index + 10, y, color = color.new(cV, 20), style = line.style_dotted, width = 1, extend = extend.right)
                label.new(bar_index - bakat, y, i == 10 ? "POC" : i == 11 ? "VAL" : "VAH", style = label.style_label_right, color = color.new(cV, 90), textcolor = cV, size = size.tiny)
    if visaZoner and array.size(zn) >= 3
        for j = 0 to int(array.size(zn) / 3) - 1
            lo = array.get(zn, j * 3)
            hi = array.get(zn, j * 3 + 1)
            ty = array.get(zn, j * 3 + 2)
            if not na(lo) and not na(hi)
                box.new(bar_index - math.round(bakat / 2), hi, bar_index + 10, lo, border_color = color.new(ty > 0 ? cS : cR, 60), border_style = line.style_dotted, bgcolor = color.new(ty > 0 ? cS : cR, 94), extend = extend.right)
if barstate.islast and visaBesked and besked != ""
    var table tb = table.new(position.top_right, 1, 3, bgcolor = color.new(color.black, 80), border_width = 0)
    table.cell(tb, 0, 0, "Jarvis", text_color = color.white, text_size = size.small, text_halign = text.align_left)
    table.cell(tb, 0, 1, besked, text_color = color.white, text_size = size.normal, text_halign = text.align_left)
    table.cell(tb, 0, 2, infotext, text_color = color.new(color.white, 30), text_size = size.small, text_halign = text.align_left)
"@
[IO.File]::WriteAllText((Join-Path $data 'jarvis-nivaer.pine'), $pine, [Text.UTF8Encoding]::new($false))
"klart -> $data\jarvis-nivaer.pine ($($pine.Length) tecken, $($lv.Count) symboler)"
