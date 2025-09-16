-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 07-09-2025 a las 07:56:23
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
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_leadtime_insumos` (IN `p_desde` DATETIME, IN `p_hasta` DATETIME, IN `p_incluir_ceros` TINYINT(1))   BEGIN
  DECLARE v_hasta DATETIME;
  SET v_hasta = IF(TIME(p_hasta)='00:00:00', DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY), p_hasta);

  /* CTE: intervalos de días entre entradas consecutivas por insumo */
  WITH entradas AS (
    SELECT
      ei.insumo_id,
      DATE(ei.fecha) AS f,
      LAG(DATE(ei.fecha)) OVER (PARTITION BY ei.insumo_id ORDER BY ei.fecha) AS f_prev
    FROM entradas_insumos ei
    WHERE ei.fecha >= p_desde
      AND ei.fecha <  v_hasta
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
    WHERE ei.fecha >= p_desde
      AND ei.fecha <  v_hasta
    GROUP BY ei.insumo_id
  ),
  resumen AS (
    SELECT
      d.insumo_id,
      COUNT(*)                           AS pares_evaluados,
      ROUND(AVG(d.dias), 2)              AS avg_dias_reabasto,
      MIN(d.dias)                        AS min_dias,
      MAX(d.dias)                        AS max_dias
    FROM diffs d
    GROUP BY d.insumo_id
  )
  /* Resultado final */
  SELECT
    i.id                                  AS insumo_id,
    i.nombre                              AS insumo,
    COALESCE(r.pares_evaluados, 0)        AS pares_evaluados,
    COALESCE(r.avg_dias_reabasto, NULL)   AS avg_dias_reabasto,
    r.min_dias,
    r.max_dias,
    u.ultima_entrada,
    /* próxima estimación solo si hay promedio y última entrada */
    CASE
      WHEN r.avg_dias_reabasto IS NULL OR u.ultima_entrada IS NULL THEN NULL
      ELSE DATE_ADD(u.ultima_entrada, INTERVAL r.avg_dias_reabasto DAY)
    END                                   AS proxima_estimada,
    CASE
      WHEN r.avg_dias_reabasto IS NULL OR u.ultima_entrada IS NULL THEN NULL
      ELSE DATEDIFF(
             DATE_ADD(u.ultima_entrada, INTERVAL r.avg_dias_reabasto DAY),
             CURRENT_DATE()
           )
    END                                   AS dias_restantes
  FROM insumos i
  LEFT JOIN resumen r ON r.insumo_id = i.id
  LEFT JOIN ultimas u ON u.insumo_id = i.id
  WHERE (p_incluir_ceros = 1)
     OR (p_incluir_ceros = 0 AND r.pares_evaluados IS NOT NULL)
  ORDER BY i.nombre;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_refrescar_reabasto_y_alertas` (IN `p_desde` DATETIME, IN `p_hasta` DATETIME, IN `p_avisar_desde_dias` INT)   BEGIN
  /* Volcar el resultado del SP de cálculo a una tabla temporal */
  CREATE TEMPORARY TABLE tmp_leadtime AS
  SELECT * FROM (
    /* Reusa la lógica del SELECT final del SP anterior */
    WITH entradas AS (
      SELECT
        ei.insumo_id,
        DATE(ei.fecha) AS f,
        LAG(DATE(ei.fecha)) OVER (PARTITION BY ei.insumo_id ORDER BY ei.fecha) AS f_prev
      FROM entradas_insumos ei
      WHERE ei.fecha >= p_desde AND ei.fecha < IF(TIME(p_hasta)='00:00:00', DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY), p_hasta)
    ),
    diffs AS (
      SELECT insumo_id, DATEDIFF(f, f_prev) AS dias
      FROM entradas WHERE f_prev IS NOT NULL
    ),
    ultimas AS (
      SELECT ei.insumo_id, DATE(MAX(ei.fecha)) AS ultima_entrada
      FROM entradas_insumos ei
      WHERE ei.fecha >= p_desde AND ei.fecha < IF(TIME(p_hasta)='00:00:00', DATE_ADD(DATE(p_hasta), INTERVAL 1 DAY), p_hasta)
      GROUP BY ei.insumo_id
    ),
    resumen AS (
      SELECT insumo_id,
             COUNT(*) AS pares_evaluados,
             ROUND(AVG(dias),2) AS avg_dias_reabasto,
             MIN(dias) AS min_dias, MAX(dias) AS max_dias
      FROM diffs GROUP BY insumo_id
    )
    SELECT
      i.id AS insumo_id, i.nombre AS insumo,
      COALESCE(r.pares_evaluados,0) AS pares_evaluados,
      r.avg_dias_reabasto, r.min_dias, r.max_dias,
      u.ultima_entrada,
      CASE WHEN r.avg_dias_reabasto IS NULL OR u.ultima_entrada IS NULL
           THEN NULL
           ELSE DATE_ADD(u.ultima_entrada, INTERVAL r.avg_dias_reabasto DAY)
      END AS proxima_estimada
    FROM insumos i
    LEFT JOIN resumen r ON r.insumo_id = i.id
    LEFT JOIN ultimas u ON u.insumo_id = i.id
  ) X;

  /* UPSERT métricas */
  INSERT INTO reabasto_metricas (insumo_id, avg_dias_reabasto, min_dias, max_dias, ultima_entrada, proxima_estimada)
  SELECT insumo_id, avg_dias_reabasto, min_dias, max_dias, ultima_entrada, proxima_estimada
  FROM tmp_leadtime
  ON DUPLICATE KEY UPDATE
    avg_dias_reabasto = VALUES(avg_dias_reabasto),
    min_dias          = VALUES(min_dias),
    max_dias          = VALUES(max_dias),
    ultima_entrada    = VALUES(ultima_entrada),
    proxima_estimada  = VALUES(proxima_estimada);

  /* Generar/asegurar alertas próximas (evita duplicados por UNIQUE) */
  INSERT IGNORE INTO reabasto_alertas (insumo_id, proxima_estimada, avisar_desde_dias)
  SELECT
    insumo_id, proxima_estimada, p_avisar_desde_dias
  FROM tmp_leadtime
  WHERE proxima_estimada IS NOT NULL
    AND DATEDIFF(proxima_estimada, CURRENT_DATE()) <= p_avisar_desde_dias
    AND DATEDIFF(proxima_estimada, CURRENT_DATE()) >= 0;

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

