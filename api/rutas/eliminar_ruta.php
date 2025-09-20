<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
$nombre = trim($input['nombre'] ?? '');

if ($nombre === '') {
    error('Nombre requerido');
}

$stmt = $conn->prepare("DELETE FROM rutas WHERE nombre = ?");
if (!$stmt) {
    error('Error en la preparación: ' . $conn->error);
}
$stmt->bind_param('s', $nombre);
if ($stmt->execute()) {
    echo json_encode(['success' => true, 'mensaje' => 'Ruta eliminada', 'resultado' => []]);
} else {
    error('Error al eliminar ruta: ' . $stmt->error);
}
