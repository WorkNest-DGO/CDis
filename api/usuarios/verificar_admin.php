<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
// No alterar la sesión actual del cajero; solo verificar credenciales

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    error('Método no permitido');
}

$data = json_decode(file_get_contents('php://input'), true);
if (!$data) { error('JSON inválido'); }

$usuario = trim($data['usuario'] ?? '');
$contrasena = (string)($data['contrasena'] ?? '');
if ($usuario === '' || $contrasena === '') { error('Faltan credenciales'); }

$stmt = $conn->prepare('SELECT id, usuario, rol, contrasena, activo FROM usuarios WHERE usuario = ? LIMIT 1');
if (!$stmt) { error('Error preparando consulta: ' . $conn->error); }
$stmt->bind_param('s', $usuario);
if (!$stmt->execute()) { $stmt->close(); error('Error ejecutando consulta: ' . $stmt->error); }
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$row || (int)$row['activo'] !== 1) { error('Usuario no válido'); }

$hashDb = (string)$row['contrasena'];
$ok = false;
// Aceptar coincidencia exacta o SHA1 según datos existentes
if ($hashDb === $contrasena) {
    $ok = true;
} elseif ($hashDb === sha1($contrasena)) {
    $ok = true;
}

if (!$ok) { error('Contraseña incorrecta'); }
if (strtolower((string)$row['rol']) !== 'admin') { error('No es administrador'); }

success(['es_admin' => true, 'usuario' => ['id' => (int)$row['id'], 'usuario' => $row['usuario']]]);
?>

