<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
$id = isset($input['id']) ? (int)$input['id'] : 0;
$nombre = trim($input['nombre'] ?? '');
$usuario = trim($input['usuario'] ?? '');
$contrasena = $input['contrasena'] ?? '';
$rol = trim($input['rol'] ?? '');
$activo = isset($input['activo']) ? (int)$input['activo'] : 1;

if ($id <= 0 || $nombre === '' || $usuario === '' || $rol === '') {
    error('Datos incompletos');
}

if ($contrasena !== '') {
    $hash = sha1($contrasena);
    $stmt = $conn->prepare("UPDATE usuarios SET nombre = ?, usuario = ?, contrasena = ?, rol = ?, activo = ? WHERE id = ?");
    if (!$stmt) {
        error('Error en la preparación: ' . $conn->error);
    }
    $stmt->bind_param('ssssii', $nombre, $usuario, $hash, $rol, $activo, $id);
} else {
    $stmt = $conn->prepare("UPDATE usuarios SET nombre = ?, usuario = ?, rol = ?, activo = ? WHERE id = ?");
    if (!$stmt) {
        error('Error en la preparación: ' . $conn->error);
    }
    $stmt->bind_param('sssii', $nombre, $usuario, $rol, $activo, $id);
}

if ($stmt->execute()) {
    echo json_encode(['success' => true, 'mensaje' => 'Usuario actualizado']);
} else {
    error('Error al actualizar usuario: ' . $stmt->error);
}
