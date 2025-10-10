<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

require __DIR__ . '/../../vendor/autoload.php';

use Mike42\Escpos\Printer;
use Mike42\Escpos\EscposImage;
use Mike42\Escpos\PrintConnectors\WindowsPrintConnector;

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
    $ids = array_values(array_filter(array_map('intval', $payload['movimiento_ids']), function ($v) {
        return $v > 0;
    }));
}

if (!$ids) {
    error('Sin movimientos para imprimir');
}

$inPlaceholders = implode(',', array_fill(0, count($ids), '?'));
$types = str_repeat('i', count($ids));

$sql = "SELECT mi.id, mi.fecha, mi.qr_token, IFNULL(mi.qr, '') AS qr_rel,
               mi.insumo_id, i.nombre AS insumo_nombre
        FROM movimientos_insumos mi
        LEFT JOIN insumos i ON i.id = mi.insumo_id
        WHERE mi.id IN ($inPlaceholders) AND mi.tipo = 'merma'";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    error('Error de consulta: ' . $conn->error);
}

$bindParams = [];
$bindParams[] = & $types;
foreach ($ids as $k => $id) {
    $bindParams[] = & $ids[$k];
}
call_user_func_array([$stmt, 'bind_param'], $bindParams);

if (!$stmt->execute()) {
    $stmt->close();
    error('Error al ejecutar consulta: ' . $stmt->error);
}

$res = $stmt->get_result();
$rows = [];
while ($row = $res->fetch_assoc()) {
    $rows[] = $row;
}
$stmt->close();

if (!$rows) {
    error('No se encontraron movimientos de merma');
}

$byId = [];
foreach ($rows as $row) {
    $byId[(int)$row['id']] = $row;
}

$ordered = [];
foreach ($ids as $id) {
    if (isset($byId[$id])) {
        $ordered[] = $byId[$id];
    }
}

$qrDirAbs = @realpath(__DIR__ . '/../../archivos/qr');
$baseDirAbs = @realpath(__DIR__ . '/../../');
if ($qrDirAbs) {
    $qrDirAbs = str_replace('\\', '/', $qrDirAbs);
}
if ($baseDirAbs) {
    $baseDirAbs = str_replace('\\', '/', $baseDirAbs);
}

try {
    $connector = new WindowsPrintConnector("smb://FUED/pos58");
    $printer = new Printer($connector);
    $printer->initialize();

    foreach ($ordered as $item) {
        $qrPath = '';
        $qrRel = trim((string)($item['qr_rel'] ?? ''));
        if ($qrRel !== '') {
            $candidates = [];
            $candidates[] = $qrRel;
            if ($qrRel[0] !== '/' && !preg_match('/^[A-Za-z]:[\\\\\/]/', $qrRel)) {
                $candidates[] = __DIR__ . '/../../' . ltrim($qrRel, '/');
            }
            if (strpos($qrRel, 'archivos/') === 0) {
                $candidates[] = __DIR__ . '/../../' . ltrim($qrRel, '/');
            }
            foreach ($candidates as $candidate) {
                if ($candidate && file_exists($candidate) && is_readable($candidate)) {
                    $qrPath = $candidate;
                    break;
                }
            }
        }

        if ($qrPath === '' || !file_exists($qrPath) || !is_readable($qrPath)) {
            $token = trim((string)($item['qr_token'] ?? ''));
            if ($token !== '' && $qrDirAbs && $baseDirAbs) {
                $pattern = rtrim($qrDirAbs, '/');
                $pattern .= '/*' . $token . '*.png';
                $matches = glob($pattern);
                if ($matches && isset($matches[0])) {
                    $abs = str_replace('\\', '/', $matches[0]);
                    if (file_exists($abs) && is_readable($abs)) {
                        $qrPath = $abs;
                    }
                }
            }
        }

        if ($qrPath === '' || !file_exists($qrPath) || !is_readable($qrPath)) {
            continue;
        }

        $img = EscposImage::load($qrPath, true);
        $printer->setJustification(Printer::JUSTIFY_CENTER);
        $printer->bitImage($img);
        $printer->feed(1);

        $insumoId = isset($item['insumo_id']) ? (int)$item['insumo_id'] : 0;
        $nombre = trim((string)($item['insumo_nombre'] ?? ''));
        $lineaNombre = ($insumoId > 0 ? ($insumoId . ' - ') : '') . $nombre;
        if ($lineaNombre !== '') {
            $printer->text($lineaNombre . "\n");
        }

        $fechaRegistro = trim((string)($item['fecha'] ?? ''));
        if ($fechaRegistro !== '') {
            $fechaLinea = $fechaRegistro;
            try {
                $dt = new DateTime($fechaRegistro);
                $fechaLinea = $dt->format('d/m/Y H:i');
            } catch (Exception $e) {
                $fechaLinea = $fechaRegistro;
            }
            $printer->text('Fecha: ' . $fechaLinea . "\n");
        }

        $movId = (int)($item['id'] ?? 0);
        if ($movId > 0) {
            $printer->text('Lote: ' . $movId . "\n");
        }

        $printer->feed(2);
        $printer->cut();
    }

    $printer->close();
} catch (Exception $e) {
    error('Error de impresión: ' . $e->getMessage());
}

success(['impresos' => count($ordered)]);
