<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
$id = isset($input['id']) ? (int)$input['id'] : 0;
if ($id <= 0) {
    error('ID inválido');
}

$stmt = $conn->prepare("DELETE FROM usuarios WHERE id = ?");
if (!$stmt) {
    error('Error en la preparación: ' . $conn->error);
}
$stmt->bind_param('i', $id);
if ($stmt->execute()) {
    echo json_encode(['success' => true, 'mensaje' => 'Usuario eliminado']);
} else {
    error('Error al eliminar usuario: ' . $stmt->error);
}
