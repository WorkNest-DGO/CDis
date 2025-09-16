<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$result = $conn->query("SELECT id, nombre, usuario, rol, activo FROM usuarios ORDER BY nombre");
if (!$result) {
    error('Error al obtener usuarios: ' . $conn->error);
}
$usuarios = [];
while ($row = $result->fetch_assoc()) {
    $row['activo'] = (int) $row['activo'];
    $usuarios[] = $row;
}
echo json_encode([
    'success' => true,
    'mensaje' => 'Usuarios obtenidos',
    'usuarios' => $usuarios
]);
?>
