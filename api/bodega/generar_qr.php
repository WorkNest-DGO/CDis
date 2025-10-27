<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/pdf_simple.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

// Base de la URL donde se alojará el sistema para los códigos QR
if (!defined('URL_BASE_QR')) {
    define('URL_BASE_QR', 'https://tokyosushiprime.com');
}

// Constante utilizada por la librería de QR
if (!defined('QR_ECLEVEL_H')) {
    define('QR_ECLEVEL_H', 'H');
}

if (!function_exists('generarToken')) {
    function generarToken() {
        return bin2hex(random_bytes(16));
    }
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['insumos']) || !is_array($input['insumos'])) {
    error('Datos inválidos');
}

$usuario_id = (int)$_SESSION['usuario_id'];
$seleccionados = [];
foreach ($input['insumos'] as $d) {
    $id = isset($d['id']) ? (int)$d['id'] : 0;
    $cant = isset($d['cantidad']) ? (float)$d['cantidad'] : 0;
    $precio = isset($d['precio_unitario']) ? (float)$d['precio_unitario'] : 0;
    if ($id > 0 && $cant > 0) {
        $q = $conn->prepare('SELECT nombre, unidad, existencia FROM insumos WHERE id = ?');
        if ($q) {
            $q->bind_param('i', $id);
            $q->execute();
            $res = $q->get_result();
            if ($row = $res->fetch_assoc()) {
                if ($cant > $row['existencia']) {
                    $q->close();
                    error('Cantidad mayor a existencia para ' . $row['nombre']);
                }
                $seleccionados[] = [
                    'id' => $id,
                    'nombre' => $row['nombre'],
                    'unidad' => $row['unidad'],
                    'cantidad' => $cant,
                    'precio_unitario' => $precio
                ];
            }
            $q->close();
        }
    }
}
if (count($seleccionados) === 0) {
    error('No se seleccionaron insumos');
}

$stmtU = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ?');
$stmtU->bind_param('i', $usuario_id);
$stmtU->execute();
$stmtU->bind_result($usuario_nombre);
$stmtU->fetch();
$stmtU->close();

