<?php
session_start();
if (isset($_SESSION['nombre'])) {
    header('Location: vistas/ventas.php');
} else {
    header('Location: login.html');
}
exit;
?>
