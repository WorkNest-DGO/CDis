<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
$nombre = trim($input['nombre'] ?? '');
$usuario = trim($input['usuario'] ?? '');
$contrasena = $input['contrasena'] ?? '';
$rol = trim($input['rol'] ?? '');
$activo = isset($input['activo']) ? (int)$input['activo'] : 1;

if ($nombre === '' || $usuario === '' || $contrasena === '' || $rol === '') {
    error('Datos incompletos');
}

$hash = sha1($contrasena);

$stmt = $conn->prepare("INSERT INTO usuarios (nombre, usuario, contrasena, rol, activo) VALUES (?, ?, ?, ?, ?)");
if (!$stmt) {
    error('Error en la preparación: ' . $conn->error);
}
$stmt->bind_param('ssssi', $nombre, $usuario, $hash, $rol, $activo);
if ($stmt->execute()) {
    echo json_encode(['success' => true, 'mensaje' => 'Usuario agregado']);
} else {
    error('Error al agregar usuario: ' . $stmt->error);
}
