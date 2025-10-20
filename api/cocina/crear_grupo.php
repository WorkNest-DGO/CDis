<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

header('Content-Type: application/json; charset=utf-8');

if (session_status() !== PHP_SESSION_ACTIVE) { session_start(); }
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
$conn->set_charset('utf8mb4');

function json_ok($payload = []) { echo json_encode(['success'=>true,'ok'=>true]+$payload, JSON_UNESCAPED_UNICODE); exit; }
function json_fail($msg, $code=400, $extra=[]) { http_response_code($code); echo json_encode(['success'=>false,'ok'=>false,'mensaje'=>$msg]+$extra, JSON_UNESCAPED_UNICODE); exit; }

// Helpers
function ensurePedidoColumn(mysqli $conn): void {
    try {
        $rs = $conn->query("SHOW COLUMNS FROM procesos_insumos LIKE 'pedido'");
        if (!$rs || $rs->num_rows === 0) {
            $conn->query("ALTER TABLE procesos_insumos ADD COLUMN pedido INT NOT NULL DEFAULT 0");
            try { $conn->query("CREATE INDEX idx_proc_pedido ON procesos_insumos(pedido)"); } catch (Throwable $e) { /* noop */ }
        }
    } catch (Throwable $e) {
        // Si no se puede verificar, intentar agregar a ciegas y en fallo continuar sin bloquear
        try { $conn->query("ALTER TABLE procesos_insumos ADD COLUMN pedido INT NOT NULL DEFAULT 0"); } catch (Throwable $e2) { /* noop */ }
    }
}

function getUnidadInsumo(mysqli $conn, int $insumoId): string {
    $stmt = $conn->prepare('SELECT unidad FROM insumos WHERE id = ? LIMIT 1');
    $stmt->bind_param('i', $insumoId);
    $stmt->execute();
    $res = $stmt->get_result();
    $unidad = '';
    if ($res && ($row = $res->fetch_assoc())) { $unidad = (string)$row['unidad']; }
    $stmt->close();
    return $unidad;
}

function getNombreInsumo(mysqli $conn, int $insumoId): string {
    $stmt = $conn->prepare('SELECT nombre FROM insumos WHERE id = ? LIMIT 1');
    $stmt->bind_param('i', $insumoId);
    $stmt->execute();
    $res = $stmt->get_result();
    $nombre = '';
    if ($res && ($row = $res->fetch_assoc())) { $nombre = (string)$row['nombre']; }
    $stmt->close();
    return $nombre !== '' ? $nombre : (string)$insumoId;
}

function corteAbiertoId(mysqli $conn): int {
    try {
        $rs = $conn->query("SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1");
        if ($rs && ($row = $rs->fetch_assoc())) { return (int)$row['id']; }
    } catch (Throwable $e) { /* noop */ }
    return 0;
}

// Entrada
$raw = file_get_contents('php://input');
$payload = json_decode($raw, true);
if (!is_array($payload)) { json_fail('JSON inválido'); }

$destino_id = isset($payload['destino_id']) ? (int)$payload['destino_id'] : 0;
$unidad_destino = isset($payload['unidad_destino']) ? trim((string)$payload['unidad_destino']) : '';
$observaciones = isset($payload['observaciones']) ? trim((string)$payload['observaciones']) : '';
$corte_id = isset($payload['corte_id']) ? (int)$payload['corte_id'] : 0;
$origenes = isset($payload['origenes']) && is_array($payload['origenes']) ? $payload['origenes'] : [];

if ($destino_id <= 0) { json_fail('destino_id requerido'); }
if (empty($origenes)) { json_fail('Debe incluir al menos un origen'); }
$userId = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;
if ($userId <= 0) { json_fail('Usuario no autenticado', 401); }

