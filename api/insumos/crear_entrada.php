<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/phpqrcode/qrlib.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'Metodo no permitido']);
    exit;
}

if (session_status() === PHP_SESSION_NONE) {
    session_start();
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

if (!function_exists('construirUrlConsultaEntrada')) {
    function construirUrlConsultaEntrada($entradaId)
    {
        $entradaId = (int) $entradaId;
        $scriptName = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '/CDI/api/insumos/crear_entrada.php';
        $scriptDir = str_replace('\\', '/', dirname($scriptName));
        if ($scriptDir === '.' || $scriptDir === '/' || $scriptDir === '\\') {
            $scriptDir = '';
        }
        $basePath = preg_replace('#/api/insumos/?$#', '', $scriptDir);
        $relativePath = rtrim($basePath, '/') . '/vistas/insumos/entrada_insumo.php';
        $relativePath = '/' . ltrim($relativePath, '/');
        return rtrim(obtenerBaseUrl(), '/') . $relativePath . '?id=' . $entradaId;
    }
}

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
$conn->set_charset('utf8mb4');

$proveedorId = filter_input(INPUT_POST, 'proveedor_id', FILTER_VALIDATE_INT) ?: 0;
$usuarioId = filter_input(INPUT_POST, 'usuario_id', FILTER_VALIDATE_INT) ?: 0;
if (!$usuarioId && isset($_SESSION['usuario_id'])) {
    $usuarioId = (int) $_SESSION['usuario_id'];
}

$productosJson = $_POST['productos'] ?? '[]';
$productos = json_decode($productosJson, true);

if (json_last_error() !== JSON_ERROR_NONE) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Formato de productos invalido']);
    exit;
}

if ($proveedorId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Proveedor invalido']);
    exit;
}

if ($usuarioId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Usuario invalido']);
    exit;
}

if (!is_array($productos) || count($productos) === 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Productos requeridos']);
    exit;
}

$descripcionGlobal = trim($_POST['descripcion'] ?? '');
$referenciaGlobal = trim($_POST['referencia_doc'] ?? '');
$folioGlobal = trim($_POST['folio_fiscal'] ?? '');

// Tipo de pago: aceptar 'efectivo', 'credito', 'transferencia' (compatibilidad con 0/1)
$credito = isset($_POST['credito']) ? (string) $_POST['credito'] : '';
$credito = strtolower(trim($credito));
if ($credito === '1' || $credito === 'true') { $credito = 'credito'; }
if ($credito === '0' || $credito === 'false') { $credito = 'efectivo'; }
$permitidos = ['efectivo','credito','transferencia'];
if (!in_array($credito, $permitidos, true)) { $credito = 'efectivo'; }

