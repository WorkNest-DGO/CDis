<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/pdf_simple.php';

if (!isset($_SESSION['usuario_id'])) {
    http_response_code(401);
    echo 'No autenticado';
    exit;
}

$token = isset($_GET['token']) ? trim(substr($_GET['token'], 0, 64)) : '';
if ($token === '') {
    http_response_code(400);
    echo 'Token requerido';
    exit;
}

$stmt = $conn->prepare('SELECT id, token, pdf_recepcion, json_data FROM qrs_insumo WHERE token = ? LIMIT 1');
$stmt->bind_param('s', $token);
$stmt->execute();
$qr = $stmt->get_result()->fetch_assoc();
$stmt->close();
if (!$qr) {
    http_response_code(404);
    echo 'QR no encontrado';
    exit;
}

$idqr = (int)$qr['id'];
$pdf_rel = $qr['pdf_recepcion'];
if ($pdf_rel) {
    $abs = realpath(__DIR__ . '/../../' . $pdf_rel);
    if ($abs && file_exists($abs)) {
        header('Location: ../../' . $pdf_rel);
        exit;
    }
}

// Regenerar recibo con totales devueltos actuales
$st = $conn->prepare("SELECT i.nombre, i.unidad, SUM(mi.cantidad) AS devuelto
                       FROM movimientos_insumos mi
                       JOIN insumos i ON i.id = mi.insumo_id
                       WHERE mi.id_qr = ? AND mi.tipo='devolucion'
                       GROUP BY i.nombre, i.unidad
                       ORDER BY i.nombre");
$st->bind_param('i', $idqr);
$st->execute();
$rs = $st->get_result();
$lineas = [];
$lineas[] = 'Token: ' . $token;
$lineas[] = 'Fecha: ' . date('Y-m-d H:i');
while ($r = $rs->fetch_assoc()) {
    $lineas[] = $r['nombre'] . ' - ' . rtrim(rtrim(number_format((float)$r['devuelto'],2,'.',''), '0'), '.') . ' ' . $r['unidad'];
}
$st->close();

$dirPdf = __DIR__ . '/../../archivos/bodega/pdfs';
if (!is_dir($dirPdf)) { mkdir($dirPdf, 0777, true); }
$pdf_rel = 'archivos/bodega/pdfs/recepcion_' . $token . '.pdf';
$pdf_path = __DIR__ . '/../../' . $pdf_rel;
generar_pdf_simple($pdf_path, 'Devolución de QR', $lineas);

$up = $conn->prepare('UPDATE qrs_insumo SET pdf_recepcion = ? WHERE id = ?');
if ($up) { $up->bind_param('si', $pdf_rel, $idqr); $up->execute(); $up->close(); }

header('Location: ../../' . $pdf_rel);
exit;
?>

