<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

// Permitir filtrar por numero de nota y/o por texto en referencia_doc/folio_fiscal
$nota = isset($_GET['nota']) ? (int)$_GET['nota'] : 0;
$q = isset($_GET['q']) ? trim((string)$_GET['q']) : '';
if ($nota <= 0 && $q === '') {
    error('Parametros invalidos: proporciona nota o texto');
}

// Verificar si existe columna 'nota'
$hasNota = false;
try {
    $rs = $conn->query("SHOW COLUMNS FROM entradas_insumos LIKE 'nota'");
    if ($rs && $rs->num_rows > 0) { $hasNota = true; }
} catch (Throwable $e) { $hasNota = false; }
if (!$hasNota) {
    error('La columna nota no existe en entradas_insumos');
}

// Construccion dinamica del WHERE segun filtros recibidos
$where = [];
$types = '';
$params = [];
if ($nota > 0) { $where[] = 'e.nota = ?'; $types .= 'i'; $params[] = $nota; }
if ($q !== '') {
    $where[] = '(LOWER(COALESCE(e.referencia_doc, "")) LIKE ? OR LOWER(COALESCE(e.folio_fiscal, "")) LIKE ?)';
    $types .= 'ss';
    $like = '%' . strtolower($q) . '%';
    $params[] = $like; $params[] = $like;
}
$whereSql = count($where) ? ('WHERE ' . implode(' AND ', $where)) : '';

$sql = "SELECT e.id, e.fecha, e.insumo_id, e.proveedor_id, e.descripcion, e.cantidad, e.unidad,
               e.costo_total, e.referencia_doc, e.folio_fiscal, e.nota, e.credito,
               p.nombre AS proveedor, i.nombre AS producto
         FROM entradas_insumos e
         LEFT JOIN proveedores p ON p.id = e.proveedor_id
         LEFT JOIN insumos i ON i.id = e.insumo_id
         $whereSql
         ORDER BY e.fecha DESC, e.id DESC";

if ($types !== '') {
    $stmt = $conn->prepare($sql);
    if (!$stmt) { error('Error al preparar consulta: ' . $conn->error); }
    $stmt->bind_param($types, ...$params);
    if (!$stmt->execute()) { $stmt->close(); error('Error al ejecutar consulta: ' . $stmt->error); }
    $res = $stmt->get_result();
    $rows = [];
    while ($r = $res->fetch_assoc()) { $rows[] = $r; }
    $stmt->close();
} else {
    // Caso improbable sin parametros: ejecutar directo
    $result = $conn->query($sql);
    if (!$result) { error('Error al obtener resultados: ' . $conn->error); }
    $rows = [];
    while ($r = $result->fetch_assoc()) { $rows[] = $r; }
}

success($rows);
?>

