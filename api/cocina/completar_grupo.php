<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

header('Content-Type: application/json; charset=utf-8');
if (session_status() !== PHP_SESSION_ACTIVE) { session_start(); }
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
$conn->set_charset('utf8mb4');

function json_ok($payload = []) { echo json_encode(['success'=>true,'ok'=>true]+$payload, JSON_UNESCAPED_UNICODE); exit; }
function json_fail($msg, $code=400, $extra=[]) { http_response_code($code); echo json_encode(['success'=>false,'ok'=>false,'mensaje'=>$msg]+$extra, JSON_UNESCAPED_UNICODE); exit; }

function obtenerBaseUrl()
{
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ||
             (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https');
    $scheme = $https ? 'https' : 'http';
    $host = isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : (isset($_SERVER['SERVER_NAME']) ? $_SERVER['SERVER_NAME'] : 'localhost');
    if (strpos($host, ':') === false && isset($_SERVER['SERVER_PORT']) && !in_array($_SERVER['SERVER_PORT'], ['80', '443'], true)) {
        $host .= ':' . $_SERVER['SERVER_PORT'];
    }
    return $scheme . '://' . $host;
}
function construirUrlConsultaEntrada($entradaId)
{
    $entradaId = (int) $entradaId;
    $scriptName = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '/CDI/api/cocina/procesado.php';
    $scriptDir = str_replace('\\', '/', dirname($scriptName));
    if ($scriptDir === '.' || $scriptDir === '/' || $scriptDir === '\\') { $scriptDir = ''; }
    $basePath = preg_replace('#/api/cocina/?$#', '', $scriptDir);
    $relativePath = rtrim($basePath, '/') . '/vistas/insumos/entrada_insumo.php';
    $relativePath = '/' . ltrim($relativePath, '/');
    return rtrim(obtenerBaseUrl(), '/') . $relativePath . '?id=' . $entradaId;
}
function construirUrlConsultaMovimiento($token)
{
    $token = trim((string)$token);
    $scriptName = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '/CDI/api/cocina/procesado.php';
    $scriptDir = str_replace('\\', '/', dirname($scriptName));
    if ($scriptDir === '.' || $scriptDir === '/' || $scriptDir === '\\') { $scriptDir = ''; }
    $basePath = preg_replace('#/api/cocina/?$#', '', $scriptDir);
    $relativePath = rtrim($basePath, '/') . '/vistas/insumos/consulta_movimiento.php';
    $relativePath = '/' . ltrim($relativePath, '/');
    return rtrim(obtenerBaseUrl(), '/') . $relativePath . '?token=' . urlencode($token);
}
function generarTokenMovimiento(mysqli $conn)
{
    do {
        $token = bin2hex(random_bytes(16));
        $stmt = $conn->prepare('SELECT 1 FROM movimientos_insumos WHERE qr_token = ? LIMIT 1');
        if (!$stmt) { break; }
        $stmt->bind_param('s', $token);
        $stmt->execute();
        $stmt->store_result();
        $existe = $stmt->num_rows > 0;
        $stmt->close();
    } while ($existe);
    return $token;
}
function notificarCambioCocina(array $ids = []) {
    $dir = __DIR__ . '/runtime';
    if (!is_dir($dir)) { @mkdir($dir, 0775, true); }
    $verFile   = $dir . '/cocina_version.txt';
    $eventsLog = $dir . '/cocina_events.jsonl';
    $fp = @fopen($verFile, 'c+');
    if (!$fp) return;
    flock($fp, LOCK_EX);
    $txt  = stream_get_contents($fp);
    $cur  = intval(trim($txt ?? '0'));
    $next = $cur + 1;
    ftruncate($fp, 0); rewind($fp); fwrite($fp, (string)$next); fflush($fp); flock($fp, LOCK_UN); fclose($fp);
    $evt = json_encode(['v'=>$next,'ids'=>array_values(array_unique(array_map('intval',$ids))), 'ts'=>time()]);
    @file_put_contents($eventsLog, $evt . PHP_EOL, FILE_APPEND | LOCK_EX);
}

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data)) { json_fail('JSON inválido'); }
$pedido = isset($data['pedido']) ? (int)$data['pedido'] : 0;
$cantRes = isset($data['cantidad_resultante']) ? (float)$data['cantidad_resultante'] : 0.0;
$motivoMermaGlobal = isset($data['motivo_merma']) ? trim((string)$data['motivo_merma']) : '';
$mermas = isset($data['mermas']) && is_array($data['mermas']) ? $data['mermas'] : [];
if ($pedido <= 0) { json_fail('pedido inválido'); }
if (!($cantRes > 0)) { json_fail('cantidad_resultante inválida'); }
$userId = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;
if ($userId <= 0) { json_fail('Usuario no autenticado', 401); }

// Asegurar columna pedido existe
try { $rs=$conn->query("SHOW COLUMNS FROM procesos_insumos LIKE 'pedido'"); if (!$rs || $rs->num_rows===0) $conn->query("ALTER TABLE procesos_insumos ADD COLUMN pedido INT NOT NULL DEFAULT 0"); } catch (Throwable $e) {}

