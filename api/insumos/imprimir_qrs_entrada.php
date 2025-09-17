<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

// Librería de impresión ESC/POS (ya usada en bodega/imprimir_qr.php)
require __DIR__ . '/../../vendor/autoload.php';
use Mike42\Escpos\Printer;
use Mike42\Escpos\EscposImage;
use Mike42\Escpos\PrintConnectors\WindowsPrintConnector;

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

// Acepta JSON: { entrada_ids: [1,2,3] }
$raw = file_get_contents('php://input');
$payload = json_decode($raw, true);
if (!is_array($payload)) {
    error('Entrada inválida');
}

$ids = [];
if (isset($payload['entrada_ids']) && is_array($payload['entrada_ids'])) {
    $ids = array_values(array_filter(array_map('intval', $payload['entrada_ids']), function ($v) {
        return $v > 0;
    }));
}

if (empty($ids)) {
    error('Sin entradas para imprimir');
}

// Consulta de datos por cada entrada
$inPlaceholders = implode(',', array_fill(0, count($ids), '?'));
$types = str_repeat('i', count($ids));

$sql = "SELECT ei.id, ei.qr, ei.cantidad, ei.unidad, ei.insumo_id, i.nombre AS insumo_nombre
        FROM entradas_insumos ei
        LEFT JOIN insumos i ON i.id = ei.insumo_id
        WHERE ei.id IN ($inPlaceholders)";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    error('Error de consulta: ' . $conn->error);
}

// bind_param requires refs
$bindParams = [];
$bindParams[] = & $types;
foreach ($ids as $k => $v) {
    $bindParams[] = & $ids[$k];
}
call_user_func_array([$stmt, 'bind_param'], $bindParams);

if (!$stmt->execute()) {
    $stmt->close();
    error('Error al ejecutar consulta: ' . $stmt->error);
}

$res = $stmt->get_result();
$entradas = [];
while ($row = $res->fetch_assoc()) {
    $entradas[] = $row;
}
$stmt->close();

if (empty($entradas)) {
    error('No se encontraron entradas');
}

// Ordena resultados según el orden de IDs recibido
$map = [];
foreach ($entradas as $e) {
    $map[(int)$e['id']] = $e;
}
$ordered = [];
foreach ($ids as $id) {
    if (isset($map[$id])) $ordered[] = $map[$id];
}

try {
    // Ajusta el conector a tu impresora (igual a bodega/imprimir_qr.php)
    $connector = new WindowsPrintConnector("smb://FUED/pos58");
    $printer = new Printer($connector);
    $printer->initialize();

    foreach ($ordered as $item) {
        $qrRel = $item['qr'];
        $qrPath = __DIR__ . '/../../' . ltrim($qrRel, '/');
        if (!file_exists($qrPath) || !is_readable($qrPath)) {
            // Intenta con ruta absoluta ya guardada
            $qrPath = $qrRel;
        }
        if (!file_exists($qrPath) || !is_readable($qrPath)) {
            // Si no existe, salta y continúa con los demás
            continue;
        }

        $img = EscposImage::load($qrPath, true);
        // Centrar y enviar imagen
        $printer->setJustification(Printer::JUSTIFY_CENTER);
        $printer->bitImage($img);
        $printer->feed(1);

        // Texto debajo del QR: "id - nombre" y "Cant: X unidad"
        $insumoId = (int)($item['insumo_id'] ?? 0);
        $nombre = trim((string)($item['insumo_nombre'] ?? ''));
        $cantidad = rtrim(rtrim(number_format((float)($item['cantidad'] ?? 0), 2, '.', ''), '0'), '.');
        $unidad = trim((string)($item['unidad'] ?? ''));

        $lineaNombre = ($insumoId > 0 ? ($insumoId . ' - ') : '') . ($nombre !== '' ? $nombre : '');
        $lineaCantidad = 'Cant: ' . ($cantidad !== '' ? $cantidad : '0') . ($unidad !== '' ? (' ' . $unidad) : '');

        if ($lineaNombre !== '') {
            $printer->text($lineaNombre . "\n");
        }
        $printer->text($lineaCantidad . "\n");
        $printer->feed(2);
        $printer->cut();
    }

    $printer->close();
} catch (Exception $e) {
    error('Error de impresión: ' . $e->getMessage());
}

success(['impresos' => count($ordered)]);
