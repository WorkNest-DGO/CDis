<?php
require_once __DIR__ . '/../../config/db.php';
header('Content-Type: application/json');
if (!defined('ENVIO_CASA_PRODUCT_ID')) define('ENVIO_CASA_PRODUCT_ID', 9001);

if (session_status() === PHP_SESSION_ACTIVE) {
    session_write_close();
}

$ultimoId = isset($_POST['ultimo_id']) ? intval($_POST['ultimo_id']) : 0;
$timeout = 25; // segundos
$start = time();

do {
    $stmt = $conn->prepare("SELECT vd.id, vd.venta_id, p.nombre AS producto, vd.cantidad, vd.estado_producto
                              FROM venta_detalles vd
                              JOIN productos p ON p.id = vd.producto_id
                              WHERE vd.id > ? AND vd.estado_producto IN ('pendiente','en_preparacion','listo')
                                AND vd.producto_id <> " . (int)ENVIO_CASA_PRODUCT_ID . "
                              ORDER BY vd.id ASC");
    if (!$stmt) {
        echo json_encode(['nueva_venta' => false, 'error' => $conn->error]);
        exit;
    }
    $stmt->bind_param('i', $ultimoId);
    $stmt->execute();
    $res = $stmt->get_result();
    $rows = $res->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    if ($rows) {
        $newLast = max(array_column($rows, 'id'));
        echo json_encode(['nueva_venta' => true, 'data' => $rows, 'ultimo_id' => $newLast]);
        exit;
    }
    usleep(500000); // 0.5 segundos
} while (time() - $start < $timeout);

echo json_encode(['nueva_venta' => false, 'ultimo_id' => $ultimoId]);
