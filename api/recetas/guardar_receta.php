<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['producto_id'], $input['receta']) || !is_array($input['receta'])) {
    error('Datos incompletos');
}

$producto_id = (int) $input['producto_id'];
$receta = $input['receta'];

$ids = [];
foreach ($receta as $r) {
    if (!isset($r['insumo_id'], $r['cantidad'])) {
        error('Formato de receta incorrecto');
    }
    $insumo_id = (int) $r['insumo_id'];
    if (in_array($insumo_id, $ids)) {
        error('Insumo repetido');
    }
    $ids[] = $insumo_id;
}


// Obtener receta existente para aplicar cambios incrementales
$existente = [];
$sel = $conn->prepare('SELECT insumo_id, cantidad FROM recetas WHERE producto_id = ?');
if (!$sel) {
    error('Error al preparar consulta: ' . $conn->error);
}
$sel->bind_param('i', $producto_id);
if (!$sel->execute()) {
    $sel->close();
    error('Error al consultar receta: ' . $sel->error);
}
$res = $sel->get_result();
while ($row = $res->fetch_assoc()) {
    $existente[(int)$row['insumo_id']] = (float)$row['cantidad'];
}
$sel->close();

$conn->begin_transaction();

$stmtIns = $conn->prepare('INSERT INTO recetas (producto_id, insumo_id, cantidad) VALUES (?, ?, ?)');
$stmtUpd = $conn->prepare('UPDATE recetas SET cantidad = ? WHERE producto_id = ? AND insumo_id = ?');
$stmtDel = $conn->prepare('DELETE FROM recetas WHERE producto_id = ? AND insumo_id = ?');
if (!$stmtIns || !$stmtUpd || !$stmtDel) {
    $conn->rollback();
    error('Error al preparar sentencias: ' . $conn->error);
}

foreach ($receta as $r) {
    $insumo_id = (int)$r['insumo_id'];
    $cantidad  = (float)$r['cantidad'];

    if (isset($existente[$insumo_id])) {
        if ($existente[$insumo_id] != $cantidad) {
            $stmtUpd->bind_param('dii', $cantidad, $producto_id, $insumo_id);
            if (!$stmtUpd->execute()) {
                $conn->rollback();
                error('Error al actualizar receta: ' . $stmtUpd->error);
            }
        }
        unset($existente[$insumo_id]);
    } else {
        $stmtIns->bind_param('iid', $producto_id, $insumo_id, $cantidad);
        if (!$stmtIns->execute()) {
            $conn->rollback();
            error('Error al insertar receta: ' . $stmtIns->error);
        }
    }
}

// Eliminar insumos que ya no están en la receta
foreach (array_keys($existente) as $idEliminar) {
    $stmtDel->bind_param('ii', $producto_id, $idEliminar);
    if (!$stmtDel->execute()) {
        $conn->rollback();
        error('Error al eliminar insumo: ' . $stmtDel->error);
    }
}

$conn->commit();
$stmtIns->close();
$stmtUpd->close();
$stmtDel->close();

success(true);
