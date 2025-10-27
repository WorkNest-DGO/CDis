<?php
require_once __DIR__ . '/../../config/db.php';

header('Content-Type: application/json; charset=utf-8');
if (session_status() !== PHP_SESSION_ACTIVE) { session_start(); }
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
$conn->set_charset('utf8mb4');

function json_ok($payload = []) { echo json_encode(['success'=>true,'ok'=>true]+$payload, JSON_UNESCAPED_UNICODE); exit; }
function json_fail($msg, $code=400, $extra=[]) { http_response_code($code); echo json_encode(['success'=>false,'ok'=>false,'mensaje'=>$msg]+$extra, JSON_UNESCAPED_UNICODE); exit; }

function corteAbiertoId(mysqli $conn): int {
    try {
        $rs = $conn->query("SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1");
        if ($rs && ($row = $rs->fetch_assoc())) { return (int)$row['id']; }
    } catch (Throwable $e) { /* noop */ }
    return 0;
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

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data)) { json_fail('JSON inválido'); }

$pedido   = isset($data['pedido']) ? (int)$data['pedido'] : 0;
$origenes = isset($data['origenes']) && is_array($data['origenes']) ? $data['origenes'] : [];
if ($pedido <= 0) { json_fail('pedido inválido'); }
if (empty($origenes)) { json_fail('Debe incluir al menos un origen'); }

$userId = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;
if ($userId <= 0) { json_fail('Usuario no autenticado', 401); }

// Validar estructura de origenes
foreach ($origenes as $idx => $o) {
    if (!is_array($o)) { json_fail('Origen inválido en índice ' . $idx); }
    $iid = isset($o['insumo_id']) ? (int)$o['insumo_id'] : 0;
    $cant = isset($o['cantidad']) ? (float)$o['cantidad'] : 0.0;
    if ($iid <= 0 || !($cant > 0)) { json_fail('origen.insumo_id y cantidad > 0 son requeridos (índice ' . $idx . ')'); }
}

