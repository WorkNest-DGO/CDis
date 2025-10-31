<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/imagen.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$id           = isset($_POST['id']) ? (int)$_POST['id'] : 0;
$nombre       = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
$unidad       = isset($_POST['unidad']) ? trim($_POST['unidad']) : '';
$existencia   = isset($_POST['existencia']) ? (float)$_POST['existencia'] : 0;
$tipo         = isset($_POST['tipo_control']) ? trim($_POST['tipo_control']) : '';
$minimo_stock = isset($_POST['minimo_stock']) ? (float)$_POST['minimo_stock'] : 0.0;
$reque        = isset($_POST['reque']) ? trim($_POST['reque']) : '';
$reque_id     = isset($_POST['reque_id']) ? (int)$_POST['reque_id'] : 0;

if ($id <= 0 || $nombre === '' || $unidad === '' || $tipo === '') {
    error('Datos incompletos');
}

// Normalizar valores adicionales
if ($minimo_stock < 0) { $minimo_stock = 0.0; }
// Si viene reque_id, resolver nombre para compatibilidad; si no existe en catálogo, usar NULL
if ($reque_id > 0) {
    try {
        $q = $conn->prepare('SELECT nombre FROM reque_tipos WHERE id = ? AND activo = 1');
        if ($q) {
            $q->bind_param('i', $reque_id);
            $q->execute();
            $q->bind_result($nom);
            if ($q->fetch()) {
                $reque = (string)$nom;
            } else {
                $reque_id = null; // no existe; evitar FK inválida
                $reque = '';
            }
            $q->close();
        }
    } catch (Throwable $e) { $reque_id = null; }
} else {
    $reque_id = null; // permitir NULL cuando no seleccionan catálogo
}

// Mapear nombre de catálogo a enumeración antigua (producción) para compatibilidad
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

// obtener imagen actual
$sel = $conn->prepare('SELECT imagen FROM insumos WHERE id = ?');
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
$actual = $res->fetch_assoc()['imagen'];
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

$stmt = $conn->prepare('UPDATE insumos SET nombre = ?, unidad = ?, existencia = ?, tipo_control = ?, imagen = ?, minimo_stock = ?, reque = ?, reque_id = ? WHERE id = ?');
if (!$stmt) {
    error('Error al preparar actualización: ' . $conn->error);
}
// Nota: pasar NULL en bind_param insertará NULL en MySQLi
$stmt->bind_param('ssdssdsii', $nombre, $unidad, $existencia, $tipo, $aliasImagen, $minimo_stock, $reque, $reque_id, $id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al actualizar insumo: ' . $stmt->error);
}
$stmt->close();

success(true);
?>
