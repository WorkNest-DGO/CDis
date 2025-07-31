<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['producto_id'], $input['nueva_existencia'])) {
    error('Datos inválidos');
}

$producto_id     = (int)$input['producto_id'];
$nueva_existencia = (int)$input['nueva_existencia'];

$stmt = $conn->prepare('UPDATE productos SET existencia = ? WHERE id = ?');
if (!$stmt) {
    error('Error al preparar actualización: ' . $conn->error);
}
$stmt->bind_param('ii', $nueva_existencia, $producto_id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al actualizar existencia: ' . $stmt->error);
}
$stmt->close();

success(true);

