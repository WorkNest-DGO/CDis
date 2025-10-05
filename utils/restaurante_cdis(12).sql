-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 05-10-2025 a las 09:17:50
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

--
-- Volcado de datos para la tabla `cortes_almacen`
--

INSERT INTO `cortes_almacen` (`id`, `fecha_inicio`, `fecha_fin`, `usuario_abre_id`, `usuario_cierra_id`, `observaciones`) VALUES
(1, '2025-10-04 23:00:23', '2025-10-05 07:56:14', 1, 1, 'cerrado'),
(2, '2025-10-05 00:25:34', NULL, 1, NULL, NULL);

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
(1, 1, 1, 29000.00, 0.00, 0.00, 1000.00, 35000.00),
(2, 1, 2, 0.00, 0.00, 0.00, 0.00, 0.00),
(3, 1, 3, 0.00, 0.00, 0.00, 0.00, 0.00),
(4, 1, 4, 0.00, 0.00, 0.00, 0.00, 0.00),
(5, 1, 7, 0.00, 0.00, 0.00, 0.00, 0.00),
(6, 1, 8, 0.00, 0.00, 0.00, 0.00, 0.00),
(7, 1, 9, 0.00, 0.00, 0.00, 0.00, 0.00),
(8, 1, 10, 0.00, 0.00, 0.00, 0.00, 0.00),
(9, 1, 11, 0.00, 0.00, 0.00, 0.00, 0.00),
(10, 1, 12, 0.00, 0.00, 0.00, 0.00, 0.00),
(11, 1, 13, 800.00, 0.00, 0.00, 0.00, 4800.00),
(12, 1, 14, 0.00, 0.00, 0.00, 0.00, 0.00),
(13, 1, 15, 0.00, 0.00, 0.00, 0.00, 0.00),
(14, 1, 16, 0.00, 0.00, 0.00, 0.00, 0.00),
(15, 1, 17, 0.00, 0.00, 0.00, 0.00, 0.00),
(16, 1, 18, 0.00, 0.00, 0.00, 0.00, 0.00),
(17, 1, 19, 0.00, 0.00, 0.00, 0.00, 0.00),
(18, 1, 20, 0.00, 0.00, 0.00, 0.00, 0.00),
(19, 1, 21, 0.00, 0.00, 0.00, 0.00, 0.00),
(20, 1, 22, 0.00, 0.00, 0.00, 0.00, 0.00),
(21, 1, 23, 0.00, 0.00, 0.00, 0.00, 0.00),
(22, 1, 24, 0.00, 0.00, 0.00, 0.00, 0.00),
(23, 1, 25, 0.00, 0.00, 0.00, 0.00, 0.00),
(24, 1, 26, 0.00, 0.00, 0.00, 0.00, 0.00),
(25, 1, 27, 0.00, 0.00, 0.00, 0.00, 0.00),
(26, 1, 28, 0.00, 0.00, 0.00, 0.00, 0.00),
(27, 1, 29, 0.00, 0.00, 0.00, 0.00, 0.00),
(28, 1, 30, 0.00, 0.00, 0.00, 0.00, 0.00),
(29, 1, 31, 0.00, 0.00, 0.00, 0.00, 0.00),
(30, 1, 32, 0.00, 0.00, 0.00, 0.00, 0.00),
(31, 1, 33, 0.00, 0.00, 0.00, 0.00, 0.00),
(32, 1, 34, 0.00, 0.00, 0.00, 0.00, 0.00),
(33, 1, 35, 0.00, 0.00, 0.00, 0.00, 0.00),
(34, 1, 36, 0.00, 0.00, 0.00, 0.00, 0.00),
(35, 1, 37, 0.00, 0.00, 0.00, 0.00, 0.00),
(36, 1, 38, 0.00, 0.00, 0.00, 0.00, 0.00),
(37, 1, 39, 0.00, 0.00, 0.00, 0.00, 0.00),
(38, 1, 40, 0.00, 0.00, 0.00, 0.00, 0.00),
(39, 1, 41, 0.00, 0.00, 0.00, 0.00, 0.00),
(40, 1, 42, 0.00, 0.00, 0.00, 0.00, 0.00),
(41, 1, 43, 0.00, 0.00, 0.00, 0.00, 0.00),
(42, 1, 44, 0.00, 0.00, 0.00, 0.00, 0.00),
(43, 1, 45, 0.00, 0.00, 0.00, 0.00, 0.00),
(44, 1, 46, 0.00, 0.00, 0.00, 0.00, 0.00),
(45, 1, 47, 0.00, 0.00, 0.00, 0.00, 0.00),
(46, 1, 48, 0.00, 0.00, 0.00, 0.00, 0.00),
(47, 1, 49, 0.00, 0.00, 0.00, 0.00, 0.00),
(48, 1, 50, 0.00, 0.00, 0.00, 0.00, 0.00),
(49, 1, 51, 0.00, 0.00, 0.00, 0.00, 0.00),
(50, 1, 52, 0.00, 0.00, 0.00, 0.00, 0.00),
(51, 1, 53, 0.00, 0.00, 0.00, 0.00, 0.00),
(52, 1, 54, 0.00, 0.00, 0.00, 0.00, 0.00),
(53, 1, 55, 0.00, 0.00, 0.00, 0.00, 0.00),
(54, 1, 56, 0.00, 0.00, 0.00, 0.00, 0.00),
(55, 1, 57, 0.00, 0.00, 0.00, 0.00, 0.00),
(56, 1, 59, 0.00, 0.00, 0.00, 0.00, 0.00),
(57, 1, 60, 0.00, 0.00, 0.00, 0.00, 0.00),
(58, 1, 61, 0.00, 0.00, 0.00, 0.00, 0.00),
(59, 1, 62, 0.00, 0.00, 0.00, 0.00, 0.00),
(60, 1, 63, 0.00, 0.00, 0.00, 0.00, 0.00),
(61, 1, 64, 0.00, 0.00, 0.00, 0.00, 0.00),
(62, 1, 65, 0.00, 0.00, 0.00, 0.00, 0.00),
(63, 1, 66, 0.00, 0.00, 0.00, 0.00, 0.00),
(64, 1, 67, 0.00, 0.00, 0.00, 0.00, 0.00),
(65, 1, 69, 0.00, 0.00, 0.00, 0.00, 0.00),
(66, 1, 70, 0.00, 0.00, 0.00, 0.00, 0.00),
(67, 1, 71, 0.00, 0.00, 0.00, 0.00, 0.00),
(68, 1, 72, 0.00, 0.00, 0.00, 0.00, 0.00),
(69, 1, 73, 0.00, 0.00, 0.00, 0.00, 0.00),
(70, 1, 74, 0.00, 0.00, 0.00, 0.00, 0.00),
(71, 1, 75, 0.00, 0.00, 0.00, 0.00, 0.00),
(72, 1, 76, 0.00, 0.00, 0.00, 0.00, 0.00),
(73, 1, 77, 0.00, 0.00, 0.00, 0.00, 0.00),
(74, 1, 78, 0.00, 0.00, 0.00, 0.00, 0.00),
(75, 1, 79, 0.00, 0.00, 0.00, 0.00, 0.00),
(76, 1, 80, 0.00, 0.00, 0.00, 0.00, 0.00),
(77, 1, 81, 0.00, 0.00, 0.00, 0.00, 0.00),
(78, 1, 82, 0.00, 0.00, 0.00, 0.00, 0.00),
(79, 1, 83, 0.00, 0.00, 0.00, 0.00, 0.00),
(80, 1, 85, 0.00, 0.00, 0.00, 0.00, 0.00),
(81, 1, 86, 0.00, 0.00, 0.00, 0.00, 0.00),
(82, 1, 87, 0.00, 0.00, 0.00, 0.00, 0.00),
(83, 1, 88, 0.00, 0.00, 0.00, 0.00, 0.00),
(84, 1, 89, 0.00, 0.00, 0.00, 0.00, 0.00),
(85, 1, 90, 0.00, 0.00, 0.00, 0.00, 0.00),
(86, 1, 91, 0.00, 0.00, 0.00, 0.00, 0.00),
(87, 1, 92, 0.00, 0.00, 0.00, 0.00, 0.00),
(88, 1, 93, 0.00, 0.00, 0.00, 0.00, 0.00),
(89, 1, 94, 0.00, 0.00, 0.00, 0.00, 0.00),
(90, 1, 95, 0.00, 0.00, 0.00, 0.00, 0.00),
(91, 1, 96, 0.00, 0.00, 0.00, 0.00, 0.00),
(92, 1, 97, 0.00, 0.00, 0.00, 0.00, 0.00),
(93, 1, 98, 0.00, 0.00, 0.00, 0.00, 0.00),
(94, 1, 99, 0.00, 0.00, 0.00, 0.00, 0.00),
(95, 1, 101, 0.00, 0.00, 0.00, 0.00, 0.00),
(96, 1, 102, 0.00, 0.00, 0.00, 0.00, 0.00),
(97, 1, 103, 0.00, 0.00, 0.00, 0.00, 0.00),
(98, 1, 104, 0.00, 0.00, 0.00, 0.00, 0.00),
(99, 1, 105, 0.00, 0.00, 0.00, 0.00, 0.00),
(100, 1, 106, 0.00, 0.00, 0.00, 0.00, 0.00),
(101, 1, 107, 0.00, 0.00, 0.00, 0.00, 0.00),
(102, 1, 108, 0.00, 0.00, 0.00, 0.00, 0.00),
(103, 1, 109, 0.00, 0.00, 0.00, 0.00, 0.00),
(104, 1, 110, 0.00, 0.00, 0.00, 0.00, 0.00),
(105, 1, 111, 0.00, 0.00, 0.00, 0.00, 0.00),
(106, 1, 112, 0.00, 0.00, 0.00, 0.00, 0.00),
(107, 1, 113, 0.00, 0.00, 0.00, 0.00, 0.00),
(108, 1, 114, 0.00, 0.00, 0.00, 0.00, 0.00),
(109, 1, 115, 0.00, 0.00, 0.00, 0.00, 0.00),
(110, 1, 116, 0.00, 0.00, 0.00, 0.00, 0.00),
(111, 1, 117, 0.00, 0.00, 0.00, 0.00, 0.00),
(112, 1, 118, 0.00, 0.00, 0.00, 0.00, 0.00),
(113, 1, 119, 0.00, 0.00, 0.00, 0.00, 0.00),
(114, 1, 120, 0.00, 0.00, 0.00, 0.00, 0.00),
(115, 1, 121, 0.00, 0.00, 0.00, 0.00, 0.00),
(116, 1, 122, 0.00, 0.00, 0.00, 0.00, 0.00),
(117, 1, 123, 0.00, 0.00, 0.00, 0.00, 0.00),
(118, 1, 124, 0.00, 0.00, 0.00, 0.00, 0.00),
(119, 1, 125, 0.00, 0.00, 0.00, 0.00, 0.00),
(120, 1, 126, 0.00, 0.00, 0.00, 0.00, 0.00),
(121, 1, 127, 0.00, 0.00, 0.00, 0.00, 0.00),
(122, 1, 128, 0.00, 0.00, 0.00, 0.00, 0.00),
(123, 1, 129, 0.00, 0.00, 0.00, 0.00, 0.00),
(124, 1, 130, 0.00, 0.00, 0.00, 0.00, 0.00),
(125, 1, 131, 0.00, 0.00, 0.00, 0.00, 0.00),
(126, 1, 132, 0.00, 0.00, 0.00, 0.00, 0.00),
(127, 1, 133, 0.00, 0.00, 0.00, 0.00, 0.00),
(128, 1, 134, 0.00, 0.00, 0.00, 0.00, 0.00),
(129, 1, 135, 0.00, 0.00, 0.00, 0.00, 0.00),
(130, 1, 136, 0.00, 0.00, 0.00, 0.00, 0.00),
(131, 1, 137, 0.00, 0.00, 0.00, 0.00, 0.00),
(132, 1, 138, 0.00, 0.00, 0.00, 0.00, 0.00),
(133, 1, 139, 0.00, 0.00, 0.00, 0.00, 0.00),
(134, 1, 140, 0.00, 0.00, 0.00, 0.00, 0.00),
(135, 1, 141, 0.00, 0.00, 0.00, 0.00, 0.00),
(136, 1, 142, 0.00, 0.00, 0.00, 0.00, 0.00),
(137, 1, 143, 0.00, 0.00, 0.00, 0.00, 0.00),
(138, 1, 144, 0.00, 0.00, 0.00, 0.00, 0.00),
(139, 1, 145, 0.00, 0.00, 0.00, 0.00, 0.00),
(140, 1, 146, 0.00, 0.00, 0.00, 0.00, 0.00),
(141, 1, 147, 0.00, 0.00, 0.00, 0.00, 0.00),
(142, 1, 148, 0.00, 0.00, 0.00, 0.00, 0.00),
(143, 1, 149, 0.00, 0.00, 0.00, 0.00, 0.00),
(144, 1, 150, 0.00, 0.00, 0.00, 0.00, 0.00),
(145, 1, 151, 0.00, 0.00, 0.00, 0.00, 0.00),
(146, 1, 152, 0.00, 0.00, 0.00, 0.00, 0.00),
(147, 1, 153, 0.00, 0.00, 0.00, 0.00, 0.00),
(148, 1, 154, 0.00, 0.00, 0.00, 0.00, 0.00),
(149, 1, 155, 0.00, 0.00, 0.00, 0.00, 0.00),
(150, 1, 156, 0.00, 0.00, 0.00, 0.00, 0.00),
(151, 1, 157, 0.00, 0.00, 0.00, 0.00, 0.00),
(152, 1, 158, 0.00, 0.00, 0.00, 0.00, 0.00),
(153, 1, 159, 0.00, 0.00, 0.00, 0.00, 0.00),
(154, 1, 160, 0.00, 0.00, 0.00, 0.00, 0.00),
(155, 1, 161, 0.00, 0.00, 0.00, 0.00, 0.00),
(156, 1, 162, 0.00, 0.00, 0.00, 0.00, 0.00),
(157, 1, 163, 0.00, 0.00, 0.00, 0.00, 0.00),
(158, 1, 164, 0.00, 0.00, 0.00, 0.00, 0.00),
(159, 1, 165, 0.00, 0.00, 0.00, 0.00, 0.00),
(160, 1, 166, 0.00, 0.00, 0.00, 0.00, 0.00),
(161, 1, 167, 0.00, 0.00, 0.00, 0.00, 0.00),
(162, 1, 168, 0.00, 0.00, 0.00, 0.00, 0.00),
(163, 1, 169, 0.00, 0.00, 0.00, 0.00, 0.00),
(164, 1, 170, 0.00, 0.00, 0.00, 0.00, 0.00),
(165, 1, 171, 0.00, 0.00, 0.00, 0.00, 0.00),
(166, 1, 172, 0.00, 0.00, 0.00, 0.00, 0.00),
(167, 1, 173, 0.00, 0.00, 0.00, 0.00, 0.00),
(168, 2, 1, 32000.00, 0.00, 0.00, 0.00, NULL),
(169, 2, 2, 0.00, 0.00, 0.00, 0.00, NULL),
(170, 2, 3, 0.00, 0.00, 0.00, 0.00, NULL),
(171, 2, 4, 0.00, 0.00, 0.00, 0.00, NULL),
(172, 2, 7, 0.00, 0.00, 0.00, 0.00, NULL),
(173, 2, 8, 0.00, 0.00, 0.00, 0.00, NULL),
(174, 2, 9, 0.00, 0.00, 0.00, 0.00, NULL),
(175, 2, 10, 0.00, 0.00, 0.00, 0.00, NULL),
(176, 2, 11, 0.00, 0.00, 0.00, 0.00, NULL),
(177, 2, 12, 0.00, 0.00, 0.00, 0.00, NULL),
(178, 2, 13, 7200.00, 0.00, 0.00, 0.00, NULL),
(179, 2, 14, 0.00, 0.00, 0.00, 0.00, NULL),
(180, 2, 15, 0.00, 0.00, 0.00, 0.00, NULL),
(181, 2, 16, 0.00, 0.00, 0.00, 0.00, NULL),
(182, 2, 17, 0.00, 0.00, 0.00, 0.00, NULL),
(183, 2, 18, 0.00, 0.00, 0.00, 0.00, NULL),
(184, 2, 19, 0.00, 0.00, 0.00, 0.00, NULL),
(185, 2, 20, 0.00, 0.00, 0.00, 0.00, NULL),
(186, 2, 21, 0.00, 0.00, 0.00, 0.00, NULL),
(187, 2, 22, 0.00, 0.00, 0.00, 0.00, NULL),
(188, 2, 23, 0.00, 0.00, 0.00, 0.00, NULL),
(189, 2, 24, 0.00, 0.00, 0.00, 0.00, NULL),
(190, 2, 25, 0.00, 0.00, 0.00, 0.00, NULL),
(191, 2, 26, 0.00, 0.00, 0.00, 0.00, NULL),
(192, 2, 27, 0.00, 0.00, 0.00, 0.00, NULL),
(193, 2, 28, 0.00, 0.00, 0.00, 0.00, NULL),
(194, 2, 29, 0.00, 0.00, 0.00, 0.00, NULL),
(195, 2, 30, 0.00, 0.00, 0.00, 0.00, NULL),
(196, 2, 31, 0.00, 0.00, 0.00, 0.00, NULL),
(197, 2, 32, 0.00, 0.00, 0.00, 0.00, NULL),
(198, 2, 33, 0.00, 0.00, 0.00, 0.00, NULL),
(199, 2, 34, 0.00, 0.00, 0.00, 0.00, NULL),
(200, 2, 35, 0.00, 0.00, 0.00, 0.00, NULL),
(201, 2, 36, 0.00, 0.00, 0.00, 0.00, NULL),
(202, 2, 37, 0.00, 0.00, 0.00, 0.00, NULL),
(203, 2, 38, 0.00, 0.00, 0.00, 0.00, NULL),
(204, 2, 39, 0.00, 0.00, 0.00, 0.00, NULL),
(205, 2, 40, 0.00, 0.00, 0.00, 0.00, NULL),
(206, 2, 41, 0.00, 0.00, 0.00, 0.00, NULL),
(207, 2, 42, 0.00, 0.00, 0.00, 0.00, NULL),
(208, 2, 43, 0.00, 0.00, 0.00, 0.00, NULL),
(209, 2, 44, 0.00, 0.00, 0.00, 0.00, NULL),
(210, 2, 45, 0.00, 0.00, 0.00, 0.00, NULL),
(211, 2, 46, 0.00, 0.00, 0.00, 0.00, NULL),
(212, 2, 47, 0.00, 0.00, 0.00, 0.00, NULL),
(213, 2, 48, 0.00, 0.00, 0.00, 0.00, NULL),
(214, 2, 49, 0.00, 0.00, 0.00, 0.00, NULL),
(215, 2, 50, 0.00, 0.00, 0.00, 0.00, NULL),
(216, 2, 51, 0.00, 0.00, 0.00, 0.00, NULL),
(217, 2, 52, 0.00, 0.00, 0.00, 0.00, NULL),
(218, 2, 53, 0.00, 0.00, 0.00, 0.00, NULL),
(219, 2, 54, 0.00, 0.00, 0.00, 0.00, NULL),
(220, 2, 55, 0.00, 0.00, 0.00, 0.00, NULL),
(221, 2, 56, 0.00, 0.00, 0.00, 0.00, NULL),
(222, 2, 57, 0.00, 0.00, 0.00, 0.00, NULL),
(223, 2, 59, 0.00, 0.00, 0.00, 0.00, NULL),
(224, 2, 60, 0.00, 0.00, 0.00, 0.00, NULL),
(225, 2, 61, 0.00, 0.00, 0.00, 0.00, NULL),
(226, 2, 62, 0.00, 0.00, 0.00, 0.00, NULL),
(227, 2, 63, 0.00, 0.00, 0.00, 0.00, NULL),
(228, 2, 64, 0.00, 0.00, 0.00, 0.00, NULL),
(229, 2, 65, 0.00, 0.00, 0.00, 0.00, NULL),
(230, 2, 66, 0.00, 0.00, 0.00, 0.00, NULL),
(231, 2, 67, 0.00, 0.00, 0.00, 0.00, NULL),
(232, 2, 69, 0.00, 0.00, 0.00, 0.00, NULL),
(233, 2, 70, 0.00, 0.00, 0.00, 0.00, NULL),
(234, 2, 71, 0.00, 0.00, 0.00, 0.00, NULL),
(235, 2, 72, 0.00, 0.00, 0.00, 0.00, NULL),
(236, 2, 73, 0.00, 0.00, 0.00, 0.00, NULL),
(237, 2, 74, 0.00, 0.00, 0.00, 0.00, NULL),
(238, 2, 75, 0.00, 0.00, 0.00, 0.00, NULL),
(239, 2, 76, 0.00, 0.00, 0.00, 0.00, NULL),
(240, 2, 77, 0.00, 0.00, 0.00, 0.00, NULL),
(241, 2, 78, 0.00, 0.00, 0.00, 0.00, NULL),
(242, 2, 79, 0.00, 0.00, 0.00, 0.00, NULL),
(243, 2, 80, 0.00, 0.00, 0.00, 0.00, NULL),
(244, 2, 81, 0.00, 0.00, 0.00, 0.00, NULL),
(245, 2, 82, 0.00, 0.00, 0.00, 0.00, NULL),
(246, 2, 83, 0.00, 0.00, 0.00, 0.00, NULL),
(247, 2, 85, 0.00, 0.00, 0.00, 0.00, NULL),
(248, 2, 86, 0.00, 0.00, 0.00, 0.00, NULL),
(249, 2, 87, 0.00, 0.00, 0.00, 0.00, NULL),
(250, 2, 88, 0.00, 0.00, 0.00, 0.00, NULL),
(251, 2, 89, 0.00, 0.00, 0.00, 0.00, NULL),
(252, 2, 90, 0.00, 0.00, 0.00, 0.00, NULL),
(253, 2, 91, 0.00, 0.00, 0.00, 0.00, NULL),
(254, 2, 92, 0.00, 0.00, 0.00, 0.00, NULL),
(255, 2, 93, 0.00, 0.00, 0.00, 0.00, NULL),
(256, 2, 94, 0.00, 0.00, 0.00, 0.00, NULL),
(257, 2, 95, 0.00, 0.00, 0.00, 0.00, NULL),
(258, 2, 96, 0.00, 0.00, 0.00, 0.00, NULL),
(259, 2, 97, 0.00, 0.00, 0.00, 0.00, NULL),
(260, 2, 98, 0.00, 0.00, 0.00, 0.00, NULL),
(261, 2, 99, 0.00, 0.00, 0.00, 0.00, NULL),
(262, 2, 101, 0.00, 0.00, 0.00, 0.00, NULL),
(263, 2, 102, 0.00, 0.00, 0.00, 0.00, NULL),
(264, 2, 103, 0.00, 0.00, 0.00, 0.00, NULL),
(265, 2, 104, 0.00, 0.00, 0.00, 0.00, NULL),
(266, 2, 105, 0.00, 0.00, 0.00, 0.00, NULL),
(267, 2, 106, 0.00, 0.00, 0.00, 0.00, NULL),
(268, 2, 107, 0.00, 0.00, 0.00, 0.00, NULL),
(269, 2, 108, 0.00, 0.00, 0.00, 0.00, NULL),
(270, 2, 109, 0.00, 0.00, 0.00, 0.00, NULL),
(271, 2, 110, 0.00, 0.00, 0.00, 0.00, NULL),
(272, 2, 111, 0.00, 0.00, 0.00, 0.00, NULL),
(273, 2, 112, 0.00, 0.00, 0.00, 0.00, NULL),
(274, 2, 113, 0.00, 0.00, 0.00, 0.00, NULL),
(275, 2, 114, 0.00, 0.00, 0.00, 0.00, NULL),
(276, 2, 115, 0.00, 0.00, 0.00, 0.00, NULL),
(277, 2, 116, 0.00, 0.00, 0.00, 0.00, NULL),
(278, 2, 117, 0.00, 0.00, 0.00, 0.00, NULL),
(279, 2, 118, 0.00, 0.00, 0.00, 0.00, NULL),
(280, 2, 119, 0.00, 0.00, 0.00, 0.00, NULL),
(281, 2, 120, 0.00, 0.00, 0.00, 0.00, NULL),
(282, 2, 121, 0.00, 0.00, 0.00, 0.00, NULL),
(283, 2, 122, 0.00, 0.00, 0.00, 0.00, NULL),
(284, 2, 123, 0.00, 0.00, 0.00, 0.00, NULL),
(285, 2, 124, 0.00, 0.00, 0.00, 0.00, NULL),
(286, 2, 125, 0.00, 0.00, 0.00, 0.00, NULL),
(287, 2, 126, 0.00, 0.00, 0.00, 0.00, NULL),
(288, 2, 127, 0.00, 0.00, 0.00, 0.00, NULL),
(289, 2, 128, 0.00, 0.00, 0.00, 0.00, NULL),
(290, 2, 129, 0.00, 0.00, 0.00, 0.00, NULL),
(291, 2, 130, 0.00, 0.00, 0.00, 0.00, NULL),
(292, 2, 131, 0.00, 0.00, 0.00, 0.00, NULL),
(293, 2, 132, 0.00, 0.00, 0.00, 0.00, NULL),
(294, 2, 133, 0.00, 0.00, 0.00, 0.00, NULL),
(295, 2, 134, 0.00, 0.00, 0.00, 0.00, NULL),
(296, 2, 135, 0.00, 0.00, 0.00, 0.00, NULL),
(297, 2, 136, 0.00, 0.00, 0.00, 0.00, NULL),
(298, 2, 137, 0.00, 0.00, 0.00, 0.00, NULL),
(299, 2, 138, 0.00, 0.00, 0.00, 0.00, NULL),
(300, 2, 139, 0.00, 0.00, 0.00, 0.00, NULL),
(301, 2, 140, 0.00, 0.00, 0.00, 0.00, NULL),
(302, 2, 141, 0.00, 0.00, 0.00, 0.00, NULL),
(303, 2, 142, 0.00, 0.00, 0.00, 0.00, NULL),
(304, 2, 143, 0.00, 0.00, 0.00, 0.00, NULL),
(305, 2, 144, 0.00, 0.00, 0.00, 0.00, NULL),
(306, 2, 145, 0.00, 0.00, 0.00, 0.00, NULL),
(307, 2, 146, 0.00, 0.00, 0.00, 0.00, NULL),
(308, 2, 147, 0.00, 0.00, 0.00, 0.00, NULL),
(309, 2, 148, 0.00, 0.00, 0.00, 0.00, NULL),
(310, 2, 149, 0.00, 0.00, 0.00, 0.00, NULL),
(311, 2, 150, 0.00, 0.00, 0.00, 0.00, NULL),
(312, 2, 151, 0.00, 0.00, 0.00, 0.00, NULL),
(313, 2, 152, 0.00, 0.00, 0.00, 0.00, NULL),
(314, 2, 153, 0.00, 0.00, 0.00, 0.00, NULL),
(315, 2, 154, 0.00, 0.00, 0.00, 0.00, NULL),
(316, 2, 155, 0.00, 0.00, 0.00, 0.00, NULL),
(317, 2, 156, 0.00, 0.00, 0.00, 0.00, NULL),
(318, 2, 157, 0.00, 0.00, 0.00, 0.00, NULL),
(319, 2, 158, 0.00, 0.00, 0.00, 0.00, NULL),
(320, 2, 159, 0.00, 0.00, 0.00, 0.00, NULL),
(321, 2, 160, 0.00, 0.00, 0.00, 0.00, NULL),
(322, 2, 161, 0.00, 0.00, 0.00, 0.00, NULL),
(323, 2, 162, 0.00, 0.00, 0.00, 0.00, NULL),
(324, 2, 163, 0.00, 0.00, 0.00, 0.00, NULL),
(325, 2, 164, 0.00, 0.00, 0.00, 0.00, NULL),
(326, 2, 165, 0.00, 0.00, 0.00, 0.00, NULL),
(327, 2, 166, 0.00, 0.00, 0.00, 0.00, NULL),
(328, 2, 167, 0.00, 0.00, 0.00, 0.00, NULL),
(329, 2, 168, 0.00, 0.00, 0.00, 0.00, NULL),
(330, 2, 169, 0.00, 0.00, 0.00, 0.00, NULL),
(331, 2, 170, 0.00, 0.00, 0.00, 0.00, NULL),
(332, 2, 171, 0.00, 0.00, 0.00, 0.00, NULL),
(333, 2, 172, 0.00, 0.00, 0.00, 0.00, NULL),
(334, 2, 173, 0.00, 0.00, 0.00, 0.00, NULL);

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
  `corte_id` int(11) DEFAULT NULL,
  `qr_token` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `despachos_detalle`
