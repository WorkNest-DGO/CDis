-- =====================================================================
-- Restaurante/CDI - Paquete de vistas y SPs para reportería y KPIs
-- Fecha de generación: 2025-10-17
-- Compatibilidad: MySQL/MariaDB (XAMPP)
-- NOTAS:
--  - Ajusta nombres de columnas/tablas si difieren en tu esquema.
--  - Las VISTAS usan CREATE OR REPLACE para facilitar re-deploy.
--  - Los SPs se recrean con DROP PROCEDURE IF EXISTS.
-- =====================================================================

/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE */;
SET SQL_MODE='STRICT_ALL_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';

-- =====================================================================
-- 1) COMPRAS Y COSTOS
-- =====================================================================

-- Vista: Compras por proveedor (monto, cantidad, costo prom. unitario)
CREATE OR REPLACE VIEW vw_compras_por_proveedor AS
SELECT
  p.id  AS proveedor_id,
  p.nombre,
  COUNT(ei.id)                                  AS compras,
  ROUND(SUM(ei.costo_total),2)                  AS monto_total,
  ROUND(SUM(ei.costo_total)/NULLIF(SUM(ei.cantidad),0),4) AS costo_prom_unit
FROM entradas_insumos ei
LEFT JOIN proveedores p ON p.id=ei.proveedor_id
GROUP BY p.id,p.nombre;

-- Vista: Compras por insumo (drill-down rápido)
CREATE OR REPLACE VIEW vw_compras_por_insumo AS
SELECT i.id AS insumo_id, i.nombre,
       COUNT(ei.id) AS compras,
       ROUND(SUM(ei.costo_total),2) AS monto_total,
       ROUND(SUM(ei.costo_total)/NULLIF(SUM(ei.cantidad),0),4) AS costo_prom_unit,
       MIN(ei.fecha) AS primera_compra,
       MAX(ei.fecha) AS ultima_compra
FROM insumos i
LEFT JOIN entradas_insumos ei ON ei.insumo_id=i.id
GROUP BY i.id,i.nombre
ORDER BY i.nombre;

-- =====================================================================
-- 2) CONSUMO / KARDEX
-- =====================================================================

-- Vista: Consumo por insumo (salidas + traspasos salida) y mermas
CREATE OR REPLACE VIEW vw_consumo_por_insumo AS
SELECT i.id AS insumo_id, i.nombre,
       SUM(CASE WHEN m.tipo='salida'   AND m.cantidad<0 THEN -m.cantidad ELSE 0 END) AS salidas,
       SUM(CASE WHEN m.tipo='traspaso' AND m.cantidad<0 THEN -m.cantidad ELSE 0 END) AS traspasos_salida,
       SUM(CASE WHEN m.tipo='merma' THEN ABS(m.cantidad) ELSE 0 END) AS mermas,
       (SUM(CASE WHEN m.tipo='salida'   AND m.cantidad<0 THEN -m.cantidad ELSE 0 END)
       +SUM(CASE WHEN m.tipo='traspaso' AND m.cantidad<0 THEN -m.cantidad ELSE 0 END)) AS consumo
FROM insumos i
LEFT JOIN movimientos_insumos m ON m.insumo_id=i.id
GROUP BY i.id,i.nombre;

