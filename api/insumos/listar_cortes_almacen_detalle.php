<?php
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../utils/response.php';

// Lista de detalle de corte calculado en tiempo real.
// Parámetros (GET):
// - corte_id: si viene, calcula para ese corte usando entradas/movimientos.
// - insumo_id: opcional para filtrar un insumo específico (aplicado tras consulta).

try {
    $corteId  = isset($_GET['corte_id']) ? (int)$_GET['corte_id'] : 0;
    $insumoId = isset($_GET['insumo_id']) ? (int)$_GET['insumo_id'] : 0;

    if ($corteId > 0) {
        $sql = "WITH corte AS (
  SELECT id, fecha_inicio, COALESCE(fecha_fin, NOW()) AS fecha_fin
  FROM cortes_almacen
  WHERE id = ?
),
rango AS (
  SELECT c.id AS corte_id, c.fecha_inicio AS desde, c.fecha_fin AS hasta
  FROM corte c
),
base_insumos AS (
  SELECT i.id AS insumo_id, i.nombre AS insumo
  FROM insumos i
),
inicial AS (
  /* Si hay registro en cortes_almacen_detalle úsalo, si no 0 */
  SELECT bi.insumo_id,
         COALESCE(MAX(cad.existencia_inicial), 0) AS existencia_inicial
  FROM base_insumos bi
  LEFT JOIN cortes_almacen_detalle cad
         ON cad.insumo_id = bi.insumo_id
        AND cad.corte_id = (SELECT corte_id FROM rango)
  GROUP BY bi.insumo_id
),
entradas AS (
  SELECT ei.insumo_id,
         COALESCE(SUM(ei.cantidad), 0) AS entradas
  FROM entradas_insumos ei
  WHERE
    (ei.corte_id = (SELECT corte_id FROM rango))
    OR (ei.corte_id IS NULL AND ei.fecha >= (SELECT desde FROM rango) AND ei.fecha < (SELECT hasta FROM rango))
  GROUP BY ei.insumo_id
),
salidas AS (
  SELECT mi.insumo_id,
         ABS(COALESCE(SUM(mi.cantidad), 0)) AS salidas
  FROM movimientos_insumos mi
  WHERE
    mi.cantidad < 0
    AND COALESCE(mi.tipo, '') IN ('', 'salida', 'traspaso', 'ajuste')
    AND (
      mi.corte_id = (SELECT corte_id FROM rango)
      OR (mi.corte_id IS NULL AND mi.fecha >= (SELECT desde FROM rango) AND mi.fecha < (SELECT hasta FROM rango))
    )
  GROUP BY mi.insumo_id
),
mermas AS (
  SELECT mi.insumo_id,
         ABS(COALESCE(SUM(mi.cantidad), 0)) AS mermas
  FROM movimientos_insumos mi
  WHERE
    mi.cantidad < 0
    AND mi.tipo = 'merma'
    AND (
      mi.corte_id = (SELECT corte_id FROM rango)
      OR (mi.corte_id IS NULL AND mi.fecha >= (SELECT desde FROM rango) AND mi.fecha < (SELECT hasta FROM rango))
    )
  GROUP BY mi.insumo_id
)
SELECT
  bi.insumo_id,
  bi.insumo,
  ini.existencia_inicial,
  COALESCE(en.entradas, 0) AS entradas,
  COALESCE(sa.salidas, 0)  AS salidas,
  COALESCE(me.mermas, 0)   AS mermas,
  ROUND(ini.existencia_inicial + COALESCE(en.entradas,0) - COALESCE(sa.salidas,0) - COALESCE(me.mermas,0), 2) AS existencia_final
FROM base_insumos bi
LEFT JOIN inicial ini ON ini.insumo_id = bi.insumo_id
LEFT JOIN entradas en ON en.insumo_id = bi.insumo_id
LEFT JOIN salidas  sa ON sa.insumo_id = bi.insumo_id
LEFT JOIN mermas   me ON me.insumo_id = bi.insumo_id
ORDER BY bi.insumo";

        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            error('Error al preparar consulta de corte: ' . $conn->error);
        }
        $stmt->bind_param('i', $corteId);
        $stmt->execute();
        $res = $stmt->get_result();
        $rows = [];
        while ($r = $res->fetch_assoc()) {
            if ($insumoId > 0 && (int)$r['insumo_id'] !== $insumoId) continue;
            $rows[] = $r;
        }
        $stmt->close();
        success($rows);
        exit;
    }

    // Fallback: sin corte_id, devolver datos crudos de la tabla detalle
    $sql = "SELECT id, corte_id, insumo_id, existencia_inicial, entradas, salidas, mermas, existencia_final FROM cortes_almacen_detalle";
    $conds = [];
    $types = '';
    $vals  = [];
    if ($insumoId > 0) { $conds[] = 'insumo_id = ?'; $types .= 'i'; $vals[] = $insumoId; }
    if ($conds) { $sql .= ' WHERE ' . implode(' AND ', $conds); }
    $sql .= ' ORDER BY id DESC';
    if ($types) {
        $stmt = $conn->prepare($sql);
        if (!$stmt) { error('Error al preparar consulta: ' . $conn->error); }
        $stmt->bind_param($types, ...$vals);
        $stmt->execute();
        $res = $stmt->get_result();
    } else {
        $res = $conn->query($sql);
        if (!$res) { error('Error al consultar: ' . $conn->error); }
    }
    $rows = [];
    while ($r = $res->fetch_assoc()) { $rows[] = $r; }
    if (isset($stmt)) $stmt->close();
    success($rows);
} catch (Throwable $e) {
    error('Error: ' . $e->getMessage());
}

?>