try {
    $verProveedor = $conn->prepare('SELECT id FROM proveedores WHERE id = ?');
    $verProveedor->bind_param('i', $proveedorId);
    $verProveedor->execute();
    $verProveedor->store_result();
    if ($verProveedor->num_rows === 0) {
        $verProveedor->close();
        throw new RuntimeException('Proveedor no encontrado');
    }
    $verProveedor->close();

    $qrDir = __DIR__ . '/../../archivos/qr';
    if (!is_dir($qrDir)) {
        if (!mkdir($qrDir, 0777, true) && !is_dir($qrDir)) {
            throw new RuntimeException('No se pudo preparar el directorio de QR');
        }
    }

    $selInsumo = $conn->prepare('SELECT existencia FROM insumos WHERE id = ?');
    // Detectar columna corte_id y obtener corte abierto
    $hasCorteCol = false; $corteId = 0;
    try {
        $rsCol = $conn->query("SHOW COLUMNS FROM entradas_insumos LIKE 'corte_id'");
        if ($rsCol && $rsCol->num_rows > 0) { $hasCorteCol = true; }
    } catch (Throwable $e) { $hasCorteCol = false; }
    if ($hasCorteCol) {
        try {
            $rsC = $conn->query("SELECT id FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1");
            if ($rsC && ($rowC = $rsC->fetch_assoc())) { $corteId = (int)$rowC['id']; }
        } catch (Throwable $e) { $corteId = 0; }
    }

    // Detectar columna 'nota' e inicializar consecutivo incremental por lote de compra
    $hasNotaCol = false; $nota = null;
    try {
        $rsN = $conn->query("SHOW COLUMNS FROM entradas_insumos LIKE 'nota'");
        if ($rsN && $rsN->num_rows > 0) { $hasNotaCol = true; }
    } catch (Throwable $e) { $hasNotaCol = false; }
    if ($hasNotaCol) {
        try {
            $rsUlt = $conn->query("SELECT COALESCE(MAX(nota), 0) AS ult FROM entradas_insumos");
            if ($rsUlt) {
                $rowUlt = $rsUlt->fetch_assoc();
                $nota = (int)($rowUlt && isset($rowUlt['ult']) ? $rowUlt['ult'] : 0) + 1;
            } else { $nota = 1; }
        } catch (Throwable $e) { $nota = 1; }
    }

    // Preparar sentencia de inserción dinámica según columnas disponibles
    $cols = [
        'insumo_id','proveedor_id','usuario_id','descripcion','cantidad','unidad','costo_total','referencia_doc','folio_fiscal','qr','cantidad_actual','credito'
    ];
    if ($hasNotaCol) { $cols[] = 'nota'; }
    if ($hasCorteCol && $corteId > 0) { $cols[] = 'corte_id'; }
    $ph = implode(', ', array_fill(0, count($cols), '?'));
    $sqlIns = 'INSERT INTO entradas_insumos (' . implode(', ', $cols) . ') VALUES (' . $ph . ')';
    $insEntrada = $conn->prepare($sqlIns);
    $updInsumo = $conn->prepare('UPDATE insumos SET existencia = existencia + ? WHERE id = ?');
    $updQr = $conn->prepare('UPDATE entradas_insumos SET qr = ? WHERE id = ?');
    $selEntradaInfo = $conn->prepare('SELECT fecha FROM entradas_insumos WHERE id = ?');
    if (!$selEntradaInfo) {
        throw new RuntimeException('No se pudo preparar la consulta de información de la entrada');
    }

    $conn->begin_transaction();
    $ids = [];
    $entradasRegistradas = [];

    foreach ($productos as $indice => $producto) {
        $insumoId = isset($producto['insumo_id']) ? (int) $producto['insumo_id'] : 0;
        $cantidad = isset($producto['cantidad']) ? (float) str_replace(',', '.', (string) $producto['cantidad']) : 0.0;
        $unidad = isset($producto['unidad']) ? trim((string) $producto['unidad']) : '';
        $costoTotal = isset($producto['costo_total']) ? (float) str_replace(',', '.', (string) $producto['costo_total']) : 0.0;
        $descripcion = trim($producto['descripcion'] ?? $descripcionGlobal);
        $referencia = trim($producto['referencia_doc'] ?? $referenciaGlobal);
        $folio = trim($producto['folio_fiscal'] ?? $folioGlobal);

        if ($insumoId <= 0 || $cantidad <= 0 || $costoTotal <= 0 || $unidad === '') {
            throw new InvalidArgumentException('Datos de producto invalidos en la fila ' . ($indice + 1));
        }

        $selInsumo->bind_param('i', $insumoId);
        $selInsumo->execute();
        $selInsumo->bind_result($existenciaActual);
        if (!$selInsumo->fetch()) {
            $selInsumo->free_result();
            throw new RuntimeException('Insumo no encontrado: ' . $insumoId);
        }
        $selInsumo->free_result();

        $cantidadActual = $cantidad;
        $qrPlaceholder = 'pendiente';

        // Bind dinámico respetando columnas opcionales (nota, corte_id)
        // Cambio: 'credito' ahora es ENUM (texto), no entero
        $types = 'iiisdsdsssds';
        $bindValues = [
            &$insumoId,
            &$proveedorId,
            &$usuarioId,
            &$descripcion,
            &$cantidad,
            &$unidad,
            &$costoTotal,
            &$referencia,
            &$folio,
            &$qrPlaceholder,
            &$cantidadActual,
            &$credito
        ];
        if ($hasNotaCol) { $types .= 'i'; $bindValues[] = &$nota; }
        if ($hasCorteCol && $corteId > 0) { $types .= 'i'; $bindValues[] = &$corteId; }
        $params = array_merge([$types], $bindValues);
        call_user_func_array([$insEntrada, 'bind_param'], $params);
        $insEntrada->execute();
        $entradaId = $insEntrada->insert_id;
        if ($entradaId <= 0) {
            throw new RuntimeException('No se pudo registrar la entrada');
        }

        $qrFileName = 'entrada_insumo_' . $entradaId . '.png';
        $qrRelativePath = 'archivos/qr/' . $qrFileName;
        $qrAbsolutePath = $qrDir . DIRECTORY_SEPARATOR . $qrFileName;
        if (file_exists($qrAbsolutePath) && !unlink($qrAbsolutePath)) {
            throw new RuntimeException('No se pudo preparar el archivo QR para la entrada ' . $entradaId);
        }

        $qrUrl = construirUrlConsultaEntrada($entradaId);
        QRcode::png($qrUrl, $qrAbsolutePath, QR_ECLEVEL_Q, 8, 2);
        if (!file_exists($qrAbsolutePath)) {
            throw new RuntimeException('No se pudo generar el QR para la entrada ' . $entradaId);
        }

        $updQr->bind_param('si', $qrRelativePath, $entradaId);
        $updQr->execute();

        $updInsumo->bind_param('di', $cantidad, $insumoId);
        $updInsumo->execute();

        $selEntradaInfo->bind_param('i', $entradaId);
        $selEntradaInfo->execute();
        $fechaTmp = null;
        $selEntradaInfo->bind_result($fechaTmp);
        $fechaRegistro = null;
        if ($selEntradaInfo->fetch()) {
            $fechaRegistro = $fechaTmp;
        }
        $selEntradaInfo->free_result();

        $ids[] = $entradaId;
        $entradasRegistradas[] = [
            'id' => $entradaId,
            'qr' => $qrRelativePath,
            'consulta_url' => $qrUrl,
            'fecha' => $fechaRegistro
        ];
    }

    $conn->commit();

    $insEntrada->close();
    $updInsumo->close();
    $selInsumo->close();
    $updQr->close();
    $selEntradaInfo->close();

    echo json_encode([
        'success' => true,
        'mensaje' => 'Entrada registrada',
        'ids' => $ids,
        'entradas' => $entradasRegistradas
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    if ($conn->in_transaction) {
        $conn->rollback();
    }
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
}

?>
