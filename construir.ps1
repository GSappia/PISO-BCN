# Genera index.html a partir de tools/plantilla.html + datos.json.
# Uso:  powershell -ExecutionPolicy Bypass -File tools\construir.ps1
#
# La plantilla lleva un marcador __DATOS__ donde se inyecta el JSON, y un
# comentario <!--FIN-HEAD--> que separa la cabecera del cuerpo del documento.

$raiz = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

$json = [System.IO.File]::ReadAllText((Join-Path $raiz 'datos.json'), [System.Text.Encoding]::UTF8)
$tpl  = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'plantilla.html'), [System.Text.Encoding]::UTF8)

$out = $tpl.Replace('__DATOS__', $json)

$marca = '<!--FIN-HEAD-->'
$i = $out.IndexOf($marca)
if ($i -lt 0) { throw "Falta el marcador $marca en plantilla.html" }

$cabeza = $out.Substring(0, $i)
$cuerpo = $out.Substring($i + $marca.Length)

$reset = @'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>
  :root{
    color-scheme: light dark;
    padding-top: env(safe-area-inset-top, 0px);
    padding-bottom: env(safe-area-inset-bottom, 0px);
  }
  body{ margin:0; font:14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; background:#f1f4f1; }
  img{ max-width:100%; }
  [hidden]{ display:none !important; }
</style>
'@

$pie = @'

</body>
</html>
'@

$web = $reset + $cabeza + "</head>`r`n<body>" + $cuerpo + $pie
[System.IO.File]::WriteAllText((Join-Path $raiz 'index.html'), $web, $utf8)

"index.html generado: " + $web.Length + " bytes"
