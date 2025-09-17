<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    error('JSON inválido');
}

$entradaId = isset($input['entrada_id']) ? (int) $input['entrada_id'] : 0;
$retirar = isset($input['retirar']) ? (float) $input['retirar'] : 0.0;
$usuarioId = isset($_SESSION['usuario_id']) ? (int) $_SESSION['usuario_id'] : 0;
if (isset($input['usuario_id'])) {
    $tmp = (int) $input['usuario_id'];
    if ($tmp > 0) {
        $usuarioId = $tmp;
    }
}

if ($entradaId <= 0) error('Entrada inválida');
if ($retirar <= 0) error('Cantidad a retirar inválida');
if ($usuarioId <= 0) error('Usuario inválido');

$sel = $conn->prepare('SELECT id, insumo_id, cantidad_actual, unidad, valor_unitario FROM entradas_insumos WHERE id = ?');
if (!$sel) error('Error de consulta: ' . $conn->error);
$sel->bind_param('i', $entradaId);
$sel->execute();
$res = $sel->get_result();
if (!$res || $res->num_rows === 0) {
    $sel->close();
    error('Entrada no encontrada');
}
$row = $res->fetch_assoc();
$sel->close();

$insumoId = (int) $row['insumo_id'];
$actual = (float) $row['cantidad_actual'];
$unidad = (string) $row['unidad'];
$valorUnit = (float) $row['valor_unitario'];

if ($retirar > $actual) {
    error('La cantidad a retirar supera la cantidad actual');
}

if (!function_exists('generarTokenQrSalida')) {
    function generarTokenQrSalida()
    {
        return bin2hex(random_bytes(16));
    }
}

$qrToken = null;
$qrRelPath = null;
$qrAbsPath = null;
$fechaMovimiento = null;
$movimientoId = null;

$conn->begin_transaction();
try {
    $upd = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual - ? WHERE id = ?');
    if (!$upd) {
        throw new RuntimeException('No se pudo preparar actualización');
    }
    $upd->bind_param('di', $retirar, $entradaId);
    if (!$upd->execute()) {
        throw new RuntimeException('No se pudo actualizar cantidad actual');
    }
    $upd->close();

    $updIns = $conn->prepare('UPDATE insumos SET existencia = GREATEST(existencia - ?, 0) WHERE id = ?');
    if ($updIns) {
        $updIns->bind_param('di', $retirar, $insumoId);
        $updIns->execute();
        $updIns->close();
    }

    $qrToken = generarTokenQrSalida();
    $qrDir = __DIR__ . '/../../archivos/qr';
    if (!is_dir($qrDir)) {
        if (!mkdir($qrDir, 0777, true) && !is_dir($qrDir)) {
            throw new RuntimeException('No se pudo preparar el directorio de códigos QR');
        }
    }
    $qrFileName = 'salida_insumo_' . $entradaId . '_' . $qrToken . '.png';
    $qrRelPath = 'archivos/qr/' . $qrFileName;
    $qrAbsPath = $qrDir . DIRECTORY_SEPARATOR . $qrFileName;

    $fechaMovimiento = date('Y-m-d H:i:s');
    $qrPayload = json_encode([
        'tipo' => 'salida_insumo',
        'entrada_id' => $entradaId,
        'insumo_id' => $insumoId,
        'cantidad' => $retirar,
        'unidad' => $unidad,
        'fecha' => $fechaMovimiento,
        'usuario_id' => $usuarioId
    ], JSON_UNESCAPED_UNICODE);
    if ($qrPayload === false) {
        throw new RuntimeException('No se pudo preparar la información del código QR');
    }

    QRcode::png($qrPayload, $qrAbsPath, QR_ECLEVEL_Q, 8, 2);
    if (!is_file($qrAbsPath)) {
        throw new RuntimeException('No se pudo generar el código QR de salida');
    }

    $obs = 'Retiro de entrada #' . $entradaId . ' (' . $retirar . ' ' . $unidad . ')';
    $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, cantidad, observacion, fecha, qr_token) VALUES ('salida', ?, ?, ?, ?, ?, ?)");
    if (!$mov) {
        throw new RuntimeException('No se pudo preparar el registro del movimiento');
    }
    $mov->bind_param('iidsss', $usuarioId, $insumoId, $retirar, $obs, $fechaMovimiento, $qrToken);
    if (!$mov->execute()) {
        throw new RuntimeException('No se pudo registrar el movimiento de salida');
    }
    $movimientoId = $mov->insert_id;
    $mov->close();

    $conn->commit();
} catch (Throwable $e) {
    if ($conn->in_transaction) {
        $conn->rollback();
    }
    if ($qrAbsPath && is_file($qrAbsPath)) {
        @unlink($qrAbsPath);
    }
    error('Error al descontar: ' . $e->getMessage());
}

success([
    'entrada_id' => $entradaId,
    'insumo_id' => $insumoId,
    'retirado' => $retirar,
    'unidad' => $unidad,
    'valor_unitario' => $valorUnit,
    'qr_token' => $qrToken,
    'qr_imagen' => $qrRelPath,
    'fecha' => $fechaMovimiento,
    'movimiento_id' => $movimientoId
]);
