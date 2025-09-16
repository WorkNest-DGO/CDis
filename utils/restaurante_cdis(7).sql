-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 16-09-2025 a las 01:53:26
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `restaurante_cdis`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_leadtime_insumos` (IN `p_desde` DATETIME, IN `p_hasta` DATETIME, IN `p_incluir_ceros` TINYINT(1), IN `p_fallback_dias` INT)   BEGIN
  DECLARE v_hasta DATETIME;
  SET v_hasta = IF(TIME(p_hasta)='00:00:00', DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY), p_hasta);

  WITH entradas AS (
    SELECT
      ei.insumo_id,
      DATE(ei.fecha) AS f,
      LAG(DATE(ei.fecha)) OVER (PARTITION BY ei.insumo_id ORDER BY ei.fecha) AS f_prev
    FROM entradas_insumos ei
    WHERE ei.fecha >= p_desde AND ei.fecha < v_hasta
  ),
  diffs AS (
    SELECT
      insumo_id,
      DATEDIFF(f, f_prev) AS dias
    FROM entradas
    WHERE f_prev IS NOT NULL
  ),
  ultimas AS (
    SELECT
      ei.insumo_id,
      DATE(MAX(ei.fecha)) AS ultima_entrada
    FROM entradas_insumos ei
    WHERE ei.fecha >= p_desde AND ei.fecha < v_hasta
    GROUP BY ei.insumo_id
  ),
  resumen AS (
    SELECT
      d.insumo_id,
      COUNT(*) AS pares_evaluados,
      ROUND(AVG(d.dias), 2) AS avg_dias_reabasto,
      MIN(d.dias) AS min_dias,
      MAX(d.dias) AS max_dias
    FROM diffs d
    GROUP BY d.insumo_id
  )
  SELECT
    i.id                                  AS insumo_id,
    i.nombre                              AS insumo,
    COALESCE(r.pares_evaluados, 0)        AS pares_evaluados,
    r.avg_dias_reabasto,
    r.min_dias,
    r.max_dias,
    u.ultima_entrada,
    /* Próxima = última + (avg o fallback si no hay avg) */
    CASE
      WHEN u.ultima_entrada IS NULL THEN NULL
      WHEN r.avg_dias_reabasto IS NULL THEN DATE_ADD(u.ultima_entrada, INTERVAL p_fallback_dias DAY)
      ELSE DATE_ADD(u.ultima_entrada, INTERVAL r.avg_dias_reabasto DAY)
    END AS proxima_estimada,
    CASE
      WHEN u.ultima_entrada IS NULL THEN NULL
      WHEN r.avg_dias_reabasto IS NULL THEN DATEDIFF(DATE_ADD(u.ultima_entrada, INTERVAL p_fallback_dias DAY), CURRENT_DATE())
      ELSE DATEDIFF(DATE_ADD(u.ultima_entrada, INTERVAL r.avg_dias_reabasto DAY), CURRENT_DATE())
    END AS dias_restantes
  FROM insumos i
  LEFT JOIN resumen r ON r.insumo_id = i.id
  LEFT JOIN ultimas u ON u.insumo_id = i.id
  WHERE (p_incluir_ceros = 1)
     OR (p_incluir_ceros = 0 AND (r.pares_evaluados IS NOT NULL OR u.ultima_entrada IS NOT NULL))
  ORDER BY i.nombre;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_refrescar_reabasto_y_alertas` (IN `p_desde` DATETIME, IN `p_hasta` DATETIME, IN `p_avisar_desde_dias` INT, IN `p_gracia_vencidos_dias` INT, IN `p_fallback_dias` INT)   BEGIN
  DECLARE v_hasta DATETIME;
  SET v_hasta = IF(TIME(p_hasta)='00:00:00', DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY), p_hasta);

  DROP TEMPORARY TABLE IF EXISTS tmp_leadtime;
  CREATE TEMPORARY TABLE tmp_leadtime
  ( insumo_id INT PRIMARY KEY,
    avg_dias_reabasto DECIMAL(10,2) NULL,
    min_dias INT NULL,
    max_dias INT NULL,
    ultima_entrada DATE NULL,
    proxima_estimada DATE NULL
  ) ENGINE=MEMORY;

  /* Calcular leadtime con fallback */
  INSERT INTO tmp_leadtime (insumo_id, avg_dias_reabasto, min_dias, max_dias, ultima_entrada, proxima_estimada)
  WITH entradas AS (
    SELECT
      ei.insumo_id,
      DATE(ei.fecha) AS f,
      LAG(DATE(ei.fecha)) OVER (PARTITION BY ei.insumo_id ORDER BY ei.fecha) AS f_prev
    FROM entradas_insumos ei
    WHERE ei.fecha >= p_desde AND ei.fecha < v_hasta
  ),
  diffs AS (
    SELECT insumo_id, DATEDIFF(f, f_prev) AS dias
    FROM entradas WHERE f_prev IS NOT NULL
  ),
  ultimas AS (
    SELECT ei.insumo_id, DATE(MAX(ei.fecha)) AS ultima_entrada
    FROM entradas_insumos ei
    WHERE ei.fecha >= p_desde AND ei.fecha < v_hasta
    GROUP BY ei.insumo_id
  ),
  resumen AS (
    SELECT insumo_id,
           COUNT(*) AS pares_evaluados,
           ROUND(AVG(dias),2) AS avg_dias_reabasto,
           MIN(dias) AS min_dias,
           MAX(dias) AS max_dias
    FROM diffs
    GROUP BY insumo_id
  )
  SELECT
    i.id AS insumo_id,
    r.avg_dias_reabasto,
    r.min_dias,
    r.max_dias,
    u.ultima_entrada,
    CASE
      WHEN u.ultima_entrada IS NULL THEN NULL
      WHEN r.avg_dias_reabasto IS NULL THEN DATE_ADD(u.ultima_entrada, INTERVAL p_fallback_dias DAY)
      ELSE DATE_ADD(u.ultima_entrada, INTERVAL r.avg_dias_reabasto DAY)
    END AS proxima_estimada
  FROM insumos i
  LEFT JOIN resumen r ON r.insumo_id = i.id
  LEFT JOIN ultimas u ON u.insumo_id = i.id;

  /* UPSERT en métricas */
  INSERT INTO reabasto_metricas (insumo_id, avg_dias_reabasto, min_dias, max_dias, ultima_entrada, proxima_estimada)
  SELECT insumo_id, avg_dias_reabasto, min_dias, max_dias, ultima_entrada, proxima_estimada
  FROM tmp_leadtime
  ON DUPLICATE KEY UPDATE
    avg_dias_reabasto = VALUES(avg_dias_reabasto),
    min_dias          = VALUES(min_dias),
    max_dias          = VALUES(max_dias),
    ultima_entrada    = VALUES(ultima_entrada),
    proxima_estimada  = VALUES(proxima_estimada);

  /* Generar alertas (proximas y vencidas) con status */
  INSERT IGNORE INTO reabasto_alertas (insumo_id, proxima_estimada, avisar_desde_dias, status)
  SELECT
    t.insumo_id,
    t.proxima_estimada,
    p_avisar_desde_dias,
    CASE
      WHEN DATEDIFF(t.proxima_estimada, CURRENT_DATE()) >= 0 THEN 'proxima'
      ELSE 'vencida'
    END AS status
  FROM tmp_leadtime t
  WHERE t.proxima_estimada IS NOT NULL
    AND DATEDIFF(t.proxima_estimada, CURRENT_DATE())
        BETWEEN -p_gracia_vencidos_dias AND p_avisar_desde_dias;

  DROP TEMPORARY TABLE IF EXISTS tmp_leadtime;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_resumen_compras_global` (IN `p_desde` DATETIME, IN `p_hasta` DATETIME)   BEGIN
  DECLARE v_hasta DATETIME;

  /* Normalizamos el rango: si viene solo fecha a las 00:00, cubre todo el día */
  SET v_hasta = IF(TIME(p_hasta)='00:00:00',
                   DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY),
                   p_hasta);

  SELECT
    COUNT(*)                                        AS compras_evaluadas,
    ROUND(SUM(ei.costo_total), 2)                   AS monto_total,
    ROUND(AVG(ei.costo_total), 2)                   AS costo_medio,
    ROUND(SUM(ei.costo_total)/NULLIF(SUM(ei.cantidad),0), 4) AS costo_promedio_unitario,
    ROUND(SUM(ei.cantidad), 2)                      AS cantidad_total,
    MIN(ei.fecha)                                   AS primera_compra,
    MAX(ei.fecha)                                   AS ultima_compra
  FROM entradas_insumos ei
  WHERE ei.fecha >= p_desde
    AND ei.fecha <  v_hasta;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_resumen_compras_insumo` (IN `p_insumo_id` INT, IN `p_desde` DATETIME, IN `p_hasta` DATETIME)   BEGIN
  /* Normalizamos el rango: [p_desde, p_hasta_fin_del_dia] */
  DECLARE v_hasta DATETIME;
  SET v_hasta = IF(TIME(p_hasta)='00:00:00', DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY), p_hasta);

  SELECT
    i.id                                           AS insumo_id,
    i.nombre                                       AS insumo,
    COALESCE(COUNT(ei.id), 0)                      AS compras_evaluadas,
    COALESCE(ROUND(SUM(ei.costo_total), 2), 0.00)  AS monto_total,
    COALESCE(ROUND(AVG(ei.costo_total), 2), 0.00)  AS costo_medio,               -- promedio por compra
    COALESCE(ROUND(SUM(ei.costo_total) / NULLIF(SUM(ei.cantidad),0), 4), 0.0000) AS costo_promedio_unitario -- ponderado
  FROM insumos i
  LEFT JOIN entradas_insumos ei
         ON ei.insumo_id = i.id
        AND ei.fecha >= p_desde
        AND ei.fecha <  v_hasta
  WHERE i.id = p_insumo_id
  GROUP BY i.id, i.nombre;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_resumen_por_insumo` (IN `p_desde` DATETIME, IN `p_hasta` DATETIME, IN `p_incluir_ceros` TINYINT(1))   BEGIN
  DECLARE v_hasta DATETIME;
  SET v_hasta = IF(TIME(p_hasta)='00:00:00',
                   DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY),
                   p_hasta);

  IF p_incluir_ceros = 1 THEN
    /* Todos los insumos; métricas en 0 cuando no hay compras en el rango */
    SELECT
      i.id                         AS insumo_id,
      i.nombre                     AS insumo,
      COALESCE(COUNT(ei.id), 0)    AS compras_evaluadas,
      COALESCE(ROUND(SUM(ei.costo_total), 2), 0.00) AS monto_total,
      COALESCE(ROUND(AVG(ei.costo_total), 2), 0.00) AS costo_medio,
      COALESCE(ROUND(SUM(ei.costo_total) / NULLIF(SUM(ei.cantidad),0), 4), 0.0000) AS costo_promedio_unitario,
      COALESCE(ROUND(SUM(ei.cantidad), 2), 0.00) AS cantidad_total,
      MIN(ei.fecha)                AS primera_compra,
      MAX(ei.fecha)                AS ultima_compra
    FROM insumos i
    LEFT JOIN entradas_insumos ei
           ON ei.insumo_id = i.id
          AND ei.fecha >= p_desde
          AND ei.fecha <  v_hasta
    GROUP BY i.id, i.nombre
    ORDER BY i.nombre;
  ELSE
    /* Solo insumos con al menos una compra en el rango */
    SELECT
      ei.insumo_id,
      i.nombre                     AS insumo,
      COUNT(ei.id)                 AS compras_evaluadas,
      ROUND(SUM(ei.costo_total), 2) AS monto_total,
      ROUND(AVG(ei.costo_total), 2) AS costo_medio,
      ROUND(SUM(ei.costo_total) / NULLIF(SUM(ei.cantidad),0), 4) AS costo_promedio_unitario,
      ROUND(SUM(ei.cantidad), 2)  AS cantidad_total,
      MIN(ei.fecha)               AS primera_compra,
      MAX(ei.fecha)               AS ultima_compra
    FROM entradas_insumos ei
    JOIN insumos i ON i.id = ei.insumo_id
    WHERE ei.fecha >= p_desde
      AND ei.fecha <  v_hasta
    GROUP BY ei.insumo_id, i.nombre
    ORDER BY i.nombre;
  END IF;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cortes_almacen`
