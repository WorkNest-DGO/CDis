<?php
function success($data) {
    header('Content-Type: application/json');
    echo json_encode(['success' => true, 'resultado' => $data]);
    exit;
}

function error($mensaje) {
    header('Content-Type: application/json');
    echo json_encode(['success' => false, 'mensaje' => $mensaje]);
    exit;
}
?>
