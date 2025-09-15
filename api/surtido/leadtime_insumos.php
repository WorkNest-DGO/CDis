<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
session_start();

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

date_default_timezone_set('America/Monterrey');

// Params
$page      = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$pageSize  = isset($_GET['pageSize']) ? max(1, min(200, (int)$_GET['pageSize'])) : 10;
$q         = isset($_GET['q']) ? trim($_GET['q']) : '';
$desde     = isset($_GET['desde']) ? $_GET['desde'] : '';
$hasta     = isset($_GET['hasta']) ? $_GET['hasta'] : '';
$incluir   = isset($_GET['incluir_ceros']) ? (int)$_GET['incluir_ceros'] : 0;
$sede_id   = isset($_GET['sede_id']) ? (int)$_GET['sede_id'] : (isset($_SESSION['sede_id']) ? (int)$_SESSION['sede_id'] : 0);

// Semana actual por defecto
$today = new DateTime('today');
$dow   = (int)$today->format('N');
$monday = (clone $today)->modify('-' . ($dow - 1) . ' days');
$sunday = (clone $monday)->modify('+6 days');
if ($desde === '') { $desde = $monday->format('Y-m-d'); }
if ($hasta === '') { $hasta = $sunday->format('Y-m-d'); }

$desde_dt = $desde . ' 00:00:00';
$hasta_dt = $hasta . ' 23:59:59';

// === Detectar número de parámetros del SP ===
$param_count = 0;
if ($res = $conn->query("
    SELECT COUNT(*) AS n
    FROM INFORMATION_SCHEMA.PARAMETERS
    WHERE SPECIFIC_SCHEMA = DATABASE()
      AND SPECIFIC_NAME = 'sp_leadtime_insumos'
")) {
    $row = $res->fetch_assoc();
    $param_count = (int)($row['n'] ?? 0);
    $res->free();
}

// === Preparar y ejecutar CALL según # de parámetros ===
if ($param_count >= 4) {
    $stmt = $conn->prepare('CALL sp_leadtime_insumos(?, ?, ?, ?)');
    if (!$stmt) { error('Error al preparar SP: ' . $conn->error); }
    // asumiendo el cuarto parámetro es sede_id (INT)
    if (!$stmt->bind_param('ssii', $desde_dt, $hasta_dt, $incluir, $sede_id)) {
        error('Error al bindear SP (4p): ' . $stmt->error);
    }
} else {
    $stmt = $conn->prepare('CALL sp_leadtime_insumos(?, ?, ?)');
    if (!$stmt) { error('Error al preparar SP: ' . $conn->error); }
    if (!$stmt->bind_param('ssi', $desde_dt, $hasta_dt, $incluir)) {
        error('Error al bindear SP (3p): ' . $stmt->error);
    }
}

if (!$stmt->execute()) {
    $msg = $stmt->error ?: $conn->error;
    $stmt->close();
    error('Error al ejecutar SP: ' . $msg);
}

$result = $stmt->get_result();
$all = [];
if ($result) {
    while ($row = $result->fetch_assoc()) {
        $all[] = $row;
    }
    $result->free();
}
$stmt->close();

// Limpiar posibles resultados pendientes del SP
while ($conn->more_results() && $conn->next_result()) {
    if ($extra = $conn->store_result()) { $extra->free(); }
}

// === Filtro y paginación en memoria ===
$qLower = mb_strtolower($q);
$filtered = array_filter($all, function($r) use ($qLower) {
    if ($qLower === '') return true;
    $cols = ['insumo', 'ultima_entrada', 'proxima_estimada'];
    foreach ($cols as $c) {
        if (isset($r[$c]) && mb_strpos(mb_strtolower((string)$r[$c]), $qLower) !== false) {
            return true;
        }
    }
    return false;
});

$filtered = array_values($filtered);
$total = count($filtered);
$start = ($page - 1) * $pageSize;
$rows = array_slice($filtered, $start, $pageSize);

success([
    'rows' => $rows,
    'total' => $total,
    'page' => $page,
    'pageSize' => $pageSize,
    'desde' => $desde,
    'hasta' => $hasta,
    'incluir_ceros' => $incluir,
    'sede_id' => $sede_id,
    'sp_param_count' => $param_count,
]);
