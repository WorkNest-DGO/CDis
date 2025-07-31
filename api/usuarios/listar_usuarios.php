<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

$result = $conn->query("SELECT id, nombre FROM usuarios WHERE activo = 1 ORDER BY nombre");
if (!$result) {
    error('Error al obtener usuarios: ' . $conn->error);
}
$usuarios = [];
while ($row = $result->fetch_assoc()) {
    $usuarios[] = $row;
}
success($usuarios);
?>
