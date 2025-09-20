<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$sql = "SELECT nombre, path, tipo, grupo, orden FROM rutas ORDER BY orden";
$result = $conn->query($sql);
if (!$result) {
    error('Error al obtener rutas: ' . $conn->error);
}
$rutas = $result->fetch_all(MYSQLI_ASSOC);

echo json_encode([
    'success' => true,
    'mensaje' => 'Rutas obtenidas',
    'resultado' => $rutas
]);
