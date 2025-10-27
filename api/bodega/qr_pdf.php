<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/pdf_simple.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

if (!isset($_SESSION['usuario_id'])) {
    http_response_code(401);
    echo 'No autenticado';
    exit;
}

$usuario_id = (int)$_SESSION['usuario_id'];
$token = isset($_GET['token']) ? trim(substr($_GET['token'], 0, 64)) : '';
if ($token === '') {
    http_response_code(400);
    echo 'Token requerido';
    exit;
}

// Buscar QR
$stmt = $conn->prepare('SELECT id, token, json_data, creado_por, creado_en, pdf_envio FROM qrs_insumo WHERE token = ? LIMIT 1');
$stmt->bind_param('s', $token);
$stmt->execute();
$res = $stmt->get_result();
$qr = $res->fetch_assoc();
$stmt->close();
if (!$qr) {
    http_response_code(404);
    echo 'QR no encontrado';
    exit;
}

$idqr = (int)$qr['id'];
$pdf_rel = $qr['pdf_envio'];

// Si existe pdf_envio y el archivo está en disco, redirigir
if (false && $pdf_rel) {
    $pdf_abs = realpath(__DIR__ . '/../../' . $pdf_rel);
    if ($pdf_abs && file_exists($pdf_abs)) {
        // Log reimpresión
        $log = $conn->prepare('INSERT INTO logs_accion (usuario_id, modulo, accion, referencia_id) VALUES (?, ?, ?, ?)');
        if ($log) {
            $mod = 'bodega'; $accion = 'Reimpresion QR';
            $log->bind_param('issi', $usuario_id, $mod, $accion, $idqr);
            $log->execute(); $log->close();
        }
        header('Location: ../../' . $pdf_rel);
        exit;
    }
}

// Regenerar PDF si no existe
$jsonArr = json_decode($qr['json_data'] ?? '[]', true);
if (!is_array($jsonArr)) { $jsonArr = []; }

// Obtener nombre usuario creador
$creado_por_nombre = '';
if (!empty($qr['creado_por'])) {
    $st = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ?');
    $st->bind_param('i', $qr['creado_por']);
    $st->execute();
    $st->bind_result($creado_por_nombre);
    $st->fetch();
    $st->close();
}

// Asegurar ruta de QR imagen
$dirQrPublic = __DIR__ . '/../../archivos/qr';
if (!is_dir($dirQrPublic)) { mkdir($dirQrPublic, 0777, true); }
$public_qr_rel = 'archivos/qr/qr_' . $token . '.png';
$public_qr_path = __DIR__ . '/../../' . $public_qr_rel;
if (!file_exists($public_qr_path)) {
    // Generar URL para recepción (misma de generar_qr.php)
    if (!defined('URL_BASE_QR')) {
        define('URL_BASE_QR', 'http://192.168.1.4080');
    }
    if (!defined('QR_ECLEVEL_H')) { define('QR_ECLEVEL_H', 'H'); }
    $urlQR = URL_BASE_QR . '/CDI/vistas/bodega/recepcion_qr.php?token=' . $token;
    QRcode::png($urlQR, $public_qr_path, QR_ECLEVEL_H, 8, 2);
}

// Consultar lotes por insumo para este QR
$insumosMov = [];
$sqlMov = $conn->prepare(
    "SELECT m.insumo_id, i.nombre AS insumo_nombre, i.unidad AS unidad, m.id_entrada AS lote_id, ei.fecha AS lote_fecha, ABS(m.cantidad) AS cantidad_lote, m.tipo
     FROM movimientos_insumos m
     JOIN insumos i ON i.id = m.insumo_id
     LEFT JOIN entradas_insumos ei ON ei.id = m.id_entrada
     WHERE m.id_qr = ? AND m.tipo IN ('salida','traspaso','merma')
     ORDER BY m.insumo_id, ei.fecha, m.id_entrada, m.id"
);
if ($sqlMov) {
    $sqlMov->bind_param('i', $idqr);
    if ($sqlMov->execute()) {
        $rs = $sqlMov->get_result();
        while ($row = $rs->fetch_assoc()) {
            $k = (int)$row['insumo_id'];
            if (!isset($insumosMov[$k])) {
                $insumosMov[$k] = [
                    'nombre' => $row['insumo_nombre'],
                    'unidad' => $row['unidad'],
                    'lotes' => [],
                    'total_por_qr' => 0.0,
                ];
            }
            $insumosMov[$k]['lotes'][] = [
                'lote_id' => isset($row['lote_id']) ? (int)$row['lote_id'] : 0,
                'fecha'   => $row['lote_fecha'],
                'cantidad'=> (float)$row['cantidad_lote'],
                'tipo'    => $row['tipo'],
            ];
            $insumosMov[$k]['total_por_qr'] += (float)$row['cantidad_lote'];
        }
    }
    $sqlMov->close();
}