$token = generarToken();
$conn->begin_transaction();
try {
    // Resolver URL base para el QR desde la entrada y validarla contra la BD (direccion_qr)
    $__base = defined('URL_BASE_QR') ? URL_BASE_QR : 'https://tokyosushiprime.com';
    if (isset($input['url_base']) && is_string($input['url_base']) && trim($input['url_base']) !== '') {
        $cand = trim($input['url_base']);
        $qdir = $conn->prepare('SELECT ip FROM direccion_qr WHERE ip = ? LIMIT 1');
        if ($qdir) {
            $qdir->bind_param('s', $cand);
            if ($qdir->execute()) {
                $rdir = $qdir->get_result();
                if ($rdir && ($row = $rdir->fetch_assoc()) && !empty($row['ip'])) {
                    $__base = $row['ip'];
                }
            }
            $qdir->close();
        }
    }
    $urlQR = $__base . '/CDI/vistas/bodega/recepcion_qr.php?token=' . $token;
    $json = json_encode($seleccionados, JSON_UNESCAPED_UNICODE);
    $ins = $conn->prepare('INSERT INTO qrs_insumo (token, json_data, estado, creado_por, creado_en) VALUES (?, ?, "pendiente", ?, NOW())');
    if (!$ins) throw new Exception($conn->error);
    $ins->bind_param('ssi', $token, $json, $usuario_id);
    if (!$ins->execute()) throw new Exception($ins->error);
    $idqr = $ins->insert_id;
    $ins->close();

    // registrar encabezado de despacho
    $desp = $conn->prepare('INSERT INTO despachos (sucursal_id, usuario_id, qr_token) VALUES (NULL, ?, ?)');
    if ($desp) {
        $desp->bind_param('is', $usuario_id, $token);
        $desp->execute();
        $despacho_id = $desp->insert_id;
        $desp->close();
    } else {
        $despacho_id = null;
    }

    $updExist = $conn->prepare('UPDATE insumos SET existencia = existencia - ? WHERE id = ?');
    // Insert de movimiento por lote consumido (FIFO) manteniendo compatibilidad con qr_token y agregando id_qr e id_entrada
    $movLote = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, usuario_destino_id, insumo_id, id_entrada, cantidad, observacion, fecha, qr_token, id_qr) VALUES ('traspaso', ?, NULL, ?, ?, ?, 'Enviado por QR a sucursal', NOW(), ?, ?)");
    $det = null;
    if ($despacho_id) {
        $det = $conn->prepare('INSERT INTO despachos_detalle (despacho_id, insumo_id, cantidad, unidad, precio_unitario) VALUES (?, ?, ?, ?, 0)');
    }

    foreach ($seleccionados as $s) {
        // FIFO: seleccionar lotes disponibles para el insumo y bloquearlos
        $restante = (float)$s['cantidad'];
        $selLotes = $conn->prepare('SELECT id, cantidad_actual FROM entradas_insumos WHERE insumo_id = ? AND cantidad_actual > 0 ORDER BY fecha ASC, id ASC FOR UPDATE');
        if (!$selLotes) throw new Exception($conn->error);
        $selLotes->bind_param('i', $s['id']);
        if (!$selLotes->execute()) throw new Exception($selLotes->error);
        $resLotes = $selLotes->get_result();

        // Preparar update de lote
        $updLote = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual - ? WHERE id = ?');
        if (!$updLote) throw new Exception($conn->error);

        while ($restante > 0 && ($l = $resLotes->fetch_assoc())) {
            $idEntrada = (int)$l['id'];
            $disp = (float)$l['cantidad_actual'];
            if ($disp <= 0) continue;
            $consumo = $restante < $disp ? $restante : $disp;

            // Descontar del lote
            $updLote->bind_param('di', $consumo, $idEntrada);
            if (!$updLote->execute()) throw new Exception($updLote->error);

            // Registrar movimiento por lote (cantidad con signo de salida)
            $consumoNeg = -$consumo;
            $movLote->bind_param('iiidsi', $usuario_id, $s['id'], $idEntrada, $consumoNeg, $token, $idqr);
            // Tipos: i=usuario_id, i=insumo_id, i=id_entrada, d=cantidad, s=qr_token, i=id_qr
            if (!$movLote->execute()) throw new Exception($movLote->error);

            $restante -= $consumo;
        }
        $updLote->close();
        $selLotes->close();

        if ($restante > 0.000001) {
            throw new Exception('stock insuficiente por lotes');
        }

        // Ajustar existencia global una sola vez por insumo
        $updExist->bind_param('di', $s['cantidad'], $s['id']);
        if (!$updExist->execute()) throw new Exception($updExist->error);

        if ($det) {
            $det->bind_param('iids', $despacho_id, $s['id'], $s['cantidad'], $s['unidad']);
            if (!$det->execute()) throw new Exception($det->error);
        }
    }
    $updExist->close();
    $movLote->close();
    if ($det) $det->close();

    $conn->commit();
} catch (Exception $e) {
    $conn->rollback();
    $msg = (string)$e->getMessage();
    if (stripos($msg, 'stock insuficiente por lotes') !== false) {
        error($msg);
    }
    error('Error al guardar');
}

$dirPdf = __DIR__ . '/../../archivos/bodega/pdfs';
if (!is_dir($dirPdf)) {
    mkdir($dirPdf, 0777, true);
}
$dirQrPublic = __DIR__ . '/../../archivos/qr';
if (!is_dir($dirQrPublic)) {
    mkdir($dirQrPublic, 0777, true);
}


$pdf_rel = 'archivos/bodega/pdfs/qr_' . $token . '.pdf';
$pdf_path = __DIR__ . '/../../' . $pdf_rel;
$public_qr_rel = 'archivos/qr/qr_' . $token . '.png';
$public_qr_path = __DIR__ . '/../../' . $public_qr_rel;

QRcode::png($urlQR, $public_qr_path, QR_ECLEVEL_H, 8, 2);
if (!file_exists($public_qr_path)) {
    error('No se pudo generar el código QR');
}

