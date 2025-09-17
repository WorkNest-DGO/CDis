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
    $insEntrada = $conn->prepare('INSERT INTO entradas_insumos (insumo_id, proveedor_id, usuario_id, descripcion, cantidad, unidad, costo_total, referencia_doc, folio_fiscal, qr, cantidad_actual) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
    $updInsumo = $conn->prepare('UPDATE insumos SET existencia = existencia + ? WHERE id = ?');
    $updQr = $conn->prepare('UPDATE entradas_insumos SET qr = ? WHERE id = ?');

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

        $cantidadActual = $existenciaActual + $cantidad;
        $qrPlaceholder = 'pendiente';

        $insEntrada->bind_param(
            'iiisdsdsssd',
            $insumoId,
            $proveedorId,
            $usuarioId,
            $descripcion,
            $cantidad,
            $unidad,
            $costoTotal,
            $referencia,
            $folio,
            $qrPlaceholder,
            $cantidadActual
        );
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

        $ids[] = $entradaId;
        $entradasRegistradas[] = [
            'id' => $entradaId,
            'qr' => $qrRelativePath,
            'consulta_url' => $qrUrl
        ];
    }

    $conn->commit();

    $insEntrada->close();
    $updInsumo->close();
    $selInsumo->close();
    $updQr->close();

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
