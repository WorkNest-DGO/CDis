<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
$usuario = trim($input['usuario'] ?? '');
$reques  = $input['reques'] ?? [];

if ($usuario === '' || !is_array($reques)) {
    error('Datos inválidos');
}

// Resolver ID del usuario por nombre
$stmtU = $conn->prepare('SELECT id FROM usuarios WHERE nombre = ?');
$stmtU->bind_param('s', $usuario);
$stmtU->execute();
$resU = $stmtU->get_result();
if (!$rowU = $resU->fetch_assoc()) {
    error('Usuario no encontrado');
}
$usuario_id = (int)$rowU['id'];

try {
    // Limpiar asignaciones actuales
    $stmtDel = $conn->prepare('DELETE FROM usuario_reque WHERE usuario = ?');
    $stmtDel->bind_param('i', $usuario_id);
    $stmtDel->execute();

    // Insertar nuevas asignaciones
    if (!empty($reques)) {
        $stmtIns = $conn->prepare('INSERT INTO usuario_reque (usuario, reque) VALUES (?, ?)');
        foreach ($reques as $rid) {
            $rid = (int)$rid;
            if ($rid <= 0) continue;
            $stmtIns->bind_param('ii', $usuario_id, $rid);
            $stmtIns->execute();
        }
    }

    echo json_encode(['success' => true, 'mensaje' => 'Áreas/Reque asignadas', 'resultado' => []]);
} catch (Throwable $e) {
    error('Error al guardar asignaciones: ' . $e->getMessage());
}
?>

