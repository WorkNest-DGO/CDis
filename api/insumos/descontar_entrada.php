<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    error('JSON inválido');
}

$entradaId = isset($input['entrada_id']) ? (int) $input['entrada_id'] : 0;
$retirar = isset($input['retirar']) ? (float) $input['retirar'] : 0.0;
// Compatibilidad: permitir campo 'cantidad' además de 'retirar'
$cantidad = isset($input['cantidad']) ? (float) $input['cantidad'] : $retirar;
// Tipo de movimiento y campos opcionales
$tipo = isset($input['tipo']) ? trim((string)$input['tipo']) : 'salida';
$observacion = isset($input['observacion']) ? (string)$input['observacion'] : '';
$idQrParam = isset($input['id_qr']) ? (int)$input['id_qr'] : null;
$qrTokenParam = isset($input['qr_token']) ? trim((string)$input['qr_token']) : '';
// Bypass opcional para FIFO (admin)
$bypass = isset($input['bypass_fifo']) ? (int)$input['bypass_fifo'] : 0;

// Si viene 'cantidad' y no 'retirar', usarla para compatibilidad
if (($retirar <= 0) && ($cantidad > 0)) {
    $retirar = $cantidad;
}
$usuarioId = isset($_SESSION['usuario_id']) ? (int) $_SESSION['usuario_id'] : 0;
if (isset($input['usuario_id'])) {
    $tmp = (int) $input['usuario_id'];
    if ($tmp > 0) {
        $usuarioId = $tmp;
    }
}

if ($entradaId <= 0) error('Entrada inválida');
// Normalizar cantidad absoluta
$cantAbs = abs(($cantidad > 0) ? $cantidad : $retirar);
if ($cantAbs <= 0) error('Cantidad a retirar inválida');
// Normalizar tipo permitido
$tiposPermitidos = ['salida','traspaso','merma'];
if ($tipo === '' || !in_array(strtolower($tipo), $tiposPermitidos, true)) {
    $tipo = 'salida';
} else {
    $tipo = strtolower($tipo);
}
// Asegurar que $retirar usado en operación sea positivo absoluto
$retirar = $cantAbs;
if ($usuarioId <= 0) error('Usuario inválido');

$sel = $conn->prepare('SELECT id, insumo_id, fecha, cantidad_actual, unidad, valor_unitario FROM entradas_insumos WHERE id = ? FOR UPDATE');
if (!$sel) error('Error de consulta: ' . $conn->error);
$sel->bind_param('i', $entradaId);
$sel->execute();
$res = $sel->get_result();
if (!$res || $res->num_rows === 0) {
    $sel->close();
    error('Entrada no encontrada');
}
$row = $res->fetch_assoc();
$sel->close();

$insumoId = (int) $row['insumo_id'];
$actual = (float) $row['cantidad_actual'];
$fechaEntrada = $row['fecha'];
$unidad = (string) $row['unidad'];
$valorUnit = (float) $row['valor_unitario'];

// Validación FIFO por consulta (opcional): sólo aplica para salida/traspaso; MERMA se permite
if ($tipo !== 'merma') {
    $fifoQ = $conn->prepare('SELECT EXISTS(SELECT 1 FROM entradas_insumos ei WHERE ei.insumo_id = ? AND ei.cantidad_actual > 0 AND (ei.fecha < ? OR (ei.fecha = ? AND ei.id < ?))) AS hay_mas_viejos');
    if ($fifoQ) {
        $fifoQ->bind_param('issi', $insumoId, $fechaEntrada, $fechaEntrada, $entradaId);
        $fifoQ->execute();
        $r = $fifoQ->get_result();
        $hayMasViejos = ($r && ($rr = $r->fetch_assoc())) ? (int)$rr['hay_mas_viejos'] : 0;
        $fifoQ->close();
        if ($hayMasViejos === 1) {
            error('No puedes retirar de la entrada #' . $entradaId . '; hay lotes más antiguos con stock (FIFO).');
        }
    }
}

