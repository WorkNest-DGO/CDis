<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
$nombre = trim($input['nombre'] ?? '');
$nuevo_nombre = trim($input['nuevo_nombre'] ?? $nombre);
$path = trim($input['path'] ?? '');
$tipo = trim($input['tipo'] ?? '');
$grupo = $input['grupo'] ?? null;
$orden = isset($input['orden']) ? (int)$input['orden'] : 0;

if ($nombre === '' || $path === '' || $tipo === '') {
    error('Datos incompletos');
}

$stmt = $conn->prepare("UPDATE rutas SET nombre = ?, path = ?, tipo = ?, grupo = ?, orden = ? WHERE nombre = ?");
if (!$stmt) {
    error('Error en la preparación: ' . $conn->error);
}
$stmt->bind_param('ssssis', $nuevo_nombre, $path, $tipo, $grupo, $orden, $nombre);
if ($stmt->execute()) {
    echo json_encode(['success' => true, 'mensaje' => 'Ruta actualizada', 'resultado' => []]);
} else {
    error('Error al actualizar ruta: ' . $stmt->error);
}
