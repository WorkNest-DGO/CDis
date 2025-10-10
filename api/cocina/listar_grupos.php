<?php
require_once __DIR__ . '/../../config/db.php';

header('Content-Type: application/json; charset=utf-8');
if (session_status() !== PHP_SESSION_ACTIVE) { session_start(); }
$conn->set_charset('utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function json_ok($payload = []) { echo json_encode(['success'=>true,'ok'=>true]+$payload, JSON_UNESCAPED_UNICODE); exit; }
function json_fail($msg, $code=400, $extra=[]) { http_response_code($code); echo json_encode(['success'=>false,'ok'=>false,'mensaje'=>$msg]+$extra, JSON_UNESCAPED_UNICODE); exit; }

// Asegurar columna pedido
try {
    $rs = $conn->query("SHOW COLUMNS FROM procesos_insumos LIKE 'pedido'");
    if (!$rs || $rs->num_rows === 0) {
        $conn->query("ALTER TABLE procesos_insumos ADD COLUMN pedido INT NOT NULL DEFAULT 0");
        try { $conn->query("CREATE INDEX idx_proc_pedido ON procesos_insumos(pedido)"); } catch (Throwable $e) { }
    }
} catch (Throwable $e) { /* noop */ }

// Corte abierto
$corte = null;
try {
    $qC = $conn->query("SELECT id, fecha_inicio FROM cortes_almacen WHERE fecha_fin IS NULL ORDER BY id DESC LIMIT 1");
    if ($qC && ($rowC = $qC->fetch_assoc())) { $corte = $rowC; }
} catch (Throwable $e) { /* noop */ }
if (!$corte) { json_ok(['grupos'=>[]]); }
$fechaInicio = $conn->real_escape_string((string)$corte['fecha_inicio']);

// Traer todos los procesos desde el corte actual
$sql = "SELECT p.id, p.pedido, p.estado,
               p.insumo_origen_id, io.nombre AS insumo_origen, p.cantidad_origen, p.unidad_origen,
               p.insumo_destino_id, ides.nombre AS insumo_destino, p.unidad_destino,
               p.creado_en, p.entrada_insumo_id, p.qr_path
        FROM procesos_insumos p
        JOIN insumos io   ON io.id = p.insumo_origen_id
        JOIN insumos ides ON ides.id = p.insumo_destino_id
        WHERE p.creado_en >= '$fechaInicio' AND p.pedido > 0
        ORDER BY p.pedido ASC, p.creado_en DESC";
$rs = $conn->query($sql);

$map = [];
while ($row = $rs->fetch_assoc()) {
    $pedido = (int)$row['pedido'];
    if ($pedido <= 0) { continue; }
    if (!isset($map[$pedido])) {
        $map[$pedido] = [
            'pedido' => $pedido,
            'estado' => (string)$row['estado'],
            'destino_id' => (int)$row['insumo_destino_id'],
            'destino' => (string)$row['insumo_destino'],
            'unidad_destino' => (string)$row['unidad_destino'],
            'entrada_insumo_id' => isset($row['entrada_insumo_id']) ? (int)$row['entrada_insumo_id'] : null,
            'qr_path' => $row['qr_path'] ?? null,
            'procesos' => []
        ];
    }
    // Normalizar estado grupal al "mínimo" progreso si hay diferencias
    $est = (string)$row['estado'];
    $prior = ['pendiente'=>0,'en_preparacion'=>1,'listo'=>2,'entregado'=>3];
    if (isset($prior[$est]) && isset($prior[$map[$pedido]['estado']]) && $prior[$est] < $prior[$map[$pedido]['estado']]) {
        $map[$pedido]['estado'] = $est;
    }
    $map[$pedido]['procesos'][] = [
        'id' => (int)$row['id'],
        'insumo_origen_id' => (int)$row['insumo_origen_id'],
        'insumo_origen' => (string)$row['insumo_origen'],
        'cantidad_origen' => (float)$row['cantidad_origen'],
        'unidad_origen' => (string)$row['unidad_origen']
    ];
}

$grupos = array_values($map);
json_ok(['grupos' => $grupos]);

?>
