<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

$query = "SELECT id, nombre FROM usuarios WHERE rol = 'repartidor' AND activo = 1 ORDER BY nombre";
$result = $conn->query($query);
if (!$result) {
    error('Error al obtener meseros: ' . $conn->error);
}
$meseros = [];
while ($row = $result->fetch_assoc()) {
    $meseros[] = $row;
}
success($meseros);
