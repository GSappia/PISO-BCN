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

# Lo que nunca es una vivienda entera para una persona.
$NO_VIVIENDA = '(?i)habitación|habitacion|compartid|compartir|coliving|residencia|' +
               'plaza de (aparcamiento|garaje)|parking|trastero|local comercial|oficina|nave|solar'

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
  if (-not $f.zona) { return $false }
  if (($f.zona -notmatch $ZONAS) -and ($f.texto -notmatch $ZONAS)) { return $false }
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

$nuevos = @()
$vistos = @{}
foreach ($a in $encontrados) {
  $clave = $a.url -replace '\?.*$', ''
  if ($vistos.ContainsKey($clave)) { continue }
  $vistos[$clave] = $true
  if ($urlsConocidas.ContainsKey($clave)) { continue }
  if ($idsConocidos.ContainsKey($a.id))   { continue }
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

  $json = $datos | ConvertTo-Json -Depth 5 -Compress
  $json = $json.Replace('<', '<')
  [System.IO.File]::WriteAllText($rutaDatos, $json, (New-Object System.Text.UTF8Encoding($false)))

  Write-Host "Anadidos a datos.json:"
  foreach ($a in $anadidos) {
    Write-Host ("  {0,6} EUR  {1,4} m2  {2,-28} {3}" -f $a.precio, $a.m2, $a.barrio, $a.anunciante)
  }
} else {
  Write-Host "Nada nuevo: datos.json se queda como estaba."
}

Write-Host ""
Write-Host "Listo."
