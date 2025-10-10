<?php
require_once __DIR__ . '/../../config/db.php';

header('Content-Type: application/json; charset=utf-8');
if (session_status() !== PHP_SESSION_ACTIVE) { session_start(); }
$conn->set_charset('utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function json_ok($payload = []) { echo json_encode(['success'=>true,'ok'=>true]+$payload, JSON_UNESCAPED_UNICODE); exit; }
function json_fail($msg, $code=400, $extra=[]) { http_response_code($code); echo json_encode(['success'=>false,'ok'=>false,'mensaje'=>$msg]+$extra, JSON_UNESCAPED_UNICODE); exit; }
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
    ftruncate($fp, 0); rewind($fp); fwrite($fp, (string)$next); fflush($fp); flock($fp, LOCK_UN); fclose($fp);
    $evt = json_encode(['v'=>$next,'ids'=>array_values(array_unique(array_map('intval',$ids))), 'ts'=>time()]);
    @file_put_contents($eventsLog, $evt . PHP_EOL, FILE_APPEND | LOCK_EX);
}

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (!is_array($data)) { json_fail('JSON inválido'); }
$pedido = isset($data['pedido']) ? (int)$data['pedido'] : 0;
$nuevo = isset($data['nuevo_estado']) ? strtolower(trim((string)$data['nuevo_estado'])) : '';
if ($pedido <= 0) { json_fail('pedido inválido'); }
$allowed = ['pendiente','en_preparacion','listo','entregado'];
if (!in_array($nuevo, $allowed, true)) { json_fail('Estado inválido'); }
$userId = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;
if ($userId <= 0) { json_fail('Usuario no autenticado', 401); }

// Asegurar columna
try { $rs=$conn->query("SHOW COLUMNS FROM procesos_insumos LIKE 'pedido'"); if (!$rs || $rs->num_rows===0) $conn->query("ALTER TABLE procesos_insumos ADD COLUMN pedido INT NOT NULL DEFAULT 0"); } catch (Throwable $e) {}

$conn->begin_transaction();
try {
    // Obtener IDs afectados
    $ids = [];
    $s = $conn->prepare('SELECT id FROM procesos_insumos WHERE pedido = ? FOR UPDATE');
    $s->bind_param('i', $pedido);
    $s->execute();
    $r = $s->get_result();
    while ($row = $r->fetch_assoc()) { $ids[] = (int)$row['id']; }
    $s->close();
    if (!$ids) { throw new RuntimeException('No hay procesos para el pedido'); }

    $set = 'estado = ?, actualizado_en = NOW()';
    $types = 's'; $args = [$nuevo];
    if ($nuevo === 'en_preparacion') { $set .= ', preparado_por = ?'; $types .= 'i'; $args[] = $userId; }
    if ($nuevo === 'listo') { $set .= ', listo_por = ?'; $types .= 'i'; $args[] = $userId; }
    $sql = "UPDATE procesos_insumos SET $set WHERE pedido = ?";
    $types .= 'i'; $args[] = $pedido;
    $u = $conn->prepare($sql);
    $u->bind_param($types, ...$args);
    $u->execute();
    $u->close();
    $conn->commit();
    notificarCambioCocina($ids);
    json_ok(['pedido'=>$pedido,'ids'=>$ids,'estado'=>$nuevo]);
} catch (Throwable $e) {
    try { $conn->rollback(); } catch (Throwable $e2) {}
    json_fail('No se pudo mover el grupo: ' . $e->getMessage());
}

?>

