<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

$query = "SELECT id, nombre, unidad, existencia, tipo_control, imagen, minimo_stock, reque FROM insumos ORDER BY nombre";
$result = $conn->query($query);

if (!$result) {
    error('Error al obtener insumos: ' . $conn->error);
}

$insumos = [];
while ($row = $result->fetch_assoc()) {
    $insumos[] = $row;
}

success($insumos);