-- Stored Procedure: Resumen Kardex por insumo y rango
DROP PROCEDURE IF EXISTS sp_kardex_resumen;
DELIMITER $$
CREATE PROCEDURE sp_kardex_resumen(IN p_desde DATETIME, IN p_hasta DATETIME, IN p_insumo INT)
BEGIN
  DECLARE v_hasta DATETIME;
  SET v_hasta = IF(TIME(p_hasta)='00:00:00', DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY), p_hasta);

  /* Saldo inicial desde cortes_almacen_detalle (si no existe, caerá en 0) */
  WITH base AS (
    SELECT i.id AS insumo_id, COALESCE(cad.existencia_inicial,0) AS inicial
    FROM insumos i
    LEFT JOIN cortes_almacen_detalle cad
           ON cad.insumo_id=i.id
    WHERE i.id = p_insumo
    LIMIT 1
  ),
  movs AS (
    SELECT
      m.insumo_id,
      SUM(CASE WHEN m.tipo='ajuste' THEN m.cantidad ELSE 0 END)                     AS ajustes,
      SUM(CASE WHEN m.tipo='devolucion' THEN m.cantidad ELSE 0 END)                 AS devoluciones,
      SUM(CASE WHEN m.tipo='merma' THEN m.cantidad ELSE 0 END)                      AS mermas_raw,
      SUM(CASE WHEN m.tipo='traspaso' AND m.cantidad<0 THEN -m.cantidad ELSE 0 END) AS traspasos_salida,
      SUM(CASE WHEN m.tipo='salida'   AND m.cantidad<0 THEN -m.cantidad ELSE 0 END) AS salidas
    FROM movimientos_insumos m
    WHERE m.fecha >= p_desde AND m.fecha < v_hasta AND m.insumo_id=p_insumo
  ),
  entradas AS (
    SELECT
      ei.insumo_id,
      SUM(CASE WHEN ei.proveedor_id IS NULL OR ei.proveedor_id<>1 THEN ei.cantidad ELSE 0 END) AS entradas,
      SUM(CASE WHEN ei.proveedor_id = 1 THEN ei.cantidad ELSE 0 END)                           AS otras_entradas
    FROM entradas_insumos ei
    WHERE ei.fecha >= p_desde AND ei.fecha < v_hasta AND ei.insumo_id=p_insumo
  )
  SELECT
    b.insumo_id,
    b.inicial AS existencia_inicial,
    COALESCE(e.entradas,0)       AS entradas_compras,
    COALESCE(m.devoluciones,0)   AS devoluciones,
    COALESCE(e.otras_entradas,0) AS otras_entradas,
    COALESCE(m.salidas,0)        AS salidas,
    COALESCE(m.traspasos_salida,0) AS traspasos_salida,
    ABS(COALESCE(m.merms_raw,0)) AS mermas,
    COALESCE(m.ajustes,0)        AS ajustes,
    (b.inicial
      + COALESCE(e.entradas,0)
      + COALESCE(m.devoluciones,0)
      + COALESCE(e.otras_entradas,0)
      - COALESCE(m.salidas,0)
      - COALESCE(m.traspasos_salida,0)
      - ABS(COALESCE(m.merms_raw,0))
      + COALESCE(m.ajustes,0)
    ) AS existencia_final;
END$$
DELIMITER ;

-- =====================================================================
-- 3) REABASTO Y ALERTAS
-- =====================================================================

-- Vista: Alertas de reabasto con días restantes
CREATE OR REPLACE VIEW vw_reabasto_alertas AS
SELECT a.insumo_id, i.nombre, a.proxima_estimada, a.status,
       DATEDIFF(a.proxima_estimada, CURRENT_DATE()) AS dias_restantes
FROM reabasto_alertas a
JOIN insumos i ON i.id=a.insumo_id;

-- =====================================================================
-- 4) PROCESOS (RENDIMIENTO)
-- =====================================================================

-- Vista: Rendimiento de procesos origen→destino (requiere v_procesos_insumos)
CREATE OR REPLACE VIEW vw_procesos_rendimiento AS
SELECT v.*,
       ROUND(v.cantidad_resultante/NULLIF(v.cantidad_origen,0),4) AS rendimiento
FROM v_procesos_insumos v;

-- =====================================================================
-- 5) BAJO STOCK (semáforo simple) - opcional si ya existe
-- =====================================================================
CREATE OR REPLACE VIEW vw_bajo_stock AS
SELECT id AS insumo_id, nombre, existencia, minimo_stock,
       CASE
         WHEN existencia <= minimo_stock THEN 'BAJO'
         ELSE 'OK'
       END AS status_stock
FROM insumos;

-- =====================================================================
-- 6) EXISTENCIAS Y COBERTURA (consumo 30 días)
-- =====================================================================
-- Días de cobertura = existencia actual / consumo promedio diario (últimos 30 días)
CREATE OR REPLACE VIEW vw_existencias_y_cobertura AS
WITH consumo_30 AS (
  SELECT
    m.insumo_id,
    SUM(CASE WHEN m.tipo='salida'   AND m.cantidad<0 THEN -m.cantidad ELSE 0 END) +
    SUM(CASE WHEN m.tipo='traspaso' AND m.cantidad<0 THEN -m.cantidad ELSE 0 END) AS consumo_30d
  FROM movimientos_insumos m
  WHERE m.fecha >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  GROUP BY m.insumo_id
)
SELECT
  i.id AS insumo_id,
  i.nombre,
  i.existencia,
  COALESCE(c.consumo_30d,0) AS consumo_30d,
  ROUND(CASE
    WHEN COALESCE(c.consumo_30d,0) = 0 THEN NULL
    ELSE i.existencia / (COALESCE(c.consumo_30d,0) / 30.0)
  END, 2) AS dias_cobertura
FROM insumos i
LEFT JOIN consumo_30 c ON c.insumo_id=i.id;

-- =====================================================================
-- FIN DEL PAQUETE
-- =====================================================================

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;