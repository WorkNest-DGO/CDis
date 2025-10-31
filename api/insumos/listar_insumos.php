<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

$query = "SELECT i.id, i.nombre, i.unidad, i.existencia, i.tipo_control, i.imagen, i.minimo_stock,
                 i.reque_id,
                 COALESCE(rt.nombre, '') AS reque_nombre
          FROM insumos i
          LEFT JOIN reque_tipos rt ON rt.id = i.reque_id
          ORDER BY i.nombre";
$result = $conn->query($query);

if (!$result) {
    error('Error al obtener insumos: ' . $conn->error);
}

$insumos = [];
while ($row = $result->fetch_assoc()) {
    $insumos[] = $row;
}

success($insumos);
