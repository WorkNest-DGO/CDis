<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// Admite JSON o application/x-www-form-urlencoded
$raw = file_get_contents('php://input');
$input = null;
if (!empty($raw) && ($raw[0] === '{' || $raw[0] === '[')) {
    $input = json_decode($raw, true);
}

function read_param($name, $default = null) {
    global $input;
    if (is_array($input) && array_key_exists($name, $input)) return $input[$name];
    if (isset($_POST[$name])) return $_POST[$name];
    return $default;
}

$entradaId = (int) read_param('entrada_id', (int) read_param('id_entrada', 0));
$delta = (float) read_param('cantidad', 0.0); // puede ser positivo o negativo
$observacion = trim((string) read_param('observacion', ''));

// Usuario desde sesión o parámetro (fallback)
$usuarioId = isset($_SESSION['usuario_id']) ? (int) $_SESSION['usuario_id'] : 0;
$uAlt = (int) read_param('usuario_id', 0);
if ($uAlt > 0) $usuarioId = $uAlt;

if ($entradaId <= 0) error('Entrada inválida');
if (!is_finite($delta) || abs($delta) < 0.000001) error('Cantidad de ajuste inválida');
if ($usuarioId <= 0) error('Usuario inválido');

// Leer entrada y bloquear
$sel = $conn->prepare('SELECT id, insumo_id, cantidad_actual, unidad FROM entradas_insumos WHERE id = ? FOR UPDATE');
if (!$sel) error('Error DB: ' . $conn->error);
$sel->bind_param('i', $entradaId);
$sel->execute();
$res = $sel->get_result();
if (!$res || $res->num_rows === 0) { $sel->close(); error('Entrada no encontrada'); }
$row = $res->fetch_assoc();
$sel->close();

$insumoId = (int)$row['insumo_id'];
$actual = (float)$row['cantidad_actual'];
$unidad = (string)$row['unidad'];

$nuevo = $actual + $delta;
if ($nuevo < -0.000001) {
    error('El ajuste no puede dejar la cantidad actual en negativo');
}

$conn->begin_transaction();
try {
    // Bypass FIFO del trigger al disminuir (solo cuando delta < 0)
    if ($delta < 0) {
        $conn->query("SET @mov_tipo = 'ajuste'");
        $conn->query('SET @bypass_fifo = 1');
    }

    // Actualizar lote
    $upd = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual + ? WHERE id = ?');
    if (!$upd) throw new RuntimeException('No se pudo preparar actualización');
    $upd->bind_param('di', $delta, $entradaId);
    if (!$upd->execute()) {
        $err = $upd->error;
        $upd->close();
        throw new RuntimeException($err ?: 'No se pudo actualizar la entrada');
    }
    $upd->close();

    // Actualizar existencia global del insumo
    $updIns = $conn->prepare('UPDATE insumos SET existencia = GREATEST(existencia + ?, 0) WHERE id = ?');
    if ($updIns) { $updIns->bind_param('di', $delta, $insumoId); $updIns->execute(); $updIns->close(); }

    // Buscar corte abierto
    $corteId = 0;
    if ($qC = $conn->prepare('SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1')) {
        if ($qC->execute()) {
            $r = $qC->get_result();
            if ($r && ($c = $r->fetch_assoc())) { $corteId = (int)$c['id']; }
        }
        $qC->close();
    }

    // Preparar observación
    $obs = $observacion !== '' ? $observacion : ('Ajuste manual de entrada #' . $entradaId . ' (' . number_format($delta, 2, '.', '') . ' ' . $unidad . ')');

    // Registrar movimiento tipo ajuste (cantidad con el mismo signo de $delta)
    if ($corteId > 0) {
        $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, corte_id) VALUES ('ajuste', ?, ?, ?, ?, ?, NOW(), ?)");
        if (!$mov) throw new RuntimeException('No se pudo registrar el movimiento');
        $mov->bind_param('iiidsi', $usuarioId, $insumoId, $entradaId, $delta, $obs, $corteId);
    } else {
        $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha) VALUES ('ajuste', ?, ?, ?, ?, ?, NOW())");
        if (!$mov) throw new RuntimeException('No se pudo registrar el movimiento');
        $mov->bind_param('iiids', $usuarioId, $insumoId, $entradaId, $delta, $obs);
    }
    if (!$mov->execute()) { $e = $mov->error; $mov->close(); throw new RuntimeException($e ?: 'Error al insertar movimiento'); }
    $movId = $mov->insert_id;
    $mov->close();

    // Limpiar vars de sesión del trigger
    @ $conn->query('SET @mov_tipo = NULL');
    @ $conn->query('SET @bypass_fifo = NULL');

    $conn->commit();

    success([
        'entrada_id' => $entradaId,
        'insumo_id' => $insumoId,
        'cantidad_anterior' => round($actual, 4),
        'ajuste' => round($delta, 4),
        'cantidad_nueva' => round($nuevo, 4),
        'movimiento_id' => $movId,
    ]);
} catch (Throwable $e) {
    if ($conn->in_transaction) { $conn->rollback(); }
    @ $conn->query('SET @mov_tipo = NULL');
    @ $conn->query('SET @bypass_fifo = NULL');
    error('No se pudo registrar el ajuste: ' . $e->getMessage());
}

?>
