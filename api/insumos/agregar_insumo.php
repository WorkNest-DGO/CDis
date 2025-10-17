<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/imagen.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$nombre       = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
$unidad       = isset($_POST['unidad']) ? trim($_POST['unidad']) : '';
$existencia   = isset($_POST['existencia']) ? (float)$_POST['existencia'] : 0;
$tipo         = isset($_POST['tipo_control']) ? trim($_POST['tipo_control']) : '';
$minimo_stock = isset($_POST['minimo_stock']) ? (float)$_POST['minimo_stock'] : 0.0;
$reque        = isset($_POST['reque']) ? trim($_POST['reque']) : '';

if ($nombre === '' || $unidad === '' || $tipo === '') {
    error('Datos incompletos');
}

// Normalizar y validar valores adicionales
if ($minimo_stock < 0) { $minimo_stock = 0.0; }
$reque_validos = ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros',''];
if (!in_array($reque, $reque_validos, true)) { $reque = ''; }

$aliasImagen = '';
if (!empty($_FILES['imagen']['name'])) {
    $dir = __DIR__ . '/../../uploads/';
    $aliasImagen = procesarImagenInsumo($_FILES['imagen'], $dir);
    if (!$aliasImagen) {
        error('Error al procesar imagen');
    }
}

$stmt = $conn->prepare('INSERT INTO insumos (nombre, unidad, existencia, tipo_control, imagen, minimo_stock, reque) VALUES (?, ?, ?, ?, ?, ?, ?)');
if (!$stmt) {
    error('Error al preparar inserción: ' . $conn->error);
}
$stmt->bind_param('ssdssds', $nombre, $unidad, $existencia, $tipo, $aliasImagen, $minimo_stock, $reque);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al agregar insumo: ' . $stmt->error);
}
$stmt->close();

success(['mensaje' => 'Insumo agregado']);
?>
