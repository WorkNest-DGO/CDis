<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Metodo no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input) {
    error('JSON invalido');
}

$nombre = isset($input['nombre']) ? trim($input['nombre']) : '';
$telefono = isset($input['telefono']) ? trim($input['telefono']) : '';
$direccion = isset($input['direccion']) ? trim($input['direccion']) : '';

// Campos extendidos
$rfc = isset($input['rfc']) ? trim($input['rfc']) : null;
$razon_social = isset($input['razon_social']) ? trim($input['razon_social']) : null;
$regimen_fiscal = isset($input['regimen_fiscal']) ? trim($input['regimen_fiscal']) : null;
$correo_facturacion = isset($input['correo_facturacion']) ? trim($input['correo_facturacion']) : null;
$telefono2 = isset($input['telefono2']) ? trim($input['telefono2']) : null;
$correo = isset($input['correo']) ? trim($input['correo']) : null;
$contacto_nombre = isset($input['contacto_nombre']) ? trim($input['contacto_nombre']) : null;
$contacto_puesto = isset($input['contacto_puesto']) ? trim($input['contacto_puesto']) : null;
$dias_credito = isset($input['dias_credito']) ? (int)$input['dias_credito'] : 0;
$limite_credito = isset($input['limite_credito']) ? (float)$input['limite_credito'] : 0.0;
$banco = isset($input['banco']) ? trim($input['banco']) : null;
$clabe = isset($input['clabe']) ? trim($input['clabe']) : null;
$cuenta_bancaria = isset($input['cuenta_bancaria']) ? trim($input['cuenta_bancaria']) : null;
$sitio_web = isset($input['sitio_web']) ? trim($input['sitio_web']) : null;
$observacion = isset($input['observacion']) ? trim($input['observacion']) : null;
$activo = isset($input['activo']) ? (int)$input['activo'] : 1;

if ($nombre === '') {
    error('Nombre requerido');
}

$stmt = $conn->prepare('INSERT INTO proveedores (
    nombre, rfc, razon_social, regimen_fiscal, correo_facturacion,
    telefono, telefono2, correo, direccion,
    contacto_nombre, contacto_puesto,
    dias_credito, limite_credito,
    banco, clabe, cuenta_bancaria,
    sitio_web, observacion, activo
) VALUES (?,?,?,?,?, ?,?,?,?, ?,?, ?,?, ?,?,?, ?,?, ?)');
if (!$stmt) {
    error('Error al preparar inserción: ' . $conn->error);
}
$stmt->bind_param(
    'sssssssssssidsssssi',
    $nombre,
    $rfc,
    $razon_social,
    $regimen_fiscal,
    $correo_facturacion,
    $telefono,
    $telefono2,
    $correo,
    $direccion,
    $contacto_nombre,
    $contacto_puesto,
    $dias_credito,
    $limite_credito,
    $banco,
    $clabe,
    $cuenta_bancaria,
    $sitio_web,
    $observacion,
    $activo
);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al agregar proveedor: ' . $stmt->error);
}
$stmt->close();

success(['mensaje' => 'Proveedor agregado']);

