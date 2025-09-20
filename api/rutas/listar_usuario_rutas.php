<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$usuario = trim($_GET['usuario'] ?? '');
if ($usuario === '') {
    error('Usuario requerido');
}

$stmt = $conn->prepare("SELECT id FROM usuarios WHERE nombre = ?");
$stmt->bind_param('s', $usuario);
$stmt->execute();
$result = $stmt->get_result();
if (!$row = $result->fetch_assoc()) {
    error('Usuario no encontrado');
}
$usuario_id = (int)$row['id'];

$sql = "SELECT r.nombre, r.path, r.tipo, r.grupo, r.orden, (ur.id IS NOT NULL) AS asignado
        FROM rutas r
        LEFT JOIN usuario_ruta ur ON ur.ruta_id = r.id AND ur.usuario_id = ?
        ORDER BY r.orden";
$stmt = $conn->prepare($sql);
$stmt->bind_param('i', $usuario_id);
$stmt->execute();
$res = $stmt->get_result();
$rutas = [];
while ($r = $res->fetch_assoc()) {
    $r['asignado'] = (bool)$r['asignado'];
    $rutas[] = $r;
}

echo json_encode([
    'success' => true,
    'mensaje' => 'Rutas obtenidas',
    'resultado' => $rutas
]);
