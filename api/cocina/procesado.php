<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

header('Content-Type: application/json; charset=utf-8');

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
$conn->set_charset('utf8mb4');

// Helpers
function json_ok($payload = []) {
    echo json_encode(['success' => true, 'ok' => true] + $payload, JSON_UNESCAPED_UNICODE);
    exit;
}
function json_fail($message, $code = 400, $extra = []) {
    http_response_code($code);
    echo json_encode(['success' => false, 'ok' => false, 'mensaje' => $message] + $extra, JSON_UNESCAPED_UNICODE);
    exit;
}

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
    if ($scriptDir === '.' || $scriptDir === '/' || $scriptDir === '\\') {
        $scriptDir = '';
    }
    $basePath = preg_replace('#/api/cocina/?$#', '', $scriptDir);
    $relativePath = rtrim($basePath, '/') . '/vistas/insumos/entrada_insumo.php';
    $relativePath = '/' . ltrim($relativePath, '/');
    return rtrim(obtenerBaseUrl(), '/') . $relativePath . '?id=' . $entradaId;
}

function construirUrlConsultaMovimiento($token)
{
    $token = trim((string)$token);
    if ($token === '') { throw new InvalidArgumentException('Token inválido'); }
    $scriptName = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '/CDI/api/cocina/procesado.php';
    $scriptDir = str_replace('\\', '/', dirname($scriptName));
    if ($scriptDir === '.' || $scriptDir === '/' || $scriptDir === '\\') { $scriptDir = ''; }
    $basePath = preg_replace('#/api/cocina/?$#', '', $scriptDir);
    $relativePath = rtrim($basePath, '/') . '/vistas/insumos/consulta_movimiento.php';
    $relativePath = '/' . ltrim($relativePath, '/');
    return rtrim(obtenerBaseUrl(), '/') . $relativePath . '?token=' . urlencode($token);
}

function generarTokenMovimiento($conn)
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

