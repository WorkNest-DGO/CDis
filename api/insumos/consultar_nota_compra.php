<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

$nota = isset($_GET['nota']) ? (int)$_GET['nota'] : 0;
if ($nota <= 0) {
    error('Nota inválida');
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

$sql = "SELECT e.id, e.fecha, e.insumo_id, e.proveedor_id, e.descripcion, e.cantidad, e.unidad,
               e.costo_total, e.nota,
               p.nombre AS proveedor, i.nombre AS producto
        FROM entradas_insumos e
        LEFT JOIN proveedores p ON p.id = e.proveedor_id
        LEFT JOIN insumos i ON i.id = e.insumo_id
        WHERE e.nota = ?
        ORDER BY e.fecha DESC, e.id DESC";
$stmt = $conn->prepare($sql);
if (!$stmt) { error('Error al preparar consulta: ' . $conn->error); }
$stmt->bind_param('i', $nota);
if (!$stmt->execute()) { $stmt->close(); error('Error al ejecutar consulta: ' . $stmt->error); }
$res = $stmt->get_result();
$rows = [];
while ($r = $res->fetch_assoc()) { $rows[] = $r; }
$stmt->close();

success($rows);
?>

