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

$nombre      = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
$unidad      = isset($_POST['unidad']) ? trim($_POST['unidad']) : '';
$existencia  = isset($_POST['existencia']) ? (float)$_POST['existencia'] : 0;
$tipo        = isset($_POST['tipo_control']) ? trim($_POST['tipo_control']) : '';

if ($nombre === '' || $unidad === '' || $tipo === '') {
    error('Datos incompletos');
}

$aliasImagen = '';
if (!empty($_FILES['imagen']['name'])) {
    $dir = __DIR__ . '/../../uploads/';
    $aliasImagen = procesarImagenInsumo($_FILES['imagen'], $dir);
    if (!$aliasImagen) {
        error('Error al procesar imagen');
    }
}

$stmt = $conn->prepare('INSERT INTO insumos (nombre, unidad, existencia, tipo_control, imagen) VALUES (?, ?, ?, ?, ?)');
if (!$stmt) {
    error('Error al preparar inserción: ' . $conn->error);
}
$stmt->bind_param('ssdss', $nombre, $unidad, $existencia, $tipo, $aliasImagen);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al agregar insumo: ' . $stmt->error);
}
$insumo_id = $stmt->insert_id;
$stmt->close();

// registrar movimiento de entrada inicial
$mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, cantidad, observacion) VALUES ('entrada', ?, ?, ?, ?)");
if ($mov) {
    $obs = 'Entrada directa por usuario';
    $mov->bind_param('iids', $_SESSION['usuario_id'], $insumo_id, $existencia, $obs);
    $mov->execute();
    $mov->close();
}

success(['mensaje' => 'Insumo agregado']);
?>