// Ordenar por agrupamiento (reque) y luego por nombre
$requeById = [];
$ids = [];
foreach ($jsonArr as $s) { if (isset($s['id'])) { $ids[] = (int)$s['id']; } }
$ids = array_values(array_unique(array_filter($ids, function($v){ return $v>0; })));
if (!empty($ids)) {
    $in = implode(',', array_fill(0, count($ids), '?'));
    $types = str_repeat('i', count($ids));
    $stR = $conn->prepare("SELECT id, reque FROM insumos WHERE id IN ($in)");
    if ($stR) {
        $stR->bind_param($types, ...$ids);
        if ($stR->execute()) {
            $rsR = $stR->get_result();
            while ($r = $rsR->fetch_assoc()) { $requeById[(int)$r['id']] = (string)$r['reque']; }
        }
        $stR->close();
    }
}
$ordenReque = ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros',''];
$idxReque = array_flip($ordenReque);
$jsonSorted = $jsonArr;
usort($jsonSorted, function($a, $b) use ($requeById, $idxReque) {
    $ia = isset($a['id']) ? (int)$a['id'] : 0;
    $ib = isset($b['id']) ? (int)$b['id'] : 0;
    $ra = $requeById[$ia] ?? '';
    $rb = $requeById[$ib] ?? '';
    $oa = $idxReque[$ra] ?? PHP_INT_MAX;
    $ob = $idxReque[$rb] ?? PHP_INT_MAX;
    if ($oa === $ob) {
        $na = (string)($a['nombre'] ?? '');
        $nb = (string)($b['nombre'] ?? '');
        return strcasecmp($na, $nb);
    }
    return $oa <=> $ob;
});

// Armar items (ya ordenados)
$items = [];
$lastReque = null;
foreach ($jsonSorted as $s) {
    $iid = isset($s['id']) ? (int)$s['id'] : 0;
    $curReque = $requeById[$iid] ?? '';
    if ($curReque !== $lastReque) {
        $items[] = [ 'section' => $curReque ];
        $lastReque = $curReque;
    }
    $solicitada = isset($s['cantidad']) ? (float)$s['cantidad'] : 0.0;
    $unidad = $s['unidad'] ?? '';
    $nombre = $s['nombre'] ?? '';
    $aplicado = isset($insumosMov[$iid]) ? (float)$insumosMov[$iid]['total_por_qr'] : 0.0;

    $left = $nombre . ' - ' . rtrim(rtrim(number_format($solicitada, 2, '.', ''), '0'), '.') . ' ' . $unidad;
    if (abs($aplicado - $solicitada) > 0.00001) {
        $left .= ' (aplicado ' . rtrim(rtrim(number_format($aplicado, 2, '.', ''), '0'), '.') . ' de ' . rtrim(rtrim(number_format($solicitada, 2, '.', ''), '0'), '.') . ')';
    }

    $right = [];
    $right[] = 'Lotes de salida:';
    $right[] = 'ID | Fecha | Cant.';
    if (isset($insumosMov[$iid]) && count($insumosMov[$iid]['lotes']) > 0) {
        foreach ($insumosMov[$iid]['lotes'] as $l) {
            $idTxt = '#' . (int)$l['lote_id'];
            $fTxt  = $l['fecha'] ? date('Y-m-d H:i', strtotime($l['fecha'])) : '-';
            $cTxt  = rtrim(rtrim(number_format((float)$l['cantidad'], 2, '.', ''), '0'), '.');
            $right[] = $idTxt . ' | ' . $fTxt . ' | ' . $cTxt;
        }
    } else {
        $right[] = '— pendiente de surtir —';
    }

    $items[] = [ 'left' => $left, 'right' => $right ];
}

// Header y paths
$headerLines = [
    'Fecha: ' . date('Y-m-d H:i', strtotime($qr['creado_en'] ?? date('Y-m-d H:i'))),
    'Entregado por: ' . ($creado_por_nombre ?: '—'),
];

$dirPdf = __DIR__ . '/../../archivos/bodega/pdfs';
if (!is_dir($dirPdf)) { mkdir($dirPdf, 0777, true); }
$pdf_rel = 'archivos/bodega/pdfs/qr_' . $token . '.pdf';
$pdf_path = __DIR__ . '/../../' . $pdf_rel;

// Generar
generar_pdf_envio_qr_detallado($pdf_path, 'Salida de insumos', $headerLines, $public_qr_path, $items);

// Actualizar referencia y log
$up = $conn->prepare('UPDATE qrs_insumo SET pdf_envio = ? WHERE id = ?');
if ($up) { $up->bind_param('si', $pdf_rel, $idqr); $up->execute(); $up->close(); }
$log = $conn->prepare('INSERT INTO logs_accion (usuario_id, modulo, accion, referencia_id) VALUES (?, ?, ?, ?)');
if ($log) { $mod = 'bodega'; $accion = 'Reimpresion QR'; $log->bind_param('issi', $usuario_id, $mod, $accion, $idqr); $log->execute(); $log->close(); }

header('Location: ../../' . $pdf_rel);
exit;
?>
