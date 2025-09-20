<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
if (!defined('ENVIO_CASA_PRODUCT_ID')) define('ENVIO_CASA_PRODUCT_ID', 9001);

$query = "SELECT
            v.tipo_entrega,
            CASE
                WHEN v.tipo_entrega = 'mesa' THEN m.nombre
                ELSE CONCAT('Domicilio - ', r.nombre)
            END AS destino,
            p.nombre AS producto,
            d.cantidad,
            d.created_at,
            d.entregado_hr,
            d.estado_producto,
            d.id AS detalle_id
          FROM venta_detalles d
          JOIN ventas v ON v.id = d.venta_id
          LEFT JOIN mesas m ON m.id = v.mesa_id
          LEFT JOIN repartidores r ON r.id = v.repartidor_id
          JOIN productos p ON p.id = d.producto_id
          WHERE d.estado_producto = 'entregado' AND DATE(d.created_at) = CURDATE() AND d.producto_id <> " . (int)ENVIO_CASA_PRODUCT_ID . "
          ORDER BY destino, d.created_at DESC";

$result = $conn->query($query);
if (!$result) {
    error('Error al obtener productos: ' . $conn->error);
}

$entregados = [];
while ($row = $result->fetch_assoc()) {
    $entregados[] = [
        'destino'      => $row['destino'],
        'tipo'         => $row['tipo_entrega'],
        'producto'     => $row['producto'],
        'cantidad'     => (int) $row['cantidad'],
        'hora'         => $row['entregado_hr'],
        'entregado_hr' => $row['entregado_hr'],
        'estado'       => $row['estado_producto'],
        'detalle_id'   => (int) $row['detalle_id']
    ];
}

success($entregados);
?>
