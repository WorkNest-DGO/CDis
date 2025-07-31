<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$producto_id = isset($_POST['producto_id']) ? (int)$_POST['producto_id'] : 0;
if ($producto_id <= 0 || empty($_FILES['imagen']['name'])) {
    error('Datos incompletos');
}

// Obtener imagen actual
$stmt = $conn->prepare('SELECT imagen FROM productos WHERE id = ?');
if (!$stmt) {
    error('Error al preparar consulta: ' . $conn->error);
}
$stmt->bind_param('i', $producto_id);
$stmt->execute();
$res = $stmt->get_result();
if (!$res || $res->num_rows === 0) {
    $stmt->close();
    error('Producto no encontrado');
}
$actual = $res->fetch_assoc()['imagen'];
$stmt->close();

$dir = __DIR__ . '/../../uploads/productos/';
if (!is_dir($dir)) {
    mkdir($dir, 0777, true);
}
$ext = pathinfo($_FILES['imagen']['name'], PATHINFO_EXTENSION);
$nombre = uniqid('prod_') . ($ext ? ".{$ext}" : '');
if (!move_uploaded_file($_FILES['imagen']['tmp_name'], $dir . $nombre)) {
    error('Error al subir imagen');
}

if ($actual && file_exists($dir . $actual)) {
    @unlink($dir . $actual);
}

$up = $conn->prepare('UPDATE productos SET imagen = ? WHERE id = ?');
if (!$up) {
    error('Error al guardar imagen: ' . $conn->error);
}
$up->bind_param('si', $nombre, $producto_id);
if (!$up->execute()) {
    $up->close();
    error('Error al actualizar producto: ' . $up->error);
}
$up->close();

success(['imagen' => $nombre]);
