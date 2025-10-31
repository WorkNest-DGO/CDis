<?php
require_once __DIR__ . '/../../config/db.php';

header('Content-Type: text/csv; charset=utf-8');
$fn = 'proveedores_' . date('Ymd_His') . '.csv';
header('Content-Disposition: attachment; filename=' . $fn);

$out = fopen('php://output', 'w');
// Encabezados de columnas
fputcsv($out, [
  'id','nombre','rfc','razon_social','regimen_fiscal','correo_facturacion',
  'telefono','telefono2','correo','direccion','contacto_nombre','contacto_puesto',
  'dias_credito','limite_credito','banco','clabe','cuenta_bancaria','sitio_web',
  'observacion','activo','fecha_alta','actualizado_en'
]);

$sql = "SELECT id, nombre, rfc, razon_social, regimen_fiscal, correo_facturacion,
                telefono, telefono2, correo, direccion, contacto_nombre, contacto_puesto,
                dias_credito, limite_credito, banco, clabe, cuenta_bancaria, sitio_web,
                observacion, activo, fecha_alta, actualizado_en
        FROM proveedores
        ORDER BY nombre";
$res = $conn->query($sql);
if ($res) {
    while ($row = $res->fetch_assoc()) {
        // Normalizar valores nulos a cadena vacía
        $vals = [];
        foreach ([
            'id','nombre','rfc','razon_social','regimen_fiscal','correo_facturacion',
            'telefono','telefono2','correo','direccion','contacto_nombre','contacto_puesto',
            'dias_credito','limite_credito','banco','clabe','cuenta_bancaria','sitio_web',
            'observacion','activo','fecha_alta','actualizado_en'] as $k) {
            $vals[] = isset($row[$k]) ? $row[$k] : '';
        }
        fputcsv($out, $vals);
    }
}
fclose($out);
exit;
?>

