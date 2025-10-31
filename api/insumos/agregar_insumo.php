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
$reque_id     = isset($_POST['reque_id']) ? (int)$_POST['reque_id'] : 0;

if ($nombre === '' || $unidad === '' || $tipo === '') {
    error('Datos incompletos');
}

// Normalizar y validar valores adicionales
if ($minimo_stock < 0) { $minimo_stock = 0.0; }
// Resolver catálogo; si no existe, dejar NULL y nombre vacío
if ($reque_id > 0) {
    try {
        $q = $conn->prepare('SELECT nombre FROM reque_tipos WHERE id = ? AND activo = 1');
        if ($q) {
            $q->bind_param('i', $reque_id);
            $q->execute();
            $q->bind_result($nom);
            if ($q->fetch()) { $reque = (string)$nom; } else { $reque_id = null; $reque = ''; }
            $q->close();
        }
    } catch (Throwable $e) { $reque_id = null; }
} else { $reque_id = null; }

// Mapear nombre del catálogo a enumeración antigua para compatibilidad en producción
$requeEnumMap = [
    'Zona Barra' => 'Zona Barra',
    'Bebidas' => 'Bebidas',
    'Refrigerador' => 'Refrigerdor',
    'Refrigerdor' => 'Refrigerdor',
    'Articulos de limpieza' => 'Articulos_de_limpieza',
    'Articulos_de_limpieza' => 'Articulos_de_limpieza',
    'Plasticos y otros' => 'Plasticos y otros',
];
if (is_null($reque_id)) {
    $reque = '';
} else {
    $reque = isset($requeEnumMap[$reque]) ? $requeEnumMap[$reque] : '';
}

$aliasImagen = '';
if (!empty($_FILES['imagen']['name'])) {
    $dir = __DIR__ . '/../../uploads/';
    $aliasImagen = procesarImagenInsumo($_FILES['imagen'], $dir);
    if (!$aliasImagen) {
        error('Error al procesar imagen');
    }
}

$stmt = $conn->prepare('INSERT INTO insumos (nombre, unidad, existencia, tipo_control, imagen, minimo_stock, reque, reque_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
if (!$stmt) {
    error('Error al preparar inserción: ' . $conn->error);
}
$stmt->bind_param('ssdssdsi', $nombre, $unidad, $existencia, $tipo, $aliasImagen, $minimo_stock, $reque, $reque_id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al agregar insumo: ' . $stmt->error);
}
$stmt->close();

success(['mensaje' => 'Insumo agregado']);
?>
