<?php
function descontarInsumos(int $productoId, int $cantidad): void
{
    global $conn;
    $q = $conn->prepare('SELECT insumo_id, cantidad FROM recetas WHERE producto_id = ?');
    if (!$q) {
        return;
    }
    $q->bind_param('i', $productoId);
    if (!$q->execute()) {
        $q->close();
        return;
    }
    $res = $q->get_result();
    while ($row = $res->fetch_assoc()) {
        $insumo = (int)$row['insumo_id'];
        $descontar = (float)$row['cantidad'] * $cantidad;
        $up = $conn->prepare('UPDATE insumos SET existencia = existencia - ? WHERE id = ?');
        if ($up) {
            $up->bind_param('di', $descontar, $insumo);
            $up->execute();
            $up->close();
        }
    }
    $q->close();
}
?>
