<?php
// /CDI/api/cocina/listen_cambios.php
// Long-poll: responde solo cuando hay cambios (versión sube) o tras timeout.

header('Content-Type: application/json');

$since    = isset($_GET['since']) ? intval($_GET['since']) : 0;
$timeout  = 25;        // segundos
$sleepUs  = 300000;    // 0.3s por iteración
$dir      = __DIR__ . '/runtime';
$verFile  = $dir . '/cocina_version.txt';
$eventsLog= $dir . '/cocina_events.jsonl';

@mkdir($dir, 0775, true);

function leerVersion($verFile) {
  if (!file_exists($verFile)) return 0;
  $fp = fopen($verFile, 'r');
  if (!$fp) return 0;
  flock($fp, LOCK_SH);
  $txt = stream_get_contents($fp);
  flock($fp, LOCK_UN);
  fclose($fp);
  return intval(trim($txt ?? '0'));
}

$start = microtime(true);

do {
  clearstatcache(true, $verFile);
  $cur = leerVersion($verFile);

  if ($cur > $since) {
    // Recolecta eventos > since y <= cur
    $ids = [];
    if (file_exists($eventsLog)) {
      $fh = fopen($eventsLog, 'r');
      if ($fh) {
        while (($line = fgets($fh)) !== false) {
          $evt = json_decode($line, true);
          if (!$evt) continue;
          if ($evt['v'] > $since && $evt['v'] <= $cur && !empty($evt['ids'])) {
            foreach ($evt['ids'] as $id) $ids[] = (int)$id;
          }
        }
        fclose($fh);
      }
    }
    $ids = array_values(array_unique($ids)); // dedup
    echo json_encode(['changed'=>true, 'version'=>$cur, 'ids'=>$ids]);
    exit;
  }

  usleep($sleepUs);
} while ((microtime(true) - $start) < $timeout);

// No hubo cambios en la ventana
echo json_encode(['changed'=>false, 'version'=>$since]);

