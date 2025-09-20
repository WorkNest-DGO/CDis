<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

$token = isset($_GET['token']) ? trim(substr($_GET['token'], 0, 64)) : '';
if ($token === '') {
    error('Token requerido');
}

// Obtener QR
$stmt = $conn->prepare('SELECT id, token, json_data, estado, creado_en, creado_por FROM qrs_insumo WHERE token = ? LIMIT 1');
$stmt->bind_param('s', $token);
$stmt->execute();
$res = $stmt->get_result();
$qr = $res->fetch_assoc();
$stmt->close();
if (!$qr) {
    error('QR no encontrado');
}

$id_qr = (int)$qr['id'];
$json = json_decode($qr['json_data'] ?? '[]', true);
if (!is_array($json)) { $json = []; }

// Traer envíos (traspaso) y devoluciones ya registradas
$sql = "SELECT mi.insumo_id, i.nombre, i.unidad, mi.id_entrada, ABS(mi.cantidad) AS cant_abs,
               CASE WHEN mi.tipo='traspaso' THEN 'traspaso' ELSE 'devolucion' END AS clase,
               ei.fecha AS fecha_entrada, ei.valor_unitario
        FROM movimientos_insumos mi
        JOIN insumos i ON i.id = mi.insumo_id
        LEFT JOIN entradas_insumos ei ON ei.id = mi.id_entrada
        WHERE mi.id_qr = ? AND mi.tipo IN ('traspaso','devolucion')
        ORDER BY i.nombre, ei.fecha, mi.id";
$st = $conn->prepare($sql);
$st->bind_param('i', $id_qr);
$st->execute();
$rs = $st->get_result();

$porEntrada = [];
$resumen = [];
while ($r = $rs->fetch_assoc()) {
    $iid = (int)$r['insumo_id'];
    $idE = isset($r['id_entrada']) ? (int)$r['id_entrada'] : 0;
    $cl = $r['clase'];
    $cant = (float)$r['cant_abs'];
    if (!isset($porEntrada[$iid][$idE])) {
        $porEntrada[$iid][$idE] = [
            'insumo_id' => $iid,
            'id_entrada' => $idE,
            'enviado' => 0.0,
            'devuelto' => 0.0,
            'fecha_entrada' => $r['fecha_entrada'],
            'valor_unitario' => isset($r['valor_unitario']) ? (float)$r['valor_unitario'] : null,
        ];
    }
    if ($cl === 'traspaso') {
        $porEntrada[$iid][$idE]['enviado'] += $cant;
    } else {
        $porEntrada[$iid][$idE]['devuelto'] += $cant;
    }
}
$st->close();

// Armar salida por insumo
$items = [];
// Índice del JSON por orden
foreach ($json as $jn) {
    $iid = (int)($jn['id'] ?? 0);
    if ($iid <= 0) continue;
    $enviado = 0.0; $devuelto = 0.0;
    $lotes = [];
    if (isset($porEntrada[$iid])) {
        foreach ($porEntrada[$iid] as $idE => $info) {
            $pend = max(0.0, (float)$info['enviado'] - (float)$info['devuelto']);
            $enviado += (float)$info['enviado'];
            $devuelto += (float)$info['devuelto'];
            $lotes[] = [
                'id_entrada' => $idE,
                'enviado' => (float)$info['enviado'],
                'devuelto' => (float)$info['devuelto'],
                'pendiente' => $pend,
                'fecha_entrada' => $info['fecha_entrada'],
                'valor_unitario' => $info['valor_unitario'],
            ];
        }
    }
    $items[] = [
        'insumo_id' => $iid,
        'nombre' => $jn['nombre'] ?? '',
        'unidad' => $jn['unidad'] ?? '',
        'enviado' => $enviado,
        'devuelto' => $devuelto,
        'pendiente' => max(0.0, $enviado - $devuelto),
        'lotes' => $lotes,
        'solicitado_json' => (float)($jn['cantidad'] ?? 0),
    ];
}

success([
    'qr' => [
        'id' => $qr['id'],
        'token' => $qr['token'],
        'estado' => $qr['estado'],
        'creado_en' => $qr['creado_en'],
        'creado_por' => $qr['creado_por'],
    ],
    'items' => $items,
]);
?>

