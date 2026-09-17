# Barrido automatico de portales. Anade a datos.json los anuncios nuevos.
#
# Corre igual en Windows PowerShell 5.1 (el PC) y en pwsh 7 (GitHub Actions).
#
# Lee los dos portales que se dejan leer sin navegador y devuelven fichas
# completas: Habitaclia y Pisos.com.
#   - Idealista y Yaencontre responden 403 a todo lo que no sea un navegador.
#   - Enalquiler monta los enlaces de ficha con JavaScript, asi que desde aqui
#     no hay forma de sacarlos.
# Esos tres siguen necesitando a Claude con el navegador abierto.
#
# Uso:  pwsh tools/buscar.ps1        (o powershell -File tools\buscar.ps1)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$raiz = Split-Path -Parent $PSScriptRoot
$rutaDatos = Join-Path $raiz 'datos.json'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

$PRECIO_MAX = 1300
$PRECIO_MIN = 450     # por debajo de esto en Barcelona es habitacion, plaza o trastero
$M2_MIN     = 20

# El precio por metro delata lo que la tarjeta no dice. Toda la busqueda se
# mueve entre 13 y 25 EUR/m2. Por encima de 30 es alquiler de temporada casi
# siempre (pisos diminutos con "todos los gastos incluidos"); por debajo de 8
# no es una vivienda entera, es una habitacion o un dato mal leido.
$RATIO_MAX = 30
$RATIO_MIN = 8

# Lo que nunca es una vivienda entera para una persona.
$NO_VIVIENDA = '(?i)habitación|habitacion|compartid|compartir|coliving|residencia|' +
               'plaza de (aparcamiento|garaje)|parking|trastero|local comercial|oficina|nave|solar|' +
               'garaje en alquiler|trastero en alquiler|local en alquiler|despacho'

# Operadores de alquiler de temporada.
$TEMPORADA_TXT = '(?i)temporada|vacacional|corta estancia|short.?term|días mínimo|meses mínimo'
$TEMPORADA_IDS = '^(55551|52795|50824|30785)'   # Spotahome, HousingAnywhere, Uniplaces y similares

# Barrios y distritos que interesan (prioritarios y secundarios).
$ZONAS = '(?i)gràcia|gracia|eixample|les corts|sarrià|sarria|sant gervasi|sagrada|' +
         'guinardó|guinardo|sants|hostafrancs|clot|camp de l|vallcarca|fort pienc|' +
         'sant antoni|poble sec|montjuïc|montjuic|vila de|la salut|putget|farró|farro|' +
         'bonanova|galvany|tres torres|maternitat|sant ramon|badal|la bordeta|font de la guatlla'

function Texto($html) {
  $t = [regex]::Replace($html, '<script[\s\S]*?</script>', ' ')
  $t = [regex]::Replace($t, '<style[\s\S]*?</style>', ' ')
  $t = [regex]::Replace($t, '<[^>]+>', ' ')
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  return ($t -replace '\s+', ' ').Trim()
}

function Baja($url) {
  try {
    return (Invoke-WebRequest -Uri $url -UserAgent $UA -TimeoutSec 30 -UseBasicParsing).Content
  } catch {
    $codigo = 'sin respuesta'
    if ($_.Exception.Response) { $codigo = [int]$_.Exception.Response.StatusCode }
    Write-Host ("    no se pudo leer ({0}): {1}" -f $codigo, $url)
    return $null
  }
}

function Numero($txt) {
  if (-not $txt) { return $null }
  $t = $txt -replace '[^\d]', ''
  if ($t -eq '') { return $null }
  return [int]$t
}

# Comprueba una ficha ya extraida. Devuelve $true si merece entrar.
function Vale($f) {
  if (-not $f.precio) { return $false }
  if ($f.precio -gt $PRECIO_MAX -or $f.precio -lt $PRECIO_MIN) { return $false }
  if (-not $f.m2 -or $f.m2 -lt $M2_MIN) { return $false }
  if ($f.hab -and $f.hab -gt 1) { return $false }
  if ($f.texto -match $NO_VIVIENDA) { return $false }
  if ($f.texto -match $TEMPORADA_TXT) { return $false }

  $ratio = $f.precio / $f.m2
  if ($ratio -gt $RATIO_MAX -or $ratio -lt $RATIO_MIN) { return $false }

  # La zona se comprueba SOLO contra el barrio extraido, nunca contra el texto
  # de la ventana: en Pisos.com la ventana se solapa con el anuncio siguiente y
  # colaban fichas de barrios que no son.
  if (-not $f.zona) { return $false }
  if ($f.zona -notmatch $ZONAS) { return $false }
  return $true
}

