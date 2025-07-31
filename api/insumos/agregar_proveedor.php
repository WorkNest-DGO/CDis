<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input) {
    error('JSON inválido');
}

$nombre = isset($input['nombre']) ? trim($input['nombre']) : '';
$telefono = isset($input['telefono']) ? trim($input['telefono']) : '';
$direccion = isset($input['direccion']) ? trim($input['direccion']) : '';

if ($nombre === '') {
    error('Nombre requerido');
}

$stmt = $conn->prepare('INSERT INTO proveedores (nombre, telefono, direccion) VALUES (?, ?, ?)');
if (!$stmt) {
    error('Error al preparar inserción: ' . $conn->error);
}
$stmt->bind_param('sss', $nombre, $telefono, $direccion);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al agregar proveedor: ' . $stmt->error);
}
$stmt->close();

success(['mensaje' => 'Proveedor agregado']);
