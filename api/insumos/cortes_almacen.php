<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';
require_once __DIR__ . '/../../vendor/autoload.php';

function abrirCorte($usuarioId) {
    global $conn;

    if (!$usuarioId) {
        error('Usuario requerido');
    }

    // validar si existe un corte abierto para este usuario
    $check = $conn->prepare('SELECT id FROM cortes_almacen WHERE usuario_abre_id = ? AND fecha_fin IS NULL LIMIT 1');
    if (!$check) {
        error('Error al verificar corte: ' . $conn->error);
    }
    $check->bind_param('i', $usuarioId);
    $check->execute();
    $res = $check->get_result();
    if ($res && $row = $res->fetch_assoc()) {
        $check->close();
        // ya hay un corte abierto, devolver id existente
        success(['corte_id' => (int)$row['id']]);
    }
    $check->close();

    $conn->begin_transaction();

    $stmt = $conn->prepare('INSERT INTO cortes_almacen (usuario_abre_id, fecha_inicio) VALUES (?, NOW())');
    if (!$stmt) {
        $conn->rollback();
        error('Error al preparar: ' . $conn->error);
    }
    $stmt->bind_param('i', $usuarioId);
    if (!$stmt->execute()) {
        $stmt->close();
        $conn->rollback();
        error('Error al abrir corte: ' . $stmt->error);
    }
    $corteId = $stmt->insert_id;
    $stmt->close();

    // registrar inventario inicial por insumo
    $resIns = $conn->query('SELECT id, existencia, nombre, unidad FROM insumos');
    if (!$resIns) {
        $conn->rollback();
        error('Error al obtener insumos: ' . $conn->error);
    }

    $hasDetalle = $conn->query("SHOW TABLES LIKE 'cortes_almacen_detalle'")->num_rows > 0;
    if ($hasDetalle) {
        $insStmt = $conn->prepare('INSERT INTO cortes_almacen_detalle (corte_id, insumo_id, existencia_inicial, entradas, salidas, mermas, existencia_final) VALUES (?, ?, ?, 0, 0, 0, NULL)');
        if (!$insStmt) {
            $conn->rollback();
            error('Error al preparar detalles: ' . $conn->error);
        }

        while ($ins = $resIns->fetch_assoc()) {
            $insumoId = (int)$ins['id'];
            $existencia = (float)$ins['existencia'];
            $insStmt->bind_param('iid', $corteId, $insumoId, $existencia);
            if (!$insStmt->execute()) {
                $insStmt->close();
                $conn->rollback();
                error('Error al insertar detalle: ' . $insStmt->error);
            }
        }
        $insStmt->close();
    }

    $conn->commit();
    success(['corte_id' => $corteId]);
}

