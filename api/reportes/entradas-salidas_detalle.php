<?php
// Detalle por lotes y QR para un insumo en un periodo/corte
// GET: insumo_id, mode=range|corte, (date_from,date_to | corte_id)

require_once __DIR__ . '/../../config/db.php';

header('Access-Control-Allow-Origin: *');

function bad_request($msg) {
    http_response_code(400);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

function as_datetime_bounds($date_from, $date_to) {
    $from = $date_from . ' 00:00:00';
    if (preg_match('/\d{2}:\d{2}:\d{2}$/', $date_from)) { $from = $date_from; }
    $toDate = new DateTime($date_to);
    if (preg_match('/\d{2}:\d{2}:\d{2}$/', $date_to)) { $toDate = new DateTime(substr($date_to,0,10)); }
    $toDate->modify('+1 day');
    $to = $toDate->format('Y-m-d 00:00:00');
    return [$from, $to];
}

$insumo_id = isset($_GET['insumo_id']) ? (int)$_GET['insumo_id'] : 0;
if ($insumo_id <= 0) { bad_request('insumo_id requerido'); }

$mode = isset($_GET['mode']) ? $_GET['mode'] : 'range';
$periodo_from = null; $periodo_to = null; $from = null; $toExclusive = null;

if ($mode === 'corte') {
    $corte_id = isset($_GET['corte_id']) ? (int)$_GET['corte_id'] : 0;
    if ($corte_id <= 0) { bad_request('corte_id requerido'); }
    $stmt = $conn->prepare('SELECT fecha_inicio, fecha_fin FROM cortes_almacen WHERE id = ? LIMIT 1');
    if (!$stmt) { bad_request('DB error: ' . $conn->error); }
    $stmt->bind_param('i', $corte_id);
    $stmt->execute();
    $res = $stmt->get_result();
    if (!$res || $res->num_rows === 0) { $stmt->close(); bad_request('Corte no encontrado'); }
    $row = $res->fetch_assoc();
    $stmt->close();
    $fi = $row['fecha_inicio'];
    $ff = $row['fecha_fin'] ?: date('Y-m-d');
    $periodo_from = substr($fi, 0, 10);
    $periodo_to = substr($ff, 0, 10);
    list($from, $toExclusive) = as_datetime_bounds($periodo_from, $periodo_to);
} else {
    $date_from = isset($_GET['date_from']) ? $_GET['date_from'] : '';
    $date_to   = isset($_GET['date_to']) ? $_GET['date_to'] : '';
    if (!$date_from || !$date_to) { bad_request('date_from y date_to requeridos'); }
    $periodo_from = substr($date_from, 0, 10);
    $periodo_to = substr($date_to, 0, 10);
    list($from, $toExclusive) = as_datetime_bounds($periodo_from, $periodo_to);
}

// Para cada id_entrada (lote) relacionado al insumo, calcular saldos y partidas
// 1) Entradas por lote
$entradas = [];
$stmtE = $conn->prepare('SELECT id AS id_entrada, fecha, cantidad FROM entradas_insumos WHERE insumo_id = ?');
if ($stmtE) {
    $stmtE->bind_param('i', $insumo_id);
    $stmtE->execute();
    $res = $stmtE->get_result();
    while ($r = $res->fetch_assoc()) { $entradas[(int)$r['id_entrada']] = ['fecha' => $r['fecha'], 'cantidad' => (float)$r['cantidad']]; }
    $stmtE->close();
}

// 2) Movimientos por lote y tipo dentro del periodo
$partidas = [];
$stmtM = $conn->prepare("SELECT id_entrada, tipo,
        SUM(CASE
              WHEN tipo='salida'   AND cantidad<0 THEN -cantidad
              WHEN tipo='traspaso' AND cantidad<0 THEN -cantidad
              ELSE 0
            END) AS qty_out,
        SUM(CASE
              WHEN tipo='ajuste'     THEN cantidad
              WHEN tipo='entrada'    THEN cantidad
              WHEN tipo='devolucion' THEN cantidad
              ELSE 0
            END) AS qty_in,
        SUM(CASE
              WHEN tipo='merma' AND cantidad>0 THEN cantidad
              WHEN tipo='merma' AND cantidad<0 THEN -cantidad
              ELSE 0
            END) AS qty_merma
    FROM movimientos_insumos
    WHERE insumo_id=? AND fecha>=? AND fecha<? AND id_entrada IS NOT NULL
    GROUP BY id_entrada, tipo");
if ($stmtM) {
    $stmtM->bind_param('iss', $insumo_id, $from, $toExclusive);
    $stmtM->execute();
    $res = $stmtM->get_result();
    while ($r = $res->fetch_assoc()) {
        $lot = (int)$r['id_entrada'];
        if (!isset($partidas[$lot])) { $partidas[$lot] = ['entradas' => 0.0, 'salidas' => 0.0, 'mermas' => 0.0, 'ajustes' => 0.0]; }
        $tipo = $r['tipo'];
        $in = (float)($r['qty_in'] ?? 0);
        $out = (float)($r['qty_out'] ?? 0);
        $mer = (float)($r['qty_merma'] ?? 0);
        if ($tipo === 'ajuste') { $partidas[$lot]['ajustes'] += $in; }
        elseif ($tipo === 'salida') { $partidas[$lot]['salidas'] += $out; }
        elseif ($tipo === 'traspaso') { $partidas[$lot]['salidas'] += $out; }
        elseif ($tipo === 'merma') { $partidas[$lot]['mermas'] += $mer; }
        else { $partidas[$lot]['entradas'] += $in; }
    }
    $stmtM->close();
}

// 3) Saldo inicial por lote (antes de from)
$saldo_ini = [];
$stmtSI = $conn->prepare("SELECT id_entrada,
        (SUM(CASE WHEN tipo='entrada' THEN cantidad WHEN tipo='devolucion' THEN cantidad WHEN tipo='ajuste' THEN cantidad ELSE 0 END)
         - SUM(CASE WHEN tipo IN ('salida','traspaso','merma') AND cantidad<0 THEN -cantidad ELSE 0 END)) AS saldo
    FROM movimientos_insumos
    WHERE insumo_id=? AND fecha < ? AND id_entrada IS NOT NULL
    GROUP BY id_entrada");
if ($stmtSI) {
    $stmtSI->bind_param('is', $insumo_id, $from);
    $stmtSI->execute();
    $res = $stmtSI->get_result();
    while ($r = $res->fetch_assoc()) { $saldo_ini[(int)$r['id_entrada']] = (float)($r['saldo'] ?? 0.0); }
    $stmtSI->close();
}

// 4) QRs asociados dentro del periodo
$qr_map = [];
$stmtQR = $conn->prepare("SELECT id_entrada, GROUP_CONCAT(DISTINCT id_qr ORDER BY id_qr SEPARATOR ',') AS qrs
    FROM movimientos_insumos WHERE insumo_id=? AND fecha>=? AND fecha<? AND id_entrada IS NOT NULL AND id_qr IS NOT NULL AND id_qr<>''
    GROUP BY id_entrada");
if ($stmtQR) {
    $stmtQR->bind_param('iss', $insumo_id, $from, $toExclusive);
    $stmtQR->execute();
    $res = $stmtQR->get_result();
    while ($r = $res->fetch_assoc()) { $qr_map[(int)$r['id_entrada']] = $r['qrs']; }
    $stmtQR->close();
}

// 5) Armar lotes
$lotes = [];
// Usar id_entrada que tenga entradas o partidas en periodo o saldo inicial distinto de 0
$id_entradas = array_unique(array_merge(array_keys($entradas), array_keys($partidas), array_keys($saldo_ini)));
foreach ($id_entradas as $idE) {
    $fec = isset($entradas[$idE]) ? substr($entradas[$idE]['fecha'], 0, 10) : null;
    $si = $saldo_ini[$idE] ?? 0.0;
    $en = $partidas[$idE]['entradas'] ?? 0.0;
    $sa = $partidas[$idE]['salidas'] ?? 0.0;
    $me = $partidas[$idE]['mermas'] ?? 0.0;
    $aj = $partidas[$idE]['ajustes'] ?? 0.0;
    $sf = $si + $en - $sa - $me + $aj;
    $qrs = isset($qr_map[$idE]) && $qr_map[$idE] !== null && $qr_map[$idE] !== '' ? explode(',', $qr_map[$idE]) : [];
    $lotes[] = [
        'id_entrada' => (int)$idE,
        'fecha' => $fec,
        'saldo_inicial' => round($si, 4),
        'entradas' => round($en, 4),
        'salidas' => round($sa, 4),
        'mermas' => round($me, 4),
        'ajustes' => round($aj, 4),
        'saldo_final' => round($sf, 4),
        'qrs' => $qrs,
    ];
}

// Ordenar por fecha de entrada (nulas al final)
usort($lotes, function($a,$b){ return strcmp($a['fecha'] ?? '9999-99-99', $b['fecha'] ?? '9999-99-99'); });

$resp = [ 'insumo_id' => $insumo_id, 'periodo' => [ 'from' => $periodo_from, 'to' => $periodo_to ], 'lotes' => $lotes ];
header('Content-Type: application/json; charset=utf-8');
echo json_encode($resp, JSON_UNESCAPED_UNICODE);
exit;

?>
