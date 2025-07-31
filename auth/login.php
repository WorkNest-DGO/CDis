<?php
require_once __DIR__ . '/../config/db.php';
session_start();
header('Content-Type: application/json');


$input = json_decode(file_get_contents("php://input"), true);
$usuario = $input['usuario'] ?? '';
$contrasena = $input['contrasena'] ?? '';

if (empty($usuario) || empty($contrasena)) {
    echo json_encode(['success' => false, 'mensaje' => 'Faltan datos']);
    exit;
}

$stmt = $conn->prepare("SELECT id, usuario FROM usuarios WHERE usuario = ? AND contrasena = ?");
$stmt->bind_param("ss", $usuario, $contrasena);
$stmt->execute();
$result = $stmt->get_result();
$usuario = $result->fetch_assoc();

if ($usuario) {
    $_SESSION['usuario_id'] = $usuario['id'];
    echo json_encode(['success' => true]);
} else {
    echo json_encode(['success' => false, 'mensaje' => 'Credenciales incorrectas']);
}
?>