$conn->begin_transaction();
try {
    // Leer grupo actual y bloquear
    $stmt = $conn->prepare('SELECT * FROM procesos_insumos WHERE pedido = ? FOR UPDATE');
    $stmt->bind_param('i', $pedido);
    $stmt->execute();
    $res = $stmt->get_result();
    $procs = [];
    while ($row = $res->fetch_assoc()) { $procs[] = $row; }
    $stmt->close();
    if (!$procs) { throw new RuntimeException('Grupo no encontrado'); }
    // Verificar que todos estén en pendiente
    foreach ($procs as $p) {
        if (($p['estado'] ?? '') !== 'pendiente') { throw new RuntimeException('Solo se puede editar un grupo en estado pendiente'); }
        if (!empty($p['entrada_insumo_id'])) { throw new RuntimeException('El grupo ya tiene entrada generada'); }
    }
    $destinoId = (int)$procs[0]['insumo_destino_id'];
    $unidadDestino = (string)($procs[0]['unidad_destino'] ?? '');
    $observaciones = (string)($procs[0]['observaciones'] ?? '');
    $corteId = isset($procs[0]['corte_id']) ? (int)$procs[0]['corte_id'] : 0;
    if ($corteId <= 0) { $corteId = corteAbiertoId($conn); }

    // Revertir salidas e inventario por cada proceso
    foreach ($procs as $p) {
        $pid = (int)$p['id'];
        try {
            $sel = $conn->prepare("SELECT id, id_entrada, cantidad FROM movimientos_insumos WHERE tipo='salida' AND observacion LIKE CONCAT('Salida lote_origen proceso id ', ?, '%') FOR UPDATE");
        } catch (Throwable $e) {
            $sel = null;
        }
        if ($sel) {
            $sel->bind_param('i', $pid);
            $sel->execute();
            $rs = $sel->get_result();
            while ($m = $rs->fetch_assoc()) {
                $movId = (int)$m['id'];
                $entradaId = isset($m['id_entrada']) ? (int)$m['id_entrada'] : 0;
                $cant = (float)$m['cantidad'];
                $dev = abs($cant);
                if ($entradaId > 0 && $dev > 0) {
                    $upd = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual + ? WHERE id = ?');
                    $upd->bind_param('di', $dev, $entradaId);
                    $upd->execute();
                    $upd->close();
                }
                $del = $conn->prepare('DELETE FROM movimientos_insumos WHERE id = ?');
                $del->bind_param('i', $movId);
                $del->execute();
                $del->close();
            }
            $sel->close();
        }
    }
    // Eliminar procesos anteriores del pedido
    $delp = $conn->prepare('DELETE FROM procesos_insumos WHERE pedido = ?');
    $delp->bind_param('i', $pedido);
    $delp->execute();
    $delp->close();

    // Unidades de origen
    $insumoIds = array_values(array_unique(array_map(function($o){ return (int)$o['insumo_id']; }, $origenes)));
    $mapUnidad = [];
    if ($insumoIds) {
        $in = implode(',', array_fill(0, count($insumoIds), '?'));
        $types = str_repeat('i', count($insumoIds));
        $st = $conn->prepare("SELECT id, unidad FROM insumos WHERE id IN ($in)");
        $st->bind_param($types, ...$insumoIds);
        $st->execute();
        $r = $st->get_result();
        while ($row = $r->fetch_assoc()) { $mapUnidad[(int)$row['id']] = (string)$row['unidad']; }
        $st->close();
    }

    $hasCorteMov = false; $hasCorteProc = false;
    try { $rs = $conn->query("SHOW COLUMNS FROM movimientos_insumos LIKE 'corte_id'"); if ($rs && $rs->num_rows>0) $hasCorteMov = true; } catch (Throwable $e) { }
    try { $rs = $conn->query("SHOW COLUMNS FROM procesos_insumos LIKE 'corte_id'"); if ($rs && $rs->num_rows>0) $hasCorteProc = true; } catch (Throwable $e) { }

    // Insertar nuevos procesos y descontar inventario
    $proceso_ids = [];
    foreach ($origenes as $o) {
        $iid = (int)$o['insumo_id'];
        $cant = (float)$o['cantidad'];
        if ($iid <= 0 || !($cant > 0)) continue;
        if ($iid === $destinoId) { throw new RuntimeException('Origen y destino no pueden ser iguales'); }
        $unidad_origen = isset($mapUnidad[$iid]) ? $mapUnidad[$iid] : '';

        if ($hasCorteProc && $corteId > 0) {
            $ins = $conn->prepare("INSERT INTO procesos_insumos (insumo_origen_id, insumo_destino_id, cantidad_origen, unidad_origen, unidad_destino, estado, observaciones, creado_por, corte_id, pedido) VALUES (?, ?, ?, ?, ?, 'pendiente', ?, ?, ?, ?)");
            $ins->bind_param('iidsssiii', $iid, $destinoId, $cant, $unidad_origen, $unidadDestino, $observaciones, $userId, $corteId, $pedido);
        } else {
            $ins = $conn->prepare("INSERT INTO procesos_insumos (insumo_origen_id, insumo_destino_id, cantidad_origen, unidad_origen, unidad_destino, estado, observaciones, creado_por, pedido) VALUES (?, ?, ?, ?, ?, 'pendiente', ?, ?, ?)");
            $ins->bind_param('iidsssii', $iid, $destinoId, $cant, $unidad_origen, $unidadDestino, $observaciones, $userId, $pedido);
        }
        $ins->execute();
        $pid = $ins->insert_id;
        $ins->close();
        $proceso_ids[] = $pid;

        // Descontar inventario FIFO
        $pendiente = $cant;
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
            if ($hasCorteMov && $corteId > 0) {
                $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, corte_id) VALUES ('salida', ?, ?, ?, ?, ?, NOW(), ?)");
                $cantNeg = -$usar;
                $mov->bind_param('iiidsi', $userId, $iid, $lotId, $cantNeg, $obsMov, $corteId);
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
    echo json_encode(['success'=>true,'ok'=>true,'pedido'=>$pedido,'proceso_ids'=>$proceso_ids], JSON_UNESCAPED_UNICODE);
    exit;
} catch (Throwable $e) {
    try { $conn->rollback(); } catch (Throwable $e2) { /* noop */ }
    json_fail('No se pudo editar el grupo: ' . $e->getMessage());
}

?>
