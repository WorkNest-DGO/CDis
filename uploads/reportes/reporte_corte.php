<?php
require_once __DIR__ . '/../../config/db.php';

$corteId = isset($_GET['corte_id']) ? (int)$_GET['corte_id'] : 0;
if (!$corteId) {
    die('ID inválido');
}

$info = $conn->prepare("SELECT c.id, c.fecha_inicio, c.fecha_fin, ua.nombre AS abierto_por, uc.nombre AS cerrado_por
                        FROM corte_almacen c
                        LEFT JOIN usuarios ua ON c.usuario_abre_id = ua.id
                        LEFT JOIN usuarios uc ON c.usuario_cierra_id = uc.id
                        WHERE c.id = ?");
$info->bind_param('i', $corteId);
$info->execute();
$resInfo = $info->get_result();
if ($resInfo->num_rows === 0) {
    die('Corte no encontrado');
}
$corte = $resInfo->fetch_assoc();
$info->close();

header('Content-Type: text/csv; charset=utf-8');
$filename = 'corte_almacen_' . date('Ymd_Hi') . '.csv';
header('Content-Disposition: attachment; filename=' . $filename);

$out = fopen('php://output', 'w');

fputcsv($out, ['Corte ID', 'Abierto por', 'Cerrado por', 'Inicio', 'Fin']);
fputcsv($out, [$corte['id'], $corte['abierto_por'], $corte['cerrado_por'], $corte['fecha_inicio'], $corte['fecha_fin']]);
fputcsv($out, []);
fputcsv($out, ['Insumo','Inicial','Entradas','Salidas','Mermas','Final']);

$det = $conn->prepare("SELECT i.nombre, d.inicial, d.entradas, d.salidas, d.mermas, d.final
                       FROM corte_almacen_detalle d
                       JOIN insumos i ON d.insumo_id = i.id
                       WHERE d.corte_id = ?");
$det->bind_param('i', $corteId);
$det->execute();
$resDet = $det->get_result();
while ($row = $resDet->fetch_assoc()) {
    fputcsv($out, [$row['nombre'], $row['inicial'], $row['entradas'], $row['salidas'], $row['mermas'], $row['final']]);
}
$det->close();

fclose($out);
exit;
