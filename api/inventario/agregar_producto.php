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

$nombre      = isset($input['nombre']) ? trim($input['nombre']) : '';
$precio      = isset($input['precio']) ? (float)$input['precio'] : null;
$descripcion = isset($input['descripcion']) ? trim($input['descripcion']) : '';
$existencia  = isset($input['existencia']) ? (int)$input['existencia'] : 0;

if ($nombre === '' || $precio === null) {
    error('Datos incompletos');
}

$stmt = $conn->prepare('INSERT INTO productos (nombre, precio, descripcion, existencia, activo) VALUES (?, ?, ?, ?, 1)');
if (!$stmt) {
    error('Error al preparar inserción: ' . $conn->error);
}
$stmt->bind_param('sdsi', $nombre, $precio, $descripcion, $existencia);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al agregar producto: ' . $stmt->error);
}
$stmt->close();

success(['mensaje' => 'Producto agregado']);