function cerrarCorte($corteId, $usuarioId, $observaciones) {
    global $conn;

    if (!$corteId || !$usuarioId) {
        error('Datos incompletos');
    }

    $conn->begin_transaction();

    // obtener inicio del corte y validar que no esté cerrado
    $stmt = $conn->prepare('SELECT fecha_inicio FROM cortes_almacen WHERE id = ? AND fecha_fin IS NULL');
    if (!$stmt) {
        $conn->rollback();
        error('Error al obtener corte: ' . $conn->error);
    }
    $stmt->bind_param('i', $corteId);
    $stmt->execute();
    $res = $stmt->get_result();
    if ($res->num_rows === 0) {
        $stmt->close();
        $conn->rollback();
        error('Corte no encontrado o ya cerrado');
    }
    $row    = $res->fetch_assoc();
    $inicio = $row['fecha_inicio'];
    $stmt->close();

    $fin = date('Y-m-d H:i:s');

    // registrar cierre del corte para obtener fecha_fin fija
    $updCorte = $conn->prepare('UPDATE cortes_almacen SET fecha_fin = ?, usuario_cierra_id = ?, observaciones = ? WHERE id = ? AND fecha_fin IS NULL');
    if (!$updCorte) {
        $conn->rollback();
        error('Error al preparar cierre: ' . $conn->error);
    }
    $updCorte->bind_param('sisi', $fin, $usuarioId, $observaciones, $corteId);
    if (!$updCorte->execute()) {
        $updCorte->close();
        $conn->rollback();
        error('Error al cerrar corte: ' . $updCorte->error);
    }
    $updCorte->close();

    // obtener insumos con existencia actual
    $resIns = $conn->query('SELECT id, existencia FROM insumos');
    if (!$resIns) {
        $conn->rollback();
        error('Error al obtener insumos: ' . $conn->error);
    }

    // obtener detalles existentes y validar duplicados
    $det = $conn->prepare('SELECT insumo_id, existencia_inicial FROM cortes_almacen_detalle WHERE corte_id = ?');
    if (!$det) {
        $conn->rollback();
        error('Error al obtener detalles: ' . $conn->error);
    }
    $det->bind_param('i', $corteId);
    $det->execute();
    $resDet = $det->get_result();
    $detalleMap = [];
    while ($d = $resDet->fetch_assoc()) {
        $detalleMap[$d['insumo_id']] = (float)$d['existencia_inicial'];
    }
    $det->close();

    $dupCheck = $conn->prepare('SELECT COUNT(*) c FROM cortes_almacen_detalle WHERE corte_id = ? GROUP BY insumo_id HAVING c > 1 LIMIT 1');
    if ($dupCheck) {
        $dupCheck->bind_param('i', $corteId);
        $dupCheck->execute();
        $dupRes = $dupCheck->get_result();
        if ($dupRes && $dupRes->num_rows > 0) {
            $dupCheck->close();
            $conn->rollback();
            error('Registros duplicados en detalle');
        }
        $dupCheck->close();
    }

    // movimientos y mermas en el rango
    $mov = $conn->prepare("SELECT insumo_id,
            SUM(CASE WHEN tipo='entrada' OR (tipo='ajuste' AND cantidad>0) THEN cantidad ELSE 0 END) AS entradas,
            SUM(CASE WHEN tipo IN ('salida','traspaso') THEN cantidad ELSE 0 END) AS salidas,
            SUM(CASE WHEN tipo='ajuste' AND cantidad<0 THEN ABS(cantidad) ELSE 0 END) AS mermas
        FROM movimientos_insumos
        WHERE fecha BETWEEN ? AND ?
        GROUP BY insumo_id");
    if (!$mov) {
        $conn->rollback();
        error('Error al calcular movimientos: ' . $conn->error);
    }
    $mov->bind_param('ss', $inicio, $fin);
    $mov->execute();
    $rMov = $mov->get_result();
    $datosMov = [];
    while ($m = $rMov->fetch_assoc()) {
        $datosMov[$m['insumo_id']] = [
            'entradas' => (float)$m['entradas'],
            'salidas'  => (float)$m['salidas'],
            'mermas'   => (float)$m['mermas']
        ];
    }
    $mov->close();

    $hasMerma = $conn->query("SHOW TABLES LIKE 'mermas_insumo'")->num_rows > 0;
    if ($hasMerma) {
        $mm = $conn->prepare('SELECT insumo_id, SUM(cantidad) AS merma FROM mermas_insumo WHERE fecha BETWEEN ? AND ? GROUP BY insumo_id');
        if ($mm) {
            $mm->bind_param('ss', $inicio, $fin);
            $mm->execute();
            $rm = $mm->get_result();
            while ($m = $rm->fetch_assoc()) {
                $id = $m['insumo_id'];
                $cantidad = (float)$m['merma'];
                if (!isset($datosMov[$id])) {
                    $datosMov[$id] = ['entradas' => 0, 'salidas' => 0, 'mermas' => 0];
                }
                $datosMov[$id]['mermas'] += $cantidad;
            }
            $mm->close();
        }
    }

    $updDet = $conn->prepare('UPDATE cortes_almacen_detalle SET entradas = ?, salidas = ?, mermas = ?, existencia_final = ? WHERE corte_id = ? AND insumo_id = ?');
    if (!$updDet) {
        $conn->rollback();
        error('Error al preparar actualización de detalle: ' . $conn->error);
    }

    $insDet = $conn->prepare('INSERT INTO cortes_almacen_detalle (corte_id, insumo_id, existencia_inicial, entradas, salidas, mermas, existencia_final) VALUES (?, ?, ?, ?, ?, ?, ?)');
    if (!$insDet) {
        $updDet->close();
        $conn->rollback();
        error('Error al preparar inserción de detalle: ' . $conn->error);
    }

    $detalles = [];
    while ($ins = $resIns->fetch_assoc()) {
        $insumoId = (int)$ins['id'];
        $existenciaActual = (float)$ins['existencia'];
        $entradas = $datosMov[$insumoId]['entradas'] ?? 0;
        $salidas  = $datosMov[$insumoId]['salidas'] ?? 0;
        $mermas   = $datosMov[$insumoId]['mermas'] ?? 0;

        if (isset($detalleMap[$insumoId])) {
            $updDet->bind_param('ddddii', $entradas, $salidas, $mermas, $existenciaActual, $corteId, $insumoId);
            if (!$updDet->execute()) {
                $insDet->close();
                $updDet->close();
                $conn->rollback();
                error('Error al actualizar detalle: ' . $updDet->error);
            }
            $inicial = $detalleMap[$insumoId];
        } else {
            $insDet->bind_param('iiddddd', $corteId, $insumoId, $existenciaActual, $entradas, $salidas, $mermas, $existenciaActual);
            if (!$insDet->execute()) {
                $insDet->close();
                $updDet->close();
                $conn->rollback();
                error('Error al insertar detalle: ' . $insDet->error);
            }
            $inicial = $existenciaActual;
        }

        $detalles[] = [
            'insumo'    => $ins['nombre'] ?? 'Insumo eliminado',
            'unidad'    => $ins['unidad'] ?? '',
            'existencia_inicial' => $inicial,
            'entradas'  => $entradas,
            'salidas'   => $salidas,
            'mermas'    => $mermas,
            'existencia_final' => $existenciaActual
        ];
    }
    $insDet->close();
    $updDet->close();

    $conn->commit();
    success(['corte_id' => $corteId, 'detalles' => $detalles]);
}

function obtenerCortes($fecha = null) {
    global $conn;
    $sql = "SELECT c.id, ui.nombre AS abierto_por, c.fecha_inicio, uc.nombre AS cerrado_por, c.fecha_fin
            FROM cortes_almacen c
            LEFT JOIN usuarios ui ON c.usuario_abre_id = ui.id
            LEFT JOIN usuarios uc ON c.usuario_cierra_id = uc.id";
    $params = [];
    if ($fecha) {
        $sql .= " WHERE DATE(c.fecha_inicio) = ?";
        $params[] = $fecha;
    }
    $sql .= " ORDER BY c.id DESC";
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        error('Error al preparar listado: ' . $conn->error);
    }
    if ($fecha) {
        $stmt->bind_param('s', $fecha);
    }
    $stmt->execute();
    $res = $stmt->get_result();
    $rows = [];
    while ($r = $res->fetch_assoc()) {
        $rows[] = $r;
    }
    $stmt->close();
    success($rows);
}

