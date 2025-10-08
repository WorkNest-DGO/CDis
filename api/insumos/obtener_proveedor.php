<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

$id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
if ($id <= 0) {
    error('ID invalido');
}

$stmt = $conn->prepare('SELECT id, nombre, rfc, razon_social, regimen_fiscal, correo_facturacion, telefono, telefono2, correo, direccion, contacto_nombre, contacto_puesto, dias_credito, limite_credito, banco, clabe, cuenta_bancaria, sitio_web, observacion, activo, fecha_alta, actualizado_en FROM proveedores WHERE id = ?');
if (!$stmt) {
    error('Error al preparar consulta: ' . $conn->error);
}
$stmt->bind_param('i', $id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al ejecutar consulta: ' . $stmt->error);
}
$res = $stmt->get_result();
$prov = $res ? $res->fetch_assoc() : null;
$stmt->close();

if (!$prov) {
    error('Proveedor no encontrado');
}

success($prov);
?>

