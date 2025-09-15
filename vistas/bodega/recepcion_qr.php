<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Base app dinámica y ruta relativa para validación
$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__app_base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
$path_actual = preg_replace('#^' . preg_quote($__app_base, '#') . '#', '', ($__sn ?: $_SERVER['PHP_SELF']));
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}

require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/pdf_simple.php';

$token = $_GET['token'] ?? '';
$mensaje = '';
$datos = [];
$pdf_recepcion = '';

if ($token !== '') {
    $stmt = $conn->prepare('SELECT * FROM qrs_insumo WHERE token = ?');
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $qr = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$qr || $qr['estado'] !== 'pendiente') {
        $mensaje = 'QR inválido o ya procesado';
    } elseif ($qr['expiracion'] && strtotime($qr['expiracion']) < time()) {
        $mensaje = 'QR expirado';
    } else {
        $datos = json_decode($qr['json_data'], true);
    }
} else {
    $mensaje = 'QR inválido';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && !$mensaje && $qr) {
    $obs = trim($_POST['observaciones'] ?? '');
    $usuario_id = $_SESSION['usuario_id'];
    $conn->begin_transaction();
    try {
        $upd = $conn->prepare('UPDATE insumos SET existencia = existencia + ? WHERE id = ?');
        $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, usuario_destino_id, insumo_id, cantidad, observacion, qr_token) VALUES ('entrada', ?, ?, ?, ?, ?, ?)");
        foreach ($datos as $d) {
            $upd->bind_param('di', $d['cantidad'], $d['id']);
            if (!$upd->execute()) throw new Exception($upd->error);

            $mov->bind_param('iiidss', $usuario_id, $qr['creado_por'], $d['id'], $d['cantidad'], $obs, $token);
            if (!$mov->execute()) throw new Exception($mov->error);
        }
        $upd->close();
        $mov->close();

        $dirPdf = __DIR__ . '/../../uploads/qrs';
        if (!is_dir($dirPdf)) {
            mkdir($dirPdf, 0777, true);
        }
        $pdf_recepcion = 'uploads/qrs/recepcion_' . $token . '.pdf';

        $stmtNombre = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ?');
        $stmtNombre->bind_param('i', $qr['creado_por']);
        $stmtNombre->execute();
        $stmtNombre->bind_result($nombre_envia);
        $stmtNombre->fetch();
        $stmtNombre->close();

        $stmtNombre = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ?');
        $stmtNombre->bind_param('i', $usuario_id);
        $stmtNombre->execute();
        $stmtNombre->bind_result($nombre_recibe);
        $stmtNombre->fetch();
        $stmtNombre->close();

        $lineas = [];
        $lineas[] = 'Fecha: ' . date('Y-m-d H:i');
        $lineas[] = 'Entregado por: ' . $nombre_envia;
        $lineas[] = 'Recibido por: ' . $nombre_recibe;
        if ($obs !== '') {
            $lineas[] = 'Observaciones: ' . $obs;
        }
        foreach ($datos as $d) {
            $lineas[] = $d['nombre'] . ' - ' . $d['cantidad'] . ' ' . $d['unidad'];
        }
        generar_pdf_simple(__DIR__ . '/../../' . $pdf_recepcion, 'Recepción de insumos', $lineas);

        $upqr = $conn->prepare('UPDATE qrs_insumo SET estado = "confirmado", pdf_recepcion = ? WHERE id = ?');
        $upqr->bind_param('si', $pdf_recepcion, $qr['id']);
        if (!$upqr->execute()) throw new Exception($upqr->error);
        $upqr->close();

        $conn->commit();
        $mensaje = 'Recepción registrada';
    } catch (Exception $e) {
        $conn->rollback();
        $mensaje = 'Error al registrar recepción';
    }
}

$title = 'Recepción QR';
ob_start();
?>

<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Modulo de CDI</h2>
            </div>
            <div class="col-12">
                <a href="">Inicio</a>
                <a href="">Catálogo de recepción en tienda</a>
            </div>
        </div>
    </div>
</div>
<div class="container mt-4">
    <h2 class="text-white">Recepción de insumos</h2>
    <?php if ($mensaje): ?>
        <p class="text-white"><?= htmlspecialchars($mensaje) ?></p>
    <?php endif; ?>

    <?php if ($datos && !$mensaje): ?>
        <form method="post">
            <div class="table-responsive">
                <table class="styled-table">
                    <thead>
                        <tr>
                            <th>Insumo</th>
                            <th>Cantidad</th>
                            <th>Unidad</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($datos as $d): ?>
                            <tr>
                                <td><?= htmlspecialchars($d['nombre']) ?></td>
                                <td><?= $d['cantidad'] ?></td>
                                <td><?= htmlspecialchars($d['unidad']) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
            <div class="mb-3">
                <label class="text-white">Observaciones:</label>
                <textarea name="observaciones" class="form-control"></textarea>
            </div>
            <button type="submit" class="btn custom-btn">Aceptar entrega</button>
            <?php if ($pdf_recepcion): ?>
                <a class="btn custom-btn" href="../../<?= $pdf_recepcion ?>" target="_blank">Ver PDF</a>
            <?php endif; ?>
        </form>
    <?php endif; ?>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

