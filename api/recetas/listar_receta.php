<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['producto_id'])) {
    error('Datos inválidos');
}

$producto_id = (int) $input['producto_id'];

$stmt = $conn->prepare('SELECT r.insumo_id, i.nombre, i.unidad, r.cantidad FROM recetas r JOIN insumos i ON i.id = r.insumo_id WHERE r.producto_id = ?');
if (!$stmt) {
    error('Error al preparar consulta: ' . $conn->error);
}
$stmt->bind_param('i', $producto_id);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al ejecutar consulta: ' . $stmt->error);
}
$res = $stmt->get_result();
$receta = [];
while ($row = $res->fetch_assoc()) {
    $receta[] = [
        'insumo_id' => (int)$row['insumo_id'],
        'nombre'    => $row['nombre'],
        'unidad'    => $row['unidad'],
        'cantidad'  => (float)$row['cantidad']
    ];
}
$stmt->close();

success($receta);
