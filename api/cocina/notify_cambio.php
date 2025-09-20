<?php
// /CDI/api/cocina/notify_cambio.php
// Recibe ids de venta_detalles cambiados y actualiza una versión global en archivos,
// para despertar a las pantallas (long-poll) sin tocar la BD.

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['ok'=>false,'msg'=>'Método no permitido']);
  exit;
}

$raw = file_get_contents('php://input');
$payload = json_decode($raw, true);
$ids = isset($payload['ids']) && is_array($payload['ids'])
  ? array_values(array_unique(array_map('intval',$payload['ids'])))
  : [];

if (!$ids) {
  echo json_encode(['ok'=>false,'msg'=>'ids vacíos']);
  exit;
}

$dir = __DIR__ . '/runtime';
@mkdir($dir, 0775, true);

$verFile   = $dir . '/cocina_version.txt';
$eventsLog = $dir . '/cocina_events.jsonl';

$fp = fopen($verFile, 'c+'); // crea si no existe
if (!$fp) {
  http_response_code(500);
  echo json_encode(['ok'=>false,'msg'=>'No se pudo abrir version.txt']);
  exit;
}

flock($fp, LOCK_EX);
$txt  = stream_get_contents($fp);
$cur  = intval(trim($txt ?? '0'));
$next = $cur + 1;
ftruncate($fp, 0);
rewind($fp);
fwrite($fp, (string)$next);
fflush($fp);
flock($fp, LOCK_UN);
fclose($fp);

// Anexa evento con versión e ids
$evt = json_encode(['v'=>$next,'ids'=>$ids,'ts'=>time()]);
file_put_contents($eventsLog, $evt . PHP_EOL, FILE_APPEND | LOCK_EX);

echo json_encode(['ok'=>true,'version'=>$next]);

