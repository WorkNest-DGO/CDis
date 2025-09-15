<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
session_start();

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

$insumo_id = isset($_GET['insumo_id']) ? (int)$_GET['insumo_id'] : 0;
$desde     = isset($_GET['desde']) ? $_GET['desde'] : '';
$hasta     = isset($_GET['hasta']) ? $_GET['hasta'] : '';

if ($insumo_id <= 0) {
    error('Parametro insumo_id requerido');
}

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

$stmt = $conn->prepare('CALL sp_resumen_compras_insumo(?, ?, ?)');
if (!$stmt) { error('Error al preparar SP: ' . $conn->error); }
$stmt->bind_param('iss', $insumo_id, $desde_dt, $hasta_dt);
if (!$stmt->execute()) { $stmt->close(); error('Error al ejecutar SP: ' . $stmt->error); }
$result = $stmt->get_result();
$row = $result ? $result->fetch_assoc() : null;
$stmt->close();
while ($conn->more_results() && $conn->next_result()) { /* flush */ }

success([
    'row' => $row,
    'desde' => $desde,
    'hasta' => $hasta,
    'insumo_id' => $insumo_id,
]);
?>