--

CREATE TABLE `despachos_detalle` (
  `id` int(11) NOT NULL,
  `despacho_id` int(11) DEFAULT NULL,
  `corte_id` int(11) DEFAULT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `unidad` varchar(20) DEFAULT NULL,
  `precio_unitario` decimal(10,2) DEFAULT NULL,
  `subtotal` decimal(10,2) GENERATED ALWAYS AS (`cantidad` * `precio_unitario`) STORED
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

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
  `corte_id` int(11) DEFAULT NULL,
  `descripcion` text DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `unidad` varchar(20) DEFAULT NULL,
  `costo_total` decimal(10,2) DEFAULT NULL,
  `valor_unitario` decimal(10,4) GENERATED ALWAYS AS (`costo_total` / nullif(`cantidad`,0)) STORED,
  `referencia_doc` varchar(100) DEFAULT NULL,
  `folio_fiscal` varchar(100) DEFAULT NULL,
  `qr` varchar(255) NOT NULL,
  `cantidad_actual` decimal(10,2) NOT NULL,
  `credito` tinyint(1) DEFAULT NULL,
  `pagado` tinyint(1) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `entradas_insumos`
--

INSERT INTO `entradas_insumos` (`id`, `insumo_id`, `proveedor_id`, `usuario_id`, `fecha`, `corte_id`, `descripcion`, `cantidad`, `unidad`, `costo_total`, `referencia_doc`, `folio_fiscal`, `qr`, `cantidad_actual`, `credito`, `pagado`) VALUES
(1, 1, 10, 1, '2025-10-04 23:01:01', 1, '', 11000.00, 'gramos', 300.00, '', '', 'archivos/qr/entrada_insumo_1.png', 0.00, 0, NULL),
(2, 13, NULL, 2, '2025-10-04 23:10:59', 1, 'Procesado desde insumo 1 lote 3', 1600.00, 'gramos', 0.00, '', '', 'archivos/qr/entrada_insumo_2.png', 1600.00, NULL, NULL),
(3, 13, NULL, 2, '2025-10-04 23:23:06', 1, 'Procesado desde insumo 1 lote 4', 800.00, 'gramos', 0.00, '', '', 'archivos/qr/entrada_insumo_3.png', 800.00, NULL, NULL),
(4, 13, NULL, 2, '2025-10-04 23:33:53', 1, 'Procesado desde insumo 1 lote 5', 1600.00, 'gramos', 0.00, '', '', 'archivos/qr/entrada_insumo_4.png', 1600.00, NULL, NULL),
(5, 13, NULL, 5, '2025-10-05 00:10:26', 1, 'Procesado desde insumo 1 lote 6', 2400.00, 'gramos', 0.00, '', '', 'archivos/qr/entrada_insumo_5.png', 2400.00, NULL, NULL),
(6, 1, 10, 1, '2025-10-05 00:51:53', 2, '', 8000.00, 'gramos', 400.00, '', '', 'archivos/qr/entrada_insumo_6.png', 7000.00, 1, NULL),
(7, 13, 1, 5, '2025-10-05 00:56:59', 2, 'Procesado desde insumo 1 lote 8', 3400.00, 'gramos', 0.00, '', '', 'archivos/qr/entrada_insumo_7.png', 3400.00, NULL, NULL);

--
-- Disparadores `entradas_insumos`
--
DELIMITER $$
CREATE TRIGGER `trg_fifo_no_break` BEFORE UPDATE ON `entradas_insumos` FOR EACH ROW BEGIN
  -- @mov_tipo y @bypass_fifo son variables de sesión opcionales que setea la app
  -- @mov_tipo: 'salida' | 'traspaso' | 'merma' | NULL
  -- @bypass_fifo: 1 para ignorar FIFO de forma explícita (opcional)

  IF NEW.cantidad_actual < OLD.cantidad_actual THEN
    IF COALESCE(@bypass_fifo, 0) = 0
       AND LOWER(COALESCE(@mov_tipo, '')) <> 'merma' THEN

      IF EXISTS (
        SELECT 1
        FROM entradas_insumos ei
        WHERE ei.insumo_id = NEW.insumo_id
          AND ei.cantidad_actual > 0
          AND (ei.fecha < NEW.fecha OR (ei.fecha = NEW.fecha AND ei.id < NEW.id))
      ) THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = 'FIFO: existen lotes más viejos con stock';
      END IF;

    END IF;
  END IF;
END
$$
DELIMITER ;

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
(1, 'Arroz', 'gramos', 36000.00, 'por_receta', 'ins_68717301313ad.jpg', 0.00),
(2, 'Alga', 'piezas', 0.00, 'por_receta', 'ins_6871716a72681.jpg', 0.00),
(3, 'Salmón fresco', 'gramos', 0.00, 'por_receta', 'ins_6871777fa2c56.png', 0.00),
(4, 'Refresco en lata', 'piezas', 0.00, 'unidad_completa', 'ins_6871731d075cb.webp', 0.00),
(7, 'Surimi', 'gramos', 0.00, 'uso_general', 'ins_688a521dcd583.jpg', 0.00),
(8, 'Tocino', 'gramos', 0.00, 'uso_general', 'ins_688a4dc84c002.jpg', 0.00),
(9, 'Pollo', 'gramos', 0.00, 'desempaquetado', 'ins_688a4e4bd5999.jpg', 0.00),
(10, 'Camarón', 'gramos', 0.00, 'desempaquetado', 'ins_688a4f5c873c6.jpg', 0.00),
(11, 'Queso Chihuahua', 'gramos', 0.00, 'unidad_completa', 'ins_688a4feca9865.jpg', 0.00),
(12, 'Philadelphia', 'gramos', 0.00, 'uso_general', 'ins_688a504f9cb40.jpg', 0.00),
(13, 'Arroz blanco', 'gramos', 10600.00, 'por_receta', 'ins_689f82d674c65.jpg', 0.00),
(14, 'Carne', 'gramos', 0.00, 'uso_general', 'ins_688a528d1261a.jpg', 0.00),
(15, 'Queso Amarillo', 'piezas', 0.00, 'uso_general', 'ins_688a53246c1c2.jpg', 0.00),
(16, 'Ajonjolí', 'gramos', 0.00, 'uso_general', 'ins_689f824a23343.jpg', 0.00),
(17, 'Panko', 'gramos', 0.00, 'por_receta', 'ins_688a53da64b5f.jpg', 0.00),
(18, 'Salsa tampico', 'mililitros', 0.00, 'no_controlado', 'ins_688a54cf1872b.jpg', 0.00),
(19, 'Anguila', 'oz', 0.00, 'por_receta', 'ins_689f828638aa9.jpg', 0.00),
(20, 'BBQ', 'oz', 0.00, 'no_controlado', 'ins_688a557431fce.jpg', 0.00),
(21, 'Serrano', 'gramos', 0.00, 'uso_general', 'ins_688a55c66f09d.jpg', 0.00),
(22, 'Chile Morrón', 'gramos', 0.00, 'por_receta', 'ins_688a5616e8f25.jpg', 0.00),
(23, 'Kanikama', 'gramos', 0.00, 'por_receta', 'ins_688a5669e24a8.jpg', 0.00),
(24, 'Aguacate', 'gramos', 0.00, 'por_receta', 'ins_689f8254c2e71.jpg', 0.00),
(25, 'Dedos de queso', 'pieza', 0.00, 'unidad_completa', 'ins_688a56fda3221.jpg', 0.00),
(26, 'Mango', 'gramos', 0.00, 'por_receta', 'ins_688a573c762f4.jpg', 0.00),
(27, 'Tostadas', 'pieza', 0.00, 'uso_general', 'ins_688a57a499b35.jpg', 0.00),
(28, 'Papa', 'gramos', 0.00, 'por_receta', 'ins_688a580061ffd.jpg', 0.00),
(29, 'Cebolla Morada', 'gramos', 0.00, 'por_receta', 'ins_688a5858752a0.jpg', 0.00),
(30, 'Salsa de soya', 'mililitros', 0.00, 'no_controlado', 'ins_688a58cc6cb6c.jpg', 0.00),
(31, 'Naranja', 'gramos', 0.00, 'por_receta', 'ins_688a590bca275.jpg', 0.00),
(32, 'Chile Caribe', 'gramos', 0.00, 'por_receta', 'ins_688a59836c32e.jpg', 0.00),
(33, 'Pulpo', 'gramos', 0.00, 'por_receta', 'ins_688a59c9a1d0b.jpg', 0.00),
(34, 'Zanahoria', 'gramos', 0.00, 'por_receta', 'ins_688a5a0a3a959.jpg', 0.00),
(35, 'Apio', 'gramos', 0.00, 'por_receta', 'ins_688a5a52af990.jpg', 0.00),
(36, 'Pepino', 'gramos', 0.00, 'uso_general', 'ins_688a5aa0cbaf5.jpg', 0.00),
(37, 'Masago', 'gramos', 0.00, 'por_receta', 'ins_688a5b3f0dca6.jpg', 0.00),
(38, 'Nuez de la india', 'gramos', 0.00, 'por_receta', 'ins_688a5be531e11.jpg', 0.00),
(39, 'Cátsup', 'mililitros', 0.00, 'por_receta', 'ins_688a5c657eb83.jpg', 0.00),
(40, 'Atún fresco', 'gramos', 0.00, 'por_receta', 'ins_688a5ce18adc5.jpg', 0.00),
(41, 'Callo almeja', 'gramos', 0.00, 'por_receta', 'ins_688a5d28de8a5.jpg', 0.00),
(42, 'Calabacin', 'gramos', 0.00, 'por_receta', 'ins_688a5d6b2bca1.jpg', 0.00),
(43, 'Fideo chino transparente', 'gramos', 0.00, 'por_receta', 'ins_688a5dd3b406d.jpg', 0.00),
(44, 'Brócoli', 'gramos', 0.00, 'por_receta', 'ins_688a5e2736870.jpg', 0.00),
(45, 'Chile de árbol', 'gramos', 0.00, 'por_receta', 'ins_688a5e6f08ccd.jpg', 0.00),
(46, 'Pasta udon', 'gramos', 0.00, 'por_receta', 'ins_688a5eb627f38.jpg', 0.00),
(47, 'Huevo', 'pieza', 0.00, 'por_receta', 'ins_688a5ef9b575e.jpg', 0.00),
(48, 'Cerdo', 'gramos', 0.00, 'por_receta', 'ins_688a5f3915f5e.jpg', 0.00),
(49, 'Masa para gyozas', 'pieza', 0.00, 'por_receta', 'ins_688a5fae2e7f1.jpg', 0.00),
(50, 'Naruto', 'gramos', 0.00, 'por_receta', 'ins_688a5ff57f62d.jpg', 0.00),
(51, 'Atún ahumado', 'gramos', 0.00, 'por_receta', 'ins_68adcd62c5a19.jpg', 0.00),
(52, 'Cacahuate con salsa (salado)', 'gramos', 0.00, 'por_receta', 'ins_68adcf253bd1d.jpg', 0.00),
(53, 'Calabaza', 'gramos', 0.00, 'por_receta', 'ins_68add0ff781fb.jpg', 0.00),
(54, 'Camarón gigante para pelar', 'pieza', 0.00, 'por_receta', 'ins_68add3264c465.jpg', 0.00),
(55, 'Cebolla', 'gramos', 0.00, 'por_receta', 'ins_68add38beff59.jpg', 0.00),
(56, 'Chile en polvo', 'gramos', 0.00, 'por_receta', 'ins_68add4a750a0e.jpg', 0.00),
(57, 'Coliflor', 'gramos', 0.00, 'por_receta', 'ins_68add5291130e.jpg', 0.00),
(59, 'Dedos de surimi', 'pieza', 0.00, 'unidad_completa', 'ins_68add5c575fbb.jpg', 0.00),
(60, 'Fideos', 'gramos', 0.00, 'por_receta', 'ins_68add629d094b.jpg', 0.00),
(61, 'Fondo de res', 'mililitros', 0.00, 'no_controlado', 'ins_68add68d317d5.jpg', 0.00),
(62, 'Gravy Naranja', 'oz', 0.00, 'no_controlado', 'ins_68add7bb461b3.jpg', 0.00),
(63, 'Salsa Aguachil', 'oz', 0.00, 'no_controlado', 'ins_68ae000034b31.jpg', 0.00),
(64, 'Julianas de zanahoria', 'gramos', 0.00, 'por_receta', 'ins_68add82c9c245.jpg', 0.00),
(65, 'Limón', 'gramos', 0.00, 'por_receta', 'ins_68add890ee640.jpg', 0.00),
(66, 'Queso Mix', 'gramos', 0.00, 'uso_general', 'ins_68ade1625f489.jpg', 0.00),
(67, 'Morrón', 'gramos', 0.00, 'por_receta', 'ins_68addcbc6d15a.jpg', 0.00),
(69, 'Pasta chukasoba', 'gramos', 0.00, 'por_receta', 'ins_68addd277fde6.jpg', 0.00),
(70, 'Pasta frita', 'gramos', 0.00, 'por_receta', 'ins_68addd91a005e.jpg', 0.00),
(71, 'Queso crema', 'gramos', 0.00, 'uso_general', 'ins_68ade11cdadcb.jpg', 0.00),
(72, 'Refresco embotellado', 'pieza', 0.00, 'unidad_completa', 'ins_68adfdd53f04e.jpg', 0.00),
(73, 'res', 'gramos', 0.00, 'uso_general', 'ins_68adfe2e49580.jpg', 0.00),
(74, 'Rodajas de naranja', 'gramos', 0.00, 'por_receta', 'ins_68adfeccd68d8.jpg', 0.00),
(75, 'Salmón', 'gramos', 0.00, 'por_receta', 'ins_68adffa2a2db0.jpg', 0.00),
(76, 'Salsa de anguila', 'mililitros', 0.00, 'no_controlado', 'ins_68ae005f1b3cd.jpg', 0.00),
(77, 'Salsa teriyaki (dulce)', 'mililitros', 0.00, 'no_controlado', 'ins_68ae00c53121a.jpg', 0.00),
(78, 'Salsas orientales', 'mililitros', 0.00, 'no_controlado', 'ins_68ae01341e7b1.jpg', 0.00),
(79, 'Shisimi', 'gramos', 0.00, 'uso_general', 'ins_68ae018d22a63.jpg', 0.00),
(80, 'Siracha', 'mililitros', 0.00, 'no_controlado', 'ins_68ae03413da26.jpg', 0.00),
(81, 'Tampico', 'mililitros', 0.00, 'uso_general', 'ins_68ae03f65bd71.jpg', 0.00),
(82, 'Tortilla de harina', 'pieza', 0.00, 'unidad_completa', 'ins_68ae04b46d24a.jpg', 0.00),
(83, 'Tostada', 'pieza', 0.00, 'unidad_completa', 'ins_68ae05924a02a.jpg', 0.00),
(85, 'Yakimeshi mini', 'gramos', 0.00, 'por_receta', 'ins_68ae061b1175b.jpg', 0.00),
(86, 'Sal con Ajo', 'pieza', 0.00, 'por_receta', 'ins_68adff6dbf111.jpg', 0.00),
(87, 'Aderezo Chipotle', 'mililitros', 0.00, 'por_receta', 'ins_68adcabeb1ee9.jpg', 0.00),
(88, 'Mezcla de Horneado', 'gramos', 0.00, 'por_receta', 'ins_68addaa3e53f7.jpg', 0.00),
(89, 'Aderezo', 'gramos', 0.00, 'uso_general', 'ins_68adcc0771a3c.jpg', 0.00),
(90, 'Camarón Empanizado', 'gramos', 0.00, 'por_receta', 'ins_68add1de1aa0e.jpg', 0.00),
(91, 'Pollo Empanizado', 'gramos', 0.00, 'por_receta', 'ins_68adde81c6be3.jpg', 0.00),
(92, 'Cebollín', 'gramos', 0.00, 'por_receta', 'ins_68add3e38d04b.jpg', 0.00),
(93, 'Aderezo Cebolla Dul.', 'oz', 0.00, 'uso_general', 'ins_68adcb8fa562e.jpg', 0.00),
(94, 'Camaron Enchiloso', 'gramos', 0.00, 'por_receta', 'ins_68add2db69e2e.jpg', 0.00),
(95, 'Pastel chocoflan', 'pieza', 0.00, 'unidad_completa', 'ins_68adddfa22fe2.jpg', 0.00),
(96, 'Pay de queso', 'pieza', 0.00, 'unidad_completa', 'ins_68adde4fa8275.jpg', 0.00),
(97, 'Helado tempura', 'pieza', 0.00, 'unidad_completa', 'ins_68add7e53c6fe.jpg', 0.00),
(98, 'Postre especial', 'pieza', 0.00, 'unidad_completa', 'ins_68addee98fdf0.jpg', 0.00),
(99, 'Búfalo', 'mililitros', 0.00, 'no_controlado', 'ins_68adce63dd347.jpg', 0.00),
(101, 'Corona 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68add55a1e3b7.jpg', 0.00),
(102, 'Golden Light 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68add76481f22.jpg', 0.00),
(103, 'Negra Modelo', 'pieza', 0.00, 'unidad_completa', 'ins_68addc59c2ea9.jpg', 0.00),
(104, 'Modelo Especial', 'pieza', 0.00, 'unidad_completa', 'ins_68addb9d59000.jpg', 0.00),
(105, 'Bud Light', 'pieza', 0.00, 'unidad_completa', 'ins_68adcdf3295e8.jpg', 0.00),
(106, 'Stella Artois', 'pieza', 0.00, 'unidad_completa', 'ins_68ae0397afb2f.jpg', 0.00),
(107, 'Ultra 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68ae05466a8e2.jpg', 0.00),
(108, 'Michelob 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68addb2d00c85.jpg', 0.00),
(109, 'Alitas de pollo', 'gramos', 0.00, 'unidad_completa', 'ins_68adccf5a1147.jpg', 0.00),
(110, 'Ranch', 'mililitros', 0.00, 'no_controlado', 'ins_68adfcddef7e3.jpg', 0.00),
(111, 'Buffalo', 'gramos', 0.00, 'no_controlado', '', 0.00),
(112, 'Chichimi', 'gramos', 0.00, 'no_controlado', 'ins_68add45bdb306.jpg', 0.00),
(113, 'Calpico', 'pieza', 0.00, 'unidad_completa', 'ins_68add19570673.jpg', 0.00),
(114, 'Vaina de soja', 'gramos', 0.00, 'uso_general', 'ins_68ae05de869d1.jpg', 0.00),
(115, 'Boneless', 'gramos', 0.00, 'por_receta', 'ins_68adcdbb6b5b4.jpg', 0.00),
(116, 'Agua members', 'pieza', 0.00, 'unidad_completa', 'ins_68adcc5feaee1.jpg', 0.00),
(117, 'Agua mineral', 'pieza', 0.00, 'unidad_completa', 'ins_68adcca85ae2c.jpg', 0.00),
(118, 'Cilantro', 'gramos', 0.00, 'por_receta', 'ins_68add4edab118.jpg', 0.00),
(119, 'Té de jazmin', 'mililitros', 0.00, 'por_receta', 'ins_68ae0474dfc36.jpg', 0.00),
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
  `referencia_id` int(11) DEFAULT NULL,
  `corte_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

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
  `fecha` datetime DEFAULT current_timestamp(),
  `corte_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `mermas_insumo`
--

INSERT INTO `mermas_insumo` (`id`, `insumo_id`, `cantidad`, `motivo`, `usuario_id`, `fecha`, `corte_id`) VALUES
(1, 1, 400.00, 'perdida coccion', 2, '2025-10-04 23:10:59', 1),
(2, 1, 200.00, 'cocer', 2, '2025-10-04 23:23:06', 1),
(3, 1, 400.00, '', 2, '2025-10-04 23:33:53', 1),
(4, 1, 600.00, 'coccion', 5, '2025-10-05 00:10:26', NULL),
(5, 1, 600.00, 'cocido', 5, '2025-10-05 00:56:59', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `movimientos_insumos`
--

CREATE TABLE `movimientos_insumos` (
  `id` int(11) NOT NULL,
  `tipo` enum('entrada','salida','ajuste','traspaso','merma','devolucion') DEFAULT 'entrada',
  `usuario_id` int(11) DEFAULT NULL,
  `usuario_destino_id` int(11) DEFAULT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `id_entrada` int(11) DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `observacion` text DEFAULT NULL,
  `fecha` datetime DEFAULT current_timestamp(),
  `corte_id` int(11) DEFAULT NULL,
  `qr_token` varchar(64) DEFAULT NULL,
  `id_qr` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `movimientos_insumos`
--

INSERT INTO `movimientos_insumos` (`id`, `tipo`, `usuario_id`, `usuario_destino_id`, `insumo_id`, `id_entrada`, `cantidad`, `observacion`, `fecha`, `corte_id`, `qr_token`, `id_qr`) VALUES
(1, '', 2, NULL, 1, NULL, -2000.00, 'Usado en proceso id 3 hacia insumo destino 13', '2025-10-04 23:10:59', 1, NULL, NULL),
(2, 'merma', 2, NULL, 1, NULL, -400.00, 'Merma del proceso id 3 - perdida coccion', '2025-10-04 23:10:59', 1, '68287d5c56b42ad967791af4432290c0', NULL),
(3, '', 2, NULL, 1, NULL, -1000.00, 'Usado en proceso id 4 hacia insumo destino 13', '2025-10-04 23:23:06', 1, NULL, NULL),
(4, 'merma', 2, NULL, 1, NULL, -200.00, 'Merma del proceso id 4 - cocer', '2025-10-04 23:23:06', 1, '425650372ceb3725375d6ed0fc17353f', NULL),
(5, '', 2, NULL, 1, NULL, -2000.00, 'Usado en proceso id 5 hacia insumo destino 13', '2025-10-04 23:33:53', 1, NULL, NULL),
(6, 'merma', 2, NULL, 1, NULL, -400.00, 'Merma del proceso id 5', '2025-10-04 23:33:53', 1, 'c75dfd50fa582bebec3b52de328ec87f', NULL),
(7, '', 5, NULL, 1, NULL, -3000.00, 'Usado en proceso id 6 hacia insumo destino 13', '2025-10-05 00:10:26', NULL, NULL, NULL),
(8, 'merma', 5, NULL, 1, NULL, -600.00, 'Merma del proceso id 6 - coccion', '2025-10-05 00:10:26', NULL, '296118afedd40daa906af9ac8f68c127', NULL),
(9, '', 5, NULL, 1, NULL, -4000.00, 'Usado en proceso id 8 hacia insumo destino 13', '2025-10-05 00:56:59', 2, NULL, NULL),
(10, 'merma', 5, NULL, 1, NULL, -600.00, 'Merma del proceso id 8 - cocido', '2025-10-05 00:56:59', 2, '163f7a4632b80ec38a280baa2c9525f5', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `procesos_insumos`
--

CREATE TABLE `procesos_insumos` (
  `id` int(11) NOT NULL,
  `insumo_origen_id` int(11) NOT NULL,
  `insumo_destino_id` int(11) NOT NULL,
  `cantidad_origen` decimal(10,2) NOT NULL,
  `unidad_origen` varchar(20) NOT NULL,
  `cantidad_resultante` decimal(10,2) DEFAULT NULL,
  `unidad_destino` varchar(20) DEFAULT NULL,
  `estado` enum('pendiente','en_preparacion','listo','entregado','cancelado') DEFAULT 'pendiente',
  `observaciones` text DEFAULT NULL,
  `creado_por` int(11) DEFAULT NULL,
  `preparado_por` int(11) DEFAULT NULL,
  `listo_por` int(11) DEFAULT NULL,
  `creado_en` datetime DEFAULT current_timestamp(),
  `actualizado_en` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `corte_id` int(11) DEFAULT NULL,
  `entrada_insumo_id` int(11) DEFAULT NULL,
  `mov_salida_id` int(11) DEFAULT NULL,
  `qr_path` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `procesos_insumos`
--

INSERT INTO `procesos_insumos` (`id`, `insumo_origen_id`, `insumo_destino_id`, `cantidad_origen`, `unidad_origen`, `cantidad_resultante`, `unidad_destino`, `estado`, `observaciones`, `creado_por`, `preparado_por`, `listo_por`, `creado_en`, `actualizado_en`, `corte_id`, `entrada_insumo_id`, `mov_salida_id`, `qr_path`) VALUES
(3, 1, 13, 2000.00, 'gramos', 1600.00, 'gramos', 'entregado', 'cocer', 2, 2, 2, '2025-10-04 23:03:29', '2025-10-05 00:09:49', 1, 2, 1, 'archivos/qr/entrada_insumo_2.png'),
(4, 1, 13, 1000.00, 'gramos', 800.00, 'gramos', 'entregado', 'cocer', 2, 2, 2, '2025-10-04 23:22:21', '2025-10-05 00:09:52', 1, 3, 3, 'archivos/qr/entrada_insumo_3.png'),
(5, 1, 13, 2000.00, 'gramos', 1600.00, 'gramos', 'entregado', 'cocer', 2, 2, 2, '2025-10-04 23:33:22', '2025-10-05 00:09:55', 1, 4, 5, 'archivos/qr/entrada_insumo_4.png'),
(6, 1, 13, 3000.00, 'gramos', 2400.00, 'gramos', 'entregado', 'cocer lento', 2, 5, 5, '2025-10-04 23:38:15', '2025-10-05 00:10:32', 1, 5, 7, 'archivos/qr/entrada_insumo_5.png'),
(7, 1, 13, 8000.00, 'gramos', NULL, 'gramos', 'listo', 'cocer3', 5, 5, 5, '2025-10-05 00:53:07', '2025-10-05 01:09:02', 2, NULL, NULL, NULL),
(8, 1, 13, 4000.00, 'gramos', 3400.00, 'gramos', 'entregado', 'null', 5, 5, 5, '2025-10-05 00:55:47', '2025-10-05 00:58:22', 2, 7, 9, 'archivos/qr/entrada_insumo_7.png'),
(9, 1, 13, 16000.00, 'gramos', NULL, 'gramos', 'listo', 'cocer', 5, 5, 5, '2025-10-05 01:14:47', '2025-10-05 01:14:50', 2, NULL, NULL, NULL);

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
  `rfc` varchar(13) DEFAULT NULL,
  `razon_social` varchar(150) DEFAULT NULL,
  `regimen_fiscal` varchar(5) DEFAULT NULL COMMENT 'Clave SAT (p.ej. 601, 603, etc.)',
  `correo_facturacion` varchar(150) DEFAULT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `telefono2` varchar(20) DEFAULT NULL,
  `correo` varchar(150) DEFAULT NULL,
  `direccion` text DEFAULT NULL,
  `contacto_nombre` varchar(100) DEFAULT NULL,
  `contacto_puesto` varchar(80) DEFAULT NULL,
  `dias_credito` int(11) DEFAULT 0,
  `limite_credito` decimal(12,2) DEFAULT 0.00,
  `banco` varchar(80) DEFAULT NULL,
  `clabe` char(18) DEFAULT NULL,
  `cuenta_bancaria` varchar(20) DEFAULT NULL,
  `sitio_web` varchar(150) DEFAULT NULL,
  `observacion` text DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT 1,
  `fecha_alta` datetime NOT NULL DEFAULT current_timestamp(),
  `actualizado_en` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ;

--
-- Volcado de datos para la tabla `proveedores`
--

INSERT INTO `proveedores` (`id`, `nombre`, `rfc`, `razon_social`, `regimen_fiscal`, `correo_facturacion`, `telefono`, `telefono2`, `correo`, `direccion`, `contacto_nombre`, `contacto_puesto`, `dias_credito`, `limite_credito`, `banco`, `clabe`, `cuenta_bancaria`, `sitio_web`, `observacion`, `activo`, `fecha_alta`, `actualizado_en`) VALUES
(1, 'CDIs', NULL, NULL, NULL, NULL, '555-123-4567', NULL, NULL, 'Calle Soya #123, CDMX', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-10-05 00:21:31'),
(2, 'Pescados del Pacífico', NULL, NULL, NULL, NULL, '618 453 5697', NULL, NULL, 'Calle Felipe Pescador 200-A, Zona Centro, 34000 Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(3, 'Abastos OXXO', NULL, NULL, NULL, NULL, '81-5555-0001', NULL, NULL, 'Parque Industrial, Monterrey, NL', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:37:33'),
(4, 'La patita', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(5, 'Sams', NULL, NULL, NULL, NULL, '800 999 7267', NULL, NULL, 'Blvd. Felipe Pescador 1401, Durango, Dgo., México', NULL, NULL, 0, 0.00, NULL, NULL, NULL, 'https://www.sams.com.mx', NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(6, 'inix', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(7, 'mercado libre', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, 'https://www.mercadolibre.com.mx', NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(8, 'Centauro', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(9, 'Fruteria los hermanos', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(10, 'Carmelita', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(11, 'Fruteria trebol', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(12, 'Gabriel', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(13, 'Limon nuevo', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(14, 'CPSmart', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(15, 'Quimicos San Ismael', NULL, NULL, NULL, NULL, '(618) 827 3132', NULL, NULL, 'Antonio Norman Fuentes 401 C, Centro, 34000 Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(16, 'Coca Cola', NULL, NULL, NULL, NULL, '+52 618 826 0330', NULL, NULL, 'Carr. Durango–Mezquital Km 3.0, Real del Mezquital, 34199 Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18'),
(17, 'Cerveceria Modelo', NULL, NULL, NULL, NULL, '(618) 814 1404', NULL, NULL, 'Carr. Durango–Torreón Km 8.5, San José I, 34208 Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, 'https://www.gmodelo.mx', NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:55:18');

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
  `pdf_recepcion` varchar(255) DEFAULT NULL,
  `corte_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

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
  `estado` enum('exitoso','error') DEFAULT 'exitoso',
  `corte_id` int(11) DEFAULT NULL
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
(21, 'proveedores', '/vistas/insumos/proveedores.php', 'link', NULL, 5),
(23, 'HistorialR', '/vistas/bodega/historial_qr.php', 'link', NULL, 7),
(24, 'Productos', '#', 'dropdown', 'Productos', 3),
(25, 'Recetas', '/vistas/recetas/recetas.php', 'dropdown-item', 'Productos', 3),
(26, 'Procesado', '/vistas/cocina/cocina2.php', 'link', NULL, 4),
(27, 'Mover', '/vistas/mover/mover.php', 'dropdown-item', 'Más', 14),
(29, 'Ticket', '/vistas/ventas/ticket.php', 'dropdown-item', 'Más', 2),
(31, 'Reporteria', '/vistas/reportes/vistas_db.php', 'dropdown-item', 'Más', 13),
(32, 'Usuarios', '/vistas/usuarios/usuarios.php', 'dropdown-item', 'Más', 6),
(33, 'Rutas', '/vistas/rutas/rutas.php', 'dropdown-item', 'Más', 7),
(34, 'Permisos', '/vistas/rutas/urutas.php', 'dropdown-item', 'Más', 8),
(35, 'Proveedores', '/vistas/insumos/proveedores.php', 'dropdown-item', 'Más', 10),
(36, 'Facturas', '/vistas/facturas/masiva.php', 'dropdown-item', 'Más', 12),
(37, 'Sedes', '/vistas/dashboard/sedes.php', 'dropdown-item', 'Más', 16),
(38, 'rastreo', '/vistas/insumos/entrada_insumo.php', 'link', NULL, 8),
(39, 'Pagos', '/vistas/insumos/entradas_pagos.php', 'link', NULL, 9);

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
  `rol` enum('supervisor','empleado','admin') NOT NULL,
  `activo` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `usuarios`
--

INSERT INTO `usuarios` (`id`, `nombre`, `usuario`, `contrasena`, `rol`, `activo`) VALUES
(1, 'Administrador', 'admin', 'admin', 'admin', 1),
(2, 'Osiris', 'Osiris', 'admin', 'supervisor', 1),
(3, 'Isa', 'Isa', 'admin', 'supervisor', 1),
(4, 'Michelle', 'Michelle', 'admin', 'supervisor', 1),
(5, 'Luisa chef', 'luisa', 'admin', 'empleado', 1);

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
(49, 1, 18),
(50, 1, 3),
(51, 1, 14),
(52, 1, 1),
(53, 1, 19),
(54, 1, 4),
(55, 1, 29),
(56, 1, 2),
(57, 1, 24),
(59, 1, 2),
(60, 1, 24),
(62, 1, 25),
(63, 1, 11),
(64, 1, 15),
(65, 1, 26),
(66, 1, 21),
(67, 1, 35),
(69, 1, 6),
(70, 1, 32),
(71, 1, 33),
(72, 1, 23),
(73, 1, 34),
(74, 1, 21),
(75, 1, 35),
(77, 1, 36),
(78, 1, 31),
(79, 1, 27),
(80, 1, 37),
(81, 1, 38),
(82, 1, 39),
(83, 2, 1),
(84, 2, 18),
(85, 2, 14),
(86, 2, 3),
(87, 2, 4),
(88, 2, 2),
(89, 2, 24),
(91, 2, 29),
(92, 2, 19),
(93, 2, 11),
(94, 2, 25),
(95, 2, 2),
(96, 2, 24),
(98, 2, 26),
(99, 2, 15),
(100, 2, 21),
(101, 2, 35),
(103, 2, 32),
(104, 2, 6),
(105, 2, 23),
(106, 2, 33),
(107, 2, 34),
(108, 2, 38),
(109, 2, 39),
(110, 2, 21),
(111, 2, 35),
(113, 2, 36),
(114, 2, 31),
(115, 2, 27),
(116, 2, 37),
(117, 3, 3),
(118, 4, 3),
(119, 5, 3),
(120, 5, 1),
(121, 5, 18),
(122, 5, 14),
(123, 5, 19),
(124, 5, 4),
(125, 5, 2),
(126, 5, 24),
(128, 5, 29),
(129, 5, 2),
(130, 5, 24),
(132, 5, 11),
(133, 5, 25),
(134, 5, 26),
(135, 5, 15),
(136, 5, 21),
(137, 5, 35),
(139, 5, 6),
(140, 5, 32),
(141, 5, 33),
(142, 5, 23),
(143, 5, 38),
(144, 5, 34),
(145, 5, 39),
(146, 5, 21),
(147, 5, 35),
(149, 5, 36),
(150, 5, 31),
(151, 5, 27),
(152, 5, 37);

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
-- Estructura Stand-in para la vista `v_procesos_insumos`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_procesos_insumos` (
`id` int(11)
,`estado` enum('pendiente','en_preparacion','listo','entregado','cancelado')
,`insumo_origen_id` int(11)
,`insumo_origen` varchar(100)
,`cantidad_origen` decimal(10,2)
,`unidad_origen` varchar(20)
,`insumo_destino_id` int(11)
,`insumo_destino` varchar(100)
,`cantidad_resultante` decimal(10,2)
,`unidad_destino` varchar(20)
,`creado_en` datetime
,`qr_path` varchar(255)
,`entrada_insumo_id` int(11)
,`mov_salida_id` int(11)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_bajo_stock`
--
DROP TABLE IF EXISTS `vw_bajo_stock`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_bajo_stock`  AS SELECT `insumos`.`id` AS `id`, `insumos`.`nombre` AS `nombre`, `insumos`.`unidad` AS `unidad`, `insumos`.`existencia` AS `existencia`, `insumos`.`tipo_control` AS `tipo_control`, `insumos`.`imagen` AS `imagen`, `insumos`.`minimo_stock` AS `minimo_stock` FROM `insumos` WHERE `insumos`.`existencia` <= `insumos`.`minimo_stock` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_procesos_insumos`
--
DROP TABLE IF EXISTS `v_procesos_insumos`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_procesos_insumos`  AS SELECT `p`.`id` AS `id`, `p`.`estado` AS `estado`, `io`.`id` AS `insumo_origen_id`, `io`.`nombre` AS `insumo_origen`, `p`.`cantidad_origen` AS `cantidad_origen`, `p`.`unidad_origen` AS `unidad_origen`, `ides`.`id` AS `insumo_destino_id`, `ides`.`nombre` AS `insumo_destino`, `p`.`cantidad_resultante` AS `cantidad_resultante`, `p`.`unidad_destino` AS `unidad_destino`, `p`.`creado_en` AS `creado_en`, `p`.`qr_path` AS `qr_path`, `p`.`entrada_insumo_id` AS `entrada_insumo_id`, `p`.`mov_salida_id` AS `mov_salida_id` FROM ((`procesos_insumos` `p` join `insumos` `io` on(`io`.`id` = `p`.`insumo_origen_id`)) join `insumos` `ides` on(`ides`.`id` = `p`.`insumo_destino_id`)) ;

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
  ADD KEY `usuario_id` (`usuario_id`),
  ADD KEY `ix_desp_corte` (`corte_id`);

--
-- Indices de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  ADD PRIMARY KEY (`id`),
  ADD KEY `despacho_id` (`despacho_id`),
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `ix_dd_corte` (`corte_id`);

--
-- Indices de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `proveedor_id` (`proveedor_id`),
  ADD KEY `usuario_id` (`usuario_id`),
  ADD KEY `idx_ei_insumo_fecha` (`insumo_id`,`fecha`),
  ADD KEY `ix_ei_corte` (`corte_id`);

--
-- Indices de la tabla `insumos`
--
ALTER TABLE `insumos`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ix_log_corte` (`corte_id`);

--
-- Indices de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  ADD PRIMARY KEY (`id`),
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `usuario_id` (`usuario_id`),
  ADD KEY `ix_merma_corte` (`corte_id`);

--
-- Indices de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `usuario_id` (`usuario_id`),
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `idx_mi_id_entrada` (`id_entrada`),
  ADD KEY `idx_mi_id_qr` (`id_qr`),
  ADD KEY `ix_mi_corte` (`corte_id`);

--
-- Indices de la tabla `procesos_insumos`
--
ALTER TABLE `procesos_insumos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_proc_estado` (`estado`),
  ADD KEY `idx_proc_origen` (`insumo_origen_id`),
  ADD KEY `idx_proc_destino` (`insumo_destino_id`),
  ADD KEY `ix_proc_corte` (`corte_id`);

--
-- Indices de la tabla `productos`
--
ALTER TABLE `productos`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `proveedores`
--
ALTER TABLE `proveedores`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ux_proveedores_rfc` (`rfc`),
  ADD KEY `ix_proveedores_nombre` (`nombre`),
  ADD KEY `ix_proveedores_correo` (`correo`),
  ADD KEY `ix_proveedores_activo` (`activo`);

--
-- Indices de la tabla `qrs_insumo`
--
ALTER TABLE `qrs_insumo`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ix_qr_corte` (`corte_id`);

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
  ADD KEY `usuario_id` (`usuario_id`),
  ADD KEY `ix_rece_corte` (`corte_id`);

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=335;

--
-- AUTO_INCREMENT de la tabla `despachos`
--
ALTER TABLE `despachos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT de la tabla `insumos`
--
ALTER TABLE `insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=174;

--
-- AUTO_INCREMENT de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `procesos_insumos`
--
ALTER TABLE `procesos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT de la tabla `productos`
--
ALTER TABLE `productos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `proveedores`
--
ALTER TABLE `proveedores`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `qrs_insumo`
--
ALTER TABLE `qrs_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=40;

--
-- AUTO_INCREMENT de la tabla `sucursales`
--
ALTER TABLE `sucursales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `usuario_ruta`
--
ALTER TABLE `usuario_ruta`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=153;

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
  ADD CONSTRAINT `despachos_ibfk_2` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`),
  ADD CONSTRAINT `fk_desp_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  ADD CONSTRAINT `despachos_detalle_ibfk_1` FOREIGN KEY (`despacho_id`) REFERENCES `despachos` (`id`),
  ADD CONSTRAINT `despachos_detalle_ibfk_2` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`),
  ADD CONSTRAINT `fk_dd_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  ADD CONSTRAINT `entradas_insumos_ibfk_1` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`),
  ADD CONSTRAINT `entradas_insumos_ibfk_2` FOREIGN KEY (`proveedor_id`) REFERENCES `proveedores` (`id`),
  ADD CONSTRAINT `entradas_insumos_ibfk_3` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`),
  ADD CONSTRAINT `fk__insumo` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`),
  ADD CONSTRAINT `fk__proveedor` FOREIGN KEY (`proveedor_id`) REFERENCES `proveedores` (`id`),
  ADD CONSTRAINT `fk__usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`),
  ADD CONSTRAINT `fk_ei_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  ADD CONSTRAINT `fk_log_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Filtros para la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  ADD CONSTRAINT `fk_merma_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `mermas_insumo_ibfk_1` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`),
  ADD CONSTRAINT `mermas_insumo_ibfk_2` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);

--
-- Filtros para la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  ADD CONSTRAINT `fk_mi_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mi_id_entrada` FOREIGN KEY (`id_entrada`) REFERENCES `entradas_insumos` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mi_qr` FOREIGN KEY (`id_qr`) REFERENCES `qrs_insumo` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `movimientos_insumos_ibfk_1` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`),
  ADD CONSTRAINT `movimientos_insumos_ibfk_2` FOREIGN KEY (`insumo_id`) REFERENCES `insumos` (`id`);

--
-- Filtros para la tabla `procesos_insumos`
--
ALTER TABLE `procesos_insumos`
  ADD CONSTRAINT `fk_proc_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `qrs_insumo`
--
ALTER TABLE `qrs_insumo`
  ADD CONSTRAINT `fk_qr_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `recepciones_log`
--
ALTER TABLE `recepciones_log`
  ADD CONSTRAINT `fk_rece_corte` FOREIGN KEY (`corte_id`) REFERENCES `cortes_almacen` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `recepciones_log_ibfk_1` FOREIGN KEY (`sucursal_id`) REFERENCES `sucursales` (`id`),
  ADD CONSTRAINT `recepciones_log_ibfk_2` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
