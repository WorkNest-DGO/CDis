<?php
// /CDI/api/cocina/estados_por_ids.php
require_once __DIR__ . '/../../config/db.php'; // conexión existente
header('Content-Type: application/json');

$raw     = file_get_contents('php://input');
$payload = json_decode($raw, true);
$ids = isset($payload['ids']) && is_array($payload['ids'])
  ? array_values(array_unique(array_map('intval',$payload['ids'])))
  : [];

if (!$ids) { echo json_encode(['ok'=>true,'estados'=>[]]); exit; }

$place = implode(',', array_fill(0, count($ids), '?'));

if ($stmt = $conn->prepare("SELECT id, estado_producto FROM venta_detalles WHERE id IN ($place)")) {
  $types = str_repeat('i', count($ids));
  $stmt->bind_param($types, ...$ids);
  $stmt->execute();
  $res = $stmt->get_result();
  $map = [];
  while ($r = $res->fetch_assoc()) {
    $map[(int)$r['id']] = $r['estado_producto'];
  }
  $stmt->close();
  echo json_encode(['ok'=>true,'estados'=>$map]);
} else {
  http_response_code(500);
  echo json_encode(['ok'=>false,'msg'=>'Error preparando consulta']);
}