$lineas = [];
$lineas[] = 'Fecha: ' . date('Y-m-d H:i');
$lineas[] = 'Entregado por: ' . $usuario_nombre;
foreach ($seleccionados as $s) {
    $lineas[] = $s['nombre'] . ' - ' . $s['cantidad'] . ' ' . $s['unidad'];
}

// Encabezado del PDF (para layout)
$headerLines = [
    'Fecha: ' . date('Y-m-d H:i'),
    'Entregado por: ' . $usuario_nombre,
];

// Consultar lotes por insumo ligados a este QR
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

// Obtener 'reque' de insumos seleccionados para ordenar por agrupamiento
$requeById = [];
if (!empty($seleccionados)) {
    $ids = array_map(function($x){ return (int)$x['id']; }, $seleccionados);
    $ids = array_values(array_unique(array_filter($ids, function($v){ return $v > 0; })));
    if (!empty($ids)) {
        $in  = implode(',', array_fill(0, count($ids), '?'));
        $types = str_repeat('i', count($ids));
        $stmtReq = $conn->prepare("SELECT id, reque FROM insumos WHERE id IN ($in)");
        if ($stmtReq) {
            $stmtReq->bind_param($types, ...$ids);
            if ($stmtReq->execute()) {
                $rs = $stmtReq->get_result();
                while ($r = $rs->fetch_assoc()) {
                    $requeById[(int)$r['id']] = (string)$r['reque'];
                }
            }
            $stmtReq->close();
        }
    }
}

// Orden deseado por agrupamiento (reque)
$ordenReque = ['Zona Barra','Bebidas','Refrigerdor','Articulos_de_limpieza','Plasticos y otros',''];
$idxReque = array_flip($ordenReque);

// Construir items para PDF ordenados por reque y nombre
$items = [];
$seleccionadosOrdenados = $seleccionados;
usort($seleccionadosOrdenados, function($a, $b) use ($requeById, $idxReque) {
    $ra = $requeById[(int)$a['id']] ?? '';
    $rb = $requeById[(int)$b['id']] ?? '';
    $ia = $idxReque[$ra] ?? PHP_INT_MAX;
    $ib = $idxReque[$rb] ?? PHP_INT_MAX;
    if ($ia === $ib) {
        return strcasecmp((string)$a['nombre'], (string)$b['nombre']);
    }
    return $ia <=> $ib;
});

$lastReque = null;
foreach ($seleccionadosOrdenados as $s) {
    $iid = (int)$s['id'];
    $curReque = $requeById[$iid] ?? '';
    if ($curReque !== $lastReque) {
        $items[] = [ 'section' => $curReque ];
        $lastReque = $curReque;
    }
    $solicitada = (float)$s['cantidad'];
    $unidad = $s['unidad'];
    $nombre = $s['nombre'];
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

// Generar PDF detallado (QR bajo el título + dos columnas)
generar_pdf_envio_qr_detallado($pdf_path, 'Salida de insumos', $headerLines, $public_qr_path, $items);
if (!file_exists($pdf_path)) {
    error('No se pudo generar el PDF');
}

$up = $conn->prepare('UPDATE qrs_insumo SET pdf_envio = ? WHERE id = ?');
$up->bind_param('si', $pdf_rel, $idqr);
$up->execute();
$up->close();

$log = $conn->prepare('INSERT INTO logs_accion (usuario_id, modulo, accion, referencia_id) VALUES (?, ?, ?, ?)');
if ($log) {
    $mod = 'bodega';
    $accion = 'Generacion QR';
    $log->bind_param('issi', $usuario_id, $mod, $accion, $idqr);
    $log->execute();
    $log->close();
}

$qr_url = 'archivos/qr/qr_' . $token . '.png';
$pdf_url = 'archivos/bodega/pdfs/qr_' . $token . '.pdf';

header('Content-Type: application/json');
echo json_encode([
  'success' => true,
  'resultado' => [
    'token' => $token,
    'qr_url' => $qr_url,
    'pdf_url' => $pdf_url,
  ]
]);

?>