$conn->begin_transaction();
try {
    // Bloquear procesos del grupo
    $ps = $conn->prepare('SELECT * FROM procesos_insumos WHERE pedido = ? FOR UPDATE');
    $ps->bind_param('i', $pedido);
    $ps->execute();
    $rs = $ps->get_result();
    $procs = [];
    while ($row = $rs->fetch_assoc()) { $procs[] = $row; }
    $ps->close();
    if (!$procs) { throw new RuntimeException('No hay procesos para el pedido'); }

    // Validar que estén en listo (o al menos no entregado)
    foreach ($procs as $p) {
        if (!in_array($p['estado'], ['listo','en_preparacion','pendiente'], true)) continue;
    }

    $destinoId = (int)$procs[0]['insumo_destino_id'];
    $unidadDestino = (string)$procs[0]['unidad_destino'];

    // Insert entrada del destino
    $qrDir = __DIR__ . '/../../archivos/qr';
    if (!is_dir($qrDir)) { @mkdir($qrDir, 0777, true); }
    $desc = 'Procesado grupo pedido ' . $pedido . ' hacia insumo ' . $destinoId;
    $cantidadActual = $cantRes;
    $proveedorFijo = 1;

    // corte_id opcional
    $hasCorteEntrada = false; $corteEntradaId = 0;
    try { $r = $conn->query("SHOW COLUMNS FROM entradas_insumos LIKE 'corte_id'"); if ($r && $r->num_rows>0) $hasCorteEntrada = true; } catch (Throwable $e) {}
    if ($hasCorteEntrada) {
        try { $r = $conn->query("SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1"); if ($r && ($x=$r->fetch_assoc())) $corteEntradaId = (int)$x['id']; } catch (Throwable $e) {}
    }

    // Detectar columna 'nota' y calcular consecutivo si aplica
    $hasNotaCol = false; $nota = null;
    try { $rn = $conn->query("SHOW COLUMNS FROM entradas_insumos LIKE 'nota'"); if ($rn && $rn->num_rows>0) { $hasNotaCol = true; } } catch (Throwable $e) { $hasNotaCol = false; }
    if ($hasNotaCol) {
        try {
            $rmax = $conn->query("SELECT COALESCE(MAX(nota), 0) AS ult FROM entradas_insumos");
            if ($rmax && ($rowMax = $rmax->fetch_assoc())) { $nota = (int)$rowMax['ult'] + 1; } else { $nota = 1; }
        } catch (Throwable $e) { $nota = 1; }
    }

    if ($hasCorteEntrada && $corteEntradaId > 0) {
        if ($hasNotaCol) {
            // Con corte_id y con nota
            $insEntrada = $conn->prepare('INSERT INTO entradas_insumos (insumo_id, proveedor_id, usuario_id, descripcion, cantidad, unidad, costo_total, referencia_doc, folio_fiscal, qr, cantidad_actual, credito, nota, corte_id) VALUES (?, ?, ?, ?, ?, ?, 0, "", "", "pendiente", ?, NULL, ?, ?)');
            $insEntrada->bind_param('iiisdsdii', $destinoId, $proveedorFijo, $userId, $desc, $cantRes, $unidadDestino, $cantidadActual, $nota, $corteEntradaId);
        } else {
            // Con corte_id y sin nota
            $insEntrada = $conn->prepare('INSERT INTO entradas_insumos (insumo_id, proveedor_id, usuario_id, descripcion, cantidad, unidad, costo_total, referencia_doc, folio_fiscal, qr, cantidad_actual, credito, corte_id) VALUES (?, ?, ?, ?, ?, ?, 0, "", "", "pendiente", ?, NULL, ?)');
            $insEntrada->bind_param('iiisdsdi', $destinoId, $proveedorFijo, $userId, $desc, $cantRes, $unidadDestino, $cantidadActual, $corteEntradaId);
        }
    } else {
        if ($hasNotaCol) {
            // Sin corte_id y con nota
            $insEntrada = $conn->prepare('INSERT INTO entradas_insumos (insumo_id, proveedor_id, usuario_id, descripcion, cantidad, unidad, costo_total, referencia_doc, folio_fiscal, qr, cantidad_actual, credito, nota) VALUES (?, ?, ?, ?, ?, ?, 0, "", "", "pendiente", ?, NULL, ?)');
            $insEntrada->bind_param('iiisdsdi', $destinoId, $proveedorFijo, $userId, $desc, $cantRes, $unidadDestino, $cantidadActual, $nota);
        } else {
            // Sin corte_id y sin nota (comportamiento anterior)
            $insEntrada = $conn->prepare('INSERT INTO entradas_insumos (insumo_id, proveedor_id, usuario_id, descripcion, cantidad, unidad, costo_total, referencia_doc, folio_fiscal, qr, cantidad_actual, credito) VALUES (?, ?, ?, ?, ?, ?, 0, "", "", "pendiente", ?, NULL)');
            $insEntrada->bind_param('iiisdsd', $destinoId, $proveedorFijo, $userId, $desc, $cantRes, $unidadDestino, $cantidadActual);
        }
    }
    $insEntrada->execute();
    $entradaId = $insEntrada->insert_id;
    $insEntrada->close();

    // Generar QR para la entrada
    $qrFileName = 'entrada_insumo_' . $entradaId . '.png';
    $qrRelativePath = 'archivos/qr/' . $qrFileName;
    $qrAbsolutePath = $qrDir . DIRECTORY_SEPARATOR . $qrFileName;
    if (file_exists($qrAbsolutePath)) { @unlink($qrAbsolutePath); }
    $qrUrl = construirUrlConsultaEntrada($entradaId);
    QRcode::png($qrUrl, $qrAbsolutePath, QR_ECLEVEL_Q, 8, 2);
    $updQr = $conn->prepare('UPDATE entradas_insumos SET qr = ? WHERE id = ?');
    $updQr->bind_param('si', $qrRelativePath, $entradaId);
    $updQr->execute();
    $updQr->close();

    // Índice de mermas por proceso_id
    $mapMerma = [];
    foreach ($mermas as $m) {
        if (!is_array($m)) continue;
        $pid = isset($m['proceso_id']) ? (int)$m['proceso_id'] : 0;
        $cant = isset($m['cantidad']) ? (float)$m['cantidad'] : 0.0;
        if ($pid > 0 && $cant > 0) { $mapMerma[$pid] = $cant; }
    }

    // corte_id para movimientos
    $hasCorteMov = false; $corteId = 0;
    try { $r = $conn->query("SHOW COLUMNS FROM movimientos_insumos LIKE 'corte_id'"); if ($r && $r->num_rows>0) $hasCorteMov = true; } catch (Throwable $e) {}
    if ($hasCorteMov) {
        try { $r = $conn->query("SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1"); if ($r && ($x=$r->fetch_assoc())) $corteId = (int)$x['id']; } catch (Throwable $e) {}
    }

    // Insertar mermas por origen
    $mermasResp = [];
    foreach ($procs as $p) {
        $pid = (int)$p['id'];
        $origenId = (int)$p['insumo_origen_id'];
        $merma = isset($mapMerma[$pid]) ? (float)$mapMerma[$pid] : 0.0;
        if ($merma <= 0) continue;
        $token = generarTokenMovimiento($conn);
        $obsMerma = ($motivoMermaGlobal !== '' ? $motivoMermaGlobal . ' - ' : '') . ('Merma del proceso id ' . $pid . ' (pedido ' . $pedido . ')');
        if ($hasCorteMov && $corteId > 0) {
            $movM = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, qr_token, corte_id) VALUES ('merma', ?, ?, ?, ?, ?, NOW(), ?, ?)");
            $movM->bind_param('iiidssi', $userId, $origenId, $entradaId, $merma, $obsMerma, $token, $corteId);
        } else {
            $movM = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, qr_token) VALUES ('merma', ?, ?, ?, ?, ?, NOW(), ?)");
            $movM->bind_param('iiidss', $userId, $origenId, $entradaId, $merma, $obsMerma, $token);
        }
        $movM->execute();
        $mermaMovId = $movM->insert_id;
        $movM->close();

        // QR merma
        $qrMermaFile = 'merma_insumo_' . $mermaMovId . '_' . $token . '.png';
        $qrMermaRel  = 'archivos/qr/' . $qrMermaFile;
        $qrMermaAbs  = $qrDir . DIRECTORY_SEPARATOR . $qrMermaFile;
        $urlMov = construirUrlConsultaMovimiento($token);
        QRcode::png($urlMov, $qrMermaAbs, QR_ECLEVEL_Q, 8, 2);
        try { $upd = $conn->prepare('UPDATE movimientos_insumos SET `qr` = ? WHERE id = ?'); if ($upd){ $upd->bind_param('si', $qrMermaFile, $mermaMovId); $upd->execute(); $upd->close(); } } catch (Throwable $e) {}
        $mermasResp[] = ['proceso_id'=>$pid,'movimiento_id'=>$mermaMovId,'qr'=>$qrMermaRel];
    }

    // Actualizar procesos con entrada_insumo_id, cantidad_resultante y qr_path (mismo valor para todos)
    $up = $conn->prepare('UPDATE procesos_insumos SET entrada_insumo_id = ?, cantidad_resultante = ?, qr_path = ?, actualizado_en = NOW() WHERE pedido = ?');
    $up->bind_param('idsi', $entradaId, $cantRes, $qrRelativePath, $pedido);
    $up->execute();
    $up->close();

    // IDs para notificar
    $ids = array_map(function($p){ return (int)$p['id']; }, $procs);
    $conn->commit();
    notificarCambioCocina($ids);
    json_ok(['pedido'=>$pedido,'entrada_insumo_id'=>$entradaId,'qr'=>$qrRelativePath,'mermas'=>$mermasResp]);
} catch (Throwable $e) {
    try { $conn->rollback(); } catch (Throwable $e2) {}
    json_fail('No se pudo completar el grupo: ' . $e->getMessage());
}

?>
