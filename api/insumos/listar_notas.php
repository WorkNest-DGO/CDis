<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    error('Metodo no permitido');
}

try {
    $sql = "SELECT DISTINCT e.nota AS nota
            FROM entradas_insumos e
            WHERE e.nota IS NOT NULL AND e.nota > 0
            ORDER BY e.nota DESC";
    $res = $conn->query($sql);
    if ($res === false) {
        error('Error al listar notas: ' . $conn->error);
    }
    $rows = [];
    while ($r = $res->fetch_assoc()) {
        // Asegurar entero
        $r['nota'] = (int)$r['nota'];
        $rows[] = $r;
    }
    success($rows);
} catch (Throwable $e) {
    error('Excepcion al listar notas: ' . $e->getMessage());
}
?>