# --------------------------------------------------------------------------
# Habitaclia: filtro de 1 dormitorio en la propia URL, una <article> por ficha
# --------------------------------------------------------------------------
function Barrido-Habitaclia {
  $res = @()
  for ($p = 1; $p -le 8; $p++) {
    $sufijo = ''
    if ($p -gt 1) { $sufijo = "/$p" }
    $url = "https://www.habitaclia.com/alquiler/viviendas/barcelona-provincia/barcelona-capital/s$sufijo" +
           "?maxPrice=$PRECIO_MAX&minRooms=1&maxRooms=1"
    $html = Baja $url
    if (-not $html) { break }

    $trozos = [regex]::Split($html, '<article') | Select-Object -Skip 1
    if ($trozos.Count -eq 0) { break }

    foreach ($t in $trozos) {
      $mId = [regex]::Match($t, 'href="([^"]*?i(\d+)\.htm[^"]*)"')
      if (-not $mId.Success) { continue }
      $id = $mId.Groups[2].Value
      if ($id -match $TEMPORADA_IDS) { continue }

      $enlace = $mId.Groups[1].Value
      if ($enlace -notmatch '^https?://') { $enlace = 'https://www.habitaclia.com' + $enlace }
      $enlace = $enlace -replace '\?.*$', ''

      $txt = Texto $t

      # "Piso con terraza en alquiler en Hostafrancs Barcelona Capital, Barcelona"
      $zona = [regex]::Match($txt, 'en alquiler en (.{3,60}?)\s*Barcelona').Groups[1].Value.Trim()
      # Habitaclia pone "N/A" cuando el anunciante oculta la direccion.
      $zona = ($zona -replace '^N/A\s*', '').Trim(' ', ',', '-')
      if ($zona.Length -lt 3) { $zona = '' }

      $ficha = [pscustomobject]@{
        portal = 'Habitaclia'; id = "hab-$id"; url = $enlace
        precio = Numero ([regex]::Match($txt, '([\d\.]+)\s*€\s*/?\s*mes').Groups[1].Value)
        m2     = Numero ([regex]::Match($txt, '(\d+)\s*m²').Groups[1].Value)
        hab    = Numero ([regex]::Match($txt, '(\d+)\s*hab').Groups[1].Value)
        zona   = $zona; texto = $txt
      }
      if (Vale $ficha) { $res += $ficha }
    }
    Start-Sleep -Milliseconds 700
  }
  return $res
}

