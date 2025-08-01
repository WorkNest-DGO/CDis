<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

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
    $resIns = $conn->query('SELECT id, existencia FROM insumos');
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

    // obtener fecha de inicio del corte y validar que esté abierto
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
    $row = $res->fetch_assoc();
    $inicio = $row['fecha_inicio'];
    $stmt->close();

    // obtener movimientos por insumo en el rango del corte
    $mov = $conn->prepare("SELECT insumo_id,
            SUM(CASE WHEN tipo='entrada' THEN cantidad ELSE 0 END) AS entradas,
            SUM(CASE WHEN tipo IN ('salida','traspaso') THEN cantidad ELSE 0 END) AS salidas,
            SUM(CASE WHEN tipo='ajuste' AND cantidad < 0 THEN ABS(cantidad) ELSE 0 END) AS mermas
        FROM movimientos_insumos
        WHERE fecha >= ? AND fecha <= NOW()
        GROUP BY insumo_id");
    if (!$mov) {
        $conn->rollback();
        error('Error al calcular movimientos: ' . $conn->error);
    }
    $mov->bind_param('s', $inicio);
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

    // mermas adicionales si existe tabla mermas_insumo
    $hasMerma = $conn->query("SHOW TABLES LIKE 'mermas_insumo'")->num_rows > 0;
    if ($hasMerma) {
        $mm = $conn->prepare('SELECT insumo_id, SUM(cantidad) AS merma FROM mermas_insumo WHERE fecha >= ? AND fecha <= NOW() GROUP BY insumo_id');
        if ($mm) {
            $mm->bind_param('s', $inicio);
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

    // existencia final actual de insumos
    $resIns = $conn->query('SELECT id, existencia FROM insumos');
    if (!$resIns) {
        $conn->rollback();
        error('Error al obtener insumos: ' . $conn->error);
    }
    $existenciasFinales = [];
    while ($row = $resIns->fetch_assoc()) {
        $existenciasFinales[$row['id']] = (float)$row['existencia'];
    }

    // obtener existencias iniciales del corte
    $det = $conn->prepare('SELECT insumo_id, existencia_inicial FROM cortes_almacen_detalle WHERE corte_id = ?');
    if (!$det) {
        $conn->rollback();
        error('Error al obtener detalles: ' . $conn->error);
    }
    $det->bind_param('i', $corteId);
    $det->execute();
    $resDet = $det->get_result();

    $updDet = $conn->prepare('UPDATE cortes_almacen_detalle SET entradas = ?, salidas = ?, mermas = ?, existencia_final = ? WHERE corte_id = ? AND insumo_id = ?');
    if (!$updDet) {
        $det->close();
        $conn->rollback();
        error('Error al preparar actualización de detalle: ' . $conn->error);
    }

    $detalles = [];
    while ($row = $resDet->fetch_assoc()) {
        $insumoId = (int)$row['insumo_id'];
        $existenciaInicial = (float)$row['existencia_inicial'];
        $entradas = $datosMov[$insumoId]['entradas'] ?? 0;
        $salidas  = $datosMov[$insumoId]['salidas'] ?? 0;
        $mermas   = $datosMov[$insumoId]['mermas'] ?? 0;
        $final    = $existenciasFinales[$insumoId] ?? 0;

        $updDet->bind_param('ddddii', $entradas, $salidas, $mermas, $final, $corteId, $insumoId);
        if (!$updDet->execute()) {
            $updDet->close();
            $det->close();
            $conn->rollback();
            error('Error al actualizar detalle: ' . $updDet->error);
        }

        $detalles[] = [
            'insumo_id' => $insumoId,
            'inicial'   => $existenciaInicial,
            'entradas'  => $entradas,
            'salidas'   => $salidas,
            'mermas'    => $mermas,
            'final'     => $final
        ];
    }
    $updDet->close();
    $det->close();

    // cerrar corte
    $upd = $conn->prepare('UPDATE cortes_almacen SET fecha_fin = NOW(), usuario_cierra_id = ?, observaciones = ? WHERE id = ?');
    if (!$upd) {
        $conn->rollback();
        error('Error al preparar cierre: ' . $conn->error);
    }
    $upd->bind_param('isi', $usuarioId, $observaciones, $corteId);
    if (!$upd->execute()) {
        $upd->close();
        $conn->rollback();
        error('Error al cerrar corte: ' . $upd->error);
    }
    $upd->close();

    $conn->commit();
    success(['corte_id' => $corteId, 'detalles' => $detalles]);
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
