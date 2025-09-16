<?php
require_once __DIR__ . '/../../config/db.php';
session_start();
header('Content-Type: application/json');


$data = json_decode(file_get_contents("php://input"), true);

if (!$data) {
    echo json_encode(["success" => false, "mensaje" => "No se recibieron datos"]);
    exit;
}

$usuario = $data['usuario'];
$contrasenaIngresada = $data['contrasena'];

// Buscar usuario
$sql = "SELECT * FROM usuarios WHERE usuario = ? AND activo = 1 LIMIT 1";
$stmt = $conn->prepare($sql);
$stmt->bind_param("s", $usuario);
$stmt->execute();
$result = $stmt->get_result();

if ($row = $result->fetch_assoc()) {
    $contrasenaBD = $row['contrasena'];

    // Comparar hash o plano
    if ($contrasenaBD === sha1($contrasenaIngresada) || $contrasenaBD === $contrasenaIngresada) {
        
        // ✅ Crear sesión
        $_SESSION['usuario_id'] = $row['id'];
        $_SESSION['usuario'] = $row['usuario'];
        $_SESSION['rol'] = $row['rol'];
        $_SESSION['nombre'] = $row['nombre'];

        echo json_encode([
            "success" => true,
            "usuario" => [
                "id" => $row['id'],
                "nombre" => $row['nombre'],
                "usuario" => $row['usuario'],
                "rol" => $row['rol']
            ]
        ]);
        exit;
    }
}

// ❌ Fallo
echo json_encode([
    "success" => false,
    "mensaje" => "Usuario o contraseña incorrectos"
]);