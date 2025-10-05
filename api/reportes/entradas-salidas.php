<?php
// Reporte de Entradas/Salidas de Insumos
// GET params:
// - mode = range|corte (default: range)
// - date_from, date_to (YYYY-MM-DD) si mode=range
// - corte_id si mode=corte
// - devoluciones_en_entradas = 0|1 (solo presentación)
// - format = json|csv|pdf (csv genera descarga; pdf responde 501 por ahora)

require_once __DIR__ . '/../../config/db.php';

header('Access-Control-Allow-Origin: *');

function bad_request($msg) {
    http_response_code(400);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

function not_implemented($msg) {
    http_response_code(501);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

function as_datetime_bounds($date_from, $date_to) {
    // Normaliza a [from, to+1d) (to exclusivo)
    $from = $date_from . ' 00:00:00';
    // Manejar edge si ya trae hora
    if (preg_match('/\d{2}:\d{2}:\d{2}$/', $date_from)) {
        $from = $date_from;
    }
    $toDate = new DateTime($date_to);
    // Si ya viene con hora, no sumar 1d directo: cortar fecha y luego +1d
    if (preg_match('/\d{2}:\d{2}:\d{2}$/', $date_to)) {
        $toDate = new DateTime(substr($date_to, 0, 10));
    }
    $toDate->modify('+1 day');
    $to = $toDate->format('Y-m-d 00:00:00');
    return [$from, $to];
}

// 1) Leer params
$mode = isset($_GET['mode']) ? $_GET['mode'] : 'range';
$format = isset($_GET['format']) ? strtolower($_GET['format']) : 'json';
$devo_in_entradas = isset($_GET['devoluciones_en_entradas']) ? (int)$_GET['devoluciones_en_entradas'] : 0;

// 2) Determinar periodo
$periodo_from = null; $periodo_to_inclusive = null; // inclusive visualmente
$from = null; $toExclusive = null;                 // para consulta

if ($mode === 'corte') {
    $corte_id = isset($_GET['corte_id']) ? (int)$_GET['corte_id'] : 0;
    if ($corte_id <= 0) { bad_request('corte_id requerido'); }
    $stmt = $conn->prepare('SELECT fecha_inicio, fecha_fin FROM cortes_almacen WHERE id = ? LIMIT 1');
    if (!$stmt) { bad_request('Error DB: ' . $conn->error); }
    $stmt->bind_param('i', $corte_id);
    $stmt->execute();
    $res = $stmt->get_result();
    if (!$res || $res->num_rows === 0) { $stmt->close(); bad_request('Corte no encontrado'); }
    $row = $res->fetch_assoc();
    $stmt->close();
    $fi = $row['fecha_inicio'];
    $ff = $row['fecha_fin'];
    if (!$fi) { bad_request('Corte sin fecha_inicio'); }
    if (!$ff) { // si abierto, usar hoy como fin visual
        $ff = date('Y-m-d');
    }
    $periodo_from = substr($fi, 0, 10);
    $periodo_to_inclusive = substr($ff, 0, 10);
    list($from, $toExclusive) = as_datetime_bounds($periodo_from, $periodo_to_inclusive);
} else { // range
    $date_from = isset($_GET['date_from']) ? $_GET['date_from'] : '';
    $date_to   = isset($_GET['date_to']) ? $_GET['date_to'] : '';
    if (!$date_from || !$date_to) { bad_request('date_from y date_to requeridos'); }
    // validar formato simple
    if (!preg_match('/^\d{4}-\d{2}-\d{2}/', $date_from) || !preg_match('/^\d{4}-\d{2}-\d{2}/', $date_to)) {
        bad_request('Formato de fecha inválido');
    }
    $periodo_from = substr($date_from, 0, 10);
    $periodo_to_inclusive = substr($date_to, 0, 10);
    list($from, $toExclusive) = as_datetime_bounds($periodo_from, $periodo_to_inclusive);
}

// Seguridad mínima: limitar periodo a 1 año
try {
    $fA = new DateTime($periodo_from);
    $tA = new DateTime($periodo_to_inclusive);
    $diff = $fA->diff($tA)->days;
    if ($diff > 370) { bad_request('Rango demasiado amplio (> 1 año)'); }
} catch (Exception $e) {}

// 3) Preparar agregaciones (sin CTE)
function fetch_keyed_sum($conn, $sql, $types, $params) {
    $stmt = $conn->prepare($sql);
    if (!$stmt) { bad_request('DB error: ' . $conn->error); }
    if ($types !== '') { $stmt->bind_param($types, ...$params); }
    if (!$stmt->execute()) { $stmt->close(); bad_request('DB exec error: ' . $stmt->error); }
    $res = $stmt->get_result();
    $out = [];
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $out[(int)$row['insumo_id']] = (float)$row['qty'];
        }
    }
    $stmt->close();
    return $out;
}

