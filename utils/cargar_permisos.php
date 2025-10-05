<?php
  require_once __DIR__ . '/../config/db.php';
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

if (!isset($_SESSION['usuario_id'])) {
    // Redirigir a login en lugar de imprimir mensaje
    $sn = isset($_SERVER['SCRIPT_NAME']) ? (string)$_SERVER['SCRIPT_NAME'] : '/';
    $snLower = strtolower($sn);
    $pos = strpos($snLower, '/cdi/');
    $basePath = ($pos !== false) ? substr($sn, 0, $pos + 4) : '/CDI';
    $loginPath = rtrim($basePath, '/') . '/login.html';
    if (!headers_sent()) {
        header('Location: ' . $loginPath);
    }
    exit;
}

if (!isset($_SESSION['rutas_permitidas'])) {
  

    $usuario_id = $_SESSION['usuario_id'];
    $sql = "SELECT r.path FROM usuario_ruta ur INNER JOIN rutas r ON ur.ruta_id = r.id WHERE ur.usuario_id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param('i', $usuario_id);
    $stmt->execute();
    $result = $stmt->get_result();

    $_SESSION['rutas_permitidas'] = [];
    while ($row = $result->fetch_assoc()) {
        $_SESSION['rutas_permitidas'][] = $row['path'];
    }
}
?>
