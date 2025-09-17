<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Método no permitido');
}

$entradaId = isset($_GET['entrada_id']) ? (int) $_GET['entrada_id'] : 0;
if ($entradaId <= 0) {
    error('Entrada inválida');
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
        $scriptName = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '/api/insumos/listar_movimientos_entrada.php';
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

function buscarRutaQrPorToken($token)
{
    $token = trim((string) $token);
    if ($token === '') {
        return null;
    }
    $qrDir = realpath(__DIR__ . '/../../archivos/qr');
    $baseDir = realpath(__DIR__ . '/../../');
    if (!$qrDir || !$baseDir) {
        return null;
    }
    $pattern = $qrDir . DIRECTORY_SEPARATOR . '*' . $token . '*.png';
    $coincidencias = glob($pattern);
    if (!$coincidencias || !isset($coincidencias[0])) {
        return null;
    }
    $rutaAbs = str_replace('\\', '/', $coincidencias[0]);
    $baseDir = str_replace('\\', '/', $baseDir);
    if (strpos($rutaAbs, $baseDir) !== 0) {
        return null;
    }
    $relativa = ltrim(substr($rutaAbs, strlen($baseDir)), '/');
    return $relativa !== '' ? $relativa : null;
}

$pattern = 'Retiro de entrada #' . $entradaId . '%';
$sql = "SELECT m.*, 
               u.nombre AS usuario_nombre,
               ud.nombre AS usuario_destino_nombre,
               i.nombre AS insumo_nombre,
               i.unidad AS insumo_unidad
        FROM movimientos_insumos m
        LEFT JOIN usuarios u ON u.id = m.usuario_id
        LEFT JOIN usuarios ud ON ud.id = m.usuario_destino_id
        LEFT JOIN insumos i ON i.id = m.insumo_id
        WHERE m.tipo = 'salida' AND m.observacion LIKE ?
        ORDER BY m.fecha DESC, m.id DESC";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    error('Error al preparar consulta: ' . $conn->error);
}

$stmt->bind_param('s', $pattern);
if (!$stmt->execute()) {
    $mensaje = method_exists($stmt, 'error') ? $stmt->error : 'Error al ejecutar consulta';
    $stmt->close();
    error($mensaje);
}

$resultado = $stmt->get_result();
$movimientos = [];
if ($resultado) {
    while ($row = $resultado->fetch_assoc()) {
        $token = isset($row['qr_token']) ? $row['qr_token'] : null;
        $qrImagen = buscarRutaQrPorToken($token);
        try {
            $consultaUrl = $token ? construirUrlConsultaMovimiento($token) : null;
        } catch (Throwable $e) {
            $consultaUrl = null;
        }
        $movimientos[] = [
            'id' => isset($row['id']) ? (int) $row['id'] : null,
            'entrada_id' => $entradaId,
            'tipo' => isset($row['tipo']) ? $row['tipo'] : null,
            'fecha' => isset($row['fecha']) ? $row['fecha'] : null,
            'usuario_id' => isset($row['usuario_id']) ? (int) $row['usuario_id'] : null,
            'usuario_nombre' => isset($row['usuario_nombre']) ? $row['usuario_nombre'] : null,
            'usuario_destino_id' => isset($row['usuario_destino_id']) ? (int) $row['usuario_destino_id'] : null,
            'usuario_destino_nombre' => isset($row['usuario_destino_nombre']) ? $row['usuario_destino_nombre'] : null,
            'insumo_id' => isset($row['insumo_id']) ? (int) $row['insumo_id'] : null,
            'insumo_nombre' => isset($row['insumo_nombre']) ? $row['insumo_nombre'] : null,
            'insumo_unidad' => isset($row['insumo_unidad']) ? $row['insumo_unidad'] : null,
            'unidad' => isset($row['insumo_unidad']) ? $row['insumo_unidad'] : null,
            'cantidad' => isset($row['cantidad']) ? (float) $row['cantidad'] : null,
            'retirado' => isset($row['cantidad']) ? (float) $row['cantidad'] : null,
            'observacion' => isset($row['observacion']) ? $row['observacion'] : null,
            'qr_token' => $token,
            'qr_consulta_url' => $consultaUrl,
            'qr_imagen' => $qrImagen
        ];
    }
}
$stmt->close();

success($movimientos);
