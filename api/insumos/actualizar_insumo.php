<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/imagen.php';
session_start();

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$id        = isset($_POST['id']) ? (int)$_POST['id'] : 0;
$nombre    = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
$unidad    = isset($_POST['unidad']) ? trim($_POST['unidad']) : '';
$existencia = isset($_POST['existencia']) ? (float)$_POST['existencia'] : 0;
$tipo      = isset($_POST['tipo_control']) ? trim($_POST['tipo_control']) : '';

if ($id <= 0 || $nombre === '' || $unidad === '' || $tipo === '') {
    error('Datos incompletos');
}

// obtener datos actuales
$sel = $conn->prepare('SELECT existencia, imagen FROM insumos WHERE id = ?');
if (!$sel) {
    error('Error al preparar consulta: ' . $conn->error);
}
$sel->bind_param('i', $id);
$sel->execute();
$res = $sel->get_result();
if (!$res || $res->num_rows === 0) {
    $sel->close();
    error('Insumo no encontrado');
}
$rowActual = $res->fetch_assoc();
$actualExist = (float)$rowActual['existencia'];
$actual = $rowActual['imagen'];
$sel->close();

$aliasImagen = $actual;
if (!empty($_FILES['imagen']['name'])) {
    $dir = __DIR__ . '/../../uploads/';
    $aliasImagen = procesarImagenInsumo($_FILES['imagen'], $dir);
    if (!$aliasImagen) {
        error('Error al procesar imagen');
    }
    if ($actual && file_exists($dir . $actual)) {
        @unlink($dir . $actual);
    }
}

$stmt = $conn->prepare('UPDATE insumos SET nombre = ?, unidad = ?, existencia = ?, tipo_control = ?, imagen = ? WHERE id = ?');
if (!$stmt) {
    error('Error al preparar actualización: ' . $conn->error);
}
$stmt->bind_param('ssdssi', $nombre, $unidad, $existencia, $tipo, $aliasImagen, $id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al actualizar insumo: ' . $stmt->error);
}
$stmt->close();

// registrar ajuste de existencia si aplica
$diferencia = $existencia - $actualExist;
if ($diferencia != 0) {
    $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, cantidad, observacion) VALUES ('ajuste', ?, ?, ?, ?)");
    if ($mov) {
        $obs = 'Ajuste manual de existencia';
        $mov->bind_param('iids', $_SESSION['usuario_id'], $id, $diferencia, $obs);
        $mov->execute();
        $mov->close();
    }
}

success(true);
?>
