<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

// Sanitización básica
$page     = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$perPage  = isset($_GET['per_page']) ? max(1, min(200, (int)$_GET['per_page'])) : 20;
$token    = isset($_GET['token']) ? trim(substr($_GET['token'], 0, 64)) : '';
$estado   = isset($_GET['estado']) ? trim($_GET['estado']) : 'todos';
$fechaIni = isset($_GET['fecha_ini']) ? trim($_GET['fecha_ini']) : '';
$fechaFin = isset($_GET['fecha_fin']) ? trim($_GET['fecha_fin']) : '';
$insumoQ  = isset($_GET['insumo']) ? trim(substr($_GET['insumo'], 0, 100)) : '';

// Validar estado
$validEstados = ['pendiente','confirmado','anulado','todos'];
if (!in_array($estado, $validEstados, true)) {
    $estado = 'todos';
}

// Normalizar fechas (si no vienen, usar últimos 7 días)
date_default_timezone_set('America/Mexico_City');
if ($fechaIni === '' || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $fechaIni)) {
    $fechaIni = date('Y-m-d', strtotime('-7 days'));
}
if ($fechaFin === '' || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $fechaFin)) {
    $fechaFin = date('Y-m-d');
}
$fechaIniDt = $fechaIni . ' 00:00:00';
$fechaFinDt = $fechaFin . ' 00:00:00'; // < fecha_fin + 1 día

// WHERE dinámico
$where = ' WHERE 1=1 ';
$types = '';
$params = [];

// Fechas
$where .= ' AND q.creado_en >= ? AND q.creado_en < DATE_ADD(?, INTERVAL 1 DAY) ';
$types .= 'ss';
$params[] = $fechaIniDt;
$params[] = $fechaFinDt;

// Estado
if ($estado !== 'todos') {
    $where .= ' AND q.estado = ? ';
    $types .= 's';
    $params[] = $estado;
}

// Token LIKE
if ($token !== '') {
    $where .= ' AND q.token LIKE ? ';
    $types .= 's';
    $params[] = '%' . $token . '%';
}

// Búsqueda por insumo en movimientos del QR
if ($insumoQ !== '') {
    $where .= ' AND EXISTS (SELECT 1 FROM movimientos_insumos mi JOIN insumos i ON i.id = mi.insumo_id WHERE mi.id_qr = q.id AND i.nombre LIKE ?) ';
    $types .= 's';
    $params[] = '%' . $insumoQ . '%';
}

// Total
$sqlCount = "SELECT COUNT(*) AS total
             FROM qrs_insumo q
             LEFT JOIN usuarios u ON u.id = q.creado_por
             $where";
$stmt = $conn->prepare($sqlCount);
if (!$stmt) {
    error('Error preparar count: ' . $conn->error);
}
$stmt->bind_param($types, ...$params);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error ejecutar count: ' . $stmt->error);
}
$res = $stmt->get_result();
$row = $res->fetch_assoc();
$total = (int)($row['total'] ?? 0);
$stmt->close();

// Datos paginados
$offset = ($page - 1) * $perPage;
$sql = "SELECT q.id, q.token, q.creado_en, q.estado, q.pdf_envio, q.json_data, u.nombre AS creado_por_nombre
        FROM qrs_insumo q
        LEFT JOIN usuarios u ON u.id = q.creado_por
        $where
        ORDER BY q.id DESC
        LIMIT ? OFFSET ?";
$stmt = $conn->prepare($sql);
if (!$stmt) {
    error('Error preparar lista: ' . $conn->error);
}
$types2 = $types . 'ii';
$params2 = array_merge($params, [$perPage, $offset]);
$stmt->bind_param($types2, ...$params2);
if (!$stmt->execute()) {
    $stmt->close();
    error('Error ejecutar lista: ' . $stmt->error);
}
$res = $stmt->get_result();
$rows = [];
while ($r = $res->fetch_assoc()) {
    $items = 0;
    $json = json_decode($r['json_data'] ?? '[]', true);
    if (is_array($json)) { $items = count($json); }
    $rows[] = [
        'id' => (int)$r['id'],
        'token' => $r['token'],
        'creado_en' => $r['creado_en'],
        'estado' => $r['estado'],
        'pdf_envio' => $r['pdf_envio'],
        'creado_por_nombre' => $r['creado_por_nombre'],
        'items_count' => $items,
    ];
}
$stmt->close();

success([
    'data' => $rows,
    'total' => $total,
    'page' => $page,
    'per_page' => $perPage,
]);
?>

