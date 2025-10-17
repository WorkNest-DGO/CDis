<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

$producto   = isset($_GET['producto']) ? trim($_GET['producto']) : '';
$unidad     = isset($_GET['unidad']) ? trim($_GET['unidad']) : '';
$cmin       = isset($_GET['cantidad_min']) && $_GET['cantidad_min'] !== '' ? (float)$_GET['cantidad_min'] : null;
$cmax       = isset($_GET['cantidad_max']) && $_GET['cantidad_max'] !== '' ? (float)$_GET['cantidad_max'] : null;
$date_from  = isset($_GET['date_from']) ? trim($_GET['date_from']) : '';
$date_to    = isset($_GET['date_to']) ? trim($_GET['date_to']) : '';
$page       = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$page_size  = isset($_GET['page_size']) ? (int)$_GET['page_size'] : 0;
if (!in_array($page_size, [0, 15, 30, 50], true)) { $page_size = 0; }

$where = [];
$params = [];
$types = '';

// Solo registros con tipo de pago NULL
$where[] = 'e.credito IS NULL';

if ($producto !== '') {
    $where[] = 'LOWER(i.nombre) LIKE ?';
    $types .= 's';
    $params[] = '%' . strtolower($producto) . '%';
}
if ($unidad !== '') {
    $where[] = 'LOWER(e.unidad) LIKE ?';
    $types .= 's';
    $params[] = '%' . strtolower($unidad) . '%';
}
if ($cmin !== null) {
    $where[] = 'e.cantidad >= ?';
    $types .= 'd';
    $params[] = $cmin;
}
if ($cmax !== null) {
    $where[] = 'e.cantidad <= ?';
    $types .= 'd';
    $params[] = $cmax;
}
if ($date_from !== '' && $date_to !== '') {
    $where[] = '(e.fecha >= ? AND e.fecha < DATE_ADD(DATE(?), INTERVAL 1 DAY))';
    $types .= 'ss';
    $params[] = $date_from . ' 00:00:00';
    $params[] = $date_to;
}

$whereSql = count($where) ? (' WHERE ' . implode(' AND ', $where)) : '';

$selectSql = "SELECT e.id, e.fecha, e.cantidad, e.unidad, e.costo_total,
                     i.nombre AS producto
              FROM entradas_insumos e
              LEFT JOIN insumos i ON i.id = e.insumo_id
              $whereSql
              ORDER BY e.fecha DESC, e.id DESC";

if ($page_size > 0) {
    $countSql = "SELECT COUNT(*) AS total
                 FROM entradas_insumos e
                 LEFT JOIN insumos i ON i.id = e.insumo_id
                 $whereSql";
    $total = 0;
    if ($types !== '') {
        $stmtC = $conn->prepare($countSql);
        if (!$stmtC) { error('Error al preparar conteo: ' . $conn->error); }
        $stmtC->bind_param($types, ...$params);
        if (!$stmtC->execute()) { $stmtC->close(); error('Error al ejecutar conteo: ' . $stmtC->error); }
        $resC = $stmtC->get_result();
        if ($rowC = $resC->fetch_assoc()) { $total = (int)$rowC['total']; }
        $stmtC->close();
    } else {
        $resC = $conn->query($countSql);
        if ($resC && ($rowC = $resC->fetch_assoc())) { $total = (int)$rowC['total']; }
    }
    $pages = $page_size > 0 ? max(1, (int)ceil($total / $page_size)) : 1;
    if ($page > $pages) { $page = $pages; }
    $offset = ($page - 1) * $page_size;
    $selectSql .= " LIMIT $page_size OFFSET $offset";

    $rows = [];
    if ($types !== '') {
        $stmt = $conn->prepare($selectSql);
        if (!$stmt) { error('Error al preparar consulta: ' . $conn->error); }
        $stmt->bind_param($types, ...$params);
        if (!$stmt->execute()) { $stmt->close(); error('Error al ejecutar consulta: ' . $stmt->error); }
        $res = $stmt->get_result();
        while ($r = $res->fetch_assoc()) { $rows[] = $r; }
        $stmt->close();
    } else {
        $result = $conn->query($selectSql);
        if (!$result) { error('Error al obtener preparados: ' . $conn->error); }
        while ($r = $result->fetch_assoc()) { $rows[] = $r; }
    }
    success(['rows' => $rows, 'total' => $total, 'page' => $page, 'page_size' => $page_size, 'pages' => $pages]);
} else {
    $rows = [];
    if ($types !== '') {
        $stmt = $conn->prepare($selectSql);
        if (!$stmt) { error('Error al preparar consulta: ' . $conn->error); }
        $stmt->bind_param($types, ...$params);
        if (!$stmt->execute()) { $stmt->close(); error('Error al ejecutar consulta: ' . $stmt->error); }
        $res = $stmt->get_result();
        while ($r = $res->fetch_assoc()) { $rows[] = $r; }
        $stmt->close();
    } else {
        $result = $conn->query($selectSql);
        if (!$result) { error('Error al obtener preparados: ' . $conn->error); }
        while ($r = $result->fetch_assoc()) { $rows[] = $r; }
    }
    success($rows);
}

?>
