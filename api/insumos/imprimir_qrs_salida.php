<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

require __DIR__ . '/../../vendor/autoload.php';

use Mike42\Escpos\Printer;
use Mike42\Escpos\EscposImage;
use Mike42\Escpos\PrintConnectors\WindowsPrintConnector;

// --- Helpers impresoras ---
function cdis_first_printer_ip(mysqli $db): string {
    $sql = "SELECT ip FROM impresoras ORDER BY print_id ASC LIMIT 1";
    if ($st = $db->prepare($sql)) {
        $st->execute();
        $st->bind_result($ip);
        if ($st->fetch() && $ip) {
            $st->close();
            return $ip;
        }
        $st->close();
    }
    throw new Exception("No hay impresoras configuradas en BD.");
}

function cdis_resolve_printer_ip(mysqli $db, ?string $fromPost): string {
    $fromPost = $fromPost !== null ? trim($fromPost) : '';
    if ($fromPost !== '') return $fromPost;
    return cdis_first_printer_ip($db);
}

// Resolver impresora elegida o fallback
try {
    $printerIp = cdis_resolve_printer_ip($conn, $_POST['printer_ip'] ?? ($_GET['printer_ip'] ?? null));
    if (!preg_match('#^(smb://|\\\\)#i', $printerIp)) {
        throw new Exception("Impresora inválida: " . $printerIp);
    }
} catch (Exception $e) {
    error($e->getMessage());
}

