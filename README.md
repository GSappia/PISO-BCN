# Pisos BCN

Buscador propio de piso de alquiler en Barcelona. Una sola página, sin servidor:
reúne los anuncios de varios portales y de las webs de inmobiliarias de barrio, y
deja filtrarlos, marcarlos y preparar los mensajes de contacto.

## Qué hace

- **111 fichas de piso y 17 de coliving**, con precio, €/m², m², barrio, distrito,
  tipo de contrato, si viene amueblado, el anunciante y notas sobre cada una.
- **Filtros**: distritos (los 10 de Barcelona, selección múltiple, con atajos para
  las zonas prioritarias y secundarias), habitaciones (selección múltiple), precio
  máximo, amueblado y orden.
- **Interruptores de visibilidad**: ocultar alquiler de temporada, ocultar
  descartados, ocultar los ya contactados, ver solo favoritos.
- **Marcas por ficha**: favorito, «ya hablé», descartado y una nota libre.
- **Mensajes preescritos** editables, con huecos que se rellenan con los datos del
  piso: `{{barrio}}`, `{{distrito}}`, `{{precio}}`, `{{m2}}`, `{{tipo}}`,
  `{{enlace}}` y `{{docs}}`.
- **Documentación**: un sitio donde guardar el enlace de descarga de cada
  documento (contrato, nóminas, DNI) para incluirlos en el mensaje de perfil.

## Criterios de la búsqueda

1 dormitorio o estudio · amueblado · contrato LAU de vivienda habitual (no de
temporada) · hasta 1.300 €/mes, franja ideal 800-950 · entrada entre octubre y
diciembre.

Zonas prioritarias: Gràcia, Eixample (incluida la Sagrada Família), Les Corts y
Sarrià-Sant Gervasi. Secundarias: Sants, Baix Guinardó, El Clot y El Camp de
l'Arpa del Clot.

## De dónde salen los datos

Cinco portales — Idealista, Habitaclia, Pisos.com, Enalquiler y Yaencontre — y las
webs propias de 16 inmobiliarias de Barcelona, que publican cosas que no llegan a
los portales: Guinot Prunera, Finques Martell, Finques Feliu, BarnaPiso, Toysan
Finques, Finques Marbà y Finques Teixidor, entre otras.

Fotocasa y Milanuncios quedan fuera: el primero bloquea la lectura automática y el
segundo exige aceptar cookies de seguimiento o crear cuenta.

## Cómo actualizar los datos

1. Edita o regenera `datos.json`.
2. Ejecuta el generador:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\construir.ps1
   ```

3. Confirma y sube los cambios:

   ```bash
   git add -A && git commit -m "Actualiza anuncios" && git push
   ```

`index.html` se genera; no lo edites a mano. Lo que se toca es
`tools/plantilla.html`, que lleva el marcador `__DATOS__` donde se inyecta el JSON.

### Forma de cada ficha en `datos.json`

```json
{
  "id": "p-2", "grupo": "p", "fila": 2,
  "estado": "Por contactar", "prioridad": "ALTA",
  "precio": 840, "m2": 55, "ratio": 15.3,
  "tipo": "1 hab", "distrito": "Gràcia", "barrio": "Vila de Gràcia",
  "amueblado": "Sí", "amuSi": true, "amuNo": false,
  "anunciante": "...", "contrato": "...", "temporada": false,
  "url": "https://...", "notas": "...", "nuevo": false
}
```

`prioridad` pinta la franja de color de la izquierda (ALTA, MEDIA, BAJA).
`temporada` marca los anuncios de alquiler de temporada, que se ocultan por
defecto. `nuevo` los sube al principio con la etiqueta «Nuevo hoy».

## Dónde se guardan tus marcas

En esta versión, en el `localStorage` del navegador: **no salen de tu equipo y no
viajan a otro dispositivo**. Nada de lo que marques o escribas se sube al
repositorio.

La misma página existe también como Artifact privado en claude.ai, donde las
marcas sí se sincronizan entre el móvil y el ordenador y se pueden adjuntar los
PDF. El código detecta solo dónde está corriendo y adapta lo que ofrece.

## Publicar en GitHub Pages

En el repositorio: **Settings → Pages → Source: Deploy from a branch → Branch:
`main` / carpeta `/ (root)`**. La web queda en
`https://<usuario>.github.io/<repositorio>/` al cabo de un par de minutos.

Ten presente que GitHub Pages es público: cualquiera con el enlace ve los
anuncios y las notas.
