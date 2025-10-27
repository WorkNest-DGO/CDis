<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

$token = isset($_GET['token']) ? trim(substr($_GET['token'], 0, 64)) : '';
$id    = isset($_GET['id']) ? (int)$_GET['id'] : 0;

if ($token === '' && $id <= 0) {
    error('Parámetros inválidos');
}

// Obtener cabecera del QR
if ($token !== '') {
    $stmt = $conn->prepare('SELECT * FROM qrs_insumo WHERE token = ? LIMIT 1');
    $stmt->bind_param('s', $token);
} else {
    $stmt = $conn->prepare('SELECT * FROM qrs_insumo WHERE id = ? LIMIT 1');
    $stmt->bind_param('i', $id);
}
if (!$stmt->execute()) {
    $stmt->close();
    error('Error al consultar QR');
}
$res = $stmt->get_result();
$qr = $res->fetch_assoc();
$stmt->close();
if (!$qr) {
    error('QR no encontrado');
}

$id_qr = (int)$qr['id'];
$jsonArr = json_decode($qr['json_data'] ?? '[]', true);
if (!is_array($jsonArr)) { $jsonArr = []; }

// Resumen por insumo
$stmt = $conn->prepare(
    'SELECT mi.insumo_id, i.nombre, i.unidad, i.reque, SUM(ABS(mi.cantidad)) AS cantidad_total
     FROM movimientos_insumos mi
     JOIN insumos i ON i.id = mi.insumo_id
     WHERE mi.id_qr = ? AND mi.tipo IN ("traspaso")
     GROUP BY mi.insumo_id, i.nombre, i.unidad, i.reque
     ORDER BY i.nombre'
);
$stmt->bind_param('i', $id_qr);
$stmt->execute();
$res = $stmt->get_result();
$resumen = [];
while ($r = $res->fetch_assoc()) {
    $resumen[] = [
        'insumo_id' => (int)$r['insumo_id'],
        'nombre' => $r['nombre'],
        'unidad' => $r['unidad'],
        'reque'  => $r['reque'] ?? '',
        'cantidad_total' => (float)$r['cantidad_total'],
    ];
}
$stmt->close();

// Desglose por lotes
$stmt = $conn->prepare(
    'SELECT mi.insumo_id, i.nombre, ABS(mi.cantidad) AS cantidad,
            mi.id_entrada, ei.fecha AS fecha_entrada, ei.valor_unitario, ei.qr AS qr_lote
     FROM movimientos_insumos mi
     JOIN insumos i ON i.id = mi.insumo_id
     LEFT JOIN entradas_insumos ei ON ei.id = mi.id_entrada
     WHERE mi.id_qr = ? AND mi.tipo = "traspaso"
     ORDER BY ei.fecha, ei.id'
);
$stmt->bind_param('i', $id_qr);
$stmt->execute();
$res = $stmt->get_result();
$lotes = [];
while ($r = $res->fetch_assoc()) {
    $lotes[] = [
        'insumo_id' => (int)$r['insumo_id'],
        'nombre' => $r['nombre'],
        'cantidad' => (float)$r['cantidad'],
        'id_entrada' => isset($r['id_entrada']) ? (int)$r['id_entrada'] : null,
        'fecha_entrada' => $r['fecha_entrada'],
        'valor_unitario' => isset($r['valor_unitario']) ? (float)$r['valor_unitario'] : null,
        'qr_lote' => $r['qr_lote'] ?? null,
    ];
}
$stmt->close();

// Devoluciones agregadas por insumo para tabla separada
$stmt = $conn->prepare(
    'SELECT mi.insumo_id, i.nombre, i.unidad, SUM(ABS(mi.cantidad)) AS cantidad_total
     FROM movimientos_insumos mi
     JOIN insumos i ON i.id = mi.insumo_id
     WHERE mi.id_qr = ? AND mi.tipo = "devolucion"
     GROUP BY mi.insumo_id, i.nombre, i.unidad
     ORDER BY i.nombre'
);
$stmt->bind_param('i', $id_qr);
$stmt->execute();
$res = $stmt->get_result();
$devoluciones = [];
while ($r = $res->fetch_assoc()) {
    $devoluciones[] = [
        'insumo_id' => (int)$r['insumo_id'],
        'nombre' => $r['nombre'],
        'unidad' => $r['unidad'],
        'cantidad_total' => (float)$r['cantidad_total'],
    ];
}
$stmt->close();

success([
    'qr' => [
        'id' => $qr['id'],
        'token' => $qr['token'],
        'estado' => $qr['estado'],
        'creado_en' => $qr['creado_en'],
        'creado_por' => $qr['creado_por'],
        'pdf_envio' => $qr['pdf_envio'],
        'json_data' => $jsonArr,
    ],
    'resumen_por_insumo' => $resumen,
    'lotes' => $lotes,
    'devoluciones' => $devoluciones,
]);
?>
