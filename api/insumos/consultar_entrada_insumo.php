<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

$id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
$insumo_id = isset($_GET['insumo_id']) ? (int)$_GET['insumo_id'] : 0;

if ($id > 0) {
    $stmt = $conn->prepare('SELECT ei.*, p.nombre AS proveedor_nombre, i.nombre AS insumo_nombre FROM entradas_insumos ei LEFT JOIN proveedores p ON p.id = ei.proveedor_id LEFT JOIN insumos i ON i.id = ei.insumo_id WHERE ei.id = ?');
    if (!$stmt) {
        error('Error al preparar consulta: ' . $conn->error);
    }
    $stmt->bind_param('i', $id);
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al ejecutar consulta: ' . $stmt->error);
    }
    $res = $stmt->get_result();
    if (!$res || $res->num_rows === 0) {
        $stmt->close();
        error('Entrada no encontrada');
    }
    $fila = $res->fetch_assoc();
    $stmt->close();
    success($fila);
} elseif ($insumo_id > 0) {
    $stmt = $conn->prepare('SELECT ei.*, p.nombre AS proveedor_nombre, i.nombre AS insumo_nombre FROM entradas_insumos ei LEFT JOIN proveedores p ON p.id = ei.proveedor_id LEFT JOIN insumos i ON i.id = ei.insumo_id WHERE ei.insumo_id = ? ORDER BY ei.fecha DESC');
    if (!$stmt) {
        error('Error al preparar consulta: ' . $conn->error);
    }
    $stmt->bind_param('i', $insumo_id);
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al ejecutar consulta: ' . $stmt->error);
    }
    $res = $stmt->get_result();
    $entradas = [];
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $entradas[] = $row;
        }
    }
    $stmt->close();
    if (empty($entradas)) {
        error('Sin registros para el insumo solicitado');
    }
    success($entradas);
} else {
    error('Parametros insuficientes');
}
