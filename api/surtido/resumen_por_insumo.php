<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
session_start();

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

$page      = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$pageSize  = isset($_GET['pageSize']) ? max(1, min(200, (int)$_GET['pageSize'])) : 10;
$q         = isset($_GET['q']) ? trim($_GET['q']) : '';
$desde     = isset($_GET['desde']) ? $_GET['desde'] : '';
$hasta     = isset($_GET['hasta']) ? $_GET['hasta'] : '';
$incluir   = isset($_GET['incluir_ceros']) ? (int)$_GET['incluir_ceros'] : 0;

// Semana por defecto
date_default_timezone_set('America/Mexico_City');
$today = new DateTime('today');
$dow   = (int)$today->format('N');
$monday = (clone $today)->modify('-' . ($dow - 1) . ' days');
$sunday = (clone $monday)->modify('+6 days');
if ($desde === '') { $desde = $monday->format('Y-m-d'); }
if ($hasta === '') { $hasta = $sunday->format('Y-m-d'); }

$desde_dt = $desde . ' 00:00:00';
$hasta_dt = $hasta . ' 00:00:00';

$stmt = $conn->prepare('CALL sp_resumen_por_insumo(?, ?, ?)');
if (!$stmt) { error('Error al preparar SP: ' . $conn->error); }
$stmt->bind_param('ssi', $desde_dt, $hasta_dt, $incluir);
if (!$stmt->execute()) { $stmt->close(); error('Error al ejecutar SP: ' . $stmt->error); }
$result = $stmt->get_result();
$all = [];
if ($result) {
    while ($row = $result->fetch_assoc()) {
        $all[] = $row;
    }
}
$stmt->close();
while ($conn->more_results() && $conn->next_result()) { /* flush */ }

// Filtrar por texto en columna insumo
$qLower = mb_strtolower($q);
$filtered = array_filter($all, function($r) use ($qLower) {
    if ($qLower === '') return true;
    $cols = ['insumo'];
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
]);
?>

