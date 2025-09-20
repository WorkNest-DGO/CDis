<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
if (!defined('ENVIO_CASA_PRODUCT_ID')) define('ENVIO_CASA_PRODUCT_ID', 9001);
if (!defined('CARGO_PLATAFORMA_PRODUCT_ID')) define('CARGO_PLATAFORMA_PRODUCT_ID', 9000);
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}
$rol = $_SESSION['rol'] ?? ($_SESSION['usuario']['rol'] ?? null);

$sql = "SELECT
  d.id                          AS detalle_id,
  v.id                          AS venta_id,
  v.fecha                       AS fecha_venta,
  v.tipo_entrega,
  CASE
    WHEN v.tipo_entrega = 'mesa' THEN
      CONCAT(
        m.nombre,
        ' (',
        COALESCE(ca.nombre, 'Sin área'),
        ')'
      )
    WHEN v.tipo_entrega = 'domicilio' THEN CONCAT('Domicilio - ', r.nombre)
    ELSE 'Venta rápida'
  END                           AS destino,

  p.id                          AS producto_id,
  p.nombre                      AS producto,
  cat.nombre                    AS categoria,
  d.cantidad,
  d.precio_unitario,
  d.subtotal,
  d.insumos_descargados,

  d.created_at                  AS hora,
  d.entregado_hr,
  TIMESTAMPDIFF(MINUTE, d.created_at, NOW()) AS minutos_transcurridos,
  d.estado_producto             AS estado,

  d.observaciones,
  v.observacion                 AS observaciones_venta,

  u.nombre                      AS mesero,
  cu.nombre                     AS cajero,
  s.nombre                      AS sede,

  v.estado_entrega,
  v.seudonimo_entrega,
  r.telefono                    AS repartidor_telefono,
  (
    SELECT GROUP_CONCAT(
             CONCAT(i.nombre, ' ',
                    ROUND(r2.cantidad * d.cantidad, 2), ' ',
                    COALESCE(i.unidad, ''))
             ORDER BY i.nombre
             SEPARATOR ' | '
           )
    FROM recetas r2
    JOIN insumos i ON i.id = r2.insumo_id
    WHERE r2.producto_id = d.producto_id
  )                              AS insumos_requeridos,

  CASE
    WHEN d.estado_producto IN ('pendiente','en_preparacion')
         AND TIMESTAMPDIFF(MINUTE, d.created_at, NOW()) >= 20
      THEN 'alta'
    WHEN d.estado_producto IN ('pendiente','en_preparacion')
         AND TIMESTAMPDIFF(MINUTE, d.created_at, NOW()) BETWEEN 10 AND 19
      THEN 'media'
    ELSE 'normal'
  END                            AS prioridad

FROM venta_detalles d
JOIN ventas v            ON v.id = d.venta_id
LEFT JOIN mesas m        ON m.id = v.mesa_id
LEFT JOIN catalogo_areas ca ON ca.id = m.area_id
LEFT JOIN repartidores r ON r.id = v.repartidor_id
JOIN productos p         ON p.id = d.producto_id
LEFT JOIN catalogo_categorias cat ON cat.id = p.categoria_id
LEFT JOIN usuarios u     ON u.id = v.usuario_id
LEFT JOIN usuarios cu    ON cu.id = v.cajero_id
LEFT JOIN sedes s        ON s.id = v.sede_id
WHERE
  (
    d.estado_producto <> 'entregado'
    OR (d.estado_producto = 'entregado' AND DATE(d.created_at) = CURDATE())
  )";
if ($rol === 'barra') {
    $sql .= " AND p.categoria_id = 1";
} elseif ($rol === 'alimentos') {
    $sql .= " AND p.categoria_id <> 1";
}
// Excluir producto de envío en cocina
$conn->query("UPDATE venta_detalles SET estado_producto='entregado', entregado_hr=NOW() WHERE producto_id IN (".(int)ENVIO_CASA_PRODUCT_ID.",".(int)CARGO_PLATAFORMA_PRODUCT_ID.") AND estado_producto <> 'entregado'");
$sql .= " AND d.producto_id <> " . (int)ENVIO_CASA_PRODUCT_ID;
$sql .= " AND d.producto_id <> " . (int)CARGO_PLATAFORMA_PRODUCT_ID;
$sql .= "\nORDER BY\n  FIELD(d.estado_producto, 'pendiente','en_preparacion','listo','entregado'),\n  minutos_transcurridos DESC,\n  destino,\n  d.created_at;\n";

$res = $conn->query($sql);
if (!$res) { error('Error al obtener productos: ' . $conn->error); }

$out = [];
while ($row = $res->fetch_assoc()) {
    if ((int)$row['producto_id'] === (int)ENVIO_CASA_PRODUCT_ID) { continue; }
    if ((int)$row['producto_id'] === (int)CARGO_PLATAFORMA_PRODUCT_ID) { continue; }
    $out[] = [
  'venta_id'             => (int)$row['venta_id'],
  'tipo'                 => $row['tipo_entrega'],
  'destino'              => $row['destino'],
  'producto_id'          => (int)$row['producto_id'],
  'producto'             => $row['producto'],
  'categoria'            => isset($row['categoria']) ? $row['categoria'] : null,
  'cantidad'             => (float)$row['cantidad'],
  'precio_unitario'      => (float)$row['precio_unitario'],
  'subtotal'             => (float)$row['subtotal'],
  'insumos_descargados'  => (int)$row['insumos_descargados'],
  'hora'                 => $row['hora'],
  'entregado_hr'         => $row['entregado_hr'],
  'minutos_transcurridos'=> (int)$row['minutos_transcurridos'],
  'estado'               => $row['estado'],
  'observaciones'        => $row['observaciones'],
  'observaciones_venta'  => $row['observaciones_venta'],
  'mesero'               => $row['mesero'],
  'cajero'               => $row['cajero'],
  'sede'                 => $row['sede'],
  'estado_entrega'       => $row['estado_entrega'],
  'seudonimo_entrega'    => $row['seudonimo_entrega'],
  'repartidor_telefono'  => $row['repartidor_telefono'],
  'insumos_requeridos'   => $row['insumos_requeridos'],
  'prioridad'            => $row['prioridad'],
  'detalle_id'           => (int)$row['detalle_id']
    ];

}


success($out);
