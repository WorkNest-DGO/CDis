<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

$limite = 50;
$stmt = $conn->prepare('SELECT id, nombre, unidad, existencia FROM insumos WHERE existencia < ? ORDER BY existencia ASC');
if (!$stmt) {
    error('Error al preparar consulta: ' . $conn->error);
}
$stmt->bind_param('d', $limite);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al ejecutar consulta: ' . $stmt->error);
}
$res = $stmt->get_result();
$insumos = [];
while ($row = $res->fetch_assoc()) {
    $insumos[] = $row;
}
$stmt->close();

success($insumos);
?>
