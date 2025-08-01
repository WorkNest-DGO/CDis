<?php
require_once __DIR__ . '/../../config/db.php';

header('Content-Type: text/csv; charset=utf-8');
$filename = 'entradas_proveedor_' . date('Ymd') . '.csv';
header('Content-Disposition: attachment; filename=' . $filename);

$output = fopen('php://output', 'w');
fputcsv($output, ['Fecha', 'Proveedor', 'Usuario', 'Insumo', 'Unidad', 'Cantidad', 'Costo total', 'Valor unitario', 'Descripción', 'Referencia', 'Folio fiscal']);

$query = "SELECT e.fecha, p.nombre AS proveedor, u.nombre AS usuario, i.nombre AS insumo, e.unidad, e.cantidad, e.costo_total, e.valor_unitario, e.descripcion, e.referencia_doc, e.folio_fiscal FROM entradas_insumos e JOIN proveedores p ON e.proveedor_id = p.id JOIN usuarios u ON e.usuario_id = u.id JOIN insumos i ON e.insumo_id = i.id ORDER BY e.fecha DESC";
$result = $conn->query($query);
if ($result) {
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, $row);
    }
}

fclose($output);
exit;
?>
