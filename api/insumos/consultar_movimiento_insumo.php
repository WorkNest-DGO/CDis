<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Método no permitido');
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
        $scriptName = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '/api/insumos/consultar_movimiento_insumo.php';
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

$token = isset($_GET['token']) ? trim($_GET['token']) : '';
$id = isset($_GET['id']) ? (int) $_GET['id'] : 0;

if ($token === '' && $id <= 0) {
    error('Parámetros insuficientes');
}

$sql = 'SELECT m.*, u.nombre AS usuario_nombre, ud.nombre AS usuario_destino_nombre, i.nombre AS insumo_nombre, i.unidad AS insumo_unidad
        FROM movimientos_insumos m
        LEFT JOIN usuarios u ON u.id = m.usuario_id
        LEFT JOIN usuarios ud ON ud.id = m.usuario_destino_id
        LEFT JOIN insumos i ON i.id = m.insumo_id
        WHERE %s
        LIMIT 1';

if ($token !== '') {
    $sql = sprintf($sql, 'm.qr_token = ?');
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        error('Error al preparar consulta: ' . $conn->error);
    }
    $stmt->bind_param('s', $token);
} else {
    $sql = sprintf($sql, 'm.id = ?');
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        error('Error al preparar consulta: ' . $conn->error);
    }
    $stmt->bind_param('i', $id);
}

if (!$stmt->execute()) {
    $mensaje = method_exists($stmt, 'error') ? $stmt->error : 'Error al ejecutar consulta';
    $stmt->close();
    error($mensaje);
}

$resultado = $stmt->get_result();
if (!$resultado || $resultado->num_rows === 0) {
    $stmt->close();
    error('Movimiento no encontrado');
}
$movimiento = $resultado->fetch_assoc();
$stmt->close();

$qrImagen = null;
$tokenMovimiento = isset($movimiento['qr_token']) ? $movimiento['qr_token'] : null;
if ($tokenMovimiento) {
    $qrDir = realpath(__DIR__ . '/../../archivos/qr');
    $baseDir = realpath(__DIR__ . '/../../');
    if ($qrDir && $baseDir) {
        $pattern = $qrDir . DIRECTORY_SEPARATOR . '*' . $tokenMovimiento . '*.png';
        $coincidencias = glob($pattern);
        if ($coincidencias && isset($coincidencias[0])) {
            $rutaAbs = $coincidencias[0];
            $rutaAbs = str_replace('\\', '/', $rutaAbs);
            $baseDir = str_replace('\\', '/', $baseDir);
            if (strpos($rutaAbs, $baseDir) === 0) {
                $relativa = ltrim(substr($rutaAbs, strlen($baseDir)), '/');
                $qrImagen = $relativa;
            }
        }
    }
}

try {
    $consultaUrl = construirUrlConsultaMovimiento($tokenMovimiento);
} catch (Throwable $e) {
    $consultaUrl = null;
}

$tipo = isset($movimiento['tipo']) ? (string) $movimiento['tipo'] : '';
$tiposLegibles = [
    'entrada' => 'Entrada',
    'salida' => 'Salida',
    'ajuste' => 'Ajuste',
    'traspaso' => 'Traspaso'
];

$datos = [
    'id' => isset($movimiento['id']) ? (int) $movimiento['id'] : null,
    'tipo' => $tipo,
    'tipo_descripcion' => isset($tiposLegibles[$tipo]) ? $tiposLegibles[$tipo] : ucfirst($tipo),
    'fecha' => isset($movimiento['fecha']) ? $movimiento['fecha'] : null,
    'usuario_id' => isset($movimiento['usuario_id']) ? (int) $movimiento['usuario_id'] : null,
    'usuario_nombre' => isset($movimiento['usuario_nombre']) ? $movimiento['usuario_nombre'] : null,
    'usuario_destino_id' => isset($movimiento['usuario_destino_id']) ? (int) $movimiento['usuario_destino_id'] : null,
    'usuario_destino_nombre' => isset($movimiento['usuario_destino_nombre']) ? $movimiento['usuario_destino_nombre'] : null,
    'insumo_id' => isset($movimiento['insumo_id']) ? (int) $movimiento['insumo_id'] : null,
    'insumo_nombre' => isset($movimiento['insumo_nombre']) ? $movimiento['insumo_nombre'] : null,
    'insumo_unidad' => isset($movimiento['insumo_unidad']) ? $movimiento['insumo_unidad'] : null,
    'cantidad' => isset($movimiento['cantidad']) ? (float) $movimiento['cantidad'] : null,
    'observacion' => isset($movimiento['observacion']) ? $movimiento['observacion'] : null,
    'qr_token' => $tokenMovimiento,
    'qr_consulta_url' => $consultaUrl,
    'qr_imagen' => $qrImagen
];

success($datos);
