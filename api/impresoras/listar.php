<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

try {
    $items = [];
    $sql = "SELECT ip, lugar FROM impresoras ORDER BY print_id ASC";
    if ($st = $conn->prepare($sql)) {
        if ($st->execute()) {
            $st->bind_result($ip, $lugar);
            while ($st->fetch()) {
                $items[] = [
                    'ip' => (string)$ip,
                    'lugar' => (string)$lugar
                ];
            }
        }
        $st->close();
    }
    success($items);
} catch (Throwable $e) {
    error('No fue posible listar impresoras');
}
?>
