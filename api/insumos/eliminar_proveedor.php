<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Metodo no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input) {
    error('JSON invalido');
}

$id = isset($input['id']) ? (int)$input['id'] : 0;
if ($id <= 0) {
    error('ID invalido');
}

// Borrado logico para evitar conflictos por FK
$stmt = $conn->prepare('UPDATE proveedores SET activo = 0 WHERE id = ?');
if (!$stmt) {
    error('Error al preparar eliminacion: ' . $conn->error);
}
$stmt->bind_param('i', $id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al eliminar proveedor: ' . $stmt->error);
}
$stmt->close();

success(['mensaje' => 'Proveedor desactivado']);
?>

