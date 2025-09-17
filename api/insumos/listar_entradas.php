<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

$q = isset($_GET['q']) ? trim($_GET['q']) : '';
$limit = isset($_GET['limit']) ? max(1, min(200, (int) $_GET['limit'])) : null;

$baseSql = "SELECT e.id,
                   e.fecha,
                   e.costo_total,
                   e.cantidad,
                   e.cantidad_actual,
                   e.unidad,
                   e.valor_unitario,
                   e.descripcion,
                   e.referencia_doc,
                   e.folio_fiscal,
                   e.qr,
                   e.costo_total AS total,
                   p.nombre AS proveedor,
                   i.nombre AS producto
            FROM entradas_insumos e
            LEFT JOIN proveedores p ON e.proveedor_id = p.id
            LEFT JOIN insumos i ON e.insumo_id = i.id";

if ($q !== '') {
    $sql = $baseSql . " WHERE i.nombre LIKE ? ORDER BY e.fecha DESC" . ($limit ? " LIMIT ?" : "");
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        error('Error al preparar consulta: ' . $conn->error);
    }
    $like = '%' . $q . '%';
    if ($limit) {
        $stmt->bind_param('si', $like, $limit);
    } else {
        $stmt->bind_param('s', $like);
    }
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al ejecutar consulta: ' . $stmt->error);
    }
    $res = $stmt->get_result();
    $entradas = [];
    while ($row = $res->fetch_assoc()) {
        $entradas[] = $row;
    }
    $stmt->close();
    success($entradas);
} else {
    $sql = $baseSql . " ORDER BY e.fecha DESC" . ($limit ? " LIMIT ?" : "");
    if ($limit) {
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            error('Error al preparar consulta: ' . $conn->error);
        }
        $stmt->bind_param('i', $limit);
        if (!$stmt->execute()) {
            $stmt->close();
            error('Error al ejecutar consulta: ' . $stmt->error);
        }
        $res = $stmt->get_result();
        $entradas = [];
        while ($row = $res->fetch_assoc()) {
            $entradas[] = $row;
        }
        $stmt->close();
        success($entradas);
    } else {
        $result = $conn->query($sql);
        if (!$result) {
            error('Error al obtener entradas: ' . $conn->error);
        }
        $entradas = [];
        while ($row = $result->fetch_assoc()) {
            $entradas[] = $row;
        }
        success($entradas);
    }
}
