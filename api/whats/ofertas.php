<?php
header('Content-Type: application/json');
require_once __DIR__ . '/../../config/db.php';

if ($conn->connect_error) {
    echo json_encode(["error" => "DB connection failed"]);
    exit;
}

$query = "SELECT descripcion FROM ofertas_dia WHERE vigente = 1 ";
$resultado = $conn->query($query);

$ofertas = [];
while ($fila = $resultado->fetch_assoc()) {
    $ofertas[] = $fila;
}

echo json_encode(["ofertas" => $ofertas]);
?>
