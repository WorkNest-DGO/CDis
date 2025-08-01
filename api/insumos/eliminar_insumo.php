<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
session_start();

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['id'])) {
    error('Datos inválidos');
}


$id = (int)$input['id'];

// obtener existencia actual para registrar salida
$sel = $conn->prepare('SELECT existencia FROM insumos WHERE id = ?');
if ($sel) {
    $sel->bind_param('i', $id);
    $sel->execute();
    $sel->bind_result($exist); 
    $sel->fetch();
    $sel->close();
} else {
    $exist = 0;
}

$stmt = $conn->prepare('DELETE FROM insumos WHERE id = ?');
if (!$stmt) {
    error('Error al preparar eliminación: ' . $conn->error);
}
$stmt->bind_param('i', $id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al eliminar insumo: ' . $stmt->error);
}
$stmt->close();

// registrar movimiento de salida por eliminación
$mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, cantidad, observacion) VALUES ('salida', ?, ?, ?, ?)");
if ($mov) {
    $cant = -$exist;
    $obs = 'Salida por eliminacion de insumo';
    $mov->bind_param('iids', $_SESSION['usuario_id'], $id, $cant, $obs);
    $mov->execute();
    $mov->close();
}

success(true);
?>