// Validar origenes
foreach ($origenes as $idx => $o) {
    if (!is_array($o)) { json_fail('Origen inválido en índice ' . $idx); }
    $iid = isset($o['insumo_id']) ? (int)$o['insumo_id'] : 0;
    $cant = isset($o['cantidad']) ? (float)$o['cantidad'] : 0.0;
    $unidad = isset($o['unidad']) ? trim((string)$o['unidad']) : '';
    if ($iid <= 0 || !($cant > 0)) { json_fail('origen.insumo_id y cantidad > 0 son requeridos (índice ' . $idx . ')'); }
    if ($iid === $destino_id) { json_fail('Origen y destino no pueden ser iguales (índice ' . $idx . ')'); }
}

// Resolver unidad destino si no vino
if ($unidad_destino === '') { $unidad_destino = getUnidadInsumo($conn, $destino_id); }
$hasCorteMov = false; $hasCorteProc = false;
try { $rs = $conn->query("SHOW COLUMNS FROM movimientos_insumos LIKE 'corte_id'"); if ($rs && $rs->num_rows>0) $hasCorteMov = true; } catch (Throwable $e) { }
try { $rs = $conn->query("SHOW COLUMNS FROM procesos_insumos LIKE 'corte_id'"); if ($rs && $rs->num_rows>0) $hasCorteProc = true; } catch (Throwable $e) { }
if ($corte_id <= 0) { $corte_id = corteAbiertoId($conn); }

ensurePedidoColumn($conn);

