<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

// Lista registros de la tabla cortes_almacen_detalle
// Parámetros opcionales (GET):
// - corte_id: filtra por corte específico
// - insumo_id: filtra por insumo

try {
    $corteId  = isset($_GET['corte_id']) ? (int)$_GET['corte_id'] : 0;
    $insumoId = isset($_GET['insumo_id']) ? (int)$_GET['insumo_id'] : 0;

    $sql = "SELECT id, corte_id, insumo_id, existencia_inicial, entradas, salidas, mermas, existencia_final
            FROM cortes_almacen_detalle";
    $conds = [];
    $types = '';
    $vals  = [];

    if ($corteId > 0) {
        $conds[] = 'corte_id = ?';
        $types  .= 'i';
        $vals[]   = $corteId;
    }
    if ($insumoId > 0) {
        $conds[] = 'insumo_id = ?';
        $types  .= 'i';
        $vals[]   = $insumoId;
    }

    if ($conds) {
        $sql .= ' WHERE ' . implode(' AND ', $conds);
    }
    $sql .= ' ORDER BY id DESC';

    if ($types) {
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            error('Error al preparar consulta: ' . $conn->error);
        }
        $stmt->bind_param($types, ...$vals);
        $stmt->execute();
        $res = $stmt->get_result();
    } else {
        $res = $conn->query($sql);
        if (!$res) {
            error('Error al consultar: ' . $conn->error);
        }
    }

    $rows = [];
    while ($r = $res->fetch_assoc()) {
        $rows[] = $r;
    }
    if (isset($stmt)) $stmt->close();
    success($rows);
} catch (Throwable $e) {
    error('Error: ' . $e->getMessage());
}

?>

