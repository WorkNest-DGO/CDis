<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
$usuario = trim($input['usuario'] ?? '');
$rutas = $input['rutas'] ?? [];

if ($usuario === '' || !is_array($rutas)) {
    error('Datos incompletos');
}

$stmt = $conn->prepare("SELECT id FROM usuarios WHERE nombre = ?");
$stmt->bind_param('s', $usuario);
$stmt->execute();
$result = $stmt->get_result();
if (!$row = $result->fetch_assoc()) {
    error('Usuario no encontrado');
}
$usuario_id = (int)$row['id'];

$conn->begin_transaction();
try {
    $stmtDel = $conn->prepare("DELETE FROM usuario_ruta WHERE usuario_id = ?");
    $stmtDel->bind_param('i', $usuario_id);
    $stmtDel->execute();

    if (!empty($rutas)) {
        $stmtIns = $conn->prepare("INSERT INTO usuario_ruta (usuario_id, ruta_id) SELECT ?, id FROM rutas WHERE nombre = ?");
        foreach ($rutas as $rutaNombre) {
            $rutaNombre = trim($rutaNombre);
            if ($rutaNombre === '') continue;
            $stmtIns->bind_param('is', $usuario_id, $rutaNombre);
            $stmtIns->execute();
        }
    }

    $conn->commit();
    echo json_encode(['success' => true, 'mensaje' => 'Rutas asignadas', 'resultado' => []]);
} catch (Exception $e) {
    $conn->rollback();
    error('Error al guardar rutas: ' . $e->getMessage());
}
