# Cocina en Tiempo Real (Long‑Poll por Notificación)

- Endpoints nuevos:
  - `CDI/api/cocina/notify_cambio.php` — recibe `ids` de `venta_detalles` cambiados y aumenta una versión global.
  - `CDI/api/cocina/listen_cambios.php` — long‑poll que despierta cuando sube la versión y devuelve `ids` afectados.
  - `CDI/api/cocina/estados_por_ids.php` — devuelve `estado_producto` para una lista de `detalle_id`.

- Runtime:
  - Carpeta `CDI/api/cocina/runtime/` con permisos de escritura para PHP. Allí se crean `cocina_version.txt` y `cocina_events.jsonl`.

- Backend (ajuste requerido):
  - Tras un `UPDATE` exitoso de `estado_producto`, notificar con POST a `notify_cambio.php` enviando los `detalle_id` afectados.

- Front (cocina2.js):
  - Mantener una sola petición long‑poll a `listen_cambios.php?since=<version>` y, al despertar, pedir `estados_por_ids.php` con los `ids` recibidos para mover tarjetas en el DOM.

## Notas

- Este enfoque no consulta la BD mientras no haya cambios.
- Por cambio real, cada cliente hace 1 fetch al long‑poll + 1 fetch por estados.

