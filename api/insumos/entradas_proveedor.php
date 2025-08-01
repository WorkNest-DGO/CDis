<?php
require_once __DIR__ . '/../../config/db.php';
session_start();
require_once __DIR__ . '/../../utils/response.php';

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $sql = "SELECT e.id, e.fecha, e.cantidad, e.unidad, e.costo_total, p.nombre AS proveedor, i.nombre AS insumo
            FROM entradas_insumos e
            JOIN proveedores p ON e.proveedor_id = p.id
            JOIN insumos i ON e.insumo_id = i.id
            ORDER BY e.fecha DESC";
    $res = $conn->query($sql);
    if (!$res) {
        error('Error al obtener entradas: ' . $conn->error);
    }
    $datos = [];
    while ($row = $res->fetch_assoc()) {
        $datos[] = $row;
    }
    success($datos);
}
elseif ($method === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        error('JSON inválido');
    }
    $proveedor_id  = isset($input['proveedor_id']) ? (int)$input['proveedor_id'] : 0;
    $insumo_id     = isset($input['insumo_id']) ? (int)$input['insumo_id'] : 0;
    $cantidad      = isset($input['cantidad']) ? (float)$input['cantidad'] : 0;
    $unidad        = trim($input['unidad'] ?? '');
    $costo_total   = isset($input['costo_total']) ? (float)$input['costo_total'] : 0;
    $valor_unitario= isset($input['valor_unitario']) ? (float)$input['valor_unitario'] : 0;
    $descripcion   = trim($input['descripcion'] ?? '');
    $referencia    = trim($input['referencia_doc'] ?? '');
    $folio         = trim($input['folio_fiscal'] ?? '');
    $usuario_id    = isset($_SESSION['usuario_id']) ? (int)$_SESSION['usuario_id'] : 0;

    if (!$proveedor_id || !$insumo_id) {
        error('Proveedor e insumo requeridos');
    }
    if ($cantidad <= 0 || $costo_total <= 0) {
        error('Cantidad y costo deben ser mayores a cero');
    }

    // validar existencia de proveedor e insumo
    $check = $conn->prepare('SELECT id FROM proveedores WHERE id = ?');
    $check->bind_param('i', $proveedor_id);
    $check->execute();
    if ($check->get_result()->num_rows === 0) {
        $check->close();
        error('Proveedor no existente');
    }
    $check->close();
    $check = $conn->prepare('SELECT id FROM insumos WHERE id = ?');
    $check->bind_param('i', $insumo_id);
    $check->execute();
    if ($check->get_result()->num_rows === 0) {
        $check->close();
        error('Insumo no existente');
    }
    $check->close();

    $stmt = $conn->prepare('INSERT INTO entradas_insumos (proveedor_id, insumo_id, cantidad, unidad, costo_total, valor_unitario, descripcion, referencia_doc, folio_fiscal, usuario_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
    if (!$stmt) {
        error('Error al preparar inserción: ' . $conn->error);
    }
    $stmt->bind_param('iidddddssi', $proveedor_id, $insumo_id, $cantidad, $unidad, $costo_total, $valor_unitario, $descripcion, $referencia, $folio, $usuario_id);
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al insertar: ' . $stmt->error);
    }
    $stmt->close();

    // registrar movimiento
    $mov = $conn->prepare("INSERT INTO movimientos_insumos (tipo, usuario_id, insumo_id, cantidad, observacion) VALUES ('entrada', ?, ?, ?, ?)");
    if ($mov) {
        $mov->bind_param('iids', $usuario_id, $insumo_id, $cantidad, $descripcion);
        $mov->execute();
        $mov->close();
    }

    // actualizar existencia de insumo
    $up = $conn->prepare('UPDATE insumos SET existencia = existencia + ? WHERE id = ?');
    if ($up) {
        $up->bind_param('di', $cantidad, $insumo_id);
        $up->execute();
        $up->close();
    }

    success(['mensaje' => 'Entrada registrada']);
}
elseif ($method === 'PUT') {
    parse_str(file_get_contents('php://input'), $input);
    $id = isset($input['id']) ? (int)$input['id'] : 0;
    if (!$id) error('ID requerido');
    $cantidad    = isset($input['cantidad']) ? (float)$input['cantidad'] : null;
    $costo_total = isset($input['costo_total']) ? (float)$input['costo_total'] : null;
    $descripcion = isset($input['descripcion']) ? $input['descripcion'] : null;
    $sql = 'UPDATE entradas_insumos SET cantidad = COALESCE(?, cantidad), costo_total = COALESCE(?, costo_total), descripcion = COALESCE(?, descripcion) WHERE id = ?';
    $stmt = $conn->prepare($sql);
    $stmt->bind_param('ddsi', $cantidad, $costo_total, $descripcion, $id);
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al actualizar');
    }
    $stmt->close();
    success(true);
}
elseif ($method === 'DELETE') {
    parse_str(file_get_contents('php://input'), $input);
    $id = isset($input['id']) ? (int)$input['id'] : 0;
    if (!$id) error('ID requerido');
    $stmt = $conn->prepare('DELETE FROM entradas_insumos WHERE id = ?');
    $stmt->bind_param('i', $id);
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al eliminar');
    }
    $stmt->close();
    success(true);
} else {
    error('Método no permitido');
}
