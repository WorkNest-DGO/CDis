<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$usuario = trim($_GET['usuario'] ?? '');
if ($usuario === '') {
    error('Usuario requerido');
}

// Resolver ID del usuario por nombre (consistente con listar_usuario_rutas.php)
$stmt = $conn->prepare('SELECT id FROM usuarios WHERE nombre = ?');
$stmt->bind_param('s', $usuario);
$stmt->execute();
$res = $stmt->get_result();
if (!$row = $res->fetch_assoc()) {
    error('Usuario no encontrado');
}
$usuario_id = (int)$row['id'];

$sql = 'SELECT rt.id, rt.nombre, (ur.id_ur IS NOT NULL) AS asignado
        FROM reque_tipos rt
        LEFT JOIN usuario_reque ur ON ur.reque = rt.id AND ur.usuario = ?
        ORDER BY rt.nombre';

$stmtL = $conn->prepare($sql);
$stmtL->bind_param('i', $usuario_id);
$stmtL->execute();
$r = $stmtL->get_result();

$tipos = [];
while ($row = $r->fetch_assoc()) {
    $row['id'] = (int)$row['id'];
    $row['asignado'] = (bool)$row['asignado'];
    $tipos[] = $row;
}

echo json_encode([
    'success' => true,
    'mensaje' => 'Áreas/Reque obtenidas',
    'resultado' => $tipos,
]);
?>

