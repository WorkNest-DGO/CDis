<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
session_start();

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

// Params
$page      = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$pageSize  = isset($_GET['pageSize']) ? max(1, min(200, (int)$_GET['pageSize'])) : 10;
$q         = isset($_GET['q']) ? trim($_GET['q']) : '';
$desde     = isset($_GET['desde']) ? $_GET['desde'] : '';
$hasta     = isset($_GET['hasta']) ? $_GET['hasta'] : '';

// Normaliza fechas: si no vienen, usa semana actual (lunes-domingo)
date_default_timezone_set('America/Mexico_City');
$today = new DateTime('today');
$dow   = (int)$today->format('N'); // 1=lunes .. 7=domingo
$monday = (clone $today)->modify('-' . ($dow - 1) . ' days');
$sunday = (clone $monday)->modify('+6 days');

if ($desde === '') { $desde = $monday->format('Y-m-d'); }
if ($hasta === '') { $hasta = $sunday->format('Y-m-d'); }

// Interpretar p_hasta como 00:00 y tratarlo como [desde, hasta+1d)
$desde_dt = $desde . ' 00:00:00';
$hasta_dt = $hasta . ' 00:00:00';

// Construye WHERE dinámico
$where = ' WHERE e.fecha >= ? AND e.fecha < DATE_ADD(?, INTERVAL 1 DAY) ';
$types = 'ss';
$params = [$desde_dt, $hasta_dt];

if ($q !== '') {
    $where .= ' AND (i.nombre LIKE ? OR p.nombre LIKE ? OR e.descripcion LIKE ? OR e.referencia_doc LIKE ? OR e.folio_fiscal LIKE ?) ';
    $search = '%' . $q . '%';
    $types .= 'sssss';
    array_push($params, $search, $search, $search, $search, $search);
}

// Total
$sqlCount = "SELECT COUNT(*) AS total
             FROM entradas_insumos e
             LEFT JOIN insumos i ON i.id = e.insumo_id
             LEFT JOIN proveedores p ON p.id = e.proveedor_id
             LEFT JOIN usuarios u ON u.id = e.usuario_id
             $where";

$stmt = $conn->prepare($sqlCount);
if (!$stmt) {
    error('Error al preparar count: ' . $conn->error);
}
$stmt->bind_param($types, ...$params);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al ejecutar count: ' . $stmt->error);
}
$res = $stmt->get_result();
$row = $res->fetch_assoc();
$total = (int)($row['total'] ?? 0);
$stmt->close();

// Datos paginados
$offset = ($page - 1) * $pageSize;
$sql = "SELECT e.id, e.fecha, i.nombre AS insumo, e.unidad, e.cantidad, e.costo_total,
               e.valor_unitario, p.nombre AS proveedor, u.nombre AS usuario,
               e.descripcion, e.referencia_doc, e.folio_fiscal
        FROM entradas_insumos e
        LEFT JOIN insumos i ON i.id = e.insumo_id
        LEFT JOIN proveedores p ON p.id = e.proveedor_id
        LEFT JOIN usuarios u ON u.id = e.usuario_id
        $where
        ORDER BY e.fecha DESC
        LIMIT ? OFFSET ?";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    error('Error al preparar consulta: ' . $conn->error);
}
$types2 = $types . 'ii';
$params2 = array_merge($params, [$pageSize, $offset]);
$stmt->bind_param($types2, ...$params2);
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

success([
    'rows' => $rows,
    'total' => $total,
    'page' => $page,
    'pageSize' => $pageSize,
    'desde' => $desde,
    'hasta' => $hasta,
]);
?>

