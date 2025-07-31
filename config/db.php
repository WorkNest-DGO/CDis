<?php
$host = 'localhost';
$user = 'root';
$pass = '';
$db   = 'cdis';

$conn = new mysqli($host, $user, $pass, $db);

if ($conn->connect_errno) {
    die('Error de conexión: ' . $conn->connect_error);
}
?>
