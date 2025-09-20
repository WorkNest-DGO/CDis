<?php
session_start();
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/pdf_simple.php';

if (!isset($_SESSION['usuario_id'])) {
    error('No autenticado');
}

// Leer JSON
$input = json_decode(file_get_contents('php://input'), true);
$token = isset($_GET['token']) ? trim(substr($_GET['token'], 0, 64)) : '';
if (!$input || $token === '') {
    error('Parámetros inválidos');
}
$modo = isset($input['modo']) ? $input['modo'] : '';
$obs = isset($input['observacion']) ? trim(substr($input['observacion'], 0, 255)) : '';
$items = isset($input['items']) && is_array($input['items']) ? $input['items'] : [];
if (!in_array($modo, ['total','parcial'], true)) {
    error('Modo inválido');
}

// Cargar QR con bloqueo
$conn->begin_transaction();
try {
    $stmt = $conn->prepare('SELECT * FROM qrs_insumo WHERE token = ? FOR UPDATE');
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $qr = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    if (!$qr) { throw new Exception('QR no encontrado'); }
    if ($qr['estado'] === 'anulado') { throw new Exception('QR anulado'); }

    $id_qr = (int)$qr['id'];
    $usuario_id = (int)$_SESSION['usuario_id'];

    // Pendientes por entrada: enviado - devuelto
    $sqlPend = "WITH trasp AS (
                    SELECT insumo_id, id_entrada, SUM(ABS(cantidad)) AS enviado
                    FROM movimientos_insumos
                    WHERE tipo='traspaso' AND id_qr = ?
                    GROUP BY insumo_id, id_entrada
                 ), dev AS (
                    SELECT insumo_id, id_entrada, SUM(cantidad) AS devuelto
                    FROM movimientos_insumos
                    WHERE tipo='devolucion' AND id_qr = ?
                    GROUP BY insumo_id, id_entrada
                 )
                 SELECT t.insumo_id, t.id_entrada, COALESCE(t.enviado,0) AS enviado, COALESCE(d.devuelto,0) AS devuelto,
                        (COALESCE(t.enviado,0) - COALESCE(d.devuelto,0)) AS pendiente
                 FROM trasp t
                 LEFT JOIN dev d ON d.insumo_id = t.insumo_id AND d.id_entrada = t.id_entrada
                 HAVING pendiente > 0
                 ORDER BY t.insumo_id, t.id_entrada";
    $st = $conn->prepare($sqlPend);
    $st->bind_param('ii', $id_qr, $id_qr);
    $st->execute();
    $rs = $st->get_result();
    $pendByInsumo = [];
    while ($r = $rs->fetch_assoc()) {
        $iid = (int)$r['insumo_id'];
        $pendByInsumo[$iid][] = [
            'id_entrada' => (int)$r['id_entrada'],
            'pendiente' => (float)$r['pendiente'],
        ];
    }
    $st->close();

    // Helper: registrar devolución para un insumo y entrada
    $insMov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, usuario_destino_id, insumo_id, id_entrada, cantidad, observacion, fecha, qr_token, id_qr)
                              VALUES ('devolucion', ?, NULL, ?, ?, ?, ?, NOW(), ?, ?)");
    $updEntrada = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual + ? WHERE id = ?');
    $updInsumo = $conn->prepare('UPDATE insumos SET existencia = existencia + ? WHERE id = ?');

    $totalDevueltoGlobal = 0.0;
    $devueltosPorInsumo = [];

    if ($modo === 'total') {
        foreach ($pendByInsumo as $iid => $arr) {
            foreach ($arr as $p) {
                $cant = (float)$p['pendiente'];
                if ($cant <= 0) continue;
                $insMov->bind_param('iiidssi', $usuario_id, $iid, $p['id_entrada'], $cant, $obs, $token, $id_qr);
                if (!$insMov->execute()) throw new Exception($insMov->error);

                $updEntrada->bind_param('di', $cant, $p['id_entrada']);
                if (!$updEntrada->execute()) throw new Exception($updEntrada->error);

                $updInsumo->bind_param('di', $cant, $iid);
                if (!$updInsumo->execute()) throw new Exception($updInsumo->error);

                $totalDevueltoGlobal += $cant;
                $devueltosPorInsumo[$iid] = ($devueltosPorInsumo[$iid] ?? 0) + $cant;
            }
        }
    } else { // parcial
        // Map insumo_id -> cantidad solicitada
        $sol = [];
        foreach ($items as $it) {
            $ii = isset($it['insumo_id']) ? (int)$it['insumo_id'] : 0;
            $ca = isset($it['cantidad']) ? (float)$it['cantidad'] : 0.0;
            if ($ii>0 && $ca>0) $sol[$ii] = ($sol[$ii] ?? 0) + $ca;
        }
        // Validar no exceder pendiente total por insumo
        foreach ($sol as $iid => $cuanto) {
            $pendTotal = 0.0;
            foreach ($pendByInsumo[$iid] ?? [] as $p) { $pendTotal += (float)$p['pendiente']; }
            if ($cuanto > $pendTotal + 1e-9) {
                throw new Exception('Solicitud excede pendiente para insumo ' . $iid);
            }
        }
        // Asignar por FIFO (orden de pendByInsumo)
        foreach ($sol as $iid => $cuanto) {
            $rest = $cuanto;
            foreach ($pendByInsumo[$iid] ?? [] as $p) {
                if ($rest <= 1e-9) break;
                $asig = min($rest, (float)$p['pendiente']);
                if ($asig <= 0) continue;

                $insMov->bind_param('iiidssi', $usuario_id, $iid, $p['id_entrada'], $asig, $obs, $token, $id_qr);
                if (!$insMov->execute()) throw new Exception($insMov->error);

                $updEntrada->bind_param('di', $asig, $p['id_entrada']);
                if (!$updEntrada->execute()) throw new Exception($updEntrada->error);

                $updInsumo->bind_param('di', $asig, $iid);
                if (!$updInsumo->execute()) throw new Exception($updInsumo->error);

                $rest -= $asig;
                $totalDevueltoGlobal += $asig;
                $devueltosPorInsumo[$iid] = ($devueltosPorInsumo[$iid] ?? 0) + $asig;
            }
            if ($rest > 1e-9) {
                throw new Exception('No fue posible asignar toda la devolución solicitada');
            }
        }
    }

    $insMov->close();
    $updEntrada->close();
    $updInsumo->close();

    // Insert en recepciones_log (opcional según estructura)
    $payload = json_encode(['modo'=>$modo,'items'=>$items,'observacion'=>$obs,'devueltos'=>$devueltosPorInsumo], JSON_UNESCAPED_UNICODE);
    $logSql = $conn->prepare('INSERT INTO recepciones_log (sucursal_id, qr_token, fecha_recepcion, usuario_id, json_recibido, estado) VALUES (NULL, ?, NOW(), ?, ?, ?)');
    if ($logSql) {
        $estado = 'devolucion';
        $logSql->bind_param('siss', $token, $usuario_id, $payload, $estado);
        $logSql->execute();
        $logSql->close();
    }

    // Recalcular pendientes post-operación
    $st2 = $conn->prepare(
        "WITH trasp AS (
            SELECT SUM(ABS(cantidad)) AS enviado FROM movimientos_insumos WHERE tipo='traspaso' AND id_qr = ?
         ), dev AS (
            SELECT SUM(cantidad) AS devuelto FROM movimientos_insumos WHERE tipo='devolucion' AND id_qr = ?
         ) SELECT (COALESCE((SELECT enviado FROM trasp),0) - COALESCE((SELECT devuelto FROM dev),0)) AS pendiente_total"
    );
    $st2->bind_param('ii', $id_qr, $id_qr);
    $st2->execute();
    $penRes = $st2->get_result()->fetch_assoc();
    $st2->close();
    $pendienteTotal = (float)($penRes['pendiente_total'] ?? 0);

    // Generar/actualizar PDF de recepción (devolución)
    $dirPdf = __DIR__ . '/../../archivos/bodega/pdfs';
    if (!is_dir($dirPdf)) { mkdir($dirPdf, 0777, true); }
    $pdf_recepcion_rel = 'archivos/bodega/pdfs/recepcion_' . $token . '.pdf';
    $pdf_recepcion_path = __DIR__ . '/../../' . $pdf_recepcion_rel;

    // Encabezado del recibo
    $nombre_usuario = '';
    $stU = $conn->prepare('SELECT nombre FROM usuarios WHERE id = ?');
    if ($stU) { $stU->bind_param('i', $usuario_id); $stU->execute(); $stU->bind_result($nombre_usuario); $stU->fetch(); $stU->close(); }
    $lineas = [];
    $lineas[] = 'Token: ' . $token;
    $lineas[] = 'Fecha: ' . date('Y-m-d H:i');
    $lineas[] = 'Usuario: ' . ($nombre_usuario ?: ('ID ' . $usuario_id));
    if ($obs !== '') $lineas[] = 'Observación: ' . $obs;
    foreach ($devueltosPorInsumo as $iid => $cant) {
        // Obtener nombre/unidad
        $rowNI = null;
        $stI = $conn->prepare('SELECT nombre, unidad FROM insumos WHERE id = ?');
        if ($stI) { $stI->bind_param('i', $iid); $stI->execute(); $rowNI = $stI->get_result()->fetch_assoc(); $stI->close(); }
        $lineas[] = ($rowNI['nombre'] ?? ('Insumo ' . $iid)) . ' - ' . rtrim(rtrim(number_format($cant,2,'.',''), '0'), '.') . ' ' . ($rowNI['unidad'] ?? '');
    }
    generar_pdf_simple($pdf_recepcion_path, 'Devolución de QR', $lineas);

    // Actualiza estado si quedo sin pendientes
    if ($pendienteTotal <= 1e-9) {
        $up = $conn->prepare('UPDATE qrs_insumo SET estado = "confirmado", pdf_recepcion = ? WHERE id = ?');
        if ($up) { $up->bind_param('si', $pdf_recepcion_rel, $id_qr); $up->execute(); $up->close(); }
    } else {
        $up = $conn->prepare('UPDATE qrs_insumo SET pdf_recepcion = ? WHERE id = ?');
        if ($up) { $up->bind_param('si', $pdf_recepcion_rel, $id_qr); $up->execute(); $up->close(); }
    }

    // Log acción
    $log = $conn->prepare('INSERT INTO logs_accion (usuario_id, modulo, accion, referencia_id) VALUES (?, ?, ?, ?)');
    if ($log) { $mod = 'bodega'; $accion = 'Devolucion QR'; $log->bind_param('issi', $usuario_id, $mod, $accion, $id_qr); $log->execute(); $log->close(); }

    $conn->commit();
    success([
        'ok' => true,
        'devueltos' => $devueltosPorInsumo,
        'pdf_recepcion' => $pdf_recepcion_rel,
        'pendiente_total' => $pendienteTotal,
    ]);
} catch (Exception $e) {
    $conn->rollback();
    error($e->getMessage());
}
?>