# --------------------------------------------------------------------------
# Pisos.com: sin filtro de habitaciones en la URL. Se toma una ventana de
# texto a partir de cada enlace de ficha, porque el enlace va por delante
# de la tarjeta y partir por la clase CSS los separa.
# --------------------------------------------------------------------------
function Barrido-Pisos {
  $res = @()
  $vistos = @{}
  for ($p = 1; $p -le 6; $p++) {
    $sufijo = ''
    if ($p -gt 1) { $sufijo = "$p/" }
    $url = "https://www.pisos.com/alquiler/pisos-barcelona_capital/hasta-$PRECIO_MAX/$sufijo"
    $html = Baja $url
    if (-not $html) { break }

    $enlaces = [regex]::Matches($html, 'href="(/alquilar/([a-z]+)-[^"]*?-(\d{6,})_\d+/)"')
    if ($enlaces.Count -eq 0) { break }

    foreach ($m in $enlaces) {
      $id = $m.Groups[3].Value
      if ($vistos.ContainsKey($id)) { continue }
      $vistos[$id] = $true

      $clase = $m.Groups[2].Value          # piso, estudio, atico, apartamento, duplex, loft...
      $enlace = 'https://www.pisos.com' + $m.Groups[1].Value

      # El precio y los metros van bastante despues del enlace en el HTML:
      # con menos de 6.000 caracteres la ventana se queda corta.
      $desde = $m.Index
      $largo = [Math]::Min(6000, $html.Length - $desde)
      $txt = Texto $html.Substring($desde, $largo)

      # "Piso en Carrer de Tarragona Hostafrancs (Distrito Sants-Montjuic. Barcelona Capital)"
      $zona = [regex]::Match($txt, '\(Distrito\s+(.{3,40}?)\s*[\.\)]').Groups[1].Value.Trim()
      if (-not $zona) { $zona = [regex]::Match($txt, '\s+en\s+(.{3,45}?)\s*\(').Groups[1].Value.Trim() }

      $hab = Numero ([regex]::Match($txt, '(\d+)\s*hab').Groups[1].Value)
      if (-not $hab -and $clase -notmatch 'estudio|loft') { continue }

      $ficha = [pscustomobject]@{
        portal = 'Pisos.com'; id = "pis-$id"; url = $enlace
        precio = Numero ([regex]::Match($txt, '([\d\.]+)\s*€\s*/?\s*mes').Groups[1].Value)
        m2     = Numero ([regex]::Match($txt, '(\d+)\s*m²').Groups[1].Value)
        hab    = $hab
        zona   = $zona; texto = $txt
      }
      if (Vale $ficha) { $res += $ficha }
    }
    Start-Sleep -Milliseconds 700
  }
  return $res
}

# --------------------------------------------------------------------------
# Webs de inmobiliarias
#
# Cada una publica a su manera, asi que se configura con su pagina de alquiler
# y el patron de sus enlaces de ficha. Son webs pequenas: si alguna cambia de
# formato deja de dar resultados, pero nunca rompe el barrido.
# --------------------------------------------------------------------------
# Ojo: hay webs que escriben los enlaces con comillas simples (Guinot Prunera)
# y otras con dobles, asi que todos los patrones aceptan las dos.
$AGENCIAS = @(
  @{ n = 'Guinot Prunera';  u = 'https://www.guinotprunera.com/es/alquiler/';                    p = 'href=["'']([^"'']*ref-\d+)["'']' },
  @{ n = 'Finques Martell'; u = 'https://finquesmartell.com/inmuebles';                          p = 'href=["'']([^"'']*/immoble/[^"'']+)["'']' },
  @{ n = 'Finques Feliu';   u = 'https://www.finquesfeliu.es/es/buscador/inter';                 p = 'href=["'']([^"'']*/node/\d+)["'']' },
  @{ n = 'BarnaPiso';       u = 'https://barnapiso.com/propietats-disponibles-barcelona/';       p = 'href=["'']([^"'']*/habitatge/[^"'']+)["'']' },
  @{ n = 'Toysan Finques';  u = 'https://toysanfinques.com/immobles/';                           p = 'href=["'']([^"'']*/immobles/[^"''/]+/)["'']' },
  @{ n = 'Finques Marba';   u = 'https://www.finquesmarba.com/alquiler/';                        p = 'href=["'']([^"'']*\?property=[^"'']+)["'']' },
  @{ n = 'Finques Teixidor';u = 'https://www.finquesteixidor.com/es/alquiler-barcelona.cfm';     p = 'href=["'']([^"'']*/ID/\d+/[^"'']*)["'']' },
  @{ n = 'Calvet Premium';  u = 'https://inmobiliaria.calvetpremium.com/es/venta_o_alquiler';    p = 'href=["'']([^"'']*/es/[a-z_]+/\d+[^"'']*)["'']' },
  @{ n = 'Fincas Ubiergo';  u = 'https://fincasubiergo.com/es/alquiler/viviendas/barcelona/barcelona'; p = 'href=["'']([^"'']*/alquiler/viviendas/barcelona/barcelona/\d+)["'']' },
  @{ n = 'Multi Espai';     u = 'https://multiespaibcn.com/status/alquiler';                     p = 'href=["'']([^"'']*/property/[^"'']+)["'']' }
)

