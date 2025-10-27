<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

$token = isset($_GET['token']) ? trim(substr($_GET['token'], 0, 64)) : '';
if ($token === '') {
    error('Token requerido');
}

// Obtener ID del QR
$st = $conn->prepare('SELECT id FROM qrs_insumo WHERE token = ? LIMIT 1');
if (!$st) { error('Error al preparar consulta'); }
$st->bind_param('s', $token);
$st->execute();
$res = $st->get_result();
$row = $res->fetch_assoc();
$st->close();
if (!$row) { error('QR no encontrado'); }
$id_qr = (int)$row['id'];

// Listar QRs (de entradas) involucrados en devoluciones de este QR
$sql = "SELECT ei.id AS id_entrada, ei.qr, ei.fecha, i.nombre AS insumo, i.unidad,
               SUM(CASE WHEN mi.tipo='devolucion' THEN mi.cantidad ELSE 0 END) AS devuelto
        FROM movimientos_insumos mi
        JOIN entradas_insumos ei ON ei.id = mi.id_entrada
        JOIN insumos i ON i.id = mi.insumo_id
        WHERE mi.id_qr = ? AND mi.tipo='devolucion' AND ei.qr IS NOT NULL AND ei.qr <> ''
        GROUP BY ei.id, ei.qr, ei.fecha, i.nombre, i.unidad
        ORDER BY ei.fecha, ei.id";

$st2 = $conn->prepare($sql);
if (!$st2) { error('Error al consultar devoluciones'); }
$st2->bind_param('i', $id_qr);
$st2->execute();
$rs = $st2->get_result();
$items = [];
while ($r = $rs->fetch_assoc()) {
    $items[] = [
        'id_entrada' => (int)$r['id_entrada'],
        'qr' => $r['qr'],
        'fecha' => $r['fecha'],
        'insumo' => $r['insumo'],
        'unidad' => $r['unidad'],
        'devuelto' => (float)$r['devuelto'],
    ];
}
$st2->close();

success(['qrs' => $items]);
?>