// Transacción
$conn->begin_transaction();
try {
    // Siguiente pedido (con bloqueo)
    $next_pedido = 1;
    try {
        $sqlNp = "SELECT COALESCE(MAX(pedido),0)+1 AS next_pedido FROM procesos_insumos FOR UPDATE";
        $rsNp = $conn->query($sqlNp);
        if ($rsNp && ($rowNp = $rsNp->fetch_assoc())) { $next_pedido = (int)$rowNp['next_pedido']; }
    } catch (Throwable $e) {
        $next_pedido = (int)floor(microtime(true));
    }

    // Preparar datos de unidades de orígenes
    $insumoIds = array_values(array_unique(array_map(function($o){ return (int)$o['insumo_id']; }, $origenes)));
    $mapUnidad = [];
    if ($insumoIds) {
        $in = implode(',', array_fill(0, count($insumoIds), '?'));
        $types = str_repeat('i', count($insumoIds));
        $stmt = $conn->prepare("SELECT id, unidad FROM insumos WHERE id IN ($in)");
        $stmt->bind_param($types, ...$insumoIds);
        $stmt->execute();
        $r = $stmt->get_result();
        while ($row = $r->fetch_assoc()) { $mapUnidad[(int)$row['id']] = (string)$row['unidad']; }
        $stmt->close();
    }

    $proceso_ids = [];
    foreach ($origenes as $o) {
        $iid = (int)$o['insumo_id'];
        $cant = (float)$o['cantidad'];
        $idEntrada = isset($o['id_entrada']) ? (int)$o['id_entrada'] : 0;
        $unidad_origen = $o['unidad'] ? trim((string)$o['unidad']) : (isset($mapUnidad[$iid]) ? $mapUnidad[$iid] : '');
        if ($unidad_origen === '') { $unidad_origen = getUnidadInsumo($conn, $iid); }

        if ($hasCorteProc && $corte_id > 0) {
            $ins = $conn->prepare("INSERT INTO procesos_insumos (insumo_origen_id, insumo_destino_id, cantidad_origen, unidad_origen, unidad_destino, estado, observaciones, creado_por, corte_id, pedido) VALUES (?, ?, ?, ?, ?, 'pendiente', ?, ?, ?, ?)");
            $ins->bind_param('iidsssiii', $iid, $destino_id, $cant, $unidad_origen, $unidad_destino, $observaciones, $userId, $corte_id, $next_pedido);
        } else {
            $ins = $conn->prepare("INSERT INTO procesos_insumos (insumo_origen_id, insumo_destino_id, cantidad_origen, unidad_origen, unidad_destino, estado, observaciones, creado_por, pedido) VALUES (?, ?, ?, ?, ?, 'pendiente', ?, ?, ?)");
            $ins->bind_param('iidsssii', $iid, $destino_id, $cant, $unidad_origen, $unidad_destino, $observaciones, $userId, $next_pedido);
        }
        $ins->execute();
        $pid = $ins->insert_id;
        $ins->close();
        $proceso_ids[] = $pid;

        // Descuento inventario del origen (FIFO o lote específico)
        $pendiente = $cant;
        if ($idEntrada > 0) {
            $sel = $conn->prepare('SELECT id, cantidad_actual FROM entradas_insumos WHERE id = ? FOR UPDATE');
            $sel->bind_param('i', $idEntrada);
            $sel->execute();
            $rs = $sel->get_result();
            $fila = $rs ? $rs->fetch_assoc() : null;
            $sel->close();
            if (!$fila || (float)$fila['cantidad_actual'] <= 0) { throw new RuntimeException('Lote especificado sin disponibilidad'); }
            $tomar = min($pendiente, (float)$fila['cantidad_actual']);
            $upd = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual - ? WHERE id = ?');
            $upd->bind_param('di', $tomar, $idEntrada);
            $upd->execute();
            $upd->close();
            // Insert movimiento salida
            $obsMov = 'Salida lote_origen proceso id ' . (int)$pid;
            if ($hasCorteMov && $corte_id > 0) {
                $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, corte_id) VALUES ('salida', ?, ?, ?, ?, ?, NOW(), ?)");
                $cantNeg = -$tomar;
                $mov->bind_param('iiidsi', $userId, $iid, $idEntrada, $cantNeg, $obsMov, $corte_id);
            } else {
                $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha) VALUES ('salida', ?, ?, ?, ?, ?, NOW())");
                $cantNeg = -$tomar;
                $mov->bind_param('iiids', $userId, $iid, $idEntrada, $cantNeg, $obsMov);
            }
            $mov->execute();
            $mov->close();
            $pendiente -= $tomar;
        }

        while ($pendiente > 0.00001) {
            $sel = $conn->prepare('SELECT id, cantidad_actual FROM entradas_insumos WHERE insumo_id = ? AND cantidad_actual > 0 ORDER BY fecha ASC, id ASC FOR UPDATE');
            $sel->bind_param('i', $iid);
            $sel->execute();
            $rs = $sel->get_result();
            $lote = $rs ? $rs->fetch_assoc() : null;
            $sel->close();
            if (!$lote) { throw new RuntimeException('Stock insuficiente para el origen ' . getNombreInsumo($conn, $iid)); }
            $usar = min($pendiente, (float)$lote['cantidad_actual']);
            $upd = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual - ? WHERE id = ?');
            $lotId = (int)$lote['id'];
            $upd->bind_param('di', $usar, $lotId);
            $upd->execute();
            $upd->close();
            $obsMov = 'Salida lote_origen proceso id ' . (int)$pid;
            if ($hasCorteMov && $corte_id > 0) {
                $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, corte_id) VALUES ('salida', ?, ?, ?, ?, ?, NOW(), ?)");
                $cantNeg = -$usar;
                $mov->bind_param('iiidsi', $userId, $iid, $lotId, $cantNeg, $obsMov, $corte_id);
            } else {
                $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha) VALUES ('salida', ?, ?, ?, ?, ?, NOW())");
                $cantNeg = -$usar;
                $mov->bind_param('iiids', $userId, $iid, $lotId, $cantNeg, $obsMov);
            }
            $mov->execute();
            $mov->close();
            $pendiente -= $usar;
        }
    }

    $conn->commit();
    echo json_encode(['success'=>true,'ok'=>true,'pedido'=>$next_pedido,'proceso_ids'=>$proceso_ids,'destino_id'=>$destino_id], JSON_UNESCAPED_UNICODE);
    exit;
} catch (Throwable $e) {
    try { $conn->rollback(); } catch (Throwable $e2) { /* noop */ }
    json_fail('Error al crear grupo: ' . $e->getMessage());
}

?>