--
-- Volcado de datos para la tabla `cortes_almacen`
--

INSERT INTO `cortes_almacen` (`id`, `fecha_inicio`, `fecha_fin`, `usuario_abre_id`, `usuario_cierra_id`, `observaciones`) VALUES
(6, '2025-08-01 12:09:55', '2025-08-01 12:37:52', 1, 1, 'ninguna'),
(7, '2025-08-01 16:48:23', '2025-08-02 00:49:20', 1, 1, 'no'),
(8, '2025-08-01 19:53:50', '2025-08-02 03:55:00', 1, 1, 'sin observacion'),
(9, '2025-09-03 16:28:12', '2025-09-04 00:28:34', 1, 1, 'cierre');

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

--
-- Volcado de datos para la tabla `cortes_almacen_detalle`
--

INSERT INTO `cortes_almacen_detalle` (`id`, `corte_id`, `insumo_id`, `existencia_inicial`, `entradas`, `salidas`, `mermas`, `existencia_final`) VALUES
(49, 6, 1, 1990.00, 0.00, -90.00, 0.00, 1900.00),
(50, 6, 2, 20.00, 0.00, 0.00, 0.00, 20.00),
(51, 6, 3, 1300.00, 0.00, 0.00, 0.00, 1300.00),
(52, 6, 4, 20.00, 0.00, 0.00, 0.00, 20.00),
(53, 6, 7, 49.00, 0.00, 0.00, 0.00, 49.00),
(54, 6, 8, 1500.00, 0.00, 0.00, 0.00, 1500.00),
(55, 6, 9, 900.00, 0.00, 0.00, 0.00, 900.00),
(56, 6, 10, 1200.00, 0.00, 0.00, 0.00, 1200.00),
(57, 6, 11, 209.00, 0.00, 0.00, 0.00, 209.00),
(58, 6, 12, 1600.00, 0.00, 0.00, 0.00, 1600.00),
(59, 6, 13, 3400.00, 0.00, 0.00, 0.00, 3400.00),
(60, 6, 14, 6700.00, 0.00, 0.00, 0.00, 6700.00),
(61, 6, 15, 4600.00, 0.00, 0.00, 0.00, 4600.00),
(62, 6, 16, 330.00, 0.00, 0.00, 30.00, 300.00),
(63, 6, 17, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(64, 6, 18, 238.00, 0.00, 0.00, 0.00, 238.00),
(65, 6, 19, 1200.00, 0.00, 0.00, 0.00, 1200.00),
(66, 6, 20, 290.00, 0.00, 0.00, 0.00, 290.00),
(67, 6, 21, 230.00, 0.00, 0.00, 0.00, 230.00),
(68, 6, 22, 230.00, 0.00, 0.00, 0.00, 230.00),
(69, 6, 23, 340.00, 0.00, 0.00, 0.00, 340.00),
(70, 6, 24, 340.00, 0.00, 0.00, 0.00, 440.00),
(71, 6, 25, 12.00, 0.00, 0.00, 0.00, 12.00),
(72, 6, 26, 340.00, 0.00, 0.00, 0.00, 340.00),
(73, 6, 27, 340.00, 0.00, 0.00, 0.00, 340.00),
(74, 6, 28, 780.00, 0.00, 0.00, 0.00, 780.00),
(75, 6, 29, 230.00, 0.00, 0.00, 0.00, 230.00),
(76, 6, 30, 340.00, 0.00, 0.00, 0.00, 340.00),
(77, 6, 31, 450.00, 0.00, 0.00, 0.00, 450.00),
(78, 6, 32, 45.00, 0.00, 0.00, 0.00, 45.00),
(79, 6, 33, 670.00, 0.00, 0.00, 0.00, 670.00),
(80, 6, 34, 56.00, 0.00, 0.00, 0.00, 56.00),
(81, 6, 35, 90.00, 0.00, 0.00, 0.00, 90.00),
(82, 6, 36, 90.00, 0.00, 0.00, 0.00, 90.00),
(83, 6, 37, 34.00, 0.00, 0.00, 0.00, 34.00),
(84, 6, 38, 560.00, 0.00, 0.00, 0.00, 560.00),
(85, 6, 39, 34.00, 0.00, 0.00, 0.00, 34.00),
(86, 6, 40, 345.00, 0.00, 0.00, 0.00, 345.00),
(87, 6, 41, 560.00, 0.00, 0.00, 0.00, 560.00),
(88, 6, 42, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(89, 6, 43, 349.00, 0.00, 0.00, 0.00, 349.00),
(90, 6, 44, 89.00, 0.00, 0.00, 0.00, 89.00),
(91, 6, 45, 78.00, 0.00, 0.00, 0.00, 78.00),
(92, 6, 46, 670.00, 0.00, 0.00, 0.00, 670.00),
(93, 6, 47, 89.00, 0.00, 0.00, 0.00, 89.00),
(94, 6, 48, 890.00, 0.00, 0.00, 0.00, 890.00),
(95, 6, 49, 45.00, 0.00, 0.00, 0.00, 45.00),
(96, 6, 50, 45.00, 0.00, 0.00, 0.00, 45.00),
(97, 7, 1, 1900.00, 0.00, 0.00, 0.00, 1900.00),
(98, 7, 2, 20.00, 0.00, 0.00, 0.00, 20.00),
(99, 7, 3, 1300.00, 0.00, 0.00, 0.00, 1300.00),
(100, 7, 4, 20.00, 0.00, 0.00, 0.00, 20.00),
(101, 7, 7, 49.00, 0.00, 0.00, 0.00, 49.00),
(102, 7, 8, 1500.00, 0.00, 0.00, 0.00, 1500.00),
(103, 7, 9, 900.00, 0.00, 0.00, 0.00, 900.00),
(104, 7, 10, 1200.00, 0.00, 0.00, 0.00, 1200.00),
(105, 7, 11, 209.00, 0.00, 0.00, 0.00, 209.00),
(106, 7, 12, 1600.00, 0.00, -600.00, 0.00, 1000.00),
(107, 7, 13, 3400.00, 0.00, 0.00, 0.00, 3400.00),
(108, 7, 14, 6700.00, 0.00, 0.00, 0.00, 6700.00),
(109, 7, 15, 4600.00, 0.00, 0.00, 0.00, 4600.00),
(110, 7, 16, 300.00, 0.00, 0.00, 0.00, 300.00),
(111, 7, 17, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(112, 7, 18, 238.00, 0.00, 0.00, 0.00, 238.00),
(113, 7, 19, 1200.00, 0.00, 0.00, 0.00, 1200.00),
(114, 7, 20, 290.00, 0.00, 0.00, 0.00, 290.00),
(115, 7, 21, 230.00, 0.00, 0.00, 0.00, 230.00),
(116, 7, 22, 230.00, 0.00, 0.00, 0.00, 230.00),
(117, 7, 23, 340.00, 0.00, 0.00, 0.00, 340.00),
(118, 7, 24, 440.00, 0.00, 0.00, 0.00, 440.00),
(119, 7, 25, 12.00, 0.00, 0.00, 0.00, 12.00),
(120, 7, 26, 340.00, 0.00, 0.00, 0.00, 340.00),
(121, 7, 27, 340.00, 0.00, 0.00, 0.00, 340.00),
(122, 7, 28, 780.00, 0.00, 0.00, 0.00, 780.00),
(123, 7, 29, 230.00, 0.00, 0.00, 0.00, 230.00),
(124, 7, 30, 340.00, 0.00, 0.00, 0.00, 340.00),
(125, 7, 31, 450.00, 0.00, -50.00, 0.00, 400.00),
(126, 7, 32, 45.00, 0.00, 0.00, 0.00, 45.00),
(127, 7, 33, 670.00, 0.00, 0.00, 0.00, 670.00),
(128, 7, 34, 56.00, 0.00, 0.00, 0.00, 56.00),
(129, 7, 35, 90.00, 0.00, 0.00, 0.00, 90.00),
(130, 7, 36, 90.00, 0.00, 0.00, 0.00, 90.00),
(131, 7, 37, 34.00, 0.00, 0.00, 0.00, 34.00),
(132, 7, 38, 560.00, 0.00, 0.00, 0.00, 560.00),
(133, 7, 39, 34.00, 0.00, 0.00, 0.00, 34.00),
(134, 7, 40, 345.00, 0.00, 0.00, 0.00, 345.00),
(135, 7, 41, 560.00, 1000.00, 0.00, 0.00, 1560.00),
(136, 7, 42, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(137, 7, 43, 349.00, 0.00, 0.00, 0.00, 349.00),
(138, 7, 44, 89.00, 0.00, 0.00, 0.00, 89.00),
(139, 7, 45, 78.00, 0.00, 0.00, 0.00, 78.00),
(140, 7, 46, 670.00, 0.00, 0.00, 0.00, 670.00),
(141, 7, 47, 89.00, 0.00, 0.00, 0.00, 89.00),
(142, 7, 48, 890.00, 0.00, 0.00, 0.00, 890.00),
(143, 7, 49, 45.00, 0.00, 0.00, 0.00, 45.00),
(144, 7, 50, 45.00, 0.00, 0.00, 0.00, 45.00),
(145, 8, 1, 1900.00, 0.00, 0.00, 0.00, 1900.00),
(146, 8, 2, 20.00, 0.00, 0.00, 0.00, 20.00),
(147, 8, 3, 1300.00, 0.00, -1000.00, 0.00, 300.00),
(148, 8, 4, 20.00, 0.00, -10.00, 0.00, 10.00),
(149, 8, 7, 49.00, 0.00, 0.00, 0.00, 49.00),
(150, 8, 8, 1500.00, 0.00, 0.00, 0.00, 1500.00),
(151, 8, 9, 900.00, 0.00, 0.00, 0.00, 900.00),
(152, 8, 10, 1170.00, 0.00, 0.00, 0.00, 1170.00),
(153, 8, 11, 209.00, 0.00, 0.00, 0.00, 209.00),
(154, 8, 12, 1000.00, 0.00, 0.00, 0.00, 1000.00),
(155, 8, 13, 3000.00, 2000.00, 0.00, 0.00, 5000.00),
(156, 8, 14, 6000.00, 0.00, 0.00, 0.00, 6000.00),
(157, 8, 15, 4600.00, 0.00, 0.00, 0.00, 4600.00),
(158, 8, 16, 200.00, 0.00, 0.00, 0.00, 200.00),
(159, 8, 17, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(160, 8, 18, 238.00, 0.00, 0.00, 0.00, 238.00),
(161, 8, 19, 1200.00, 0.00, 0.00, 0.00, 1200.00),
(162, 8, 20, 290.00, 0.00, 0.00, 0.00, 290.00),
(163, 8, 21, 230.00, 0.00, 0.00, 0.00, 230.00),
(164, 8, 22, 230.00, 0.00, 0.00, 0.00, 230.00),
(165, 8, 23, 340.00, 0.00, 0.00, 0.00, 340.00),
(166, 8, 24, 440.00, 0.00, 0.00, 0.00, 440.00),
(167, 8, 25, 12.00, 0.00, 0.00, 0.00, 12.00),
(168, 8, 26, 340.00, 0.00, 0.00, 0.00, 340.00),
(169, 8, 27, 340.00, 0.00, 0.00, 0.00, 340.00),
(170, 8, 28, 780.00, 0.00, 0.00, 0.00, 780.00),
(171, 8, 29, 230.00, 0.00, 0.00, 0.00, 230.00),
(172, 8, 30, 340.00, 0.00, 0.00, 0.00, 340.00),
(173, 8, 31, 400.00, 0.00, 0.00, 0.00, 400.00),
(174, 8, 32, 45.00, 0.00, 0.00, 0.00, 45.00),
(175, 8, 33, 670.00, 0.00, 0.00, 0.00, 670.00),
(176, 8, 34, 56.00, 0.00, 0.00, 0.00, 56.00),
(177, 8, 35, 90.00, 0.00, 0.00, 0.00, 90.00),
(178, 8, 36, 90.00, 0.00, 0.00, 0.00, 90.00),
(179, 8, 37, 34.00, 0.00, 0.00, 0.00, 34.00),
(180, 8, 38, 560.00, 0.00, 0.00, 0.00, 560.00),
(181, 8, 39, 34.00, 0.00, 0.00, 0.00, 34.00),
(182, 8, 40, 345.00, 0.00, 0.00, 0.00, 345.00),
(183, 8, 41, 1560.00, 0.00, 0.00, 1000.00, 560.00),
(184, 8, 42, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(185, 8, 43, 349.00, 0.00, 0.00, 0.00, 349.00),
(186, 8, 44, 89.00, 0.00, 0.00, 0.00, 89.00),
(187, 8, 45, 78.00, 0.00, 0.00, 0.00, 78.00),
(188, 8, 46, 670.00, 0.00, 0.00, 0.00, 670.00),
(189, 8, 47, 89.00, 0.00, 0.00, 0.00, 89.00),
(190, 8, 48, 890.00, 0.00, 0.00, 0.00, 890.00),
(191, 8, 49, 45.00, 0.00, 0.00, 0.00, 45.00),
(192, 8, 50, 45.00, 0.00, 0.00, 0.00, 45.00),
(193, 9, 1, 1800.00, 0.00, 0.00, 0.00, 1800.00),
(194, 9, 2, 20.00, 0.00, 0.00, 0.00, 20.00),
(195, 9, 3, 300.00, 0.00, 0.00, 0.00, 300.00),
(196, 9, 4, 10.00, 0.00, 0.00, 0.00, 10.00),
(197, 9, 7, 49.00, 0.00, 0.00, 0.00, 49.00),
(198, 9, 8, 1500.00, 0.00, 0.00, 0.00, 1500.00),
(199, 9, 9, 900.00, 0.00, 0.00, 0.00, 900.00),
(200, 9, 10, 1170.00, 0.00, 0.00, 0.00, 1170.00),
(201, 9, 11, 209.00, 0.00, 0.00, 0.00, 209.00),
(202, 9, 12, 1000.00, 0.00, 0.00, 0.00, 1000.00),
(203, 9, 13, 5000.00, 0.00, 0.00, 0.00, 5000.00),
(204, 9, 14, 6000.00, 0.00, 0.00, 0.00, 6000.00),
(205, 9, 15, 4600.00, 0.00, 0.00, 0.00, 4600.00),
(206, 9, 16, 200.00, 0.00, 0.00, 0.00, 200.00),
(207, 9, 17, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(208, 9, 18, 238.00, 0.00, 0.00, 0.00, 238.00),
(209, 9, 19, 1200.00, 0.00, 0.00, 0.00, 1200.00),
(210, 9, 20, 290.00, 0.00, 0.00, 0.00, 290.00),
(211, 9, 21, 230.00, 0.00, 0.00, 0.00, 230.00),
(212, 9, 22, 230.00, 0.00, 0.00, 0.00, 230.00),
(213, 9, 23, 340.00, 0.00, 0.00, 0.00, 340.00),
(214, 9, 24, 440.00, 0.00, 0.00, 0.00, 440.00),
(215, 9, 25, 12.00, 0.00, 0.00, 0.00, 12.00),
(216, 9, 26, 340.00, 0.00, 0.00, 0.00, 340.00),
(217, 9, 27, 340.00, 0.00, 0.00, 0.00, 340.00),
(218, 9, 28, 780.00, 0.00, 0.00, 0.00, 780.00),
(219, 9, 29, 230.00, 0.00, 0.00, 0.00, 230.00),
(220, 9, 30, 340.00, 0.00, 0.00, 0.00, 340.00),
(221, 9, 31, 400.00, 0.00, 0.00, 0.00, 400.00),
(222, 9, 32, 45.00, 0.00, 0.00, 0.00, 45.00),
(223, 9, 33, 670.00, 0.00, 0.00, 0.00, 670.00),
(224, 9, 34, 56.00, 0.00, 0.00, 0.00, 56.00),
(225, 9, 35, 90.00, 0.00, 0.00, 0.00, 90.00),
(226, 9, 36, 90.00, 0.00, 0.00, 0.00, 90.00),
(227, 9, 37, 34.00, 0.00, 0.00, 0.00, 34.00),
(228, 9, 38, 560.00, 0.00, 0.00, 0.00, 560.00),
(229, 9, 39, 34.00, 0.00, 0.00, 0.00, 34.00),
(230, 9, 40, 345.00, 0.00, 0.00, 0.00, 345.00),
(231, 9, 41, 560.00, 0.00, 0.00, 0.00, 560.00),
(232, 9, 42, 4000.00, 0.00, 0.00, 0.00, 4000.00),
(233, 9, 43, 349.00, 0.00, 0.00, 0.00, 349.00),
(234, 9, 44, 89.00, 0.00, 0.00, 0.00, 89.00),
(235, 9, 45, 78.00, 0.00, 0.00, 0.00, 78.00),
(236, 9, 46, 670.00, 0.00, 0.00, 0.00, 670.00),
(237, 9, 47, 89.00, 0.00, 0.00, 0.00, 89.00),
(238, 9, 48, 890.00, 0.00, 0.00, 0.00, 890.00),
(239, 9, 49, 45.00, 0.00, 0.00, 0.00, 45.00),
(240, 9, 50, 45.00, 0.00, 0.00, 0.00, 45.00);

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
  `folio_fiscal` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `entradas_insumos`
--

INSERT INTO `entradas_insumos` (`id`, `insumo_id`, `proveedor_id`, `usuario_id`, `fecha`, `descripcion`, `cantidad`, `unidad`, `costo_total`, `referencia_doc`, `folio_fiscal`) VALUES
(1, 1, 1, 1, '2025-08-01 01:46:19', 'Entrada de Arroz para sushi', 2400.00, 'gramos', 365.00, 'REF1001', 'FISCAL2001'),
(2, 2, 1, 1, '2025-08-01 01:46:19', 'Entrada de Alga Nori', 20.00, 'piezas', 13.00, 'REF1002', 'FISCAL2002'),
(3, 3, 1, 1, '2025-08-01 01:46:19', 'Entrada de Salmón fresco', 1300.00, 'gramos', 210.00, 'REF1003', 'FISCAL2003'),
(4, 4, 1, 1, '2025-08-01 01:46:19', 'Entrada de Refresco en lata', 20.00, 'piezas', 23.00, 'REF1004', 'FISCAL2004'),
(5, 7, 1, 1, '2025-08-01 01:46:19', 'Entrada de Surimi', 49.00, 'pieza', 32.35, 'REF1005', 'FISCAL2005'),
(6, 8, 1, 1, '2025-08-01 01:46:19', 'Entrada de Tocino', 1500.00, 'gramos', 255.00, 'REF1006', 'FISCAL2006'),
(7, 2, 2, 1, '2025-09-06 21:37:12', '0', 4000.00, '0', 200.00, 'ref-h79880', 'mar7913209');

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
(1, 'Arroz para sushi', 'gramos', 1800.00, 'por_receta', 'ins_68717301313ad.jpg', 0.00),
(2, 'Alga Nori', 'piezas', 4020.00, 'por_receta', 'ins_6871716a72681.jpg', 0.00),
(3, 'Salmón fresco', 'gramos', 300.00, 'por_receta', 'ins_6871777fa2c56.png', 0.00),
(4, 'Refresco en lata', 'piezas', 10.00, 'unidad_completa', 'ins_6871731d075cb.webp', 0.00),
(7, 'Surimi', 'pieza', 49.00, 'uso_general', 'ins_688a521dcd583.jpg', 0.00),
(8, 'Tocino', 'gramos', 1500.00, 'uso_general', 'ins_688a4dc84c002.jpg', 0.00),
(9, 'Pollo', 'gramos', 900.00, 'desempaquetado', 'ins_688a4e4bd5999.jpg', 0.00),
(10, 'Camarón', 'pieza', 1170.00, 'desempaquetado', 'ins_688a4f5c873c6.jpg', 0.00),
(11, 'Queso chihuahua', 'gramos', 209.00, 'unidad_completa', 'ins_688a4feca9865.jpg', 0.00),
(12, 'Philadelphia', 'gramos', 1000.00, 'uso_general', 'ins_688a504f9cb40.jpg', 0.00),
(13, 'Arroz blanco', 'gramos', 5000.00, 'por_receta', 'ins_688a51ce64ae2.jpg', 0.00),
(14, 'Carne de res', 'gramos', 6000.00, 'uso_general', 'ins_688a528d1261a.jpg', 0.00),
(15, 'Queso americano', 'gramos', 4600.00, 'uso_general', 'ins_688a53246c1c2.jpg', 0.00),
(16, 'Ajonjolí', 'gramos', 200.00, 'uso_general', 'ins_688a539309feb.jpg', 0.00),
(17, 'Panko', 'gramos', 4000.00, 'por_receta', 'ins_688a53da64b5f.jpg', 0.00),
(18, 'Salsa tampico', 'mililitros', 238.00, 'no_controlado', 'ins_688a54cf1872b.jpg', 0.00),
(19, 'Anguila', 'gramos', 1200.00, 'por_receta', 'ins_688a552023b54.jpg', 0.00),
(20, 'salsa bbq', 'mililitros', 290.00, 'no_controlado', 'ins_688a557431fce.jpg', 0.00),
(21, 'Chile serrano', 'gramos', 230.00, 'uso_general', 'ins_688a55c66f09d.jpg', 0.00),
(22, 'Chile morrón', 'gramos', 230.00, 'por_receta', 'ins_688a5616e8f25.jpg', 0.00),
(23, 'Kanikama', 'gramos', 340.00, 'por_receta', 'ins_688a5669e24a8.jpg', 0.00),
(24, 'Aguacate', 'gramos', 440.00, 'por_receta', 'ins_688a56a371905.jpg', 0.00),
(25, 'Dedos de queso', 'pieza', 12.00, 'unidad_completa', 'ins_688a56fda3221.jpg', 0.00),
(26, 'Mango', 'gramos', 340.00, 'por_receta', 'ins_688a573c762f4.jpg', 0.00),
(27, 'Tostadas', 'pieza', 340.00, 'uso_general', 'ins_688a57a499b35.jpg', 0.00),
(28, 'Papa', 'gramos', 780.00, 'por_receta', 'ins_688a580061ffd.jpg', 0.00),
(29, 'Cebolla morada', 'gramos', 230.00, 'por_receta', 'ins_688a5858752a0.jpg', 0.00),
(30, 'Salsa de soya', 'mililitros', 340.00, 'no_controlado', 'ins_688a58cc6cb6c.jpg', 0.00),
(31, 'Naranja', 'gramos', 400.00, 'por_receta', 'ins_688a590bca275.jpg', 0.00),
(32, 'Chile caribe', 'gramos', 45.00, 'por_receta', 'ins_688a59836c32e.jpg', 0.00),
(33, 'Pulpo', 'gramos', 670.00, 'por_receta', 'ins_688a59c9a1d0b.jpg', 0.00),
(34, 'Zanahoria', 'gramos', 56.00, 'por_receta', 'ins_688a5a0a3a959.jpg', 0.00),
(35, 'Apio', 'gramos', 90.00, 'por_receta', 'ins_688a5a52af990.jpg', 0.00),
(36, 'Pepino', 'gramos', 90.00, 'uso_general', 'ins_688a5aa0cbaf5.jpg', 0.00),
(37, 'Masago', 'gramos', 34.00, 'por_receta', 'ins_688a5b3f0dca6.jpg', 0.00),
(38, 'Nuez de la india', 'gramos', 560.00, 'por_receta', 'ins_688a5be531e11.jpg', 0.00),
(39, 'Cátsup', 'gramos', 34.00, 'por_receta', 'ins_688a5c657eb83.jpg', 0.00),
(40, 'Atún', 'gramos', 345.00, 'por_receta', 'ins_688a5ce18adc5.jpg', 0.00),
(41, 'Callo', 'gramos', 560.00, 'por_receta', 'ins_688a5d28de8a5.jpg', 0.00),
(42, 'Calabacin', 'gramos', 4000.00, 'unidad_completa', 'ins_688a5d6b2bca1.jpg', 0.00),
(43, 'Fideo chino transparente', 'gramos', 349.00, 'por_receta', 'ins_688a5dd3b406d.jpg', 0.00),
(44, 'Brócoli', 'gramos', 89.00, 'por_receta', 'ins_688a5e2736870.jpg', 0.00),
(45, 'Chile de árbol', 'pieza', 78.00, 'por_receta', 'ins_688a5e6f08ccd.jpg', 0.00),
(46, 'Pasta udon', 'gramos', 670.00, 'por_receta', 'ins_688a5eb627f38.jpg', 0.00),
(47, 'Huevo', 'pieza', 89.00, 'por_receta', 'ins_688a5ef9b575e.jpg', 0.00),
(48, 'Cerdo', 'gramos', 890.00, 'por_receta', 'ins_688a5f3915f5e.jpg', 0.00),
(49, 'Masa para gyozas', 'pieza', 45.00, 'por_receta', 'ins_688a5fae2e7f1.jpg', 0.00),
(50, 'Naruto', 'gramos', 45.00, 'por_receta', 'ins_688a5ff57f62d.jpg', 0.00);

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
(2, 'Pescados del Pacífico', '555-987-6543', 'Av. Mar #456, CDMX');

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
  `generado_en` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

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
(1, NULL, NULL, NULL, '2025-08-01', NULL, '2025-09-06 23:53:32'),
(2, 36.00, 36, 36, '2025-09-06', '2025-10-12', '2025-09-06 23:53:32'),
(3, NULL, NULL, NULL, '2025-08-01', NULL, '2025-09-06 23:53:32'),
(4, NULL, NULL, NULL, '2025-08-01', NULL, '2025-09-06 23:53:32'),
(7, NULL, NULL, NULL, '2025-08-01', NULL, '2025-09-06 23:53:32'),
(8, NULL, NULL, NULL, '2025-08-01', NULL, '2025-09-06 23:53:32'),
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
(15, 'Ayuda', '/vistas/ayuda.php', 'link', NULL, 4),
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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=241;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT de la tabla `insumos`
--
ALTER TABLE `insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=51;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `qrs_insumo`
--
ALTER TABLE `qrs_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT de la tabla `reabasto_alertas`
--
ALTER TABLE `reabasto_alertas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

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