function ensureSchema($conn) {
    // Crear tabla de procesos si no existe
    $conn->query(
        "CREATE TABLE IF NOT EXISTS `procesos_insumos` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `insumo_origen_id` INT NOT NULL,
          `insumo_destino_id` INT NOT NULL,
          `cantidad_origen` DECIMAL(10,2) NOT NULL,
          `unidad_origen` VARCHAR(20) NOT NULL,
          `cantidad_resultante` DECIMAL(10,2) DEFAULT NULL,
          `unidad_destino` VARCHAR(20) DEFAULT NULL,
          `estado` ENUM('pendiente','en_preparacion','listo','entregado','cancelado') DEFAULT 'pendiente',
          `observaciones` TEXT NULL,
          `creado_por` INT NULL,
          `preparado_por` INT NULL,
          `listo_por` INT NULL,
          `creado_en` DATETIME DEFAULT CURRENT_TIMESTAMP,
          `actualizado_en` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          `entrada_insumo_id` INT NULL,
          `mov_salida_id` INT NULL,
          `qr_path` VARCHAR(255) NULL,
          PRIMARY KEY (`id`),
          KEY `idx_proc_estado` (`estado`),
          KEY `idx_proc_origen` (`insumo_origen_id`),
          KEY `idx_proc_destino` (`insumo_destino_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;"
    );

    // Intentar crear o reemplazar la vista (ignorar error si no hay permisos)
    try {
        $conn->query(
            "CREATE OR REPLACE VIEW v_procesos_insumos AS
             SELECT p.id, p.estado,
                    io.id AS insumo_origen_id, io.nombre AS insumo_origen, p.cantidad_origen, p.unidad_origen,
                    ides.id AS insumo_destino_id, ides.nombre AS insumo_destino, p.cantidad_resultante, p.unidad_destino,
                    p.creado_en, p.qr_path,
                    p.entrada_insumo_id, p.mov_salida_id
             FROM procesos_insumos p
             JOIN insumos io   ON io.id = p.insumo_origen_id
             JOIN insumos ides ON ides.id = p.insumo_destino_id"
        );
    } catch (Throwable $e) {
        // noop
    }
}

ensureSchema($conn);

// Notificación de cambios para long-poll (similar a notify_cambio.php)
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
    ftruncate($fp, 0);
    rewind($fp);
    fwrite($fp, (string)$next);
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    $evt = json_encode(['v'=>$next,'ids'=>array_values(array_unique(array_map('intval',$ids))), 'ts'=>time()]);
    @file_put_contents($eventsLog, $evt . PHP_EOL, FILE_APPEND | LOCK_EX);
}

$method = $_SERVER['REQUEST_METHOD'];
$action = isset($_REQUEST['action']) ? strtolower(trim($_REQUEST['action'])) : '';
if ($action === '' && $method === 'PATCH') {
    $raw = json_decode(file_get_contents('php://input'), true);
    if (isset($raw['action'])) { $action = strtolower((string)$raw['action']); }
}

// Dispatcher
switch ($action) {
    case 'create':
        if ($method !== 'POST') { json_fail('Método no permitido', 405); }
        $origenId = isset($_POST['insumo_origen_id']) ? (int)$_POST['insumo_origen_id'] : 0;
        $destinoId = isset($_POST['insumo_destino_id']) ? (int)$_POST['insumo_destino_id'] : 0;
        $cantidad  = isset($_POST['cantidad_origen']) ? (float)$_POST['cantidad_origen'] : 0.0;
        if ($origenId <= 0 || $destinoId <= 0) { json_fail('Insumos inválidos'); }
        if ($origenId === $destinoId) { json_fail('El insumo origen y destino no pueden ser iguales'); }
        if ($cantidad <= 0) { json_fail('Cantidad inválida'); }
        $obs = isset($_POST['observaciones']) ? trim((string)$_POST['observaciones']) : '';
        $userId = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;

        // Validar insumos
        $stmt = $conn->prepare('SELECT id, nombre, unidad, existencia FROM insumos WHERE id IN (?, ?)');
        $stmt->bind_param('ii', $origenId, $destinoId);
        $stmt->execute();
        $res = $stmt->get_result();
        $info = [];
        while ($r = $res->fetch_assoc()) { $info[(int)$r['id']] = $r; }
        $stmt->close();
        if (!isset($info[$origenId]) || !isset($info[$destinoId])) { json_fail('Insumo no encontrado'); }
        $unidadOrigen = (string)$info[$origenId]['unidad'];
        $unidadDestino = (string)$info[$destinoId]['unidad'];
        $existOrigen = (float)$info[$origenId]['existencia'];
        if ($existOrigen < $cantidad) { json_fail('Stock insuficiente del insumo de origen'); }

        $ins = $conn->prepare('INSERT INTO procesos_insumos (insumo_origen_id, insumo_destino_id, cantidad_origen, unidad_origen, unidad_destino, estado, observaciones, creado_por) VALUES (?, ?, ?, ?, ?, \'pendiente\', ?, ?)');
        $ins->bind_param('iidsssi', $origenId, $destinoId, $cantidad, $unidadOrigen, $unidadDestino, $obs, $userId);
        $ins->execute();
        $pid = $ins->insert_id;
        $ins->close();

        $row = [
            'id' => $pid,
            'insumo_origen_id' => $origenId,
            'insumo_destino_id' => $destinoId,
            'cantidad_origen' => $cantidad,
            'unidad_origen' => $unidadOrigen,
            'unidad_destino' => $unidadDestino,
            'estado' => 'pendiente',
            'observaciones' => $obs,
        ];
        notificarCambioCocina([$pid]);
        json_ok(['id' => $pid, 'data' => $row]);
        break;

    case 'list':
        if (!in_array($method, ['GET','POST'], true)) { json_fail('Método no permitido', 405); }
        $estado = isset($_REQUEST['estado']) ? strtolower(trim($_REQUEST['estado'])) : '';
        $allowedEstados = ['pendiente','en_preparacion','listo','entregado','todos',''];
        if (!in_array($estado, $allowedEstados, true)) { $estado = ''; }
        // Intentar usar la vista; si falla, usar JOIN directo
        $where = '';
        if ($estado && $estado !== 'todos') {
            $where = "WHERE p.estado = '" . $conn->real_escape_string($estado) . "'";
        } elseif ($estado === 'todos' || $estado === '') {
            $where = "WHERE p.estado IN ('pendiente','en_preparacion','listo','entregado')";
        }
        $sql = "SELECT p.id, p.estado,
                       io.id AS insumo_origen_id, io.nombre AS insumo_origen, p.cantidad_origen, p.unidad_origen,
                       ides.id AS insumo_destino_id, ides.nombre AS insumo_destino, p.cantidad_resultante, p.unidad_destino,
                       p.creado_en, p.qr_path, p.entrada_insumo_id, p.mov_salida_id
                FROM procesos_insumos p
                JOIN insumos io   ON io.id = p.insumo_origen_id
                JOIN insumos ides ON ides.id = p.insumo_destino_id
                $where
                ORDER BY p.creado_en DESC";
        $rs = $conn->query($sql);
        $items = [];
        while ($r = $rs->fetch_assoc()) { $items[] = $r; }
        echo json_encode(['success' => true, 'ok' => true, 'items' => $items], JSON_UNESCAPED_UNICODE);
        exit;

    case 'move':
        // Cambiar estado simple
        if (!in_array($method, ['POST','PATCH'], true)) { json_fail('Método no permitido', 405); }
        $payload = $method === 'PATCH' ? json_decode(file_get_contents('php://input'), true) : $_POST;
        $id = isset($payload['id']) ? (int)$payload['id'] : 0;
        $nuevo = isset($payload['nuevo_estado']) ? strtolower(trim((string)$payload['nuevo_estado'])) : '';
        $allowed = ['pendiente','en_preparacion','listo','entregado'];
        if ($id <= 0 || !in_array($nuevo, $allowed, true)) { json_fail('Parámetros inválidos'); }
        $userId = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : null;

        $setCols = "estado = ?";
        $args = [$nuevo];
        $types = 's';
        if ($nuevo === 'en_preparacion') { $setCols .= ', preparado_por = ?'; $types .= 'i'; $args[] = $userId; }
        if ($nuevo === 'listo') { $setCols .= ', listo_por = ?'; $types .= 'i'; $args[] = $userId; }
        $setCols .= ', actualizado_en = NOW()';
        $sql = "UPDATE procesos_insumos SET $setCols WHERE id = ?";
        $types .= 'i';
        $args[] = $id;
        $stmt = $conn->prepare($sql);
        $stmt->bind_param($types, ...$args);
        $stmt->execute();
        $stmt->close();
        notificarCambioCocina([$id]);
        json_ok(['id' => $id, 'estado' => $nuevo]);
        break;

    case 'complete':
        if ($method !== 'POST') { json_fail('Método no permitido', 405); }
        $id = isset($_POST['id']) ? (int)$_POST['id'] : 0;
        $cantRes = isset($_POST['cantidad_resultante']) ? (float)$_POST['cantidad_resultante'] : 0.0;
        $motivoMerma = isset($_POST['motivo_merma']) ? trim((string)$_POST['motivo_merma']) : '';
        if ($id <= 0 || $cantRes <= 0) { json_fail('Parámetros inválidos'); }
        $userId = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;
        if ($userId <= 0) { json_fail('Usuario no autenticado', 401); }

        $conn->begin_transaction();
        try {
            // 1) Bloquear proceso
            $stmt = $conn->prepare('SELECT * FROM procesos_insumos WHERE id = ? FOR UPDATE');
            $stmt->bind_param('i', $id);
            $stmt->execute();
            $res = $stmt->get_result();
            if (!$res || $res->num_rows === 0) { throw new RuntimeException('Proceso no encontrado'); }
            $p = $res->fetch_assoc();
            $stmt->close();

            if ($p['estado'] !== 'listo') { throw new RuntimeException('El proceso debe estar en estado "listo"'); }
            if (!empty($p['entrada_insumo_id'])) { throw new RuntimeException('El proceso ya fue completado'); }

            $insumoOrigen = (int)$p['insumo_origen_id'];
            $insumoDestino = (int)$p['insumo_destino_id'];
            $cantOrigen = (float)$p['cantidad_origen'];
            $unidadOrigen = (string)$p['unidad_origen'];
            $unidadDestino = (string)$p['unidad_destino'];

            // 2) Insert ENTRADA para destino
            $qrDir = __DIR__ . '/../../archivos/qr';
            if (!is_dir($qrDir)) { @mkdir($qrDir, 0777, true); }
            $insEntrada = $conn->prepare('INSERT INTO entradas_insumos (insumo_id, proveedor_id, usuario_id, descripcion, cantidad, unidad, costo_total, referencia_doc, folio_fiscal, qr, cantidad_actual, credito) VALUES (?, NULL, ?, ?, ?, ?, 0, "", "", "pendiente", ?, NULL)');
            $desc = 'Procesado desde insumo ' . $insumoOrigen . ' lote ' . $id;
            $cantidadActual = $cantRes;
            $insEntrada->bind_param('iisdsd', $insumoDestino, $userId, $desc, $cantRes, $unidadDestino, $cantidadActual);
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

            // 3) SALIDA del origen (respetando FIFO si hay lotes)
            $restante = $cantOrigen;
            // Consumir de lotes más antiguos
            $selLotes = $conn->prepare('SELECT id, cantidad_actual FROM entradas_insumos WHERE insumo_id = ? AND cantidad_actual > 0 ORDER BY fecha ASC, id ASC FOR UPDATE');
            $selLotes->bind_param('i', $insumoOrigen);
            $selLotes->execute();
            $rs = $selLotes->get_result();
            $lotes = [];
            while ($row = $rs->fetch_assoc()) { $lotes[] = $row; }
            $selLotes->close();

            foreach ($lotes as $l) {
                if ($restante <= 0) break;
                $entradaLoteId = (int)$l['id'];
                $disp = (float)$l['cantidad_actual'];
                if ($disp <= 0) continue;
                $usar = min($restante, $disp);
                // Esto respetará TRIGGER FIFO
                $upd = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual - ? WHERE id = ?');
                $upd->bind_param('di', $usar, $entradaLoteId);
                $upd->execute();
                $upd->close();
                $restante -= $usar;
            }
            if ($restante > 0.00001) {
                throw new RuntimeException('Stock insuficiente en lotes para descontar el origen (restante: ' . $restante . ')');
            }

            // Registrar movimiento global de producción (sin id_entrada específico)
            $obs = 'Usado en proceso id ' . $id . ' hacia insumo destino ' . $insumoDestino;
            $mov = $conn->prepare('INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha) VALUES (\'produccion\', ?, ?, NULL, ?, ?, NOW())');
            $cantNeg = -$cantOrigen;
            $mov->bind_param('iids', $userId, $insumoOrigen, $cantNeg, $obs);
            $mov->execute();
            $movId = $mov->insert_id;
            $mov->close();

            // 4) Actualizar existencias en insumos
            $u1 = $conn->prepare('UPDATE insumos SET existencia = GREATEST(existencia - ?, 0) WHERE id = ?');
            $u1->bind_param('di', $cantOrigen, $insumoOrigen);
            $u1->execute();
            $u1->close();
            $u2 = $conn->prepare('UPDATE insumos SET existencia = existencia + ? WHERE id = ?');
            $u2->bind_param('di', $cantRes, $insumoDestino);
            $u2->execute();
            $u2->close();

            // 4.1) Merma (si resultado < origen) -> registrar en mermas_insumo y movimiento 'merma' con QR
            $merma = $cantOrigen - $cantRes;
            $merma = $merma > 0 ? $merma : 0;
            $mermaMovId = null;
            $mermaQrPath = null;
            if ($merma > 0.00001) {
                // mermas_insumo
                $insMerma = $conn->prepare('INSERT INTO mermas_insumo (insumo_id, cantidad, motivo, usuario_id) VALUES (?, ?, ?, ?)');
                $insMerma->bind_param('idsi', $insumoOrigen, $merma, $motivoMerma, $userId);
                $insMerma->execute();
                $insMerma->close();

                // movimiento 'merma' solo para traza (no tocamos stock nuevamente)
                $obsMerma = 'Merma del proceso id ' . $id . ($motivoMerma !== '' ? (' - ' . $motivoMerma) : '');
                $cantMermaNeg = -$merma;
                $token = generarTokenMovimiento($conn);
                $movM = $conn->prepare('INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, qr_token) VALUES (\'merma\', ?, ?, NULL, ?, ?, NOW(), ?)');
                $movM->bind_param('iidss', $userId, $insumoOrigen, $cantMermaNeg, $obsMerma, $token);
                $movM->execute();
                $mermaMovId = $movM->insert_id;
                $movM->close();

                // QR imagen para la merma
                $qrMermaFile = 'merma_insumo_' . $mermaMovId . '_' . $token . '.png';
                $qrMermaRel = 'archivos/qr/' . $qrMermaFile;
                $qrMermaAbs = $qrDir . DIRECTORY_SEPARATOR . $qrMermaFile;
                $urlMov = construirUrlConsultaMovimiento($token);
                QRcode::png($urlMov, $qrMermaAbs, QR_ECLEVEL_Q, 8, 2);
                // no hay campo de imagen en movimientos; devolvemos por respuesta
                $mermaQrPath = $qrMermaRel;
            }

            // 5) Actualizar proceso (mantener en 'listo' por UI)
            $up = $conn->prepare('UPDATE procesos_insumos SET cantidad_resultante = ?, entrada_insumo_id = ?, mov_salida_id = ?, qr_path = ?, actualizado_en = NOW() WHERE id = ?');
            $up->bind_param('diisi', $cantRes, $entradaId, $movId, $qrRelativePath, $id);
            $up->execute();
            $up->close();

            $conn->commit();
            notificarCambioCocina([$id]);
            echo json_encode([
                'success' => true,
                'ok' => true,
                'id' => $id,
                'entrada_insumo_id' => $entradaId,
                'mov_salida_id' => $movId,
                'qr_path' => $qrRelativePath,
                'merma' => $merma,
                'merma_movimiento_id' => $mermaMovId,
                'merma_qr' => $mermaQrPath
            ], JSON_UNESCAPED_UNICODE);
            exit;
        } catch (Throwable $e) {
            if ($conn->in_transaction) { $conn->rollback(); }
            json_fail('Error al completar: ' . $e->getMessage(), 400);
        }
        break;

    default:
        json_fail('Acción no soportada', 400);
}

?>