function obtenerRutasQrPorToken($token)
{
    $token = trim((string) $token);
    if ($token === '') {
        return [null, null];
    }

    $baseDir = realpath(__DIR__ . '/../../');
    if (!$baseDir) {
        return [null, null];
    }
    $qrDir = $baseDir . DIRECTORY_SEPARATOR . 'archivos' . DIRECTORY_SEPARATOR . 'qr';
    if (!is_dir($qrDir)) {
        return [null, null];
    }

    $pattern = rtrim($qrDir, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . '*' . $token . '*.png';
    $matches = glob($pattern);
    if (!$matches || !isset($matches[0])) {
        return [null, null];
    }

    $absPath = $matches[0];
    if (!is_file($absPath) || !is_readable($absPath)) {
        return [null, null];
    }

    $absPath = str_replace('\\', '/', $absPath);
    $baseDir = str_replace('\\', '/', $baseDir);
    $relative = null;
    if (strpos($absPath, $baseDir) === 0) {
        $relative = ltrim(substr($absPath, strlen($baseDir)), '/');
    }

    return [$absPath, $relative];
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$raw = file_get_contents('php://input');
$payload = json_decode($raw, true);
if (!is_array($payload)) {
    error('Entrada inválida');
}

$ids = [];
if (isset($payload['movimiento_ids']) && is_array($payload['movimiento_ids'])) {
    $ids = array_values(array_filter(array_map('intval', $payload['movimiento_ids']), function ($value) {
        return $value > 0;
    }));
}

if (empty($ids)) {
    error('Sin movimientos para imprimir');
}

$placeholders = implode(',', array_fill(0, count($ids), '?'));
$types = str_repeat('i', count($ids));

$sql = "SELECT m.id,
               m.fecha,
               m.cantidad,
               m.observacion,
               m.qr_token,
               m.insumo_id,
               i.nombre AS insumo_nombre,
               i.unidad AS insumo_unidad,
               u.nombre AS usuario_nombre
        FROM movimientos_insumos m
        LEFT JOIN insumos i ON i.id = m.insumo_id
        LEFT JOIN usuarios u ON u.id = m.usuario_id
        WHERE m.id IN ($placeholders) AND m.tipo = 'salida'";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    error('Error de consulta: ' . $conn->error);
}

$params = [];
$params[] = &$types;
foreach ($ids as $index => $value) {
    $params[] = &$ids[$index];
}

call_user_func_array([$stmt, 'bind_param'], $params);

if (!$stmt->execute()) {
    $stmt->close();
    error('Error al ejecutar consulta: ' . $stmt->error);
}

$result = $stmt->get_result();
$movimientos = [];
while ($row = $result->fetch_assoc()) {
    [$abs, $rel] = obtenerRutasQrPorToken(isset($row['qr_token']) ? $row['qr_token'] : null);
    $row['_qr_abs'] = $abs;
    $row['_qr_rel'] = $rel;
    $movimientos[] = $row;
}
$stmt->close();

if (empty($movimientos)) {
    error('No se encontraron movimientos de salida');
}

$map = [];
foreach ($movimientos as $movimiento) {
    $map[(int) $movimiento['id']] = $movimiento;
}

$ordered = [];
foreach ($ids as $id) {
    if (isset($map[$id])) {
        $ordered[] = $map[$id];
    }
}

if (empty($ordered)) {
    error('Los movimientos solicitados no están disponibles');
}

$impresos = 0;
$sinQr = [];

try {
    $connector = new WindowsPrintConnector($printerIp);
    $printer = new Printer($connector);
    $printer->initialize();

    foreach ($ordered as $item) {
        $qrAbs = isset($item['_qr_abs']) ? $item['_qr_abs'] : null;
        if (!$qrAbs) {
            $sinQr[] = isset($item['id']) ? (int) $item['id'] : null;
            continue;
        }

        $img = EscposImage::load($qrAbs, true);
        $printer->setJustification(Printer::JUSTIFY_CENTER);
        $printer->bitImage($img);
        $printer->feed(1);

        $movId = isset($item['id']) ? (int) $item['id'] : 0;
        $insumoId = isset($item['insumo_id']) ? (int) $item['insumo_id'] : 0;
        $insumoNombre = trim((string) ($item['insumo_nombre'] ?? ''));
        $cantidad = isset($item['cantidad']) ? (float) $item['cantidad'] : null;
        $unidad = trim((string) ($item['insumo_unidad'] ?? ''));
        $fechaRegistro = trim((string) ($item['fecha'] ?? ''));
        $usuarioNombre = trim((string) ($item['usuario_nombre'] ?? ''));
        $observacion = trim((string) ($item['observacion'] ?? ''));

        $lineaMovimiento = $movId > 0 ? ('Salida #' . $movId) : 'Salida de insumo';
        $lineaInsumo = ($insumoId > 0 ? ($insumoId . ' - ') : '') . ($insumoNombre !== '' ? $insumoNombre : 'Insumo');

        $lineaCantidad = null;
        if ($cantidad !== null) {
            $lineaCantidad = 'Cantidad: ' . number_format($cantidad, 2, '.', ',');
            if ($unidad !== '') {
                $lineaCantidad .= ' ' . $unidad;
            }
        }

        $lineaFecha = '';
        if ($fechaRegistro !== '') {
            try {
                $dt = new DateTime($fechaRegistro);
                $lineaFecha = 'Fecha: ' . $dt->format('d/m/Y H:i');
            } catch (Exception $e) {
                $lineaFecha = 'Fecha: ' . $fechaRegistro;
            }
        }

        $lineaUsuario = $usuarioNombre !== '' ? ('Usuario: ' . $usuarioNombre) : '';
        $lineaObservacion = $observacion !== '' ? $observacion : '';

        if ($lineaMovimiento !== '') {
            $printer->text($lineaMovimiento . "\n");
        }
        if ($lineaInsumo !== '') {
            $printer->text($lineaInsumo . "\n");
        }
        if ($lineaCantidad !== null) {
            $printer->text($lineaCantidad . "\n");
        }
        if ($lineaFecha !== '') {
            $printer->text($lineaFecha . "\n");
        }
        if ($lineaUsuario !== '') {
            $printer->text($lineaUsuario . "\n");
        }
        if ($lineaObservacion !== '') {
            $printer->text($lineaObservacion . "\n");
        }

        $printer->feed(2);
        $printer->cut();
        $impresos++;
    }

    $printer->close();
} catch (Exception $e) {
    error('Error de impresión: ' . $e->getMessage());
}

if ($impresos === 0) {
    error('No se encontraron códigos QR disponibles para imprimir');
}

$resultado = ['impresos' => $impresos];
if (!empty($sinQr)) {
    $resultado['sin_qr'] = array_values(array_filter($sinQr));
}

success($resultado);