--

CREATE TABLE `cortes_almacen` (
  `id` int(11) NOT NULL,
  `fecha_inicio` datetime DEFAULT current_timestamp(),
  `fecha_fin` datetime DEFAULT NULL,
  `usuario_abre_id` int(11) DEFAULT NULL,
  `usuario_cierra_id` int(11) DEFAULT NULL,
  `observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cortes_almacen_detalle`
--

CREATE TABLE `cortes_almacen_detalle` (
  `id` int(11) NOT NULL,
  `corte_id` int(11) DEFAULT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `existencia_inicial` decimal(10,2) DEFAULT NULL,
  `entradas` decimal(10,2) DEFAULT NULL,
  `salidas` decimal(10,2) DEFAULT NULL,
  `mermas` decimal(10,2) DEFAULT NULL,
  `existencia_final` decimal(10,2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `despachos`
--

CREATE TABLE `despachos` (
  `id` int(11) NOT NULL,
  `sucursal_id` int(11) DEFAULT NULL,
  `usuario_id` int(11) DEFAULT NULL,
  `fecha_envio` datetime DEFAULT current_timestamp(),
  `fecha_recepcion` datetime DEFAULT NULL,
  `estado` enum('pendiente','recibido','cancelado') DEFAULT 'pendiente',
  `qr_token` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `despachos`
--

INSERT INTO `despachos` (`id`, `sucursal_id`, `usuario_id`, `fecha_envio`, `fecha_recepcion`, `estado`, `qr_token`) VALUES
(1, NULL, 1, '2025-08-01 00:02:55', NULL, 'pendiente', '948e3f38b829837c819f43a44eb5571f'),
(2, NULL, 1, '2025-08-01 00:23:01', NULL, 'pendiente', '6566e881df844b6c08868944b246b4cd'),
(3, NULL, 1, '2025-08-01 00:23:26', NULL, 'pendiente', 'e13a1dce53f51bf4b0c9705f08977fdf'),
(4, NULL, 1, '2025-08-01 00:34:00', NULL, 'pendiente', '53bd2f12ca2e97dd17aed95403fc7ca1'),
(5, NULL, 1, '2025-08-01 00:37:17', NULL, 'pendiente', '9c4f85ef2f10ff272c63d98287f6705a'),
(6, NULL, 1, '2025-08-01 00:49:47', NULL, 'pendiente', '9b7e462db0b6e7760064e3a469c55a6a'),
(7, NULL, 1, '2025-08-01 00:50:28', NULL, 'pendiente', '5dc71f070f4b50f376ef2f67c43c437a'),
(8, NULL, 1, '2025-08-01 12:29:01', NULL, 'pendiente', '9d152e2f0f2393c394e345390fd5f285'),
(9, NULL, 1, '2025-08-01 16:48:48', NULL, 'pendiente', '9890d7d7c7ad5089d239838c4034aa1f'),
(10, NULL, 1, '2025-08-01 19:39:10', NULL, 'pendiente', '6a8203ff8689140588d880518db7f28c'),
(11, NULL, 1, '2025-08-01 19:52:10', NULL, 'pendiente', 'ab4a7b6126a2ff25ae1aaa5b1d2629e2'),
(12, NULL, 1, '2025-08-01 19:54:42', NULL, 'pendiente', '3f023baf44fd34a7175912d3bd41b46f'),
(13, NULL, 1, '2025-08-15 10:01:11', NULL, 'pendiente', '432713b3dcf1f23f9674da38f9c099c5');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `despachos_detalle`
--

CREATE TABLE `despachos_detalle` (
  `id` int(11) NOT NULL,
  `despacho_id` int(11) DEFAULT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `unidad` varchar(20) DEFAULT NULL,
  `precio_unitario` decimal(10,2) DEFAULT NULL,
  `subtotal` decimal(10,2) GENERATED ALWAYS AS (`cantidad` * `precio_unitario`) STORED
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `despachos_detalle`
--

INSERT INTO `despachos_detalle` (`id`, `despacho_id`, `insumo_id`, `cantidad`, `unidad`, `precio_unitario`) VALUES
(1, 1, 16, 340.00, 'gramos', 0.00),
(2, 1, 17, 455.00, 'gramos', 0.00),
(3, 2, 1, 400.00, 'gramos', 0.00),
(4, 3, 1, 10.00, 'gramos', 0.00),
(5, 4, 17, 2.00, 'gramos', 0.00),
(6, 5, 17, 500.00, 'gramos', 0.00),
(7, 6, 16, 1.00, 'gramos', 0.00),
(8, 7, 16, 9.00, 'gramos', 0.00),
(9, 8, 1, 90.00, 'gramos', 0.00),
(10, 9, 12, 600.00, 'gramos', 0.00),
(11, 9, 31, 50.00, 'gramos', 0.00),
(12, 10, 10, 30.00, 'pieza', 0.00),
(13, 10, 16, 100.00, 'gramos', 0.00),
(14, 11, 13, 400.00, 'gramos', 0.00),
(15, 11, 14, 700.00, 'gramos', 0.00),
(16, 12, 3, 1000.00, 'gramos', 0.00),
(17, 12, 4, 10.00, 'piezas', 0.00),
(18, 13, 1, 100.00, 'gramos', 0.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `entradas_insumos`
--

CREATE TABLE `entradas_insumos` (
  `id` int(11) NOT NULL,
  `insumo_id` int(11) NOT NULL,
  `proveedor_id` int(11) DEFAULT NULL,
  `usuario_id` int(11) DEFAULT NULL,
  `fecha` datetime DEFAULT current_timestamp(),
  `descripcion` text DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `unidad` varchar(20) DEFAULT NULL,
  `costo_total` decimal(10,2) DEFAULT NULL,
  `valor_unitario` decimal(10,4) GENERATED ALWAYS AS (`costo_total` / nullif(`cantidad`,0)) STORED,
  `referencia_doc` varchar(100) DEFAULT NULL,
  `folio_fiscal` varchar(100) DEFAULT NULL,
  `qr` varchar(255) NOT NULL,
  `cantidad_actual` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `entradas_insumos`
--

INSERT INTO `entradas_insumos` (`id`, `insumo_id`, `proveedor_id`, `usuario_id`, `fecha`, `descripcion`, `cantidad`, `unidad`, `costo_total`, `referencia_doc`, `folio_fiscal`, `qr`, `cantidad_actual`) VALUES
(1, 1, 1, 1, '2025-07-01 10:00:00', 'Arroz compra julio 1', 2000.00, 'gramos', 300.00, 'REF-ARZ-01', 'FAC-ARZ-01', '', 0.00),
(2, 1, 1, 1, '2025-07-15 10:00:00', 'Arroz compra julio 15', 2100.00, 'gramos', 315.00, 'REF-ARZ-02', 'FAC-ARZ-02', '', 0.00),
(3, 1, 1, 1, '2025-08-01 10:00:00', 'Arroz compra agosto 1', 1900.00, 'gramos', 290.00, 'REF-ARZ-03', 'FAC-ARZ-03', '', 0.00),
(4, 1, 1, 1, '2025-08-20 10:00:00', 'Arroz compra agosto 20', 2200.00, 'gramos', 330.00, 'REF-ARZ-04', 'FAC-ARZ-04', '', 0.00),
(5, 2, 1, 1, '2025-07-05 09:00:00', 'Nori lote julio', 100.00, 'piezas', 65.00, 'REF-NORI-01', 'FAC-NORI-01', '', 0.00),
(6, 2, 1, 1, '2025-08-10 09:00:00', 'Nori lote agosto', 120.00, 'piezas', 72.00, 'REF-NORI-02', 'FAC-NORI-02', '', 0.00),
(7, 2, 1, 1, '2025-09-06 09:00:00', 'Nori lote septiembre', 130.00, 'piezas', 78.00, 'REF-NORI-03', 'FAC-NORI-03', '', 0.00),
(8, 3, 2, 1, '2025-07-02 08:00:00', 'Salmón semana 1', 1000.00, 'gramos', 200.00, 'REF-SAL-01', 'FAC-SAL-01', '', 0.00),
(9, 3, 2, 1, '2025-07-09 08:00:00', 'Salmón semana 2', 950.00, 'gramos', 195.00, 'REF-SAL-02', 'FAC-SAL-02', '', 0.00),
(10, 3, 2, 1, '2025-07-16 08:00:00', 'Salmón semana 3', 1100.00, 'gramos', 220.00, 'REF-SAL-03', 'FAC-SAL-03', '', 0.00),
(11, 3, 2, 1, '2025-07-23 08:00:00', 'Salmón semana 4', 1050.00, 'gramos', 210.00, 'REF-SAL-04', 'FAC-SAL-04', '', 0.00),
(12, 3, 2, 1, '2025-07-30 08:00:00', 'Salmón semana 5', 980.00, 'gramos', 196.00, 'REF-SAL-05', 'FAC-SAL-05', '', 0.00),
(13, 3, 2, 1, '2025-08-06 08:00:00', 'Salmón semana 6', 1000.00, 'gramos', 200.00, 'REF-SAL-06', 'FAC-SAL-06', '', 0.00),
(14, 1, 1, 1, '2025-07-05 10:15:00', 'Arroz compra jul 5', 1800.00, 'gramos', 270.00, 'ARZ-JUL05', 'FAC-ARZ-05', '', 0.00),
(15, 1, 1, 1, '2025-08-10 10:10:00', 'Arroz compra ago 10', 2000.00, 'gramos', 300.00, 'ARZ-AGO10', 'FAC-ARZ-10', '', 0.00),
(16, 1, 1, 1, '2025-08-28 10:20:00', 'Arroz compra ago 28', 2100.00, 'gramos', 315.00, 'ARZ-AGO28', 'FAC-ARZ-28', '', 0.00),
(17, 1, 1, 1, '2025-09-12 10:05:00', 'Arroz compra sep 12', 1900.00, 'gramos', 285.00, 'ARZ-SEP12', 'FAC-ARZ-12', '', 0.00),
(18, 2, 1, 1, '2025-07-28 09:10:00', 'Nori compra jul 28', 80.00, 'piezas', 52.00, 'NORI-JUL28', 'FAC-NORI-28', '', 0.00),
(19, 2, 1, 1, '2025-08-25 09:30:00', 'Nori compra ago 25', 110.00, 'piezas', 66.00, 'NORI-AGO25', 'FAC-NORI-25', '', 0.00),
(20, 2, 1, 1, '2025-09-10 09:45:00', 'Nori compra sep 10', 115.00, 'piezas', 69.00, 'NORI-SEP10', 'FAC-NORI-10', '', 0.00),
(21, 3, 2, 1, '2025-09-03 08:10:00', 'Salmón semana Sep-1', 1020.00, 'gramos', 204.00, 'SAL-SEP-01', 'FAC-SAL-SEP01', '', 0.00),
(22, 3, 2, 1, '2025-09-10 08:12:00', 'Salmón semana Sep-2', 980.00, 'gramos', 196.00, 'SAL-SEP-02', 'FAC-SAL-SEP02', '', 0.00),
(23, 3, 2, 1, '2025-09-17 08:14:00', 'Salmón semana Sep-3', 1100.00, 'gramos', 220.00, 'SAL-SEP-03', 'FAC-SAL-SEP03', '', 0.00),
(24, 12, 1, 1, '2025-08-18 11:00:00', 'Philadelphia compra ago 18', 700.00, 'gramos', 140.00, 'PHI-AGO18', 'FAC-PHI-18', '', 0.00),
(25, 12, 1, 1, '2025-09-09 11:05:00', 'Philadelphia compra sep 9', 900.00, 'gramos', 186.00, 'PHI-SEP09', 'FAC-PHI-09', '', 0.00),
(26, 31, 2, 1, '2025-08-02 07:45:00', 'Naranja compra ago 2', 60.00, 'gramos', 30.00, 'NAR-AGO02', 'FAC-NAR-02', '', 0.00),
(27, 31, 2, 1, '2025-08-29 07:50:00', 'Naranja compra ago 29', 50.00, 'gramos', 27.50, 'NAR-AGO29', 'FAC-NAR-29', '', 0.00),
(28, 31, 2, 1, '2025-09-11 07:55:00', 'Naranja compra sep 11', 65.00, 'gramos', 33.80, 'NAR-SEP11', 'FAC-NAR-11', '', 0.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `insumos`
--

CREATE TABLE `insumos` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) DEFAULT NULL,
  `unidad` varchar(20) DEFAULT NULL,
  `existencia` decimal(10,2) DEFAULT NULL,
  `tipo_control` enum('por_receta','unidad_completa','uso_general','no_controlado','desempaquetado') DEFAULT 'por_receta',
  `imagen` varchar(255) DEFAULT NULL,
  `minimo_stock` decimal(10,2) DEFAULT 0.00
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `insumos`
--

INSERT INTO `insumos` (`id`, `nombre`, `unidad`, `existencia`, `tipo_control`, `imagen`, `minimo_stock`) VALUES
(1, 'Arroz', 'gramos', 25750.00, 'por_receta', 'ins_68717301313ad.jpg', 0.00),
(2, 'Alga', 'piezas', 29988.50, 'por_receta', 'ins_6871716a72681.jpg', 0.00),
(3, 'Salmón fresco', 'gramos', 30000.00, 'por_receta', 'ins_6871777fa2c56.png', 0.00),
(4, 'Refresco en lata', 'piezas', 29999.00, 'unidad_completa', 'ins_6871731d075cb.webp', 0.00),
(7, 'Surimi', 'gramos', 30000.00, 'uso_general', 'ins_688a521dcd583.jpg', 0.00),
(8, 'Tocino', 'gramos', 29650.00, 'uso_general', 'ins_688a4dc84c002.jpg', 0.00),
(9, 'Pollo', 'gramos', 29970.00, 'desempaquetado', 'ins_688a4e4bd5999.jpg', 0.00),
(10, 'Camarón', 'gramos', 29910.00, 'desempaquetado', 'ins_688a4f5c873c6.jpg', 0.00),
(11, 'Queso Chihuahua', 'gramos', 30000.00, 'unidad_completa', 'ins_688a4feca9865.jpg', 0.00),
(12, 'Philadelphia', 'gramos', 29390.00, 'uso_general', 'ins_688a504f9cb40.jpg', 0.00),
(13, 'Arroz blanco', 'gramos', 30000.00, 'por_receta', 'ins_689f82d674c65.jpg', 0.00),
(14, 'Carne', 'gramos', 29820.00, 'uso_general', 'ins_688a528d1261a.jpg', 0.00),
(15, 'Queso Amarillo', 'piezas', 29998.00, 'uso_general', 'ins_688a53246c1c2.jpg', 0.00),
(16, 'Ajonjolí', 'gramos', 29994.00, 'uso_general', 'ins_689f824a23343.jpg', 0.00),
(17, 'Panko', 'gramos', 30000.00, 'por_receta', 'ins_688a53da64b5f.jpg', 0.00),
(18, 'Salsa tampico', 'mililitros', 30000.00, 'no_controlado', 'ins_688a54cf1872b.jpg', 0.00),
(19, 'Anguila', 'oz', 30000.00, 'por_receta', 'ins_689f828638aa9.jpg', 0.00),
(20, 'BBQ', 'oz', 30000.00, 'no_controlado', 'ins_688a557431fce.jpg', 0.00),
(21, 'Serrano', 'gramos', 29975.00, 'uso_general', 'ins_688a55c66f09d.jpg', 0.00),
(22, 'Chile Morrón', 'gramos', 30000.00, 'por_receta', 'ins_688a5616e8f25.jpg', 0.00),
(23, 'Kanikama', 'gramos', 29990.00, 'por_receta', 'ins_688a5669e24a8.jpg', 0.00),
(24, 'Aguacate', 'gramos', 29400.00, 'por_receta', 'ins_689f8254c2e71.jpg', 0.00),
(25, 'Dedos de queso', 'pieza', 30000.00, 'unidad_completa', 'ins_688a56fda3221.jpg', 0.00),
(26, 'Mango', 'gramos', 30000.00, 'por_receta', 'ins_688a573c762f4.jpg', 0.00),
(27, 'Tostadas', 'pieza', 30000.00, 'uso_general', 'ins_688a57a499b35.jpg', 0.00),
(28, 'Papa', 'gramos', 30000.00, 'por_receta', 'ins_688a580061ffd.jpg', 0.00),
(29, 'Cebolla Morada', 'gramos', 30000.00, 'por_receta', 'ins_688a5858752a0.jpg', 0.00),
(30, 'Salsa de soya', 'mililitros', 30000.00, 'no_controlado', 'ins_688a58cc6cb6c.jpg', 0.00),
(31, 'Naranja', 'gramos', 30000.00, 'por_receta', 'ins_688a590bca275.jpg', 0.00),
(32, 'Chile Caribe', 'gramos', 30000.00, 'por_receta', 'ins_688a59836c32e.jpg', 0.00),
(33, 'Pulpo', 'gramos', 29870.00, 'por_receta', 'ins_688a59c9a1d0b.jpg', 0.00),
(34, 'Zanahoria', 'gramos', 30000.00, 'por_receta', 'ins_688a5a0a3a959.jpg', 0.00),
(35, 'Apio', 'gramos', 30000.00, 'por_receta', 'ins_688a5a52af990.jpg', 0.00),
(36, 'Pepino', 'gramos', 29260.00, 'uso_general', 'ins_688a5aa0cbaf5.jpg', 0.00),
(37, 'Masago', 'gramos', 30000.00, 'por_receta', 'ins_688a5b3f0dca6.jpg', 0.00),
(38, 'Nuez de la india', 'gramos', 30000.00, 'por_receta', 'ins_688a5be531e11.jpg', 0.00),
(39, 'Cátsup', 'mililitros', 30000.00, 'por_receta', 'ins_688a5c657eb83.jpg', 0.00),
(40, 'Atún fresco', 'gramos', 30000.00, 'por_receta', 'ins_688a5ce18adc5.jpg', 0.00),
(41, 'Callo almeja', 'gramos', 30000.00, 'por_receta', 'ins_688a5d28de8a5.jpg', 0.00),
(42, 'Calabacin', 'gramos', 30000.00, 'por_receta', 'ins_688a5d6b2bca1.jpg', 0.00),
(43, 'Fideo chino transparente', 'gramos', 30000.00, 'por_receta', 'ins_688a5dd3b406d.jpg', 0.00),
(44, 'Brócoli', 'gramos', 30000.00, 'por_receta', 'ins_688a5e2736870.jpg', 0.00),
(45, 'Chile de árbol', 'gramos', 29970.00, 'por_receta', 'ins_688a5e6f08ccd.jpg', 0.00),
(46, 'Pasta udon', 'gramos', 29970.00, 'por_receta', 'ins_688a5eb627f38.jpg', 0.00),
(47, 'Huevo', 'pieza', 30000.00, 'por_receta', 'ins_688a5ef9b575e.jpg', 0.00),
(48, 'Cerdo', 'gramos', 29940.00, 'por_receta', 'ins_688a5f3915f5e.jpg', 0.00),
(49, 'Masa para gyozas', 'pieza', 30000.00, 'por_receta', 'ins_688a5fae2e7f1.jpg', 0.00),
(50, 'Naruto', 'gramos', 30000.00, 'por_receta', 'ins_688a5ff57f62d.jpg', 0.00),
(51, 'Atún ahumado', 'gramos', 30000.00, 'por_receta', 'ins_68adcd62c5a19.jpg', 0.00),
(52, 'Cacahuate con salsa (salado)', 'gramos', 30000.00, 'por_receta', 'ins_68adcf253bd1d.jpg', 0.00),
(53, 'Calabaza', 'gramos', 30000.00, 'por_receta', 'ins_68add0ff781fb.jpg', 0.00),
(54, 'Camarón gigante para pelar', 'pieza', 30000.00, 'por_receta', 'ins_68add3264c465.jpg', 0.00),
(55, 'Cebolla', 'gramos', 30000.00, 'por_receta', 'ins_68add38beff59.jpg', 0.00),
(56, 'Chile en polvo', 'gramos', 30000.00, 'por_receta', 'ins_68add4a750a0e.jpg', 0.00),
(57, 'Coliflor', 'gramos', 30000.00, 'por_receta', 'ins_68add5291130e.jpg', 0.00),
(59, 'Dedos de surimi', 'pieza', 30000.00, 'unidad_completa', 'ins_68add5c575fbb.jpg', 0.00),
(60, 'Fideos', 'gramos', 30000.00, 'por_receta', 'ins_68add629d094b.jpg', 0.00),
(61, 'Fondo de res', 'mililitros', 29880.00, 'no_controlado', 'ins_68add68d317d5.jpg', 0.00),
(62, 'Gravy Naranja', 'oz', 30000.00, 'no_controlado', 'ins_68add7bb461b3.jpg', 0.00),
(63, 'Salsa Aguachil', 'oz', 29990.00, 'no_controlado', 'ins_68ae000034b31.jpg', 0.00),
(64, 'Julianas de zanahoria', 'gramos', 30000.00, 'por_receta', 'ins_68add82c9c245.jpg', 0.00),
(65, 'Limón', 'gramos', 30000.00, 'por_receta', 'ins_68add890ee640.jpg', 0.00),
(66, 'Queso Mix', 'gramos', 29360.00, 'uso_general', 'ins_68ade1625f489.jpg', 0.00),
(67, 'Morrón', 'gramos', 30000.00, 'por_receta', 'ins_68addcbc6d15a.jpg', 0.00),
(69, 'Pasta chukasoba', 'gramos', 30000.00, 'por_receta', 'ins_68addd277fde6.jpg', 0.00),
(70, 'Pasta frita', 'gramos', 30000.00, 'por_receta', 'ins_68addd91a005e.jpg', 0.00),
(71, 'Queso crema', 'gramos', 30000.00, 'uso_general', 'ins_68ade11cdadcb.jpg', 0.00),
(72, 'Refresco embotellado', 'pieza', 29987.00, 'unidad_completa', 'ins_68adfdd53f04e.jpg', 0.00),
(73, 'res', 'gramos', 30000.00, 'uso_general', 'ins_68adfe2e49580.jpg', 0.00),
(74, 'Rodajas de naranja', 'gramos', 30000.00, 'por_receta', 'ins_68adfeccd68d8.jpg', 0.00),
(75, 'Salmón', 'gramos', 30000.00, 'por_receta', 'ins_68adffa2a2db0.jpg', 0.00),
(76, 'Salsa de anguila', 'mililitros', 30000.00, 'no_controlado', 'ins_68ae005f1b3cd.jpg', 0.00),
(77, 'Salsa teriyaki (dulce)', 'mililitros', 30000.00, 'no_controlado', 'ins_68ae00c53121a.jpg', 0.00),
(78, 'Salsas orientales', 'mililitros', 29980.00, 'no_controlado', 'ins_68ae01341e7b1.jpg', 0.00),
(79, 'Shisimi', 'gramos', 30000.00, 'uso_general', 'ins_68ae018d22a63.jpg', 0.00),
(80, 'Siracha', 'mililitros', 29970.00, 'no_controlado', 'ins_68ae03413da26.jpg', 0.00),
(81, 'Tampico', 'mililitros', 29970.00, 'uso_general', 'ins_68ae03f65bd71.jpg', 0.00),
(82, 'Tortilla de harina', 'pieza', 30000.00, 'unidad_completa', 'ins_68ae04b46d24a.jpg', 0.00),
(83, 'Tostada', 'pieza', 30000.00, 'unidad_completa', 'ins_68ae05924a02a.jpg', 0.00),
(85, 'Yakimeshi mini', 'gramos', 30000.00, 'por_receta', 'ins_68ae061b1175b.jpg', 0.00),
(86, 'Sal con Ajo', 'pieza', 30000.00, 'por_receta', 'ins_68adff6dbf111.jpg', 0.00),
(87, 'Aderezo Chipotle', 'mililitros', 29620.00, 'por_receta', 'ins_68adcabeb1ee9.jpg', 0.00),
(88, 'Mezcla de Horneado', 'gramos', 30000.00, 'por_receta', 'ins_68addaa3e53f7.jpg', 0.00),
(89, 'Aderezo', 'gramos', 30000.00, 'uso_general', 'ins_68adcc0771a3c.jpg', 0.00),
(90, 'Camarón Empanizado', 'gramos', 29285.00, 'por_receta', 'ins_68add1de1aa0e.jpg', 0.00),
(91, 'Pollo Empanizado', 'gramos', 30000.00, 'por_receta', 'ins_68adde81c6be3.jpg', 0.00),
(92, 'Cebollín', 'gramos', 30000.00, 'por_receta', 'ins_68add3e38d04b.jpg', 0.00),
(93, 'Aderezo Cebolla Dul.', 'oz', 30000.00, 'uso_general', 'ins_68adcb8fa562e.jpg', 0.00),
(94, 'Camaron Enchiloso', 'gramos', 29880.00, 'por_receta', 'ins_68add2db69e2e.jpg', 0.00),
(95, 'Pastel chocoflan', 'pieza', 30000.00, 'unidad_completa', 'ins_68adddfa22fe2.jpg', 0.00),
(96, 'Pay de queso', 'pieza', 30000.00, 'unidad_completa', 'ins_68adde4fa8275.jpg', 0.00),
(97, 'Helado tempura', 'pieza', 30000.00, 'unidad_completa', 'ins_68add7e53c6fe.jpg', 0.00),
(98, 'Postre especial', 'pieza', 30000.00, 'unidad_completa', 'ins_68addee98fdf0.jpg', 0.00),
(99, 'Búfalo', 'mililitros', 29990.00, 'no_controlado', 'ins_68adce63dd347.jpg', 0.00),
(101, 'Corona 1/2', 'pieza', 30000.00, 'unidad_completa', 'ins_68add55a1e3b7.jpg', 0.00),
(102, 'Golden Light 1/2', 'pieza', 30000.00, 'unidad_completa', 'ins_68add76481f22.jpg', 0.00),
(103, 'Negra Modelo', 'pieza', 30000.00, 'unidad_completa', 'ins_68addc59c2ea9.jpg', 0.00),
(104, 'Modelo Especial', 'pieza', 29996.00, 'unidad_completa', 'ins_68addb9d59000.jpg', 0.00),
(105, 'Bud Light', 'pieza', 30000.00, 'unidad_completa', 'ins_68adcdf3295e8.jpg', 0.00),
(106, 'Stella Artois', 'pieza', 30000.00, 'unidad_completa', 'ins_68ae0397afb2f.jpg', 0.00),
(107, 'Ultra 1/2', 'pieza', 30000.00, 'unidad_completa', 'ins_68ae05466a8e2.jpg', 0.00),
(108, 'Michelob 1/2', 'pieza', 30000.00, 'unidad_completa', 'ins_68addb2d00c85.jpg', 0.00),
(109, 'Alitas de pollo', 'gramos', 30000.00, 'unidad_completa', 'ins_68adccf5a1147.jpg', 0.00),
(110, 'Ranch', 'mililitros', 30000.00, 'no_controlado', 'ins_68adfcddef7e3.jpg', 0.00),
(111, 'Buffalo', 'gramos', 30000.00, 'no_controlado', '', 0.00),
(112, 'Chichimi', 'gramos', 30000.00, 'no_controlado', 'ins_68add45bdb306.jpg', 0.00),
(113, 'Calpico', 'pieza', 30000.00, 'unidad_completa', 'ins_68add19570673.jpg', 0.00),
(114, 'Vaina de soja', 'gramos', 30000.00, 'uso_general', 'ins_68ae05de869d1.jpg', 0.00),
(115, 'Boneless', 'gramos', 30000.00, 'por_receta', 'ins_68adcdbb6b5b4.jpg', 0.00),
(116, 'Agua members', 'pieza', 30000.00, 'unidad_completa', 'ins_68adcc5feaee1.jpg', 0.00),
(117, 'Agua mineral', 'pieza', 30000.00, 'unidad_completa', 'ins_68adcca85ae2c.jpg', 0.00),
(118, 'Cilantro', 'gramos', 30000.00, 'por_receta', 'ins_68add4edab118.jpg', 0.00),
(119, 'Té de jazmin', 'mililitros', 30000.00, 'por_receta', 'ins_68ae0474dfc36.jpg', 0.00),
(120, 'bolsa camiseta 35x60', 'kilo', 0.00, 'unidad_completa', '', 0.00),
(121, 'bolsa camiseta 25x50', 'kilo', 0.00, 'unidad_completa', '', 0.00),
(122, 'bolsa camiseta 25x40', 'kilo', 0.00, 'unidad_completa', '', 0.00),
(123, 'bolsa poliseda 15x25', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(124, 'bolsa rollo 20x30', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(125, 'bowls cpp1911-3', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(126, 'bowls cpp20', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(127, 'bowls cpp1911-3 tapa', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(128, 'bowls cpp20 tapa', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(129, 'baso termico 1l', 'piza', 0.00, 'unidad_completa', '', 0.00),
(130, 'bisagra 22x22', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(131, 'servilleta', 'paquete', 0.00, 'unidad_completa', '', 0.00),
(132, 'Papel aluminio 400', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(133, 'Vitafilim 14', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(134, 'guante vinil', 'caja', 0.00, 'unidad_completa', '', 0.00),
(135, 'Popote 26cm', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(136, 'Bolsa papel x 100pz', 'paquete', 0.00, 'unidad_completa', '', 0.00),
(137, 'rollo impresora mediano', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(138, 'rollo impresora grande', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(139, 'tenedor fantasy mediano 25pz', 'paquete', 0.00, 'unidad_completa', '', 0.00),
(140, 'Bolsa basura 90x120 negra', 'bulto', 0.00, 'unidad_completa', '', 0.00),
(141, 'Ts2', 'tira', 0.00, 'unidad_completa', '', 0.00),
(142, 'Ts1', 'tira', 0.00, 'unidad_completa', '', 0.00),
(143, 'TS200', 'tira', 0.00, 'unidad_completa', '', 0.00),
(144, 'S100', 'tira', 0.00, 'unidad_completa', '', 0.00),
(145, 'Pet 1l c/tapa', 'bulto', 0.00, 'unidad_completa', '', 0.00),
(146, 'Pet 1/2l c/tapa', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(147, 'Cuchara mediana fantasy 50pz', 'paquete', 0.00, 'unidad_completa', '', 0.00),
(148, 'Charola 8x8', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(149, 'Charola 6x6', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(150, 'Charola 8x8 negra', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(151, 'Charola 6x6 negra', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(152, 'Polipapel', 'kilo', 0.00, 'unidad_completa', '', 0.00),
(153, 'Charola pastelera', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(154, 'Papel secante', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(155, 'Papel rollo higienico', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(156, 'Fabuloso 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00),
(157, 'Desengrasante 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00),
(158, 'Cloro 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00),
(159, 'Iorizante 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00),
(160, 'Windex 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00),
(161, 'quitacochambre 1l', 'litro', 0.00, 'unidad_completa', '', 0.00),
(162, 'Fibra metal', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(163, 'Esponja', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(164, 'Escoba', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(165, 'Recogedor', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(166, 'Trapeador', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(167, 'Cubeta 16l', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(168, 'Sanitas', 'paquete', 0.00, 'unidad_completa', '', 0.00),
(169, 'Jabon polvo 9k', 'bulto', 0.00, 'unidad_completa', '', 0.00),
(170, 'Shampoo trastes 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00),
(171, 'Jaladores', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(172, 'Cofia', 'pieza', 0.00, 'unidad_completa', '', 0.00),
(173, 'Trapo', 'pieza', 0.00, 'unidad_completa', '', 0.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `logs_accion`
--

CREATE TABLE `logs_accion` (
  `id` int(11) NOT NULL,
  `usuario_id` int(11) DEFAULT NULL,
  `modulo` varchar(50) DEFAULT NULL,
  `accion` varchar(100) DEFAULT NULL,
  `fecha` datetime DEFAULT current_timestamp(),
  `referencia_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `logs_accion`
--

INSERT INTO `logs_accion` (`id`, `usuario_id`, `modulo`, `accion`, `fecha`, `referencia_id`) VALUES
(1, 1, 'bodega', 'Generacion QR', '2025-07-31 20:04:39', 0),
(2, 1, 'bodega', 'Generacion QR', '2025-08-01 00:02:55', 2),
(3, 1, 'bodega', 'Generacion QR', '2025-08-01 00:23:02', 3),
(4, 1, 'bodega', 'Generacion QR', '2025-08-01 00:23:26', 4),
(5, 1, 'bodega', 'Generacion QR', '2025-08-01 00:34:00', 5),
(6, 1, 'bodega', 'Generacion QR', '2025-08-01 00:37:17', 6),
(7, 1, 'bodega', 'Generacion QR', '2025-08-01 00:49:47', 7),
(8, 1, 'bodega', 'Generacion QR', '2025-08-01 00:50:28', 8),
(9, 1, 'bodega', 'Generacion QR', '2025-08-01 12:29:01', 9),
(10, 1, 'bodega', 'Generacion QR', '2025-08-01 16:48:48', 10),
(11, 1, 'bodega', 'Generacion QR', '2025-08-01 19:39:10', 11),
(12, 1, 'bodega', 'Generacion QR', '2025-08-01 19:52:10', 12),
(13, 1, 'bodega', 'Generacion QR', '2025-08-01 19:54:42', 13),
(14, 1, 'bodega', 'Generacion QR', '2025-08-15 10:01:11', 14);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `mermas_insumo`
--

CREATE TABLE `mermas_insumo` (
  `id` int(11) NOT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `motivo` text DEFAULT NULL,
  `usuario_id` int(11) DEFAULT NULL,
  `fecha` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `movimientos_insumos`
--

CREATE TABLE `movimientos_insumos` (
  `id` int(11) NOT NULL,
  `tipo` enum('entrada','salida','ajuste','traspaso') DEFAULT 'entrada',
  `usuario_id` int(11) DEFAULT NULL,
  `usuario_destino_id` int(11) DEFAULT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `observacion` text DEFAULT NULL,
  `fecha` datetime DEFAULT current_timestamp(),
  `qr_token` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `movimientos_insumos`
--

INSERT INTO `movimientos_insumos` (`id`, `tipo`, `usuario_id`, `usuario_destino_id`, `insumo_id`, `cantidad`, `observacion`, `fecha`, `qr_token`) VALUES
(1, 'salida', 1, NULL, 1, 2000.00, NULL, '2025-07-31 20:04:39', '62afd20d75927cb9d96cc62351da69cf'),
(51, 'traspaso', 1, NULL, 16, -340.00, '', '2025-08-01 00:02:55', '948e3f38b829837c819f43a44eb5571f'),
(52, 'traspaso', 1, NULL, 17, -455.00, '', '2025-08-01 00:02:55', '948e3f38b829837c819f43a44eb5571f'),
(53, 'traspaso', 1, NULL, 1, -400.00, 'Enviado por QR a sucursal', '2025-08-01 00:23:01', '6566e881df844b6c08868944b246b4cd'),
(54, 'traspaso', 1, NULL, 1, -10.00, 'Enviado por QR a sucursal', '2025-08-01 00:23:26', 'e13a1dce53f51bf4b0c9705f08977fdf'),
(55, 'traspaso', 1, NULL, 17, -2.00, '', '2025-08-01 00:34:00', '53bd2f12ca2e97dd17aed95403fc7ca1'),
(56, 'traspaso', 1, NULL, 17, -500.00, 'Enviado por QR a sucursal', '2025-08-01 00:37:17', '9c4f85ef2f10ff272c63d98287f6705a'),
(57, 'traspaso', 1, NULL, 16, -1.00, 'Enviado por QR a sucursal', '2025-08-01 00:49:47', '9b7e462db0b6e7760064e3a469c55a6a'),
(58, 'traspaso', 1, NULL, 16, -9.00, 'Enviado por QR a sucursal', '2025-08-01 00:50:28', '5dc71f070f4b50f376ef2f67c43c437a'),
(59, 'traspaso', 1, NULL, 1, -90.00, 'Enviado por QR a sucursal', '2025-08-01 12:29:01', '9d152e2f0f2393c394e345390fd5f285'),
(60, 'ajuste', 1, NULL, 24, 100.00, 'Ajuste manual de existencia', '2025-08-01 12:31:38', NULL),
(61, 'ajuste', 1, NULL, 16, -30.00, 'Ajuste manual de existencia', '2025-08-01 12:34:56', NULL),
(62, 'traspaso', 1, NULL, 12, -600.00, 'Enviado por QR a sucursal', '2025-08-01 16:48:48', '9890d7d7c7ad5089d239838c4034aa1f'),
(63, 'traspaso', 1, NULL, 31, -50.00, 'Enviado por QR a sucursal', '2025-08-01 16:48:48', '9890d7d7c7ad5089d239838c4034aa1f'),
(64, 'ajuste', 1, NULL, 41, 1000.00, 'Ajuste manual de existencia', '2025-08-01 16:49:08', NULL),
(65, 'traspaso', 1, NULL, 10, -30.00, 'Enviado por QR a sucursal', '2025-08-01 19:39:10', '6a8203ff8689140588d880518db7f28c'),
(66, 'traspaso', 1, NULL, 16, -100.00, 'Enviado por QR a sucursal', '2025-08-01 19:39:10', '6a8203ff8689140588d880518db7f28c'),
(67, 'traspaso', 1, NULL, 13, -400.00, 'Enviado por QR a sucursal', '2025-08-01 19:52:10', 'ab4a7b6126a2ff25ae1aaa5b1d2629e2'),
(68, 'traspaso', 1, NULL, 14, -700.00, 'Enviado por QR a sucursal', '2025-08-01 19:52:10', 'ab4a7b6126a2ff25ae1aaa5b1d2629e2'),
(69, 'ajuste', 1, NULL, 13, 2000.00, 'Ajuste manual de existencia', '2025-08-01 19:54:18', NULL),
(70, 'ajuste', 1, NULL, 41, -1000.00, 'Ajuste manual de existencia', '2025-08-01 19:54:26', NULL),
(71, 'traspaso', 1, NULL, 3, -1000.00, 'Enviado por QR a sucursal', '2025-08-01 19:54:42', '3f023baf44fd34a7175912d3bd41b46f'),
(72, 'traspaso', 1, NULL, 4, -10.00, 'Enviado por QR a sucursal', '2025-08-01 19:54:42', '3f023baf44fd34a7175912d3bd41b46f'),
(73, 'traspaso', 1, NULL, 1, -100.00, 'Enviado por QR a sucursal', '2025-08-15 10:01:11', '432713b3dcf1f23f9674da38f9c099c5'),
(74, 'entrada', 1, NULL, 2, 4000.00, 'alga', '2025-09-06 21:37:12', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `productos`
--

CREATE TABLE `productos` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `precio` decimal(10,2) NOT NULL,
  `descripcion` text DEFAULT NULL,
  `existencia` int(11) DEFAULT 0,
  `activo` tinyint(1) DEFAULT 1,
  `imagen` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `proveedores`
--

CREATE TABLE `proveedores` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) DEFAULT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `direccion` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `proveedores`
--

INSERT INTO `proveedores` (`id`, `nombre`, `telefono`, `direccion`) VALUES
(1, 'Suministros Sushi MX', '555-123-4567', 'Calle Soya #123, CDMX'),
(2, 'Pescados del Pacífico', '555-987-6543', 'Av. Mar #456, CDMX'),
(3, 'Abastos OXX', '81-5555-0001', 'Parque Industrial, Monterrey, NL');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `qrs_insumo`
--

CREATE TABLE `qrs_insumo` (
  `id` int(11) NOT NULL,
  `token` varchar(64) NOT NULL,
  `json_data` text DEFAULT NULL,
  `estado` enum('pendiente','confirmado','anulado') DEFAULT 'pendiente',
  `creado_por` int(11) DEFAULT NULL,
  `creado_en` datetime DEFAULT current_timestamp(),
  `expiracion` datetime DEFAULT NULL,
  `pdf_envio` varchar(255) DEFAULT NULL,
  `pdf_recepcion` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `qrs_insumo`
--

INSERT INTO `qrs_insumo` (`id`, `token`, `json_data`, `estado`, `creado_por`, `creado_en`, `expiracion`, `pdf_envio`, `pdf_recepcion`) VALUES
(1, '62afd20d75927cb9d96cc62351da69cf', '[{\"id\":1,\"nombre\":\"Arroz para sushi\",\"unidad\":\"gramos\",\"cantidad\":2000}]', 'pendiente', 1, '2025-07-31 20:04:39', NULL, 'archivos/bodega/pdfs/qr_62afd20d75927cb9d96cc62351da69cf.pdf', NULL),
(2, '948e3f38b829837c819f43a44eb5571f', '[{\"id\":16,\"nombre\":\"Ajonjolí\",\"unidad\":\"gramos\",\"cantidad\":340},{\"id\":17,\"nombre\":\"Panko\",\"unidad\":\"gramos\",\"cantidad\":455}]', 'pendiente', 1, '2025-08-01 00:02:55', NULL, 'archivos/bodega/pdfs/qr_948e3f38b829837c819f43a44eb5571f.pdf', NULL),
(3, '6566e881df844b6c08868944b246b4cd', '[{\"id\":1,\"nombre\":\"Arroz para sushi\",\"unidad\":\"gramos\",\"cantidad\":400,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 00:23:01', NULL, 'archivos/bodega/pdfs/qr_6566e881df844b6c08868944b246b4cd.pdf', NULL),
(4, 'e13a1dce53f51bf4b0c9705f08977fdf', '[{\"id\":1,\"nombre\":\"Arroz para sushi\",\"unidad\":\"gramos\",\"cantidad\":10,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 00:23:26', NULL, 'archivos/bodega/pdfs/qr_e13a1dce53f51bf4b0c9705f08977fdf.pdf', NULL),
(5, '53bd2f12ca2e97dd17aed95403fc7ca1', '[{\"id\":17,\"nombre\":\"Panko\",\"unidad\":\"gramos\",\"cantidad\":2}]', 'pendiente', 1, '2025-08-01 00:34:00', NULL, 'archivos/bodega/pdfs/qr_53bd2f12ca2e97dd17aed95403fc7ca1.pdf', NULL),
(6, '9c4f85ef2f10ff272c63d98287f6705a', '[{\"id\":17,\"nombre\":\"Panko\",\"unidad\":\"gramos\",\"cantidad\":500,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 00:37:17', NULL, 'archivos/bodega/pdfs/qr_9c4f85ef2f10ff272c63d98287f6705a.pdf', NULL),
(7, '9b7e462db0b6e7760064e3a469c55a6a', '[{\"id\":16,\"nombre\":\"Ajonjolí\",\"unidad\":\"gramos\",\"cantidad\":1,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 00:49:47', NULL, 'archivos/bodega/pdfs/qr_9b7e462db0b6e7760064e3a469c55a6a.pdf', NULL),
(8, '5dc71f070f4b50f376ef2f67c43c437a', '[{\"id\":16,\"nombre\":\"Ajonjolí\",\"unidad\":\"gramos\",\"cantidad\":9,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 00:50:28', NULL, 'archivos/bodega/pdfs/qr_5dc71f070f4b50f376ef2f67c43c437a.pdf', NULL),
(9, '9d152e2f0f2393c394e345390fd5f285', '[{\"id\":1,\"nombre\":\"Arroz para sushi\",\"unidad\":\"gramos\",\"cantidad\":90,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 12:29:01', NULL, 'archivos/bodega/pdfs/qr_9d152e2f0f2393c394e345390fd5f285.pdf', NULL),
(10, '9890d7d7c7ad5089d239838c4034aa1f', '[{\"id\":12,\"nombre\":\"Philadelphia\",\"unidad\":\"gramos\",\"cantidad\":600,\"precio_unitario\":0},{\"id\":31,\"nombre\":\"Naranja\",\"unidad\":\"gramos\",\"cantidad\":50,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 16:48:48', NULL, 'archivos/bodega/pdfs/qr_9890d7d7c7ad5089d239838c4034aa1f.pdf', NULL),
(11, '6a8203ff8689140588d880518db7f28c', '[{\"id\":10,\"nombre\":\"Camarón\",\"unidad\":\"pieza\",\"cantidad\":30,\"precio_unitario\":0},{\"id\":16,\"nombre\":\"Ajonjolí\",\"unidad\":\"gramos\",\"cantidad\":100,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 19:39:10', NULL, 'archivos/bodega/pdfs/qr_6a8203ff8689140588d880518db7f28c.pdf', NULL),
(12, 'ab4a7b6126a2ff25ae1aaa5b1d2629e2', '[{\"id\":13,\"nombre\":\"Arroz blanco\",\"unidad\":\"gramos\",\"cantidad\":400,\"precio_unitario\":0},{\"id\":14,\"nombre\":\"Carne de res\",\"unidad\":\"gramos\",\"cantidad\":700,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 19:52:10', NULL, 'archivos/bodega/pdfs/qr_ab4a7b6126a2ff25ae1aaa5b1d2629e2.pdf', NULL),
(13, '3f023baf44fd34a7175912d3bd41b46f', '[{\"id\":3,\"nombre\":\"Salmón fresco\",\"unidad\":\"gramos\",\"cantidad\":1000,\"precio_unitario\":0},{\"id\":4,\"nombre\":\"Refresco en lata\",\"unidad\":\"piezas\",\"cantidad\":10,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-01 19:54:42', NULL, 'archivos/bodega/pdfs/qr_3f023baf44fd34a7175912d3bd41b46f.pdf', NULL),
(14, '432713b3dcf1f23f9674da38f9c099c5', '[{\"id\":1,\"nombre\":\"Arroz para sushi\",\"unidad\":\"gramos\",\"cantidad\":100,\"precio_unitario\":0}]', 'pendiente', 1, '2025-08-15 10:01:11', NULL, 'archivos/bodega/pdfs/qr_432713b3dcf1f23f9674da38f9c099c5.pdf', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `reabasto_alertas`
--

CREATE TABLE `reabasto_alertas` (
  `id` int(11) NOT NULL,
  `insumo_id` int(11) NOT NULL,
  `proxima_estimada` date NOT NULL,
  `avisar_desde_dias` int(11) NOT NULL DEFAULT 3,
  `status` enum('proxima','vencida') DEFAULT NULL,
  `generado_en` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `reabasto_alertas`
--

INSERT INTO `reabasto_alertas` (`id`, `insumo_id`, `proxima_estimada`, `avisar_desde_dias`, `status`, `generado_en`) VALUES
(1, 2, '2025-10-12', 40, NULL, '2025-09-07 00:02:31'),
(2, 1, '2025-09-06', 10, NULL, '2025-09-07 00:30:02');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `reabasto_metricas`
--

CREATE TABLE `reabasto_metricas` (
  `insumo_id` int(11) NOT NULL,
  `avg_dias_reabasto` decimal(10,2) DEFAULT NULL,
  `min_dias` int(11) DEFAULT NULL,
  `max_dias` int(11) DEFAULT NULL,
  `ultima_entrada` date DEFAULT NULL,
  `proxima_estimada` date DEFAULT NULL,
  `actualizado_en` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `reabasto_metricas`
--

INSERT INTO `reabasto_metricas` (`insumo_id`, `avg_dias_reabasto`, `min_dias`, `max_dias`, `ultima_entrada`, `proxima_estimada`, `actualizado_en`) VALUES
(1, 16.67, 14, 19, '2025-08-20', '2025-09-06', '2025-09-07 00:12:51'),
(2, 31.50, 27, 36, '2025-09-06', '2025-10-08', '2025-09-07 00:12:51'),
(3, 7.00, 7, 7, '2025-08-06', '2025-08-13', '2025-09-07 00:12:51'),
(4, NULL, NULL, NULL, NULL, NULL, '2025-09-07 00:12:51'),
(7, NULL, NULL, NULL, NULL, NULL, '2025-09-07 00:12:51'),
(8, NULL, NULL, NULL, NULL, NULL, '2025-09-07 00:12:51'),
(9, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(10, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(11, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(12, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(13, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(14, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(15, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(16, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(17, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(18, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(19, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(20, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(21, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(22, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(23, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(24, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(25, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(26, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(27, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(28, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(29, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(30, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(31, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(32, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(33, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(34, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(35, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(36, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(37, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(38, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(39, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(40, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(41, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(42, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(43, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(44, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(45, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(46, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(47, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(48, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(49, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32'),
(50, NULL, NULL, NULL, NULL, NULL, '2025-09-06 23:53:32');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `recepciones_log`
--

CREATE TABLE `recepciones_log` (
  `id` int(11) NOT NULL,
  `sucursal_id` int(11) DEFAULT NULL,
  `qr_token` varchar(64) DEFAULT NULL,
  `fecha_recepcion` datetime DEFAULT current_timestamp(),
  `usuario_id` int(11) DEFAULT NULL,
  `json_recibido` text DEFAULT NULL,
  `estado` enum('exitoso','error') DEFAULT 'exitoso'
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `rutas`
--

CREATE TABLE `rutas` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `path` varchar(255) NOT NULL,
  `tipo` enum('link','dropdown','dropdown-item') NOT NULL,
  `grupo` varchar(50) DEFAULT NULL,
  `orden` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `rutas`
--

INSERT INTO `rutas` (`id`, `nombre`, `path`, `tipo`, `grupo`, `orden`) VALUES
(1, 'Inicio', '/vistas/index.php', 'link', NULL, 1),
(2, 'Productos', '#', 'dropdown', 'Productos', 2),
(3, 'Insumos', '/vistas/insumos/insumos.php', 'dropdown-item', 'Productos', 1),
(4, 'Inventario', '/vistas/inventario/inventario.php', 'dropdown-item', 'Productos', 2),
(6, 'Cortes', '/vistas/insumos/cortes.php', 'link', NULL, 6),
(11, 'Más', '#', 'dropdown', 'Más', 3),
(14, 'Reportes', '/vistas/reportes/reportes.php', 'dropdown-item', 'Más', 1),
(15, 'Ayuda', '/vistas/surtido/surtido.php', 'link', NULL, 4),
(18, 'Generar QR', '/vistas/bodega/generar_qr.php', 'dropdown-item', 'Más', 1),
(19, 'Recibir QR', '/vistas/bodega/recepcion_qr.php', 'dropdown-item', 'Más', 2),
(21, 'proveedores', '/vistas/insumos/proveedores.php', 'link', NULL, 5);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sucursales`
--

CREATE TABLE `sucursales` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `ubicacion` varchar(255) DEFAULT NULL,
  `token_acceso` varchar(64) DEFAULT NULL,
  `activo` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usuarios`
--

CREATE TABLE `usuarios` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `usuario` varchar(50) NOT NULL,
  `contrasena` varchar(255) NOT NULL,
  `rol` enum('cajero','mesero','admin','repartidor','cocinero') NOT NULL,
  `activo` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `usuarios`
--

INSERT INTO `usuarios` (`id`, `nombre`, `usuario`, `contrasena`, `rol`, `activo`) VALUES
(1, 'Administrador', 'admin', 'admin', 'admin', 1),
(2, 'Carlos Mesero', 'carlos', 'admin', 'mesero', 1),
(3, 'Laura Cajera', 'laura', 'admin', 'cajero', 1),
(4, 'Juan reparto', 'juan', 'admin', 'repartidor', 1),
(5, 'Luisa chef', 'luisa', 'admin', 'cocinero', 1),
(6, ' alejandro mesero', 'alex', 'admin', 'mesero', 1),
(7, 'pancho mesero', 'pancho', 'admin', 'mesero', 1);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usuario_ruta`
--

CREATE TABLE `usuario_ruta` (
  `id` int(11) NOT NULL,
  `usuario_id` int(11) NOT NULL,
  `ruta_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `usuario_ruta`
--

INSERT INTO `usuario_ruta` (`id`, `usuario_id`, `ruta_id`) VALUES
(1, 1, 1),
(2, 1, 2),
(3, 1, 3),
(4, 1, 4),
(5, 1, 21),
(6, 1, 6),
(7, 1, 7),
(8, 1, 8),
(9, 1, 9),
(10, 1, 10),
(11, 1, 11),
(12, 1, 12),
(13, 1, 13),
(14, 1, 14),
(15, 1, 15),
(16, 1, 5),
(43, 1, 17),
(44, 1, 18),
(45, 1, 19);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_bajo_stock`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_bajo_stock` (
`id` int(11)
,`nombre` varchar(100)
,`unidad` varchar(20)
,`existencia` decimal(10,2)
,`tipo_control` enum('por_receta','unidad_completa','uso_general','no_controlado','desempaquetado')
,`imagen` varchar(255)
,`minimo_stock` decimal(10,2)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_bajo_stock`
--
DROP TABLE IF EXISTS `vw_bajo_stock`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_bajo_stock`  AS SELECT `insumos`.`id` AS `id`, `insumos`.`nombre` AS `nombre`, `insumos`.`unidad` AS `unidad`, `insumos`.`existencia` AS `existencia`, `insumos`.`tipo_control` AS `tipo_control`, `insumos`.`imagen` AS `imagen`, `insumos`.`minimo_stock` AS `minimo_stock` FROM `insumos` WHERE `insumos`.`existencia` <= `insumos`.`minimo_stock` ;

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `cortes_almacen`
--
ALTER TABLE `cortes_almacen`
  ADD PRIMARY KEY (`id`),
  ADD KEY `usuario_abre_id` (`usuario_abre_id`),
  ADD KEY `usuario_cierra_id` (`usuario_cierra_id`);

--
-- Indices de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  ADD PRIMARY KEY (`id`),
  ADD KEY `corte_id` (`corte_id`),
  ADD KEY `insumo_id` (`insumo_id`);

--
-- Indices de la tabla `despachos`
--
ALTER TABLE `despachos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `sucursal_id` (`sucursal_id`),
  ADD KEY `usuario_id` (`usuario_id`);

--
-- Indices de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  ADD PRIMARY KEY (`id`),
  ADD KEY `despacho_id` (`despacho_id`),
  ADD KEY `insumo_id` (`insumo_id`);

--
-- Indices de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `proveedor_id` (`proveedor_id`),
  ADD KEY `usuario_id` (`usuario_id`),
  ADD KEY `idx_ei_insumo_fecha` (`insumo_id`,`fecha`);

--
-- Indices de la tabla `insumos`
--
ALTER TABLE `insumos`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  ADD PRIMARY KEY (`id`),
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `usuario_id` (`usuario_id`);

--
-- Indices de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `usuario_id` (`usuario_id`),
  ADD KEY `insumo_id` (`insumo_id`);

--
-- Indices de la tabla `productos`
--
ALTER TABLE `productos`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `proveedores`
--
ALTER TABLE `proveedores`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `qrs_insumo`
--
ALTER TABLE `qrs_insumo`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `reabasto_alertas`
--
ALTER TABLE `reabasto_alertas`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_alerta_insumo_fecha` (`insumo_id`,`proxima_estimada`);

--
-- Indices de la tabla `reabasto_metricas`
--
ALTER TABLE `reabasto_metricas`
  ADD PRIMARY KEY (`insumo_id`);

--
-- Indices de la tabla `recepciones_log`
--
ALTER TABLE `recepciones_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `sucursal_id` (`sucursal_id`),
  ADD KEY `usuario_id` (`usuario_id`);

--
-- Indices de la tabla `rutas`
--
ALTER TABLE `rutas`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `sucursales`
--
ALTER TABLE `sucursales`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `token_acceso` (`token_acceso`);

--
-- Indices de la tabla `usuarios`
--
ALTER TABLE `usuarios`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `usuario` (`usuario`);

--
-- Indices de la tabla `usuario_ruta`
--
ALTER TABLE `usuario_ruta`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `cortes_almacen`
--
ALTER TABLE `cortes_almacen`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=408;

--
-- AUTO_INCREMENT de la tabla `despachos`
--
ALTER TABLE `despachos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=29;

--
-- AUTO_INCREMENT de la tabla `insumos`
--
ALTER TABLE `insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=174;

--
-- AUTO_INCREMENT de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=75;

--
-- AUTO_INCREMENT de la tabla `productos`
--
ALTER TABLE `productos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `proveedores`
--
ALTER TABLE `proveedores`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `qrs_insumo`
--
ALTER TABLE `qrs_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT de la tabla `reabasto_alertas`
--
ALTER TABLE `reabasto_alertas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `recepciones_log`
--
ALTER TABLE `recepciones_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `rutas`
--
ALTER TABLE `rutas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=23;

--
-- AUTO_INCREMENT de la tabla `sucursales`
--
ALTER TABLE `sucursales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `usuario_ruta`
--
ALTER TABLE `usuario_ruta`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=46;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `cortes_almacen`
--
ALTER TABLE `cortes_almacen`
  ADD CONSTRAINT `cortes_almacen_ibfk_1` FOREIGN KEY (`usuario_abre_id`) REFERENCES `usuarios` (`id`),
  ADD CONSTRAINT `cortes_almacen_ibfk_2` FOREIGN KEY (`usuario_cierra_id`) REFERENCES `usuarios` (`id`);

--
-- Filtros para la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  ADD CONSTRAINT `cortes_almacen_detalle_ibfk_1` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`),
  ADD CONSTRAINT `cortes_almacen_detalle_ibfk_2` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`);

--
-- Filtros para la tabla `despachos`
--
ALTER TABLE `despachos`
  ADD CONSTRAINT `despachos_ibfk_1` FOREIGN KEY (`sucursal_id`) REFERENCES `sucursales` (`id`),
  ADD CONSTRAINT `despachos_ibfk_2` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);

--
-- Filtros para la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  ADD CONSTRAINT `despachos_detalle_ibfk_1` FOREIGN KEY (`despacho_id`) REFERENCES `despachos` (`id`),
  ADD CONSTRAINT `despachos_detalle_ibfk_2` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`);

--
-- Filtros para la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  ADD CONSTRAINT `entradas_insumos_ibfk_1` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`),
  ADD CONSTRAINT `entradas_insumos_ibfk_2` FOREIGN KEY (`proveedor_id`) REFERENCES `proveedores` (`id`),
  ADD CONSTRAINT `entradas_insumos_ibfk_3` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`),
  ADD CONSTRAINT `fk__insumo` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`),
  ADD CONSTRAINT `fk__proveedor` FOREIGN KEY (`proveedor_id`) REFERENCES `proveedores` (`id`),
  ADD CONSTRAINT `fk__usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);

--
-- Filtros para la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  ADD CONSTRAINT `mermas_insumo_ibfk_1` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`),
  ADD CONSTRAINT `mermas_insumo_ibfk_2` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);

--
-- Filtros para la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  ADD CONSTRAINT `movimientos_insumos_ibfk_1` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`),
  ADD CONSTRAINT `movimientos_insumos_ibfk_2` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`);

--
-- Filtros para la tabla `recepciones_log`
--
ALTER TABLE `recepciones_log`
  ADD CONSTRAINT `recepciones_log_ibfk_1` FOREIGN KEY (`sucursal_id`) REFERENCES `sucursales` (`id`),
  ADD CONSTRAINT `recepciones_log_ibfk_2` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