# No se intenta leer las fichas una a una: cada web esta hecha de una forma y
# un lector generico falla en todas. Lo que si funciona en cualquiera es mirar
# que precios dentro de tu horquilla anuncia hoy y compararlo con la vez
# anterior. Si la lista cambia, esa inmobiliaria ha movido su oferta y toca
# mirarla; si no cambia, no hay nada que ver.
function Vigilar-Agencias($previas) {
  $estado = @()
  foreach ($ag in $AGENCIAS) {
    $html = Baja $ag.u
    if (-not $html) {
      Write-Host ("    {0,-18} no responde" -f $ag.n)
      $estado += [pscustomobject]@{ nombre = $ag.n; url = $ag.u; precios = @(); huella = 'sin-respuesta'; cambio = $false }
      continue
    }

    $txt = Texto $html
    $precios = @()
    foreach ($m in [regex]::Matches($txt, '([\d\.]{3,6})\s*€')) {
      $v = Numero $m.Groups[1].Value
      if ($v -and $v -ge $PRECIO_MIN -and $v -le $PRECIO_MAX) { $precios += $v }
    }
    $precios = @($precios | Sort-Object -Unique)
    $huella = ($precios -join ',')

    $antes = $null
    if ($previas) { $antes = $previas | Where-Object { $_.nombre -eq $ag.n } | Select-Object -First 1 }
    $cambio = $false
    if ($antes -and $antes.huella -ne $huella -and $antes.huella -ne 'sin-respuesta') { $cambio = $true }

    $aviso = ''
    if ($cambio) { $aviso = '  <-- ha cambiado' }
    Write-Host ("    {0,-18} {1} anuncios en tu horquilla{2}" -f $ag.n, $precios.Count, $aviso)

    $estado += [pscustomobject]@{ nombre = $ag.n; url = $ag.u; precios = $precios; huella = $huella; cambio = $cambio }
    Start-Sleep -Milliseconds 600
  }
  return $estado
}

