<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

$credito = isset($_GET['credito']) && $_GET['credito'] !== '' ? (int)$_GET['credito'] : null; // 0|1|null
$pagado  = isset($_GET['pagado']) && $_GET['pagado'] !== '' ? (int)$_GET['pagado'] : null;   // 0|1|null
$q       = isset($_GET['q']) ? trim($_GET['q']) : '';

$where = [];
$params = [];
$types = '';

if ($credito !== null) {
    $where[] = 'e.credito = ?';
    $types .= 'i';
    $params[] = $credito;
}
if ($pagado !== null) {
    $where[] = 'COALESCE(e.pagado, 0) = ?';
    $types .= 'i';
    $params[] = $pagado;
}
if ($q !== '') {
    $where[] = '(i.nombre LIKE ? OR p.nombre LIKE ? OR e.descripcion LIKE ? OR e.referencia_doc LIKE ? OR e.folio_fiscal LIKE ?)';
    $types .= 'sssss';
    $like = '%' . $q . '%';
    array_push($params, $like, $like, $like, $like, $like);
}

$whereSql = count($where) ? (' WHERE ' . implode(' AND ', $where)) : '';

$sql = "SELECT e.id, e.fecha, e.insumo_id, e.proveedor_id, e.usuario_id, e.descripcion,
               e.cantidad, e.unidad, e.costo_total, e.valor_unitario,
               e.referencia_doc, e.folio_fiscal, e.qr, e.cantidad_actual,
               e.credito, e.pagado,
               p.nombre AS proveedor, i.nombre AS producto
        FROM entradas_insumos e
        LEFT JOIN proveedores p ON p.id = e.proveedor_id
        LEFT JOIN insumos i ON i.id = e.insumo_id
        $whereSql
        ORDER BY e.fecha DESC, e.id DESC";

if ($types !== '') {
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        error('Error al preparar consulta: ' . $conn->error);
    }
    $stmt->bind_param($types, ...$params);
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al ejecutar consulta: ' . $stmt->error);
    }
    $res = $stmt->get_result();
    $rows = [];
    while ($r = $res->fetch_assoc()) {
        $rows[] = $r;
    }
    $stmt->close();
    success($rows);
} else {
    $result = $conn->query($sql);
    if (!$result) {
        error('Error al obtener entradas: ' . $conn->error);
    }
    $rows = [];
    while ($r = $result->fetch_assoc()) {
        $rows[] = $r;
    }
    success($rows);
}

