<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

// Router sencillo para CRUD de reque_tipos
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$accion = isset($_REQUEST['accion']) ? strtolower(trim($_REQUEST['accion'])) : '';
if ($accion === '' && strtoupper($method) === 'GET') { $accion = 'listar'; }

function listar($conn) {
    $res = $conn->query("SELECT id, nombre, activo FROM reque_tipos ORDER BY nombre");
    if (!$res) { error('Error al listar: ' . $conn->error); }
    $out = [];
    while ($r = $res->fetch_assoc()) { $out[] = [ 'id'=>(int)$r['id'], 'nombre'=>$r['nombre'], 'activo'=>(int)$r['activo'] ]; }
    success($out);
}

function crear($conn) {
    $nombre = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
    $activo = isset($_POST['activo']) ? (int)$_POST['activo'] : 1;
    if ($nombre === '') { error('Nombre requerido'); }
    $stmt = $conn->prepare('INSERT INTO reque_tipos (nombre, activo) VALUES (?, ?)');
    if (!$stmt) { error('Error DB: ' . $conn->error); }
    $stmt->bind_param('si', $nombre, $activo);
    if (!$stmt->execute()) { $msg = $stmt->error; $stmt->close(); error('No se pudo crear: ' . $msg); }
    $newId = $stmt->insert_id;
    $stmt->close();
    // devolver fila creada
    $sel = $conn->prepare('SELECT id, nombre, activo FROM reque_tipos WHERE id = ? LIMIT 1');
    $sel->bind_param('i', $newId); $sel->execute(); $res = $sel->get_result();
    $row = $res ? $res->fetch_assoc() : null; $sel->close();
    success([ 'id'=>(int)$row['id'], 'nombre'=>$row['nombre'], 'activo'=>(int)$row['activo'] ]);
}

function actualizar($conn) {
    $id = isset($_POST['id']) ? (int)$_POST['id'] : 0;
    $nombre = isset($_POST['nombre']) ? trim($_POST['nombre']) : '';
    $activo = isset($_POST['activo']) ? (int)$_POST['activo'] : 1;
    if ($id <= 0) { error('ID invalido'); }
    if ($nombre === '') { error('Nombre requerido'); }
    $stmt = $conn->prepare('UPDATE reque_tipos SET nombre = ?, activo = ? WHERE id = ?');
    if (!$stmt) { error('Error DB: ' . $conn->error); }
    $stmt->bind_param('sii', $nombre, $activo, $id);
    if (!$stmt->execute()) { $msg = $stmt->error; $stmt->close(); error('No se pudo actualizar: ' . $msg); }
    $stmt->close();
    success([ 'id'=>$id, 'nombre'=>$nombre, 'activo'=>$activo ]);
}

function eliminar($conn) {
    $id = isset($_POST['id']) ? (int)$_POST['id'] : 0;
    if ($id <= 0) { error('ID invalido'); }
    // validar referencias
    $chk = $conn->prepare('SELECT COUNT(*) c FROM insumos WHERE reque_id = ?');
    $chk->bind_param('i', $id); $chk->execute(); $res = $chk->get_result(); $row = $res->fetch_assoc(); $chk->close();
    if (($row['c'] ?? 0) > 0) { error('No se puede eliminar: hay insumos que lo usan'); }
    $stmt = $conn->prepare('DELETE FROM reque_tipos WHERE id = ? LIMIT 1');
    if (!$stmt) { error('Error DB: ' . $conn->error); }
    $stmt->bind_param('i', $id);
    if (!$stmt->execute()) { $msg = $stmt->error; $stmt->close(); error('No se pudo eliminar: ' . $msg); }
    $stmt->close();
    success([ 'id'=>$id, 'eliminado'=>true ]);
}

switch ($accion) {
    case 'listar': listar($conn); break;
    case 'crear': if ($_SERVER['REQUEST_METHOD'] !== 'POST') error('Metodo no permitido'); crear($conn); break;
    case 'actualizar': if ($_SERVER['REQUEST_METHOD'] !== 'POST') error('Metodo no permitido'); actualizar($conn); break;
    case 'eliminar': if ($_SERVER['REQUEST_METHOD'] !== 'POST') error('Metodo no permitido'); eliminar($conn); break;
    default: listar($conn); break;
}

?>