if ($cantAbs > $actual) {
    error('La cantidad a retirar supera la cantidad actual');
}

if (!function_exists('obtenerBaseUrl')) {
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
}

if (!function_exists('construirUrlConsultaMovimiento')) {
    function construirUrlConsultaMovimiento($token)
    {
        $token = trim((string) $token);
        if ($token === '') {
            throw new InvalidArgumentException('Token de consulta inválido');
        }
        $scriptName = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '/api/insumos/descontar_entrada.php';
        $scriptDir = str_replace('\\', '/', dirname($scriptName));
        if ($scriptDir === '.' || $scriptDir === '/' || $scriptDir === '\\') {
            $scriptDir = '';
        }
        $basePath = preg_replace('#/api/insumos/?$#', '', $scriptDir);
        $relativePath = rtrim($basePath, '/') . '/vistas/insumos/consulta_movimiento.php';
        $relativePath = '/' . ltrim($relativePath, '/');
        return rtrim(obtenerBaseUrl(), '/') . $relativePath . '?token=' . urlencode($token);
    }
}

if (!function_exists('generarTokenQrSalida')) {
    function generarTokenQrSalida(mysqli $conn)
    {
        do {
            $token = bin2hex(random_bytes(16));
            $stmt = $conn->prepare('SELECT id FROM movimientos_insumos WHERE qr_token = ? LIMIT 1');
            if (!$stmt) {
                throw new RuntimeException('No se pudo preparar la validación del token QR');
            }
            $stmt->bind_param('s', $token);
            $stmt->execute();
            $stmt->store_result();
            $existe = $stmt->num_rows > 0;
            $stmt->close();
        } while ($existe);

        return $token;
    }
}

$qrToken = null;
$qrRelPath = null;
$qrAbsPath = null;
$qrConsultaUrl = null;
$fechaMovimiento = null;
$movimientoId = null;

