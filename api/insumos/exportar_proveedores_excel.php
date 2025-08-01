<?php
require_once __DIR__ . '/../../config/db.php';

header('Content-Type: text/csv; charset=utf-8');
$filename = 'proveedores_' . date('Ymd') . '.csv';
header('Content-Disposition: attachment; filename=' . $filename);

$output = fopen('php://output', 'w');
fputcsv($output, ['ID', 'Nombre del proveedor', 'Teléfono', 'Dirección']);

$result = $conn->query("SELECT id, nombre, telefono, direccion FROM proveedores ORDER BY nombre");
if ($result) {
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, $row);
    }
}

fclose($output);
exit;
?>
