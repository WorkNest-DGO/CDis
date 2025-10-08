<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

$credito   = isset($_GET['credito']) && $_GET['credito'] !== '' ? (int)$_GET['credito'] : null; // 0|1|null
$pagado    = isset($_GET['pagado']) && $_GET['pagado'] !== '' ? (int)$_GET['pagado'] : null;   // 0|1|null
$q         = isset($_GET['q']) ? trim($_GET['q']) : '';
$date_from = isset($_GET['date_from']) ? trim($_GET['date_from']) : '';
$date_to   = isset($_GET['date_to']) ? trim($_GET['date_to']) : '';
$page      = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$page_size = isset($_GET['page_size']) ? (int)$_GET['page_size'] : 0;
if (!in_array($page_size, [0, 15, 30, 50], true)) { $page_size = 0; }

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
// Búsqueda case-insensitive: forzar LOWER() de columnas y parámetro en minúsculas
if ($q !== '') {
    $where[] = '(LOWER(i.nombre) LIKE ? OR LOWER(p.nombre) LIKE ? OR LOWER(e.descripcion) LIKE ? OR LOWER(e.referencia_doc) LIKE ? OR LOWER(e.folio_fiscal) LIKE ?)';
    $types .= 'sssss';
    $like = '%' . strtolower($q) . '%';
    array_push($params, $like, $like, $like, $like, $like);
}
// Filtro por rango de fechas (inclusive): [date_from 00:00:00, date_to +1d 00:00:00)
if ($date_from !== '' && $date_to !== '') {
    $where[] = '(e.fecha >= ? AND e.fecha < DATE_ADD(DATE(?), INTERVAL 1 DAY))';
    $types .= 'ss';
    $params[] = $date_from . ' 00:00:00';
    $params[] = $date_to;
}

$whereSql = count($where) ? (' WHERE ' . implode(' AND ', $where)) : '';

// Base SELECT
$selectSql = "SELECT e.id, e.fecha, e.insumo_id, e.proveedor_id, e.usuario_id, e.descripcion,
                     e.cantidad, e.unidad, e.costo_total, e.valor_unitario,
                     e.referencia_doc, e.folio_fiscal, e.qr, e.cantidad_actual,
                     e.credito, e.pagado,
                     p.nombre AS proveedor, i.nombre AS producto
              FROM entradas_insumos e
              LEFT JOIN proveedores p ON p.id = e.proveedor_id
              LEFT JOIN insumos i ON i.id = e.insumo_id
              $whereSql
              ORDER BY e.fecha DESC, e.id DESC";

// Si hay paginación solicitada, calcular total y aplicar LIMIT/OFFSET
if ($page_size > 0) {
    $countSql = "SELECT COUNT(*) AS total
                 FROM entradas_insumos e
                 LEFT JOIN proveedores p ON p.id = e.proveedor_id
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
        if (!$result) { error('Error al obtener entradas: ' . $conn->error); }
        while ($r = $result->fetch_assoc()) { $rows[] = $r; }
    }
    success(['rows' => $rows, 'total' => $total, 'page' => $page, 'page_size' => $page_size, 'pages' => $pages]);
} else {
    // Sin paginación: devolver arreglo simple para compatibilidad
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
        if (!$result) { error('Error al obtener entradas: ' . $conn->error); }
        while ($r = $result->fetch_assoc()) { $rows[] = $r; }
    }
    success($rows);
}