$conn->begin_transaction();
try {
    // Variables de sesión para TRIGGER FIFO (@mov_tipo y @bypass_fifo)
    $tipoEsc = $conn->real_escape_string($tipo);
    if (!$conn->query("SET @mov_tipo = '" . $tipoEsc . "'")) {
        throw new RuntimeException('No se pudo inicializar variable de sesión @mov_tipo');
    }
    if ($bypass === 1) {
        if (!$conn->query('SET @bypass_fifo = 1')) {
            throw new RuntimeException('No se pudo inicializar variable de sesión @bypass_fifo');
        }
    }

    // Descontar del lote (TRIGGER aplicará FIFO según @mov_tipo)
    $upd = $conn->prepare('UPDATE entradas_insumos SET cantidad_actual = cantidad_actual - ? WHERE id = ?');
    if (!$upd) {
        throw new RuntimeException('No se pudo preparar actualización');
    }
    $upd->bind_param('di', $cantAbs, $entradaId);
    if (!$upd->execute()) {
        // Capturar posible SIGNAL del TRIGGER FIFO (SQLSTATE '45000')
        $err = $upd->error;
        if (stripos($err, '45000') !== false || stripos($err, 'FIFO') !== false) {
            throw new RuntimeException($err);
        }
        throw new RuntimeException('No se pudo actualizar cantidad actual');
    }
    $upd->close();

    // Coherencia global
    $updIns = $conn->prepare('UPDATE insumos SET existencia = GREATEST(existencia - ?, 0) WHERE id = ?');
    if ($updIns) {
        $updIns->bind_param('di', $cantAbs, $insumoId);
        $updIns->execute();
        $updIns->close();
    }

    // QR (compatibilidad): usar el provisto o generar
    $qrToken = ($qrTokenParam !== '') ? $qrTokenParam : generarTokenQrSalida($conn);
    $qrConsultaUrl = construirUrlConsultaMovimiento($qrToken);
    $qrDir = __DIR__ . '/../../archivos/qr';
    if (!is_dir($qrDir)) {
        if (!mkdir($qrDir, 0777, true) && !is_dir($qrDir)) {
            throw new RuntimeException('No se pudo preparar el directorio de códigos QR');
        }
    }
    $qrFileName = 'salida_insumo_' . $entradaId . '_' . $qrToken . '.png';
    $qrRelPath = 'archivos/qr/' . $qrFileName;
    $qrAbsPath = $qrDir . DIRECTORY_SEPARATOR . $qrFileName;

    $fechaMovimiento = date('Y-m-d H:i:s');
    QRcode::png($qrConsultaUrl, $qrAbsPath, QR_ECLEVEL_Q, 8, 2);
    if (!is_file($qrAbsPath)) {
        throw new RuntimeException('No se pudo generar el código QR de salida');
    }

    // Movimiento por lote: en 'merma' la cantidad se registra positiva (trazabilidad),
    // en 'salida'/'traspaso' se registra negativa
    $obs = ($observacion !== '') ? $observacion : ('Retiro de entrada #' . $entradaId . ' (' . $cantAbs . ' ' . $unidad . ')');
    $cantMovimiento = ($tipo === 'merma') ? $cantAbs : -$cantAbs;

    // Buscar corte abierto para asociar el movimiento (si existe)
    $corteIdAbierto = 0;
    if ($qC = $conn->prepare("SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1")) {
        $qC->execute();
        $rC = $qC->get_result();
        if ($rC && ($cR = $rC->fetch_assoc())) {
            $corteIdAbierto = (int)$cR['id'];
        }
        $qC->close();
    }

    if ($corteIdAbierto > 0) {
        $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, qr_token, id_qr, corte_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        if (!$mov) {
            throw new RuntimeException('No se pudo preparar el registro del movimiento');
        }
        $mov->bind_param('siiidsssii', $tipo, $usuarioId, $insumoId, $entradaId, $cantMovimiento, $obs, $fechaMovimiento, $qrToken, $idQrParam, $corteIdAbierto);
    } else {
        // Sin corte abierto, insertar sin corte_id (NULL)
        $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, id_entrada, cantidad, observacion, fecha, qr_token, id_qr) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
        if (!$mov) {
            throw new RuntimeException('No se pudo preparar el registro del movimiento');
        }
        $mov->bind_param('siiidsssi', $tipo, $usuarioId, $insumoId, $entradaId, $cantMovimiento, $obs, $fechaMovimiento, $qrToken, $idQrParam);
    }

    if (!$mov->execute()) {
        throw new RuntimeException('No se pudo registrar el movimiento de salida');
    }
    $movimientoId = $mov->insert_id;
    $mov->close();

    // Limpiar variables de sesión del TRIGGER
    @ $conn->query('SET @mov_tipo = NULL');
    @ $conn->query('SET @bypass_fifo = NULL');

    $conn->commit();
} catch (Throwable $e) {
    if ($conn->in_transaction) {
        $conn->rollback();
    }
    // Asegurar limpieza de variables de sesión
    @ $conn->query('SET @mov_tipo = NULL');
    @ $conn->query('SET @bypass_fifo = NULL');
    if ($qrAbsPath && is_file($qrAbsPath)) {
        @unlink($qrAbsPath);
    }
    $msg = (string)$e->getMessage();
    if (stripos($msg, '45000') !== false || stripos($msg, 'FIFO') !== false) {
        http_response_code(409);
        header('Content-Type: application/json');
        echo json_encode(['success' => false, 'mensaje' => $msg, 'code' => 'FIFO_TRIGGER']);
        exit;
    }
    error('Error al descontar: ' . $msg);
}

success([
    'entrada_id' => $entradaId,
    'insumo_id' => $insumoId,
    'retirado' => $cantAbs,
    'unidad' => $unidad,
    'valor_unitario' => $valorUnit,
    'qr_token' => $qrToken,
    'qr_consulta_url' => $qrConsultaUrl,
    'qr_imagen' => $qrRelPath,
    'fecha' => $fechaMovimiento,
    'movimiento_id' => $movimientoId,
    'tipo' => $tipo,
    'id_entrada' => $entradaId
]);