# --------------------------------------------------------------------------
# Barrido
# --------------------------------------------------------------------------
Write-Host ("Barrido de portales - {0}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm'))
Write-Host ""

$encontrados = @()
Write-Host "  Habitaclia..."
$lote = Barrido-Habitaclia
Write-Host ("    {0} fichas validas" -f $lote.Count)
$encontrados += $lote

Write-Host "  Pisos.com..."
$lote = Barrido-Pisos
Write-Host ("    {0} fichas validas" -f $lote.Count)
$encontrados += $lote

$datosPrevios = Get-Content $rutaDatos -Raw -Encoding UTF8 | ConvertFrom-Json
$agenciasAntes = $null
if ($datosPrevios.PSObject.Properties.Name -contains 'agencias') { $agenciasAntes = $datosPrevios.agencias }

Write-Host "  Webs de inmobiliarias..."
$agenciasAhora = Vigilar-Agencias $agenciasAntes
$conCambio = @($agenciasAhora | Where-Object { $_.cambio })
Write-Host ("    {0} vigiladas, {1} con cambios" -f $agenciasAhora.Count, $conCambio.Count)

Write-Host ""
Write-Host ("Total tras filtrar: {0}" -f $encontrados.Count)

# --------------------------------------------------------------------------
# Comparar con lo que ya hay
# --------------------------------------------------------------------------
$datos = Get-Content $rutaDatos -Raw -Encoding UTF8 | ConvertFrom-Json

$urlsConocidas = @{}
foreach ($f in $datos.pisos)     { if ($f.url) { $urlsConocidas[($f.url -replace '\?.*$','')] = $true } }
foreach ($f in $datos.colivings) { if ($f.url) { $urlsConocidas[($f.url -replace '\?.*$','')] = $true } }

$idsConocidos = @{}
foreach ($f in $datos.pisos) { if ($f.id) { $idsConocidos[[string]$f.id] = $true } }

# Un mismo piso se anuncia en varios portales con URLs distintas. La pareja
# precio + metros lo identifica bastante bien: si ya hay una ficha con los dos
# iguales, se da por duplicado.
$huellas = @{}
foreach ($f in $datos.pisos) {
  if ($f.precio -and $f.m2) { $huellas[("{0}|{1}" -f $f.precio, $f.m2)] = $true }
}

$nuevos = @()
$vistos = @{}
foreach ($a in $encontrados) {
  $clave = $a.url -replace '\?.*$', ''
  if ($vistos.ContainsKey($clave)) { continue }
  $vistos[$clave] = $true
  if ($urlsConocidas.ContainsKey($clave)) { continue }
  if ($idsConocidos.ContainsKey($a.id))   { continue }
  $huella = "{0}|{1}" -f $a.precio, $a.m2
  if ($huellas.ContainsKey($huella)) { continue }
  $huellas[$huella] = $true
  $nuevos += $a
}

Write-Host ("Nuevos, en tus zonas y no vistos antes: {0}" -f $nuevos.Count)
Write-Host ""

# --------------------------------------------------------------------------
# Escribir datos.json
# --------------------------------------------------------------------------
foreach ($f in $datos.pisos) {
  if ($f.PSObject.Properties.Name -contains 'nuevo') { $f.nuevo = $false }
}

$hoy = Get-Date -Format 'dd/MM/yyyy'
$fila = 200
$anadidos = @()

foreach ($a in $nuevos) {
  $fila++
  $ratio = $null
  if ($a.m2 -and $a.m2 -gt 5) { $ratio = [math]::Round($a.precio / $a.m2, 1) }
  $tipo = '1 hab'
  if (-not $a.hab) { $tipo = 'Estudio' }

  $anadidos += [pscustomobject]@{
    id = $a.id; grupo = 'p'; fila = $fila
    estado = 'Por aclarar'; prioridad = 'BAJA'
    precio = $a.precio; m2 = $a.m2; ratio = $ratio
    tipo = $tipo; distrito = ''; barrio = $a.zona
    amueblado = 'Por confirmar'; amuSi = $false; amuNo = $false
    anunciante = $a.portal; contrato = 'Por confirmar'; temporada = $false
    url = $a.url
    notas = ("Encontrado por el barrido automatico del {0} en {1}. SIN VERIFICAR: nadie ha comprobado todavia el mobiliario, el tipo de contrato ni la cedula de habitabilidad. Abrelo antes de fiarte." -f $hoy, $a.portal)
    nuevo = $true
    auto = $true
  }
}

if ($anadidos.Count -gt 0) {
  $datos.pisos = @($anadidos) + @($datos.pisos)
  $datos.generado = Get-Date -Format 'yyyy-MM-dd'
}

# El resultado del barrido se guarda SIEMPRE, encuentre o no algo. Asi la
# pagina puede decir cuando corrio por ultima vez y que vio: un boton que no
# deja rastro parece roto aunque haya funcionado.
$barrido = [pscustomobject]@{
  fecha      = Get-Date -Format 'yyyy-MM-dd'
  hora       = Get-Date -Format 'HH:mm'
  revisados  = $encontrados.Count
  nuevos     = $anadidos.Count
  portales   = ("Habitaclia, Pisos.com y {0} webs de inmobiliarias" -f $AGENCIAS.Count)
  agenciasConCambio = @($conCambio | ForEach-Object { $_.nombre })
}

if ($datos.PSObject.Properties.Name -contains 'agencias') {
  $datos.agencias = $agenciasAhora
} else {
  $datos | Add-Member -NotePropertyName agencias -NotePropertyValue $agenciasAhora
}
if ($datos.PSObject.Properties.Name -contains 'barrido') {
  $datos.barrido = $barrido
} else {
  $datos | Add-Member -NotePropertyName barrido -NotePropertyValue $barrido
}

$json = $datos | ConvertTo-Json -Depth 5 -Compress
$json = $json.Replace('<', '<')
[System.IO.File]::WriteAllText($rutaDatos, $json, (New-Object System.Text.UTF8Encoding($false)))

if ($anadidos.Count -gt 0) {
  Write-Host "Anadidos a datos.json:"
  foreach ($a in $anadidos) {
    Write-Host ("  {0,6} EUR  {1,4} m2  {2,-28} {3}" -f $a.precio, $a.m2, $a.barrio, $a.anunciante)
  }
} else {
  Write-Host "Nada nuevo, pero queda anotado el barrido con su hora."
}

Write-Host ""
Write-Host "Listo."
