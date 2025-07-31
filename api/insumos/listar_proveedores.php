<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

$query = "SELECT id, nombre, telefono, direccion FROM proveedores ORDER BY nombre";
$result = $conn->query($query);

if (!$result) {
    error('Error al obtener proveedores: ' . $conn->error);
}

$proveedores = [];
while ($row = $result->fetch_assoc()) {
    $proveedores[] = $row;
}

success($proveedores);
