<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

function abrirCorte($usuarioId) {
    global $conn;
    if (!$usuarioId) {
        error('Usuario requerido');
    }
    $stmt = $conn->prepare('INSERT INTO cortes_almacen (usuario_abre_id, fecha_inicio) VALUES (?, NOW())');
    if (!$stmt) {
        error('Error al preparar: ' . $conn->error);
    }
    $stmt->bind_param('i', $usuarioId);
    if (!$stmt->execute()) {
        $stmt->close();
        error('Error al abrir corte: ' . $stmt->error);
    }
    $id = $stmt->insert_id;
    $stmt->close();
    success(['corte_id' => $id]);
}

function cerrarCorte($corteId, $usuarioId, $observaciones) {
    global $conn;
    if (!$corteId || !$usuarioId) {
        error('Datos incompletos');
    }
    $stmt = $conn->prepare('SELECT fecha_inicio FROM cortes_almacen WHERE id = ?');
    if (!$stmt) {
        error('Error al obtener corte: ' . $conn->error);
    }
    $stmt->bind_param('i', $corteId);
    $stmt->execute();
    $res = $stmt->get_result();
    if ($res->num_rows === 0) {
        $stmt->close();
        error('Corte no encontrado');
    }
    $row = $res->fetch_assoc();
    $inicio = $row['fecha_inicio'];
    $stmt->close();

    $upd = $conn->prepare('UPDATE cortes_almacen SET usuario_cierra_id = ?, fecha_fin = NOW(), observaciones = ? WHERE id = ?');
    if (!$upd) {
        error('Error al preparar cierre: ' . $conn->error);
    }
    $upd->bind_param('isi', $usuarioId, $observaciones, $corteId);
    if (!$upd->execute()) {
        $upd->close();
        error('Error al cerrar corte: ' . $upd->error);
    }
    $upd->close();

    $mov = $conn->prepare("SELECT insumo_id,
           SUM(CASE WHEN tipo='entrada' THEN cantidad ELSE 0 END) AS entradas,
           SUM(CASE WHEN tipo='salida' THEN cantidad ELSE 0 END) AS salidas
        FROM movimientos_insumos
        WHERE fecha >= ? AND fecha <= NOW()
        GROUP BY insumo_id");
    if (!$mov) {
        error('Error al calcular movimientos: ' . $conn->error);
    }
    $mov->bind_param('s', $inicio);
    $mov->execute();
    $rMov = $mov->get_result();
    $datosMov = [];
    while ($m = $rMov->fetch_assoc()) {
        $datosMov[$m['insumo_id']] = [
            'entradas' => (float)$m['entradas'],
            'salidas' => (float)$m['salidas']
        ];
    }
    $mov->close();

    $hasMerma = $conn->query("SHOW TABLES LIKE 'mermas_insumo'")->num_rows > 0;
    $mermas = [];
    if ($hasMerma) {
        $mm = $conn->prepare('SELECT insumo_id, SUM(cantidad) AS mermas FROM mermas_insumo WHERE fecha >= ? AND fecha <= NOW() GROUP BY insumo_id');
        if ($mm) {
            $mm->bind_param('s', $inicio);
            $mm->execute();
            $rm = $mm->get_result();
            while ($m = $rm->fetch_assoc()) {
                $mermas[$m['insumo_id']] = (float)$m['mermas'];
            }
            $mm->close();
        }
    }

    $resIns = $conn->query('SELECT id, nombre, existencia FROM insumos');
    if (!$resIns) {
        error('Error al obtener insumos: ' . $conn->error);
    }

    $hasDetalle = $conn->query("SHOW TABLES LIKE 'cortes_almacen_detalle'")->num_rows > 0;

    $detalles = [];
    while ($ins = $resIns->fetch_assoc()) {
        $id = (int)$ins['id'];
        $final = (float)$ins['existencia'];
        $entradas = isset($datosMov[$id]) ? $datosMov[$id]['entradas'] : 0;
        $salidas = isset($datosMov[$id]) ? $datosMov[$id]['salidas'] : 0;
        $merma = isset($mermas[$id]) ? $mermas[$id] : 0;
        $inicial = $final - $entradas + $salidas + $merma;
        $d = [
            'insumo_id' => $id,
            'insumo' => $ins['nombre'],
            'inicial' => $inicial,
            'entradas' => $entradas,
            'salidas' => $salidas,
            'mermas' => $merma,
            'final' => $final
        ];
        $detalles[] = $d;

        if ($hasDetalle) {
            $existencia_inicial = $inicial;
            $existencia_final   = $final;

            $insert = "INSERT INTO cortes_almacen_detalle (
                corte_id,
                insumo_id,
                existencia_inicial,
                entradas,
                salidas,
                mermas,
                existencia_final
            ) VALUES (?, ?, ?, ?, ?, ?, ?)";

            $stmtDet = $conn->prepare($insert);
            if ($stmtDet) {
                $stmtDet->bind_param(
                    "iiddddd",
                    $corteId,
                    $id,
                    $existencia_inicial,
                    $entradas,
                    $salidas,
                    $merma,
                    $existencia_final
                );
                $stmtDet->execute();
                $stmtDet->close();
            }
        }
    }
    success(['mensaje' => 'Corte cerrado', 'detalles' => $detalles]);
}

function obtenerCortes() {
    global $conn;
    $sql = "SELECT c.id, ui.nombre AS abierto_por, c.fecha_inicio, uc.nombre AS cerrado_por, c.fecha_fin
            FROM cortes_almacen c
            LEFT JOIN usuarios ui ON c.usuario_abre_id = ui.id
            LEFT JOIN usuarios uc ON c.usuario_cierra_id = uc.id
            ORDER BY c.id DESC";
    $res = $conn->query($sql);
    if (!$res) {
        error('Error al listar cortes: ' . $conn->error);
    }
    $rows = [];
    while ($r = $res->fetch_assoc()) {
        $rows[] = $r;
    }
    success($rows);
}

function obtenerDetalleCorte($corteId) {
    global $conn;
    $stmt = $conn->prepare("SELECT i.nombre AS insumo, d.inicial, d.entradas, d.salidas, d.mermas, d.final
        FROM cortes_almacen_detalle d
        JOIN insumos i ON d.insumo_id = i.id
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
        obtenerCortes();
        break;
    case 'detalle':
        $cid = isset($_GET['corte_id']) ? (int)$_GET['corte_id'] : 0;
        obtenerDetalleCorte($cid);
        break;
    default:
        error('Acción no válida');
}