function obtenerDetalleCorte($corteId) {
    global $conn;
    $stmt = $conn->prepare("SELECT COALESCE(i.nombre,'Insumo eliminado') AS insumo,
            COALESCE(i.unidad,'') AS unidad,
            d.existencia_inicial, d.entradas, d.salidas, d.mermas, d.existencia_final
        FROM cortes_almacen_detalle d
        LEFT JOIN insumos i ON d.insumo_id = i.id
        WHERE d.corte_id = ?");
    if (!$stmt) {
        error('Error al preparar detalle: ' . $conn->error);
    }
    $stmt->bind_param('i', $corteId);
    $stmt->execute();
    $res = $stmt->get_result();
    $detalles = [];
    while ($row = $res->fetch_assoc()) {
        $detalles[] = $row;
    }
    $stmt->close();
    success($detalles);
}

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;

function exportarExcel($corteId) {
    global $conn;
    if (!$corteId) {
        error('Corte inválido');
    }
    $stmt = $conn->prepare("SELECT COALESCE(i.nombre,'Insumo eliminado') AS insumo,
            COALESCE(i.unidad,'') AS unidad,
            d.existencia_inicial, d.entradas, d.salidas, d.mermas, d.existencia_final
        FROM cortes_almacen_detalle d
        LEFT JOIN insumos i ON d.insumo_id = i.id
        WHERE d.corte_id = ?");
    if (!$stmt) {
        error('Error al obtener datos: ' . $conn->error);
    }
    $stmt->bind_param('i', $corteId);
    $stmt->execute();
    $res = $stmt->get_result();
    $spreadsheet = new Spreadsheet();
    $sheet = $spreadsheet->getActiveSheet();
    $sheet->fromArray(['Insumo','Unidad','Inicial','Entradas','Salidas','Mermas','Final'], NULL, 'A1');
    $row = 2;
    while ($d = $res->fetch_assoc()) {
        $sheet->fromArray([
            $d['insumo'],
            $d['unidad'],
            $d['existencia_inicial'],
            $d['entradas'],
            $d['salidas'],
            $d['mermas'],
            $d['existencia_final']
        ], NULL, 'A' . $row);
        $row++;
    }
    $stmt->close();
    $fileName = '/uploads/reportes/corte_almacen_' . $corteId . '_' . date('Ymd_His') . '.xlsx';
    $path = __DIR__ . '/../../' . ltrim($fileName, '/');
    $writer = new Xlsx($spreadsheet);
    $writer->save($path);
    success(['archivo' => $fileName]);
}

$accion = $_GET['accion'] ?? $_POST['accion'] ?? '';

switch ($accion) {
    case 'abrir':
        $user = isset($_POST['usuario_id']) ? (int)$_POST['usuario_id'] : 0;
        abrirCorte($user);
        break;
    case 'cerrar':
        $corteId = isset($_POST['corte_id']) ? (int)$_POST['corte_id'] : 0;
        $user = isset($_POST['usuario_id']) ? (int)$_POST['usuario_id'] : 0;
        $obs = $_POST['observaciones'] ?? '';
        cerrarCorte($corteId, $user, $obs);
        break;
    case 'listar':
        $fecha = $_GET['fecha'] ?? null;
        obtenerCortes($fecha);
        break;
    case 'detalle':
        $cid = isset($_GET['corte_id']) ? (int)$_GET['corte_id'] : 0;
        obtenerDetalleCorte($cid);
        break;
    case 'exportar_excel':
        $cid = isset($_POST['corte_id']) ? (int)$_POST['corte_id'] : 0;
        exportarExcel($cid);
        break;
    default:
        error('Acción no válida');
}
