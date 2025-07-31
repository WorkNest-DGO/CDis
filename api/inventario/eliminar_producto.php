<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['id'])) {
    error('Datos inválidos');
}

$id = (int)$input['id'];

$stmt = $conn->prepare('DELETE FROM productos WHERE id = ?');
if (!$stmt) {
    error('Error al preparar eliminación: ' . $conn->error);
}
$stmt->bind_param('i', $id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al eliminar producto: ' . $stmt->error);
}
$stmt->close();

success(true);
?>
