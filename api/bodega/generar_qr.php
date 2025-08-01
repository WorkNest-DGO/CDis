<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/pdf_simple.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

// Base de la URL donde se alojará el sistema para los códigos QR
if (!defined('URL_BASE_QR')) {
    define('URL_BASE_QR', 'http://192.168.1.4080');
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
    $urlQR = URL_BASE_QR . '/CDI/vistas/bodega/recepcion_qr.php?token=' . $token;
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

    $upd = $conn->prepare('UPDATE insumos SET existencia = existencia - ? WHERE id = ?');
    $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, cantidad, observacion, fecha, qr_token) VALUES ('traspaso', ?, ?, ?, 'Enviado por QR a sucursal', NOW(), ?)");
    $det = null;
    if ($despacho_id) {
        $det = $conn->prepare('INSERT INTO despachos_detalle (despacho_id, insumo_id, cantidad, unidad, precio_unitario) VALUES (?, ?, ?, ?, 0)');
    }

    foreach ($seleccionados as $s) {
        $upd->bind_param('di', $s['cantidad'], $s['id']);
        if (!$upd->execute()) throw new Exception($upd->error);

        $neg = -$s['cantidad'];
        $mov->bind_param('iids', $usuario_id, $s['id'], $neg, $token);
        if (!$mov->execute()) throw new Exception($mov->error);

        if ($det) {
            $det->bind_param('iids', $despacho_id, $s['id'], $s['cantidad'], $s['unidad']);
            if (!$det->execute()) throw new Exception($det->error);
        }
    }
    $upd->close();
    $mov->close();
    if ($det) $det->close();

    $conn->commit();
} catch (Exception $e) {
    $conn->rollback();
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

generar_pdf_con_imagen($pdf_path, 'Salida de insumos', $lineas, $public_qr_path, 150, 10, 40, 40);
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