// Insumos
$insumos = [];
$resI = $conn->query('SELECT id, nombre, unidad FROM insumos');
if ($resI) {
    while ($r = $resI->fetch_assoc()) {
        $insumos[(int)$r['id']] = ['insumo_id' => (int)$r['id'], 'insumo' => $r['nombre'], 'unidad' => $r['unidad']];
    }
}

// Entradas de compra
$E_COMPRA = fetch_keyed_sum(
    $conn,
    'SELECT insumo_id, SUM(cantidad) qty FROM entradas_insumos WHERE fecha >= ? AND fecha < ? GROUP BY insumo_id',
    'ss', [$from, $toExclusive]
);
$E_COMPRA_ACUM = fetch_keyed_sum(
    $conn,
    'SELECT insumo_id, SUM(cantidad) qty FROM entradas_insumos WHERE fecha < ? GROUP BY insumo_id',
    's', [$from]
);

// Movimientos periodo
$MOVI_OTRAS = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(cantidad) qty FROM movimientos_insumos WHERE tipo='entrada' AND fecha >= ? AND fecha < ? GROUP BY insumo_id",
    'ss', [$from, $toExclusive]
);
$MOVI_DEV = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(cantidad) qty FROM movimientos_insumos WHERE tipo='devolucion' AND fecha >= ? AND fecha < ? GROUP BY insumo_id",
    'ss', [$from, $toExclusive]
);
$MOVI_SAL = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(-cantidad) qty FROM movimientos_insumos WHERE tipo='salida' AND cantidad<0 AND fecha >= ? AND fecha < ? GROUP BY insumo_id",
    'ss', [$from, $toExclusive]
);
$MOVI_TRASP = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(-cantidad) qty FROM movimientos_insumos WHERE tipo='traspaso' AND cantidad<0 AND fecha >= ? AND fecha < ? GROUP BY insumo_id",
    'ss', [$from, $toExclusive]
);
$MOVI_MERMA = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(-cantidad) qty FROM movimientos_insumos WHERE tipo='merma' AND cantidad<0 AND fecha >= ? AND fecha < ? GROUP BY insumo_id",
    'ss', [$from, $toExclusive]
);
// Ajustes ±
$MOVI_AJUSTE = [];
$stmtAj = $conn->prepare("SELECT insumo_id, SUM(cantidad) qty FROM movimientos_insumos WHERE tipo='ajuste' AND fecha >= ? AND fecha < ? GROUP BY insumo_id");
if ($stmtAj) {
    $stmtAj->bind_param('ss', $from, $toExclusive);
    $stmtAj->execute();
    $resAj = $stmtAj->get_result();
    while ($row = $resAj->fetch_assoc()) { $MOVI_AJUSTE[(int)$row['insumo_id']] = (float)$row['qty']; }
    $stmtAj->close();
}

// Movimientos acumulados antes de from
$ACUM_OTRAS = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(cantidad) qty FROM movimientos_insumos WHERE tipo='entrada' AND fecha < ? GROUP BY insumo_id",
    's', [$from]
);
$ACUM_DEV = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(cantidad) qty FROM movimientos_insumos WHERE tipo='devolucion' AND fecha < ? GROUP BY insumo_id",
    's', [$from]
);
$ACUM_SAL = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(-cantidad) qty FROM movimientos_insumos WHERE tipo='salida' AND cantidad<0 AND fecha < ? GROUP BY insumo_id",
    's', [$from]
);
$ACUM_TRASP = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(-cantidad) qty FROM movimientos_insumos WHERE tipo='traspaso' AND cantidad<0 AND fecha < ? GROUP BY insumo_id",
    's', [$from]
);
$ACUM_MERMA = fetch_keyed_sum($conn,
    "SELECT insumo_id, SUM(-cantidad) qty FROM movimientos_insumos WHERE tipo='merma' AND cantidad<0 AND fecha < ? GROUP BY insumo_id",
    's', [$from]
);
$ACUM_AJUSTE = [];
$stmtAj2 = $conn->prepare("SELECT insumo_id, SUM(cantidad) qty FROM movimientos_insumos WHERE tipo='ajuste' AND fecha < ? GROUP BY insumo_id");
if ($stmtAj2) {
    $stmtAj2->bind_param('s', $from);
    $stmtAj2->execute();
    $resAj2 = $stmtAj2->get_result();
    while ($row = $resAj2->fetch_assoc()) { $ACUM_AJUSTE[(int)$row['insumo_id']] = (float)$row['qty']; }
    $stmtAj2->close();
}

