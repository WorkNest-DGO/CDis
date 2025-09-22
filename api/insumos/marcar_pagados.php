<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Metodo no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['ids'])) {
    error('JSON invalido: ids requeridos');
}

$ids = array_filter(array_map('intval', (array)$input['ids']), function($v){ return $v > 0; });
if (!count($ids)) {
    error('Lista de ids vacia');
}

$pagado = isset($input['pagado']) ? (int)$input['pagado'] : 1; // por defecto, marcar como pagado
$pagado = ($pagado === 1) ? 1 : 0;

$placeholders = implode(',', array_fill(0, count($ids), '?'));
$types = str_repeat('i', count($ids) + 1);
$params = array_merge([$pagado], $ids);

$sql = "UPDATE entradas_insumos SET pagado = ? WHERE id IN ($placeholders)";
$stmt = $conn->prepare($sql);
if (!$stmt) {
    error('Error al preparar actualizacion: ' . $conn->error);
}
$stmt->bind_param($types, ...$params);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al actualizar: ' . $stmt->error);
}
$af = $stmt->affected_rows;
$stmt->close();

success(['actualizados' => $af]);

