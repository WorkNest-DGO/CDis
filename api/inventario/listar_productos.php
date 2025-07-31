<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

$query = "SELECT id, nombre, precio, existencia, descripcion, activo, imagen FROM productos ORDER BY nombre ASC";
$result = $conn->query($query);

if (!$result) {
    error('Error al obtener productos: ' . $conn->error);
}

$productos = [];
while ($row = $result->fetch_assoc()) {
    $productos[] = $row;
}

success($productos);

