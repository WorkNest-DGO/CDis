<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../utils/inventario.php';
if (!defined('ENVIO_CASA_PRODUCT_ID')) define('ENVIO_CASA_PRODUCT_ID', 9001);

// Antes se invocaba al procedimiento almacenado
// `sp_descuento_insumos_por_detalle` para rebajar inventario.
// Esa función fue eliminada y el descuento se hace aquí
// mediante `descontarInsumos()`.


if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !isset($input['detalle_id'], $input['nuevo_estado'])) {
    error('Datos inválidos');
}

$detalle_id = (int)$input['detalle_id'];
$nuevo_estado = $input['nuevo_estado'];
$permitidos = ['pendiente', 'en_preparacion', 'listo', 'entregado'];
if (!in_array($nuevo_estado, $permitidos, true)) {
    error('Estado no válido');
}

$stmt = $conn->prepare('SELECT estado_producto, producto_id, cantidad, insumos_descargados FROM venta_detalles WHERE id = ?');
if (!$stmt) {
    error('Error al preparar consulta: ' . $conn->error);
}
$stmt->bind_param('i', $detalle_id);
$stmt->execute();
$result = $stmt->get_result();
if (!$result || $result->num_rows === 0) {
    $stmt->close();
    error('Detalle no encontrado');
}
$detalle = $result->fetch_assoc();
$actual   = $detalle['estado_producto'];
$stmt->close();

// NO-OP para producto de envío: responder éxito sin cambiar estado
if (isset($detalle['producto_id']) && (int)$detalle['producto_id'] === (int)ENVIO_CASA_PRODUCT_ID) {
    success(['mensaje' => 'Línea de envío ya está entregada (bloqueada en cocina).']);
}

if ($actual === 'entregado') {
    error('No se puede modificar este producto');
}

$transiciones = [
    'pendiente'        => 'en_preparacion',
    'en_preparacion'   => 'listo',
    'listo'            => 'entregado'
];

if (!isset($transiciones[$actual]) || $transiciones[$actual] !== $nuevo_estado) {
    error('Transición no permitida');
}

// La actualización del estado ya no depende de triggers o procedimientos
// almacenados. Todo se realiza directamente desde PHP.
if ($nuevo_estado === 'entregado') {
    $upd = $conn->prepare("UPDATE venta_detalles SET estado_producto = ?, entregado_hr = IF(entregado_hr IS NULL, NOW(), entregado_hr) WHERE id = ?");
} else {
    $upd = $conn->prepare('UPDATE venta_detalles SET estado_producto = ? WHERE id = ?');
}
if (!$upd) {
    error('Error al preparar actualización: ' . $conn->error);
}
$upd->bind_param('si', $nuevo_estado, $detalle_id);
if (!$upd->execute()) {
    $upd->close();
    error('Error al actualizar: ' . $upd->error);
}

$upd->close();

// Al pasar a "en_preparacion" solo registramos el cambio de estado
if ($nuevo_estado === 'en_preparacion') {
    $log = $conn->prepare('INSERT INTO logs_accion (usuario_id, modulo, accion, referencia_id) VALUES (?, ?, ?, ?)');
    if ($log) {
        $usuario_id = $input['usuario_id'] ?? null;
        $mod        = 'cocina';
        $accion     = 'Producto iniciado';
        $log->bind_param('issi', $usuario_id, $mod, $accion, $detalle_id);
        $log->execute();
        $log->close();
    }
}

// Al pasar a "listo" aseguramos que los insumos ya se descontaron y restamos
// la existencia del producto vendido.
if ($nuevo_estado === 'listo') {
    // Descontamos insumos solo una vez por producto utilizando la receta
    if ((int)$detalle['insumos_descargados'] === 0) {
        $productoId = (int)$detalle['producto_id'];
        $cantidadVenta = (int)$detalle['cantidad'];
        $rec = $conn->prepare('SELECT insumo_id, cantidad FROM recetas WHERE producto_id = ?');
        if ($rec) {
            $rec->bind_param('i', $productoId);
            if ($rec->execute()) {
                $res = $rec->get_result();
                while ($row = $res->fetch_assoc()) {
                    $insumoId = (int)$row['insumo_id'];
                    $descuento = $cantidadVenta * (float)$row['cantidad'];
                    $upInsumo = $conn->prepare('UPDATE insumos SET existencia = existencia - ? WHERE id = ?');
                    if ($upInsumo) {
                        $upInsumo->bind_param('di', $descuento, $insumoId);
                        $upInsumo->execute();
                        $upInsumo->close();
                    }
                }
            }
            $rec->close();
        }

        $stmt = $conn->prepare('UPDATE venta_detalles SET insumos_descargados = 1 WHERE id = ?');
        if ($stmt) {
            $stmt->bind_param('i', $detalle_id);
            $stmt->execute();
            $stmt->close();
        }
    } else {
        // Aseguramos el flag por si proviene de datos inconsistentes
        $stmt = $conn->prepare('UPDATE venta_detalles SET insumos_descargados = 1 WHERE id = ? AND insumos_descargados = 0');
        if ($stmt) {
            $stmt->bind_param('i', $detalle_id);
            $stmt->execute();
            $stmt->close();
        }
    }

    // Descontar existencia del producto vendido
    $updProd = $conn->prepare('UPDATE productos SET existencia = existencia - ? WHERE id = ?');
    if ($updProd) {
        $cant = (int)$detalle['cantidad'];
        $pid  = (int)$detalle['producto_id'];
        $updProd->bind_param('ii', $cant, $pid);
        $updProd->execute();
        $updProd->close();
    }

    $log = $conn->prepare('INSERT INTO logs_accion (usuario_id, modulo, accion, referencia_id) VALUES (?, ?, ?, ?)');
    if ($log) {
        $usuario_id = $input['usuario_id'] ?? null;
        $mod        = 'cocina';
        $accion     = 'Producto marcado como listo';
        $log->bind_param('issi', $usuario_id, $mod, $accion, $detalle_id);
        $log->execute();
        $log->close();
    }
}

// Notificar cambio a pantallas de cocina (long-poll por versión)
try {
    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host   = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $base   = rtrim(dirname($_SERVER['REQUEST_URI'] ?? '/'), '/');
    $url    = $scheme . '://' . $host . $base . '/notify_cambio.php';
    $ctx = stream_context_create(['http' => [
        'method'  => 'POST',
        'header'  => "Content-Type: application/json",
        'content' => json_encode(['ids' => [$detalle_id]]),
        'timeout' => 2
    ]]);
    @file_get_contents($url, false, $ctx);
} catch (\Throwable $e) {
    // opcional: log
}

success(true);
?>