// Warnings: salidas/mermas/traspasos sin id_entrada
$warnings = [];
$stmtW = $conn->prepare("SELECT insumo_id, COUNT(*) c FROM movimientos_insumos WHERE tipo IN ('salida','merma','traspaso') AND (id_entrada IS NULL OR id_entrada = 0) AND fecha >= ? AND fecha < ? GROUP BY insumo_id");
if ($stmtW) {
    $stmtW->bind_param('ss', $from, $toExclusive);
    $stmtW->execute();
    $resW = $stmtW->get_result();
    while ($w = $resW->fetch_assoc()) {
        $warnings[] = ['insumo_id' => (int)$w['insumo_id'], 'msg' => 'Movimientos sin id_entrada en salidas; usando promedio móvil.'];
    }
    $stmtW->close();
}

// 4) Construcción de filas y totales
$rows = [];
$tot = [
    'inicial' => 0.0,
    'entradas_compra' => 0.0,
    'devoluciones' => 0.0,
    'otras_entradas' => 0.0,
    'salidas' => 0.0,
    'traspasos_salida' => 0.0,
    'mermas' => 0.0,
    'ajustes' => 0.0,
    'final' => 0.0,
];

foreach ($insumos as $id => $info) {
    $inicial =
        ($E_COMPRA_ACUM[$id] ?? 0) +
        ($ACUM_OTRAS[$id] ?? 0) +
        ($ACUM_DEV[$id] ?? 0) -
        ($ACUM_SAL[$id] ?? 0) -
        ($ACUM_TRASP[$id] ?? 0) -
        ($ACUM_MERMA[$id] ?? 0) +
        ($ACUM_AJUSTE[$id] ?? 0);

    $entradas_compra = $E_COMPRA[$id] ?? 0;
    $devoluciones = $MOVI_DEV[$id] ?? 0;
    $otras_entradas = $MOVI_OTRAS[$id] ?? 0;
    $salidas = $MOVI_SAL[$id] ?? 0;
    $traspasos_salida = $MOVI_TRASP[$id] ?? 0;
    $mermas = $MOVI_MERMA[$id] ?? 0;
    $ajustes = $MOVI_AJUSTE[$id] ?? 0;

    $final = $inicial + $entradas_compra + $devoluciones + $otras_entradas - $salidas - $traspasos_salida - $mermas + $ajustes;

    $row = [
        'insumo_id' => $id,
        'insumo' => $info['insumo'],
        'unidad' => $info['unidad'],
        'inicial' => round((float)$inicial, 4),
        'entradas_compra' => round((float)$entradas_compra, 4),
        'devoluciones' => round((float)$devoluciones, 4),
        'otras_entradas' => round((float)$otras_entradas, 4),
        'salidas' => round((float)$salidas, 4),
        'traspasos_salida' => round((float)$traspasos_salida, 4),
        'mermas' => round((float)$mermas, 4),
        'ajustes' => round((float)$ajustes, 4),
        'final' => round((float)$final, 4),
    ];

    if ($devo_in_entradas === 1) {
        $row['entradas_compra'] = round($row['entradas_compra'] + $row['devoluciones'], 4);
    }

    foreach ($tot as $k => $v) { $tot[$k] += $row[$k]; }
    $rows[] = $row;
}

$payload = [
    'mode' => $mode,
    'periodo' => [ 'from' => $periodo_from, 'to' => $periodo_to_inclusive ],
    'rows' => $rows,
    'totales' => array_map(function($v){ return round((float)$v, 4); }, $tot),
    'warnings' => $warnings,
];

if ($format === 'csv') {
    $fn = 'reporte_entradas_salidas_' . $periodo_from . '_a_' . $periodo_to_inclusive . '.csv';
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename=' . $fn);
    $out = fopen('php://output', 'w');
    fputcsv($out, ['Insumo','Unidad','Inicial','Entradas(Compras)','Devoluciones','Otras entradas','Salidas','Traspasos (salida)','Mermas','Ajustes ±','Final']);
    foreach ($rows as $r) {
        fputcsv($out, [
            $r['insumo'], $r['unidad'], $r['inicial'], $r['entradas_compra'], $r['devoluciones'], $r['otras_entradas'], $r['salidas'], $r['traspasos_salida'], $r['mermas'], $r['ajustes'], $r['final']
        ]);
    }
    fputcsv($out, ['TOTAL','','',$tot['entradas_compra'],$tot['devoluciones'],$tot['otras_entradas'],$tot['salidas'],$tot['traspasos_salida'],$tot['mermas'],$tot['ajustes'],$tot['final']]);
    fclose($out);
    exit;
} elseif ($format === 'pdf') {
    not_implemented('Exportación a PDF pendiente');
} else {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

?>

