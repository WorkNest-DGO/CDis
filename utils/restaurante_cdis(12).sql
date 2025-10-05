-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 26-09-2025 a las 22:29:10
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
(11, '2025-09-16 10:48:12', '2025-09-26 22:24:39', 1, 1, ''),
(12, '2025-09-26 14:25:23', NULL, 1, NULL, NULL);

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
(408, 11, 1, 25750.00, 0.00, -9000.00, 0.00, 0.00),
(409, 11, 2, 29988.50, 0.00, 0.00, 0.00, 0.00),
(410, 11, 3, 30000.00, 0.00, 0.00, 0.00, 0.00),
(411, 11, 4, 29999.00, 0.00, 0.00, 0.00, 0.00),
(412, 11, 7, 30000.00, 0.00, 0.00, 0.00, 0.00),
(413, 11, 8, 29650.00, 0.00, 0.00, 0.00, 0.00),
(414, 11, 9, 29970.00, 0.00, 0.00, 0.00, 0.00),
(415, 11, 10, 29910.00, 0.00, -2200.00, 0.00, 0.00),
(416, 11, 11, 30000.00, 0.00, 0.00, 0.00, 0.00),
(417, 11, 12, 29390.00, 0.00, 0.00, 0.00, 0.00),
(418, 11, 13, 30000.00, 0.00, 0.00, 0.00, 0.00),
(419, 11, 14, 29820.00, 0.00, 0.00, 0.00, 0.00),
(420, 11, 15, 29998.00, 0.00, 0.00, 0.00, 0.00),
(421, 11, 16, 29994.00, 0.00, 0.00, 0.00, 40000.00),
(422, 11, 17, 30000.00, 0.00, 0.00, 0.00, 0.00),
(423, 11, 18, 30000.00, 0.00, 0.00, 0.00, 0.00),
(424, 11, 19, 30000.00, 0.00, 0.00, 0.00, 0.00),
(425, 11, 20, 30000.00, 0.00, 0.00, 0.00, 0.00),
(426, 11, 21, 29975.00, 0.00, 0.00, 0.00, 0.00),
(427, 11, 22, 30000.00, 0.00, 0.00, 0.00, 0.00),
(428, 11, 23, 29990.00, 0.00, 0.00, 0.00, 0.00),
(429, 11, 24, 29400.00, 0.00, 0.00, 0.00, 0.00),
(430, 11, 25, 30000.00, 0.00, 0.00, 0.00, 0.00),
(431, 11, 26, 30000.00, 0.00, 0.00, 0.00, 0.00),
(432, 11, 27, 30000.00, 0.00, 0.00, 0.00, 0.00),
(433, 11, 28, 30000.00, 0.00, 0.00, 0.00, 0.00),
(434, 11, 29, 30000.00, 0.00, 0.00, 0.00, 0.00),
(435, 11, 30, 30000.00, 0.00, 0.00, 0.00, 0.00),
(436, 11, 31, 30000.00, 0.00, 0.00, 0.00, 0.00),
(437, 11, 32, 30000.00, 0.00, 0.00, 0.00, 0.00),
(438, 11, 33, 29870.00, 0.00, 0.00, 0.00, 0.00),
(439, 11, 34, 30000.00, 0.00, 0.00, 0.00, 0.00),
(440, 11, 35, 30000.00, 0.00, 0.00, 0.00, 0.00),
(441, 11, 36, 29260.00, 0.00, 0.00, 0.00, 0.00),
(442, 11, 37, 30000.00, 0.00, 0.00, 0.00, 0.00),
(443, 11, 38, 30000.00, 0.00, 0.00, 0.00, 0.00),
(444, 11, 39, 30000.00, 0.00, 0.00, 0.00, 0.00),
(445, 11, 40, 30000.00, 0.00, -2500.00, 0.00, 0.00),
(446, 11, 41, 30000.00, 0.00, 0.00, 0.00, 0.00),
(447, 11, 42, 30000.00, 0.00, 0.00, 0.00, 0.00),
(448, 11, 43, 30000.00, 0.00, 0.00, 0.00, 0.00),
(449, 11, 44, 30000.00, 0.00, 0.00, 0.00, 0.00),
(450, 11, 45, 29970.00, 0.00, 0.00, 0.00, 0.00),
(451, 11, 46, 29970.00, 0.00, 0.00, 0.00, 0.00),
(452, 11, 47, 30000.00, 0.00, 0.00, 0.00, 0.00),
(453, 11, 48, 29940.00, 0.00, 0.00, 0.00, 0.00),
(454, 11, 49, 30000.00, 0.00, 0.00, 0.00, 0.00),
(455, 11, 50, 30000.00, 0.00, 0.00, 0.00, 0.00),
(456, 11, 51, 30000.00, 0.00, 0.00, 0.00, 0.00),
(457, 11, 52, 30000.00, 0.00, 0.00, 0.00, 0.00),
(458, 11, 53, 30000.00, 0.00, 0.00, 0.00, 0.00),
(459, 11, 54, 30000.00, 0.00, 0.00, 0.00, 0.00),
(460, 11, 55, 30000.00, 0.00, 0.00, 0.00, 0.00),
(461, 11, 56, 30000.00, 0.00, 0.00, 0.00, 0.00),
(462, 11, 57, 30000.00, 0.00, 0.00, 0.00, 0.00),
(463, 11, 59, 30000.00, 0.00, 0.00, 0.00, 0.00),
(464, 11, 60, 30000.00, 0.00, 0.00, 0.00, 0.00),
(465, 11, 61, 29880.00, 0.00, 0.00, 0.00, 0.00),
(466, 11, 62, 30000.00, 0.00, 0.00, 0.00, 0.00),
(467, 11, 63, 29990.00, 0.00, 0.00, 0.00, 0.00),
(468, 11, 64, 30000.00, 0.00, 0.00, 0.00, 0.00),
(469, 11, 65, 30000.00, 0.00, 0.00, 0.00, 3000.00),
(470, 11, 66, 29360.00, 0.00, 0.00, 0.00, 0.00),
(471, 11, 67, 30000.00, 0.00, 0.00, 0.00, 0.00),
(472, 11, 69, 30000.00, 0.00, 0.00, 0.00, 0.00),
(473, 11, 70, 30000.00, 0.00, 0.00, 0.00, 0.00),
(474, 11, 71, 30000.00, 0.00, 0.00, 0.00, 0.00),
(475, 11, 72, 29987.00, 0.00, -75.00, 0.00, 80.00),
(476, 11, 73, 30000.00, 0.00, 0.00, 0.00, 0.00),
(477, 11, 74, 30000.00, 0.00, 0.00, 0.00, 0.00),
(478, 11, 75, 30000.00, 0.00, 0.00, 0.00, 0.00),
(479, 11, 76, 30000.00, 0.00, 0.00, 0.00, 0.00),
(480, 11, 77, 30000.00, 0.00, 0.00, 0.00, 0.00),
(481, 11, 78, 29980.00, 0.00, 0.00, 0.00, 0.00),
(482, 11, 79, 30000.00, 0.00, 0.00, 0.00, 0.00),
(483, 11, 80, 29970.00, 0.00, 0.00, 0.00, 0.00),
(484, 11, 81, 29970.00, 0.00, 0.00, 0.00, 0.00),
(485, 11, 82, 30000.00, 0.00, 0.00, 0.00, 0.00),
(486, 11, 83, 30000.00, 0.00, 0.00, 0.00, 0.00),
(487, 11, 85, 30000.00, 0.00, 0.00, 0.00, 0.00),
(488, 11, 86, 30000.00, 0.00, 0.00, 0.00, 0.00),
(489, 11, 87, 29620.00, 0.00, 0.00, 0.00, 0.00),
(490, 11, 88, 30000.00, 0.00, 0.00, 0.00, 0.00),
(491, 11, 89, 30000.00, 0.00, 0.00, 0.00, 0.00),
(492, 11, 90, 29285.00, 0.00, 0.00, 0.00, 0.00),
(493, 11, 91, 30000.00, 0.00, 0.00, 0.00, 0.00),
(494, 11, 92, 30000.00, 0.00, 0.00, 0.00, 0.00),
(495, 11, 93, 30000.00, 0.00, 0.00, 0.00, 0.00),
(496, 11, 94, 29880.00, 0.00, 0.00, 0.00, 0.00),
(497, 11, 95, 30000.00, 0.00, 0.00, 0.00, 0.00),
(498, 11, 96, 30000.00, 0.00, 0.00, 0.00, 0.00),
(499, 11, 97, 30000.00, 0.00, 0.00, 0.00, 0.00),
(500, 11, 98, 30000.00, 0.00, 0.00, 0.00, 0.00),
(501, 11, 99, 29990.00, 0.00, 0.00, 0.00, 0.00),
(502, 11, 101, 30000.00, 0.00, 0.00, 0.00, 0.00),
(503, 11, 102, 30000.00, 0.00, 0.00, 0.00, 0.00),
(504, 11, 103, 30000.00, 0.00, 0.00, 0.00, 0.00),
(505, 11, 104, 29996.00, 0.00, 0.00, 0.00, 0.00),
(506, 11, 105, 30000.00, 0.00, 0.00, 0.00, 0.00),
(507, 11, 106, 30000.00, 0.00, 0.00, 0.00, 0.00),
(508, 11, 107, 30000.00, 0.00, 0.00, 0.00, 0.00),
(509, 11, 108, 30000.00, 0.00, 0.00, 0.00, 0.00),
(510, 11, 109, 30000.00, 0.00, 0.00, 0.00, 0.00),
(511, 11, 110, 30000.00, 0.00, 0.00, 0.00, 0.00),
(512, 11, 111, 30000.00, 0.00, 0.00, 0.00, 0.00),
(513, 11, 112, 30000.00, 0.00, 0.00, 0.00, 0.00),
(514, 11, 113, 30000.00, 0.00, 0.00, 0.00, 0.00),
(515, 11, 114, 30000.00, 0.00, 0.00, 0.00, 0.00),
(516, 11, 115, 30000.00, 0.00, 0.00, 0.00, 0.00),
(517, 11, 116, 30000.00, 0.00, 0.00, 0.00, 0.00),
(518, 11, 117, 30000.00, 0.00, 0.00, 0.00, 0.00),
(519, 11, 118, 30000.00, 0.00, 0.00, 0.00, 0.00),
(520, 11, 119, 30000.00, 0.00, 0.00, 0.00, 0.00),
(521, 11, 120, 0.00, 0.00, 0.00, 0.00, 0.00),
(522, 11, 121, 0.00, 0.00, 0.00, 0.00, 0.00),
(523, 11, 122, 0.00, 0.00, 0.00, 0.00, 0.00),
(524, 11, 123, 0.00, 0.00, 0.00, 0.00, 0.00),
(525, 11, 124, 0.00, 0.00, 0.00, 0.00, 0.00),
(526, 11, 125, 0.00, 0.00, 0.00, 0.00, 0.00),
(527, 11, 126, 0.00, 0.00, 0.00, 0.00, 0.00),
(528, 11, 127, 0.00, 0.00, 0.00, 0.00, 0.00),
(529, 11, 128, 0.00, 0.00, 0.00, 0.00, 0.00),
(530, 11, 129, 0.00, 0.00, 0.00, 0.00, 0.00),
(531, 11, 130, 0.00, 0.00, 0.00, 0.00, 0.00),
(532, 11, 131, 0.00, 0.00, 0.00, 0.00, 0.00),
(533, 11, 132, 0.00, 0.00, 0.00, 0.00, 0.00),
(534, 11, 133, 0.00, 0.00, 0.00, 0.00, 0.00),
(535, 11, 134, 0.00, 0.00, 0.00, 0.00, 0.00),
(536, 11, 135, 0.00, 0.00, 0.00, 0.00, 0.00),
(537, 11, 136, 0.00, 0.00, -0.50, 0.00, 0.50),
(538, 11, 137, 0.00, 0.00, 0.00, 0.00, 0.00),
(539, 11, 138, 0.00, 0.00, 0.00, 0.00, 0.00),
(540, 11, 139, 0.00, 0.00, 0.00, 0.00, 0.00),
(541, 11, 140, 0.00, 0.00, -0.50, 0.00, 0.50),
(542, 11, 141, 0.00, 0.00, 0.00, 0.00, 0.00),
(543, 11, 142, 0.00, 0.00, 0.00, 0.00, 0.00),
(544, 11, 143, 0.00, 0.00, 0.00, 0.00, 0.00),
(545, 11, 144, 0.00, 0.00, 0.00, 0.00, 0.00),
(546, 11, 145, 0.00, 0.00, 0.00, 0.00, 0.00),
(547, 11, 146, 0.00, 0.00, 0.00, 0.00, 0.00),
(548, 11, 147, 0.00, 0.00, 0.00, 0.00, 0.00),
(549, 11, 148, 0.00, 0.00, 0.00, 0.00, 0.00),
(550, 11, 149, 0.00, 0.00, 0.00, 0.00, 0.00),
(551, 11, 150, 0.00, 0.00, 0.00, 0.00, 0.00),
(552, 11, 151, 0.00, 0.00, 0.00, 0.00, 0.00),
(553, 11, 152, 0.00, 0.00, 0.00, 0.00, 0.00),
(554, 11, 153, 0.00, 0.00, 0.00, 0.00, 0.00),
(555, 11, 154, 0.00, 0.00, 0.00, 0.00, 0.00),
(556, 11, 155, 0.00, 0.00, 0.00, 0.00, 0.00),
(557, 11, 156, 0.00, 0.00, 0.00, 0.00, 0.00),
(558, 11, 157, 0.00, 0.00, 0.00, 0.00, 0.00),
(559, 11, 158, 0.00, 0.00, 0.00, 0.00, 0.00),
(560, 11, 159, 0.00, 0.00, 0.00, 0.00, 0.00),
(561, 11, 160, 0.00, 0.00, 0.00, 0.00, 0.00),
(562, 11, 161, 0.00, 0.00, 0.00, 0.00, 0.00),
(563, 11, 162, 0.00, 0.00, 0.00, 0.00, 0.00),
(564, 11, 163, 0.00, 0.00, 0.00, 0.00, 0.00),
(565, 11, 164, 0.00, 0.00, 0.00, 0.00, 0.00),
(566, 11, 165, 0.00, 0.00, 0.00, 0.00, 0.00),
(567, 11, 166, 0.00, 0.00, 0.00, 0.00, 0.00),
(568, 11, 167, 0.00, 0.00, 0.00, 0.00, 0.00),
(569, 11, 168, 0.00, 0.00, 0.00, 0.00, 0.00),
(570, 11, 169, 0.00, 0.00, 0.00, 0.00, 0.00),
(571, 11, 170, 0.00, 0.00, 0.00, 0.00, 0.00),
(572, 11, 171, 0.00, 0.00, 0.00, 0.00, 0.00),
(573, 11, 172, 0.00, 0.00, 0.00, 0.00, 0.00),
(574, 11, 173, 0.00, 0.00, 0.00, 0.00, 0.00),
(575, 12, 1, 0.00, 0.00, 0.00, 0.00, NULL),
(576, 12, 2, 0.00, 0.00, 0.00, 0.00, NULL),
(577, 12, 3, 0.00, 0.00, 0.00, 0.00, NULL),
(578, 12, 4, 0.00, 0.00, 0.00, 0.00, NULL),
(579, 12, 7, 0.00, 0.00, 0.00, 0.00, NULL),
(580, 12, 8, 0.00, 0.00, 0.00, 0.00, NULL),
(581, 12, 9, 0.00, 0.00, 0.00, 0.00, NULL),
(582, 12, 10, 0.00, 0.00, 0.00, 0.00, NULL),
(583, 12, 11, 0.00, 0.00, 0.00, 0.00, NULL),
(584, 12, 12, 0.00, 0.00, 0.00, 0.00, NULL),
(585, 12, 13, 0.00, 0.00, 0.00, 0.00, NULL),
(586, 12, 14, 0.00, 0.00, 0.00, 0.00, NULL),
(587, 12, 15, 0.00, 0.00, 0.00, 0.00, NULL),
(588, 12, 16, 40000.00, 0.00, 0.00, 0.00, NULL),
(589, 12, 17, 0.00, 0.00, 0.00, 0.00, NULL),
(590, 12, 18, 0.00, 0.00, 0.00, 0.00, NULL),
(591, 12, 19, 0.00, 0.00, 0.00, 0.00, NULL),
(592, 12, 20, 0.00, 0.00, 0.00, 0.00, NULL),
(593, 12, 21, 0.00, 0.00, 0.00, 0.00, NULL),
(594, 12, 22, 0.00, 0.00, 0.00, 0.00, NULL),
(595, 12, 23, 0.00, 0.00, 0.00, 0.00, NULL),
(596, 12, 24, 0.00, 0.00, 0.00, 0.00, NULL),
(597, 12, 25, 0.00, 0.00, 0.00, 0.00, NULL),
(598, 12, 26, 0.00, 0.00, 0.00, 0.00, NULL),
(599, 12, 27, 0.00, 0.00, 0.00, 0.00, NULL),
(600, 12, 28, 0.00, 0.00, 0.00, 0.00, NULL),
(601, 12, 29, 0.00, 0.00, 0.00, 0.00, NULL),
(602, 12, 30, 0.00, 0.00, 0.00, 0.00, NULL),
(603, 12, 31, 0.00, 0.00, 0.00, 0.00, NULL),
(604, 12, 32, 0.00, 0.00, 0.00, 0.00, NULL),
(605, 12, 33, 0.00, 0.00, 0.00, 0.00, NULL),
(606, 12, 34, 0.00, 0.00, 0.00, 0.00, NULL),
(607, 12, 35, 0.00, 0.00, 0.00, 0.00, NULL),
(608, 12, 36, 0.00, 0.00, 0.00, 0.00, NULL),
(609, 12, 37, 0.00, 0.00, 0.00, 0.00, NULL),
(610, 12, 38, 0.00, 0.00, 0.00, 0.00, NULL),
(611, 12, 39, 0.00, 0.00, 0.00, 0.00, NULL),
(612, 12, 40, 0.00, 0.00, 0.00, 0.00, NULL),
(613, 12, 41, 0.00, 0.00, 0.00, 0.00, NULL),
(614, 12, 42, 0.00, 0.00, 0.00, 0.00, NULL),
(615, 12, 43, 0.00, 0.00, 0.00, 0.00, NULL),
(616, 12, 44, 0.00, 0.00, 0.00, 0.00, NULL),
(617, 12, 45, 0.00, 0.00, 0.00, 0.00, NULL),
(618, 12, 46, 0.00, 0.00, 0.00, 0.00, NULL),
(619, 12, 47, 0.00, 0.00, 0.00, 0.00, NULL),
(620, 12, 48, 0.00, 0.00, 0.00, 0.00, NULL),
(621, 12, 49, 0.00, 0.00, 0.00, 0.00, NULL),
(622, 12, 50, 0.00, 0.00, 0.00, 0.00, NULL),
(623, 12, 51, 0.00, 0.00, 0.00, 0.00, NULL),
(624, 12, 52, 0.00, 0.00, 0.00, 0.00, NULL),
(625, 12, 53, 0.00, 0.00, 0.00, 0.00, NULL),
(626, 12, 54, 0.00, 0.00, 0.00, 0.00, NULL),
(627, 12, 55, 0.00, 0.00, 0.00, 0.00, NULL),
(628, 12, 56, 0.00, 0.00, 0.00, 0.00, NULL),
(629, 12, 57, 0.00, 0.00, 0.00, 0.00, NULL),
(630, 12, 59, 0.00, 0.00, 0.00, 0.00, NULL),
(631, 12, 60, 0.00, 0.00, 0.00, 0.00, NULL),
(632, 12, 61, 0.00, 0.00, 0.00, 0.00, NULL),
(633, 12, 62, 0.00, 0.00, 0.00, 0.00, NULL),
(634, 12, 63, 0.00, 0.00, 0.00, 0.00, NULL),
(635, 12, 64, 0.00, 0.00, 0.00, 0.00, NULL),
(636, 12, 65, 3000.00, 0.00, 0.00, 0.00, NULL),
(637, 12, 66, 0.00, 0.00, 0.00, 0.00, NULL),
(638, 12, 67, 0.00, 0.00, 0.00, 0.00, NULL),
(639, 12, 69, 0.00, 0.00, 0.00, 0.00, NULL),
(640, 12, 70, 0.00, 0.00, 0.00, 0.00, NULL),
(641, 12, 71, 0.00, 0.00, 0.00, 0.00, NULL),
(642, 12, 72, 80.00, 0.00, 0.00, 0.00, NULL),
(643, 12, 73, 0.00, 0.00, 0.00, 0.00, NULL),
(644, 12, 74, 0.00, 0.00, 0.00, 0.00, NULL),
(645, 12, 75, 0.00, 0.00, 0.00, 0.00, NULL),
(646, 12, 76, 0.00, 0.00, 0.00, 0.00, NULL),
(647, 12, 77, 0.00, 0.00, 0.00, 0.00, NULL),
(648, 12, 78, 0.00, 0.00, 0.00, 0.00, NULL),
(649, 12, 79, 0.00, 0.00, 0.00, 0.00, NULL),
(650, 12, 80, 0.00, 0.00, 0.00, 0.00, NULL),
(651, 12, 81, 0.00, 0.00, 0.00, 0.00, NULL),
(652, 12, 82, 0.00, 0.00, 0.00, 0.00, NULL),
(653, 12, 83, 0.00, 0.00, 0.00, 0.00, NULL),
(654, 12, 85, 0.00, 0.00, 0.00, 0.00, NULL),
(655, 12, 86, 0.00, 0.00, 0.00, 0.00, NULL),
(656, 12, 87, 0.00, 0.00, 0.00, 0.00, NULL),
(657, 12, 88, 0.00, 0.00, 0.00, 0.00, NULL),
(658, 12, 89, 0.00, 0.00, 0.00, 0.00, NULL),
(659, 12, 90, 0.00, 0.00, 0.00, 0.00, NULL),
(660, 12, 91, 0.00, 0.00, 0.00, 0.00, NULL),
(661, 12, 92, 0.00, 0.00, 0.00, 0.00, NULL),
(662, 12, 93, 0.00, 0.00, 0.00, 0.00, NULL),
(663, 12, 94, 0.00, 0.00, 0.00, 0.00, NULL),
(664, 12, 95, 0.00, 0.00, 0.00, 0.00, NULL),
(665, 12, 96, 0.00, 0.00, 0.00, 0.00, NULL),
(666, 12, 97, 0.00, 0.00, 0.00, 0.00, NULL),
(667, 12, 98, 0.00, 0.00, 0.00, 0.00, NULL),
(668, 12, 99, 0.00, 0.00, 0.00, 0.00, NULL),
(669, 12, 101, 0.00, 0.00, 0.00, 0.00, NULL),
(670, 12, 102, 0.00, 0.00, 0.00, 0.00, NULL),
(671, 12, 103, 0.00, 0.00, 0.00, 0.00, NULL),
(672, 12, 104, 0.00, 0.00, 0.00, 0.00, NULL),
(673, 12, 105, 0.00, 0.00, 0.00, 0.00, NULL),
(674, 12, 106, 0.00, 0.00, 0.00, 0.00, NULL),
(675, 12, 107, 0.00, 0.00, 0.00, 0.00, NULL),
(676, 12, 108, 0.00, 0.00, 0.00, 0.00, NULL),
(677, 12, 109, 0.00, 0.00, 0.00, 0.00, NULL),
(678, 12, 110, 0.00, 0.00, 0.00, 0.00, NULL),
(679, 12, 111, 0.00, 0.00, 0.00, 0.00, NULL),
(680, 12, 112, 0.00, 0.00, 0.00, 0.00, NULL),
(681, 12, 113, 0.00, 0.00, 0.00, 0.00, NULL),
(682, 12, 114, 0.00, 0.00, 0.00, 0.00, NULL),
(683, 12, 115, 0.00, 0.00, 0.00, 0.00, NULL),
(684, 12, 116, 0.00, 0.00, 0.00, 0.00, NULL),
(685, 12, 117, 0.00, 0.00, 0.00, 0.00, NULL),
(686, 12, 118, 0.00, 0.00, 0.00, 0.00, NULL),
(687, 12, 119, 0.00, 0.00, 0.00, 0.00, NULL),
(688, 12, 120, 0.00, 0.00, 0.00, 0.00, NULL),
(689, 12, 121, 0.00, 0.00, 0.00, 0.00, NULL),
(690, 12, 122, 0.00, 0.00, 0.00, 0.00, NULL),
(691, 12, 123, 0.00, 0.00, 0.00, 0.00, NULL),
(692, 12, 124, 0.00, 0.00, 0.00, 0.00, NULL),
(693, 12, 125, 0.00, 0.00, 0.00, 0.00, NULL),
(694, 12, 126, 0.00, 0.00, 0.00, 0.00, NULL),
(695, 12, 127, 0.00, 0.00, 0.00, 0.00, NULL),
(696, 12, 128, 0.00, 0.00, 0.00, 0.00, NULL),
(697, 12, 129, 0.00, 0.00, 0.00, 0.00, NULL),
(698, 12, 130, 0.00, 0.00, 0.00, 0.00, NULL),
(699, 12, 131, 0.00, 0.00, 0.00, 0.00, NULL),
(700, 12, 132, 0.00, 0.00, 0.00, 0.00, NULL),
(701, 12, 133, 0.00, 0.00, 0.00, 0.00, NULL),
(702, 12, 134, 0.00, 0.00, 0.00, 0.00, NULL),
(703, 12, 135, 0.00, 0.00, 0.00, 0.00, NULL),
(704, 12, 136, 0.50, 0.00, 0.00, 0.00, NULL),
(705, 12, 137, 0.00, 0.00, 0.00, 0.00, NULL),
(706, 12, 138, 0.00, 0.00, 0.00, 0.00, NULL),
(707, 12, 139, 0.00, 0.00, 0.00, 0.00, NULL),
(708, 12, 140, 0.50, 0.00, 0.00, 0.00, NULL),
(709, 12, 141, 0.00, 0.00, 0.00, 0.00, NULL),
(710, 12, 142, 0.00, 0.00, 0.00, 0.00, NULL),
(711, 12, 143, 0.00, 0.00, 0.00, 0.00, NULL),
(712, 12, 144, 0.00, 0.00, 0.00, 0.00, NULL),
(713, 12, 145, 0.00, 0.00, 0.00, 0.00, NULL),
(714, 12, 146, 0.00, 0.00, 0.00, 0.00, NULL),
(715, 12, 147, 0.00, 0.00, 0.00, 0.00, NULL),
(716, 12, 148, 0.00, 0.00, 0.00, 0.00, NULL),
(717, 12, 149, 0.00, 0.00, 0.00, 0.00, NULL),
(718, 12, 150, 0.00, 0.00, 0.00, 0.00, NULL),
(719, 12, 151, 0.00, 0.00, 0.00, 0.00, NULL),
(720, 12, 152, 0.00, 0.00, 0.00, 0.00, NULL),
(721, 12, 153, 0.00, 0.00, 0.00, 0.00, NULL),
(722, 12, 154, 0.00, 0.00, 0.00, 0.00, NULL),
(723, 12, 155, 0.00, 0.00, 0.00, 0.00, NULL),
(724, 12, 156, 0.00, 0.00, 0.00, 0.00, NULL),
(725, 12, 157, 0.00, 0.00, 0.00, 0.00, NULL),
(726, 12, 158, 0.00, 0.00, 0.00, 0.00, NULL),
(727, 12, 159, 0.00, 0.00, 0.00, 0.00, NULL),
(728, 12, 160, 0.00, 0.00, 0.00, 0.00, NULL),
(729, 12, 161, 0.00, 0.00, 0.00, 0.00, NULL),
(730, 12, 162, 0.00, 0.00, 0.00, 0.00, NULL),
(731, 12, 163, 0.00, 0.00, 0.00, 0.00, NULL),
(732, 12, 164, 0.00, 0.00, 0.00, 0.00, NULL),
(733, 12, 165, 0.00, 0.00, 0.00, 0.00, NULL),
(734, 12, 166, 0.00, 0.00, 0.00, 0.00, NULL),
(735, 12, 167, 0.00, 0.00, 0.00, 0.00, NULL),
(736, 12, 168, 0.00, 0.00, 0.00, 0.00, NULL),
(737, 12, 169, 0.00, 0.00, 0.00, 0.00, NULL),
(738, 12, 170, 0.00, 0.00, 0.00, 0.00, NULL),
(739, 12, 171, 0.00, 0.00, 0.00, 0.00, NULL),
(740, 12, 172, 0.00, 0.00, 0.00, 0.00, NULL),
(741, 12, 173, 0.00, 0.00, 0.00, 0.00, NULL);

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
(15, NULL, 1, '2025-09-17 22:44:49', NULL, 'pendiente', 'da8568fc0a77f206750d491dee1000a7'),
(16, NULL, 1, '2025-09-17 22:45:21', NULL, 'pendiente', '3fd4f355a33f96b8766a30f7f0462bfa'),
(17, NULL, 1, '2025-09-17 23:27:48', NULL, 'pendiente', 'a357371467689079d141472230d979e8'),
(18, NULL, 1, '2025-09-18 13:43:27', NULL, 'pendiente', '907b09f6fc6fd7b1b3974e9aef4309f2'),
(19, NULL, 1, '2025-09-18 14:10:50', NULL, 'pendiente', '71bb223e5c63d472cfe242151c375fc4'),
(20, NULL, 1, '2025-09-18 14:27:20', NULL, 'pendiente', '6f619c2fb321dafe5615cd9ea63107ff'),
(22, NULL, 1, '2025-09-18 14:28:42', NULL, 'pendiente', 'b1566d2d82d0b8ab9887da30dc87db1b'),
(23, NULL, 1, '2025-09-18 14:31:27', NULL, 'pendiente', '67d3704c31187498186ffac0cb29c9b2'),
(25, NULL, 1, '2025-09-18 14:37:58', NULL, 'pendiente', 'a8decbe9053be5df999edaf130fbb1c9'),
(26, NULL, 1, '2025-09-18 16:13:55', NULL, 'pendiente', '3c1906ad9cdfd4a9b3b1f33ccda75f09'),
(27, NULL, 1, '2025-09-18 16:18:12', NULL, 'pendiente', 'a9d32c1596c0d1042e37d2a3197a83c2'),
(28, NULL, 1, '2025-09-18 18:21:04', NULL, 'pendiente', '387e70779d36050f13c3286f4a0064c3'),
(29, NULL, 1, '2025-09-18 18:23:02', NULL, 'pendiente', 'a1b09e98868128bcdb98bf7cf8690bcf'),
(30, NULL, 1, '2025-09-18 21:43:23', NULL, 'pendiente', '59c2709cc700b049df5a9b9180b9425f'),
(31, NULL, 1, '2025-09-19 20:54:49', NULL, 'pendiente', '216b75837353c3e99906e8ed82b6e476');

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
(33, 30, 1, 5000.00, 'gramos', 0.00),
(34, 30, 10, 1200.00, 'gramos', 0.00),
(35, 30, 40, 800.00, 'gramos', 0.00),
(36, 30, 72, 75.00, 'pieza', 0.00),
(37, 31, 1, 4000.00, 'gramos', 0.00),
(38, 31, 10, 1000.00, 'gramos', 0.00),
(39, 31, 40, 1700.00, 'gramos', 0.00);

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
  `cantidad_actual` decimal(10,2) NOT NULL,
  `credito` tinyint(1) DEFAULT NULL,
  `pagado` tinyint(1) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `entradas_insumos`
--

INSERT INTO `entradas_insumos` (`id`, `insumo_id`, `proveedor_id`, `usuario_id`, `fecha`, `descripcion`, `cantidad`, `unidad`, `costo_total`, `referencia_doc`, `folio_fiscal`, `qr`, `cantidad_actual`, `credito`, `pagado`) VALUES
(56, 1, 14, 1, '2025-09-18 21:26:23', '', 5000.00, 'gramos', 150.00, '', '', 'archivos/qr/entrada_insumo_56.png', 0.00, NULL, NULL),
(57, 40, 14, 1, '2025-09-18 21:26:23', '', 500.00, 'gramos', 200.00, '', '', 'archivos/qr/entrada_insumo_57.png', 0.00, NULL, NULL),
(58, 10, 14, 1, '2025-09-18 21:26:23', '', 500.00, 'gramos', 150.00, '', '', 'archivos/qr/entrada_insumo_58.png', 0.00, NULL, NULL),
(59, 1, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 50.00, '', '', 'archivos/qr/entrada_insumo_59.png', 0.00, NULL, NULL),
(60, 10, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_60.png', 0.00, NULL, NULL),
(61, 40, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_61.png', 0.00, NULL, NULL),
(62, 1, 11, 1, '2025-09-18 21:30:48', '', 3000.00, 'gramos', 80.00, '', '', 'archivos/qr/entrada_insumo_62.png', 0.00, NULL, NULL),
(63, 40, 11, 1, '2025-09-18 21:30:48', '', 1000.00, 'gramos', 350.00, '', '', 'archivos/qr/entrada_insumo_63.png', 0.00, NULL, NULL),
(64, 10, 11, 1, '2025-09-18 21:30:48', '', 500.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_64.png', 0.00, NULL, NULL),
(65, 72, 16, 1, '2025-09-18 21:35:35', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_65.png', 5.00, NULL, NULL),
(66, 72, 16, 1, '2025-09-18 21:36:17', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_66.png', 25.00, NULL, NULL),
(67, 72, 16, 1, '2025-09-18 21:36:37', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_67.png', 50.00, NULL, NULL),
(68, 65, 13, 1, '2025-09-19 20:46:20', '', 3000.00, 'gramos', 40.00, '', '', 'archivos/qr/entrada_insumo_68.png', 3000.00, NULL, NULL),
(69, 140, 8, 1, '2025-09-19 20:47:11', '', 1.00, 'bulto', 80.00, '', '', 'archivos/qr/entrada_insumo_69.png', 0.50, NULL, NULL),
(70, 136, 8, 1, '2025-09-19 20:47:11', '', 1.00, 'paquete', 80.00, '', '', 'archivos/qr/entrada_insumo_70.png', 0.50, NULL, NULL),
(71, 16, 14, 1, '2025-09-19 21:18:44', '', 40000.00, 'gramos', 70.00, '', '', 'archivos/qr/entrada_insumo_71.png', 40000.00, NULL, NULL),
(72, 1, 10, 1, '2025-09-26 14:27:44', '', 99999.00, 'gramos', 90.00, '', '', 'archivos/qr/entrada_insumo_72.png', 99999.00, 0, NULL),
(73, 89, 10, 1, '2025-09-26 14:27:44', '', 99999.00, 'gramos', 99.00, '', '', 'archivos/qr/entrada_insumo_73.png', 99999.00, 0, NULL);

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
(1, 'Arroz', 'gramos', 99999.00, 'por_receta', 'ins_68717301313ad.jpg', 0.00),
(2, 'Alga', 'piezas', 0.00, 'por_receta', 'ins_6871716a72681.jpg', 0.00),
(3, 'Salmón fresco', 'gramos', 0.00, 'por_receta', 'ins_6871777fa2c56.png', 0.00),
(4, 'Refresco en lata', 'piezas', 0.00, 'unidad_completa', 'ins_6871731d075cb.webp', 0.00),
(7, 'Surimi', 'gramos', 0.00, 'uso_general', 'ins_688a521dcd583.jpg', 0.00),
(8, 'Tocino', 'gramos', 0.00, 'uso_general', 'ins_688a4dc84c002.jpg', 0.00),
(9, 'Pollo', 'gramos', 0.00, 'desempaquetado', 'ins_688a4e4bd5999.jpg', 0.00),
(10, 'Camarón', 'gramos', 0.00, 'desempaquetado', 'ins_688a4f5c873c6.jpg', 0.00),
(11, 'Queso Chihuahua', 'gramos', 0.00, 'unidad_completa', 'ins_688a4feca9865.jpg', 0.00),
(12, 'Philadelphia', 'gramos', 0.00, 'uso_general', 'ins_688a504f9cb40.jpg', 0.00),
(13, 'Arroz blanco', 'gramos', 0.00, 'por_receta', 'ins_689f82d674c65.jpg', 0.00),
(14, 'Carne', 'gramos', 0.00, 'uso_general', 'ins_688a528d1261a.jpg', 0.00),
(15, 'Queso Amarillo', 'piezas', 0.00, 'uso_general', 'ins_688a53246c1c2.jpg', 0.00),
(16, 'Ajonjolí', 'gramos', 40000.00, 'uso_general', 'ins_689f824a23343.jpg', 0.00),
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
(65, 'Limón', 'gramos', 3000.00, 'por_receta', 'ins_68add890ee640.jpg', 0.00),
(66, 'Queso Mix', 'gramos', 0.00, 'uso_general', 'ins_68ade1625f489.jpg', 0.00),
(67, 'Morrón', 'gramos', 0.00, 'por_receta', 'ins_68addcbc6d15a.jpg', 0.00),
(69, 'Pasta chukasoba', 'gramos', 0.00, 'por_receta', 'ins_68addd277fde6.jpg', 0.00),
(70, 'Pasta frita', 'gramos', 0.00, 'por_receta', 'ins_68addd91a005e.jpg', 0.00),
(71, 'Queso crema', 'gramos', 0.00, 'uso_general', 'ins_68ade11cdadcb.jpg', 0.00),
(72, 'Refresco embotellado', 'pieza', 80.00, 'unidad_completa', 'ins_68adfdd53f04e.jpg', 0.00),
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
(89, 'Aderezo', 'gramos', 99999.00, 'uso_general', 'ins_68adcc0771a3c.jpg', 0.00),
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
(136, 'Bolsa papel x 100pz', 'paquete', 0.50, 'unidad_completa', '', 0.00),
(137, 'rollo impresora mediano', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(138, 'rollo impresora grande', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(139, 'tenedor fantasy mediano 25pz', 'paquete', 0.00, 'unidad_completa', '', 0.00),
(140, 'Bolsa basura 90x120 negra', 'bulto', 0.50, 'unidad_completa', '', 0.00),
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
(29, 1, 'bodega', 'Generacion QR', '2025-09-18 21:43:23', 31),
(30, 1, 'bodega', 'Devolucion QR', '2025-09-18 23:15:06', 31),
(31, 1, 'bodega', 'Generacion QR', '2025-09-19 20:54:49', 32);

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
  `tipo` enum('entrada','salida','ajuste','traspaso','merma','devolucion') DEFAULT 'entrada',
  `usuario_id` int(11) DEFAULT NULL,
  `usuario_destino_id` int(11) DEFAULT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `id_entrada` int(11) DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `observacion` text DEFAULT NULL,
  `fecha` datetime DEFAULT current_timestamp(),
  `qr_token` varchar(64) DEFAULT NULL,
  `id_qr` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `movimientos_insumos`
--

INSERT INTO `movimientos_insumos` (`id`, `tipo`, `usuario_id`, `usuario_destino_id`, `insumo_id`, `id_entrada`, `cantidad`, `observacion`, `fecha`, `qr_token`, `id_qr`) VALUES
(111, 'traspaso', 1, NULL, 1, 56, -5000.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(112, 'traspaso', 1, NULL, 10, 58, -500.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(113, 'traspaso', 1, NULL, 10, 60, -700.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(114, 'traspaso', 1, NULL, 40, 57, -500.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(115, 'traspaso', 1, NULL, 40, 61, -300.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(116, 'traspaso', 1, NULL, 72, 65, -50.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(117, 'traspaso', 1, NULL, 72, 66, -25.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(118, 'devolucion', 1, NULL, 10, 58, 200.00, 'refresco golpeado camaron extra', '2025-09-18 23:15:06', '59c2709cc700b049df5a9b9180b9425f', 31),
(119, 'devolucion', 1, NULL, 72, 65, 5.00, 'refresco golpeado camaron extra', '2025-09-18 23:15:06', '59c2709cc700b049df5a9b9180b9425f', 31),
(120, 'salida', 1, NULL, 140, 69, -0.50, 'Retiro de entrada #69 (0.5 bulto)', '2025-09-20 04:49:22', '185ab598af58ba225da659d014194b4e', NULL),
(121, 'salida', 1, NULL, 136, 70, -0.50, 'Retiro de entrada #70 (0.5 paquete)', '2025-09-20 04:50:22', 'fdb782bb3b6d2a4e8b5b0a2385c44fb1', NULL),
(122, 'traspaso', 1, NULL, 1, 59, -1000.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(123, 'traspaso', 1, NULL, 1, 62, -3000.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(124, 'traspaso', 1, NULL, 10, 58, -200.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(125, 'traspaso', 1, NULL, 10, 60, -300.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(126, 'traspaso', 1, NULL, 10, 64, -500.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(127, 'traspaso', 1, NULL, 40, 61, -700.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(128, 'traspaso', 1, NULL, 40, 63, -1000.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32);

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
(1, 'Suministros Sushi MX', NULL, NULL, NULL, NULL, '555-123-4567', NULL, NULL, 'Calle Soya #123, CDMX', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:36:48'),
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
  `pdf_recepcion` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `qrs_insumo`
--

INSERT INTO `qrs_insumo` (`id`, `token`, `json_data`, `estado`, `creado_por`, `creado_en`, `expiracion`, `pdf_envio`, `pdf_recepcion`) VALUES
(31, '59c2709cc700b049df5a9b9180b9425f', '[{\"id\":1,\"nombre\":\"Arroz\",\"unidad\":\"gramos\",\"cantidad\":5000,\"precio_unitario\":0},{\"id\":10,\"nombre\":\"Camarón\",\"unidad\":\"gramos\",\"cantidad\":1200,\"precio_unitario\":0},{\"id\":40,\"nombre\":\"Atún fresco\",\"unidad\":\"gramos\",\"cantidad\":800,\"precio_unitario\":0},{\"id\":72,\"nombre\":\"Refresco embotellado\",\"unidad\":\"pieza\",\"cantidad\":75,\"precio_unitario\":0}]', 'pendiente', 1, '2025-09-18 21:43:23', NULL, 'archivos/bodega/pdfs/qr_59c2709cc700b049df5a9b9180b9425f.pdf', 'archivos/bodega/pdfs/recepcion_59c2709cc700b049df5a9b9180b9425f.pdf'),
(32, '216b75837353c3e99906e8ed82b6e476', '[{\"id\":1,\"nombre\":\"Arroz\",\"unidad\":\"gramos\",\"cantidad\":4000,\"precio_unitario\":0},{\"id\":10,\"nombre\":\"Camarón\",\"unidad\":\"gramos\",\"cantidad\":1000,\"precio_unitario\":0},{\"id\":40,\"nombre\":\"Atún fresco\",\"unidad\":\"gramos\",\"cantidad\":1700,\"precio_unitario\":0}]', 'pendiente', 1, '2025-09-19 20:54:49', NULL, 'archivos/bodega/pdfs/qr_216b75837353c3e99906e8ed82b6e476.pdf', NULL);

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

--
-- Volcado de datos para la tabla `recepciones_log`
--

INSERT INTO `recepciones_log` (`id`, `sucursal_id`, `qr_token`, `fecha_recepcion`, `usuario_id`, `json_recibido`, `estado`) VALUES
(1, NULL, '59c2709cc700b049df5a9b9180b9425f', '2025-09-18 23:15:06', 1, '{\"modo\":\"parcial\",\"items\":[{\"insumo_id\":10,\"cantidad\":200},{\"insumo_id\":72,\"cantidad\":5}],\"observacion\":\"refresco golpeado camaron extra\",\"devueltos\":{\"10\":200,\"72\":5}}', '');

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
(26, 'Cocina', '/vistas/cocina/cocina2.php', 'link', NULL, 4),
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
  `rol` enum('supervisor','admin','empleado') NOT NULL,
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
(82, 1, 39);

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
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `idx_mi_id_entrada` (`id_entrada`),
  ADD KEY `idx_mi_id_qr` (`id_qr`);

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=742;

--
-- AUTO_INCREMENT de la tabla `despachos`
--
ALTER TABLE `despachos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

--
-- AUTO_INCREMENT de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=40;

--
-- AUTO_INCREMENT de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=74;

--
-- AUTO_INCREMENT de la tabla `insumos`
--
ALTER TABLE `insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=174;

--
-- AUTO_INCREMENT de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

--
-- AUTO_INCREMENT de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=129;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=33;

--
-- AUTO_INCREMENT de la tabla `reabasto_alertas`
--
ALTER TABLE `reabasto_alertas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `recepciones_log`
--
ALTER TABLE `recepciones_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=83;

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
  ADD CONSTRAINT `fk_mi_id_entrada` FOREIGN KEY (`id_entrada`) REFERENCES `entradas_insumos` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mi_qr` FOREIGN KEY (`id_qr`) REFERENCES `qrs_insumo` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
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
-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 26-09-2025 a las 22:29:10
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
(11, '2025-09-16 10:48:12', '2025-09-26 22:24:39', 1, 1, ''),
(12, '2025-09-26 14:25:23', NULL, 1, NULL, NULL);

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
(408, 11, 1, 25750.00, 0.00, -9000.00, 0.00, 0.00),
(409, 11, 2, 29988.50, 0.00, 0.00, 0.00, 0.00),
(410, 11, 3, 30000.00, 0.00, 0.00, 0.00, 0.00),
(411, 11, 4, 29999.00, 0.00, 0.00, 0.00, 0.00),
(412, 11, 7, 30000.00, 0.00, 0.00, 0.00, 0.00),
(413, 11, 8, 29650.00, 0.00, 0.00, 0.00, 0.00),
(414, 11, 9, 29970.00, 0.00, 0.00, 0.00, 0.00),
(415, 11, 10, 29910.00, 0.00, -2200.00, 0.00, 0.00),
(416, 11, 11, 30000.00, 0.00, 0.00, 0.00, 0.00),
(417, 11, 12, 29390.00, 0.00, 0.00, 0.00, 0.00),
(418, 11, 13, 30000.00, 0.00, 0.00, 0.00, 0.00),
(419, 11, 14, 29820.00, 0.00, 0.00, 0.00, 0.00),
(420, 11, 15, 29998.00, 0.00, 0.00, 0.00, 0.00),
(421, 11, 16, 29994.00, 0.00, 0.00, 0.00, 40000.00),
(422, 11, 17, 30000.00, 0.00, 0.00, 0.00, 0.00),
(423, 11, 18, 30000.00, 0.00, 0.00, 0.00, 0.00),
(424, 11, 19, 30000.00, 0.00, 0.00, 0.00, 0.00),
(425, 11, 20, 30000.00, 0.00, 0.00, 0.00, 0.00),
(426, 11, 21, 29975.00, 0.00, 0.00, 0.00, 0.00),
(427, 11, 22, 30000.00, 0.00, 0.00, 0.00, 0.00),
(428, 11, 23, 29990.00, 0.00, 0.00, 0.00, 0.00),
(429, 11, 24, 29400.00, 0.00, 0.00, 0.00, 0.00),
(430, 11, 25, 30000.00, 0.00, 0.00, 0.00, 0.00),
(431, 11, 26, 30000.00, 0.00, 0.00, 0.00, 0.00),
(432, 11, 27, 30000.00, 0.00, 0.00, 0.00, 0.00),
(433, 11, 28, 30000.00, 0.00, 0.00, 0.00, 0.00),
(434, 11, 29, 30000.00, 0.00, 0.00, 0.00, 0.00),
(435, 11, 30, 30000.00, 0.00, 0.00, 0.00, 0.00),
(436, 11, 31, 30000.00, 0.00, 0.00, 0.00, 0.00),
(437, 11, 32, 30000.00, 0.00, 0.00, 0.00, 0.00),
(438, 11, 33, 29870.00, 0.00, 0.00, 0.00, 0.00),
(439, 11, 34, 30000.00, 0.00, 0.00, 0.00, 0.00),
(440, 11, 35, 30000.00, 0.00, 0.00, 0.00, 0.00),
(441, 11, 36, 29260.00, 0.00, 0.00, 0.00, 0.00),
(442, 11, 37, 30000.00, 0.00, 0.00, 0.00, 0.00),
(443, 11, 38, 30000.00, 0.00, 0.00, 0.00, 0.00),
(444, 11, 39, 30000.00, 0.00, 0.00, 0.00, 0.00),
(445, 11, 40, 30000.00, 0.00, -2500.00, 0.00, 0.00),
(446, 11, 41, 30000.00, 0.00, 0.00, 0.00, 0.00),
(447, 11, 42, 30000.00, 0.00, 0.00, 0.00, 0.00),
(448, 11, 43, 30000.00, 0.00, 0.00, 0.00, 0.00),
(449, 11, 44, 30000.00, 0.00, 0.00, 0.00, 0.00),
(450, 11, 45, 29970.00, 0.00, 0.00, 0.00, 0.00),
(451, 11, 46, 29970.00, 0.00, 0.00, 0.00, 0.00),
(452, 11, 47, 30000.00, 0.00, 0.00, 0.00, 0.00),
(453, 11, 48, 29940.00, 0.00, 0.00, 0.00, 0.00),
(454, 11, 49, 30000.00, 0.00, 0.00, 0.00, 0.00),
(455, 11, 50, 30000.00, 0.00, 0.00, 0.00, 0.00),
(456, 11, 51, 30000.00, 0.00, 0.00, 0.00, 0.00),
(457, 11, 52, 30000.00, 0.00, 0.00, 0.00, 0.00),
(458, 11, 53, 30000.00, 0.00, 0.00, 0.00, 0.00),
(459, 11, 54, 30000.00, 0.00, 0.00, 0.00, 0.00),
(460, 11, 55, 30000.00, 0.00, 0.00, 0.00, 0.00),
(461, 11, 56, 30000.00, 0.00, 0.00, 0.00, 0.00),
(462, 11, 57, 30000.00, 0.00, 0.00, 0.00, 0.00),
(463, 11, 59, 30000.00, 0.00, 0.00, 0.00, 0.00),
(464, 11, 60, 30000.00, 0.00, 0.00, 0.00, 0.00),
(465, 11, 61, 29880.00, 0.00, 0.00, 0.00, 0.00),
(466, 11, 62, 30000.00, 0.00, 0.00, 0.00, 0.00),
(467, 11, 63, 29990.00, 0.00, 0.00, 0.00, 0.00),
(468, 11, 64, 30000.00, 0.00, 0.00, 0.00, 0.00),
(469, 11, 65, 30000.00, 0.00, 0.00, 0.00, 3000.00),
(470, 11, 66, 29360.00, 0.00, 0.00, 0.00, 0.00),
(471, 11, 67, 30000.00, 0.00, 0.00, 0.00, 0.00),
(472, 11, 69, 30000.00, 0.00, 0.00, 0.00, 0.00),
(473, 11, 70, 30000.00, 0.00, 0.00, 0.00, 0.00),
(474, 11, 71, 30000.00, 0.00, 0.00, 0.00, 0.00),
(475, 11, 72, 29987.00, 0.00, -75.00, 0.00, 80.00),
(476, 11, 73, 30000.00, 0.00, 0.00, 0.00, 0.00),
(477, 11, 74, 30000.00, 0.00, 0.00, 0.00, 0.00),
(478, 11, 75, 30000.00, 0.00, 0.00, 0.00, 0.00),
(479, 11, 76, 30000.00, 0.00, 0.00, 0.00, 0.00),
(480, 11, 77, 30000.00, 0.00, 0.00, 0.00, 0.00),
(481, 11, 78, 29980.00, 0.00, 0.00, 0.00, 0.00),
(482, 11, 79, 30000.00, 0.00, 0.00, 0.00, 0.00),
(483, 11, 80, 29970.00, 0.00, 0.00, 0.00, 0.00),
(484, 11, 81, 29970.00, 0.00, 0.00, 0.00, 0.00),
(485, 11, 82, 30000.00, 0.00, 0.00, 0.00, 0.00),
(486, 11, 83, 30000.00, 0.00, 0.00, 0.00, 0.00),
(487, 11, 85, 30000.00, 0.00, 0.00, 0.00, 0.00),
(488, 11, 86, 30000.00, 0.00, 0.00, 0.00, 0.00),
(489, 11, 87, 29620.00, 0.00, 0.00, 0.00, 0.00),
(490, 11, 88, 30000.00, 0.00, 0.00, 0.00, 0.00),
(491, 11, 89, 30000.00, 0.00, 0.00, 0.00, 0.00),
(492, 11, 90, 29285.00, 0.00, 0.00, 0.00, 0.00),
(493, 11, 91, 30000.00, 0.00, 0.00, 0.00, 0.00),
(494, 11, 92, 30000.00, 0.00, 0.00, 0.00, 0.00),
(495, 11, 93, 30000.00, 0.00, 0.00, 0.00, 0.00),
(496, 11, 94, 29880.00, 0.00, 0.00, 0.00, 0.00),
(497, 11, 95, 30000.00, 0.00, 0.00, 0.00, 0.00),
(498, 11, 96, 30000.00, 0.00, 0.00, 0.00, 0.00),
(499, 11, 97, 30000.00, 0.00, 0.00, 0.00, 0.00),
(500, 11, 98, 30000.00, 0.00, 0.00, 0.00, 0.00),
(501, 11, 99, 29990.00, 0.00, 0.00, 0.00, 0.00),
(502, 11, 101, 30000.00, 0.00, 0.00, 0.00, 0.00),
(503, 11, 102, 30000.00, 0.00, 0.00, 0.00, 0.00),
(504, 11, 103, 30000.00, 0.00, 0.00, 0.00, 0.00),
(505, 11, 104, 29996.00, 0.00, 0.00, 0.00, 0.00),
(506, 11, 105, 30000.00, 0.00, 0.00, 0.00, 0.00),
(507, 11, 106, 30000.00, 0.00, 0.00, 0.00, 0.00),
(508, 11, 107, 30000.00, 0.00, 0.00, 0.00, 0.00),
(509, 11, 108, 30000.00, 0.00, 0.00, 0.00, 0.00),
(510, 11, 109, 30000.00, 0.00, 0.00, 0.00, 0.00),
(511, 11, 110, 30000.00, 0.00, 0.00, 0.00, 0.00),
(512, 11, 111, 30000.00, 0.00, 0.00, 0.00, 0.00),
(513, 11, 112, 30000.00, 0.00, 0.00, 0.00, 0.00),
(514, 11, 113, 30000.00, 0.00, 0.00, 0.00, 0.00),
(515, 11, 114, 30000.00, 0.00, 0.00, 0.00, 0.00),
(516, 11, 115, 30000.00, 0.00, 0.00, 0.00, 0.00),
(517, 11, 116, 30000.00, 0.00, 0.00, 0.00, 0.00),
(518, 11, 117, 30000.00, 0.00, 0.00, 0.00, 0.00),
(519, 11, 118, 30000.00, 0.00, 0.00, 0.00, 0.00),
(520, 11, 119, 30000.00, 0.00, 0.00, 0.00, 0.00),
(521, 11, 120, 0.00, 0.00, 0.00, 0.00, 0.00),
(522, 11, 121, 0.00, 0.00, 0.00, 0.00, 0.00),
(523, 11, 122, 0.00, 0.00, 0.00, 0.00, 0.00),
(524, 11, 123, 0.00, 0.00, 0.00, 0.00, 0.00),
(525, 11, 124, 0.00, 0.00, 0.00, 0.00, 0.00),
(526, 11, 125, 0.00, 0.00, 0.00, 0.00, 0.00),
(527, 11, 126, 0.00, 0.00, 0.00, 0.00, 0.00),
(528, 11, 127, 0.00, 0.00, 0.00, 0.00, 0.00),
(529, 11, 128, 0.00, 0.00, 0.00, 0.00, 0.00),
(530, 11, 129, 0.00, 0.00, 0.00, 0.00, 0.00),
(531, 11, 130, 0.00, 0.00, 0.00, 0.00, 0.00),
(532, 11, 131, 0.00, 0.00, 0.00, 0.00, 0.00),
(533, 11, 132, 0.00, 0.00, 0.00, 0.00, 0.00),
(534, 11, 133, 0.00, 0.00, 0.00, 0.00, 0.00),
(535, 11, 134, 0.00, 0.00, 0.00, 0.00, 0.00),
(536, 11, 135, 0.00, 0.00, 0.00, 0.00, 0.00),
(537, 11, 136, 0.00, 0.00, -0.50, 0.00, 0.50),
(538, 11, 137, 0.00, 0.00, 0.00, 0.00, 0.00),
(539, 11, 138, 0.00, 0.00, 0.00, 0.00, 0.00),
(540, 11, 139, 0.00, 0.00, 0.00, 0.00, 0.00),
(541, 11, 140, 0.00, 0.00, -0.50, 0.00, 0.50),
(542, 11, 141, 0.00, 0.00, 0.00, 0.00, 0.00),
(543, 11, 142, 0.00, 0.00, 0.00, 0.00, 0.00),
(544, 11, 143, 0.00, 0.00, 0.00, 0.00, 0.00),
(545, 11, 144, 0.00, 0.00, 0.00, 0.00, 0.00),
(546, 11, 145, 0.00, 0.00, 0.00, 0.00, 0.00),
(547, 11, 146, 0.00, 0.00, 0.00, 0.00, 0.00),
(548, 11, 147, 0.00, 0.00, 0.00, 0.00, 0.00),
(549, 11, 148, 0.00, 0.00, 0.00, 0.00, 0.00),
(550, 11, 149, 0.00, 0.00, 0.00, 0.00, 0.00),
(551, 11, 150, 0.00, 0.00, 0.00, 0.00, 0.00),
(552, 11, 151, 0.00, 0.00, 0.00, 0.00, 0.00),
(553, 11, 152, 0.00, 0.00, 0.00, 0.00, 0.00),
(554, 11, 153, 0.00, 0.00, 0.00, 0.00, 0.00),
(555, 11, 154, 0.00, 0.00, 0.00, 0.00, 0.00),
(556, 11, 155, 0.00, 0.00, 0.00, 0.00, 0.00),
(557, 11, 156, 0.00, 0.00, 0.00, 0.00, 0.00),
(558, 11, 157, 0.00, 0.00, 0.00, 0.00, 0.00),
(559, 11, 158, 0.00, 0.00, 0.00, 0.00, 0.00),
(560, 11, 159, 0.00, 0.00, 0.00, 0.00, 0.00),
(561, 11, 160, 0.00, 0.00, 0.00, 0.00, 0.00),
(562, 11, 161, 0.00, 0.00, 0.00, 0.00, 0.00),
(563, 11, 162, 0.00, 0.00, 0.00, 0.00, 0.00),
(564, 11, 163, 0.00, 0.00, 0.00, 0.00, 0.00),
(565, 11, 164, 0.00, 0.00, 0.00, 0.00, 0.00),
(566, 11, 165, 0.00, 0.00, 0.00, 0.00, 0.00),
(567, 11, 166, 0.00, 0.00, 0.00, 0.00, 0.00),
(568, 11, 167, 0.00, 0.00, 0.00, 0.00, 0.00),
(569, 11, 168, 0.00, 0.00, 0.00, 0.00, 0.00),
(570, 11, 169, 0.00, 0.00, 0.00, 0.00, 0.00),
(571, 11, 170, 0.00, 0.00, 0.00, 0.00, 0.00),
(572, 11, 171, 0.00, 0.00, 0.00, 0.00, 0.00),
(573, 11, 172, 0.00, 0.00, 0.00, 0.00, 0.00),
(574, 11, 173, 0.00, 0.00, 0.00, 0.00, 0.00),
(575, 12, 1, 0.00, 0.00, 0.00, 0.00, NULL),
(576, 12, 2, 0.00, 0.00, 0.00, 0.00, NULL),
(577, 12, 3, 0.00, 0.00, 0.00, 0.00, NULL),
(578, 12, 4, 0.00, 0.00, 0.00, 0.00, NULL),
(579, 12, 7, 0.00, 0.00, 0.00, 0.00, NULL),
(580, 12, 8, 0.00, 0.00, 0.00, 0.00, NULL),
(581, 12, 9, 0.00, 0.00, 0.00, 0.00, NULL),
(582, 12, 10, 0.00, 0.00, 0.00, 0.00, NULL),
(583, 12, 11, 0.00, 0.00, 0.00, 0.00, NULL),
(584, 12, 12, 0.00, 0.00, 0.00, 0.00, NULL),
(585, 12, 13, 0.00, 0.00, 0.00, 0.00, NULL),
(586, 12, 14, 0.00, 0.00, 0.00, 0.00, NULL),
(587, 12, 15, 0.00, 0.00, 0.00, 0.00, NULL),
(588, 12, 16, 40000.00, 0.00, 0.00, 0.00, NULL),
(589, 12, 17, 0.00, 0.00, 0.00, 0.00, NULL),
(590, 12, 18, 0.00, 0.00, 0.00, 0.00, NULL),
(591, 12, 19, 0.00, 0.00, 0.00, 0.00, NULL),
(592, 12, 20, 0.00, 0.00, 0.00, 0.00, NULL),
(593, 12, 21, 0.00, 0.00, 0.00, 0.00, NULL),
(594, 12, 22, 0.00, 0.00, 0.00, 0.00, NULL),
(595, 12, 23, 0.00, 0.00, 0.00, 0.00, NULL),
(596, 12, 24, 0.00, 0.00, 0.00, 0.00, NULL),
(597, 12, 25, 0.00, 0.00, 0.00, 0.00, NULL),
(598, 12, 26, 0.00, 0.00, 0.00, 0.00, NULL),
(599, 12, 27, 0.00, 0.00, 0.00, 0.00, NULL),
(600, 12, 28, 0.00, 0.00, 0.00, 0.00, NULL),
(601, 12, 29, 0.00, 0.00, 0.00, 0.00, NULL),
(602, 12, 30, 0.00, 0.00, 0.00, 0.00, NULL),
(603, 12, 31, 0.00, 0.00, 0.00, 0.00, NULL),
(604, 12, 32, 0.00, 0.00, 0.00, 0.00, NULL),
(605, 12, 33, 0.00, 0.00, 0.00, 0.00, NULL),
(606, 12, 34, 0.00, 0.00, 0.00, 0.00, NULL),
(607, 12, 35, 0.00, 0.00, 0.00, 0.00, NULL),
(608, 12, 36, 0.00, 0.00, 0.00, 0.00, NULL),
(609, 12, 37, 0.00, 0.00, 0.00, 0.00, NULL),
(610, 12, 38, 0.00, 0.00, 0.00, 0.00, NULL),
(611, 12, 39, 0.00, 0.00, 0.00, 0.00, NULL),
(612, 12, 40, 0.00, 0.00, 0.00, 0.00, NULL),
(613, 12, 41, 0.00, 0.00, 0.00, 0.00, NULL),
(614, 12, 42, 0.00, 0.00, 0.00, 0.00, NULL),
(615, 12, 43, 0.00, 0.00, 0.00, 0.00, NULL),
(616, 12, 44, 0.00, 0.00, 0.00, 0.00, NULL),
(617, 12, 45, 0.00, 0.00, 0.00, 0.00, NULL),
(618, 12, 46, 0.00, 0.00, 0.00, 0.00, NULL),
(619, 12, 47, 0.00, 0.00, 0.00, 0.00, NULL),
(620, 12, 48, 0.00, 0.00, 0.00, 0.00, NULL),
(621, 12, 49, 0.00, 0.00, 0.00, 0.00, NULL),
(622, 12, 50, 0.00, 0.00, 0.00, 0.00, NULL),
(623, 12, 51, 0.00, 0.00, 0.00, 0.00, NULL),
(624, 12, 52, 0.00, 0.00, 0.00, 0.00, NULL),
(625, 12, 53, 0.00, 0.00, 0.00, 0.00, NULL),
(626, 12, 54, 0.00, 0.00, 0.00, 0.00, NULL),
(627, 12, 55, 0.00, 0.00, 0.00, 0.00, NULL),
(628, 12, 56, 0.00, 0.00, 0.00, 0.00, NULL),
(629, 12, 57, 0.00, 0.00, 0.00, 0.00, NULL),
(630, 12, 59, 0.00, 0.00, 0.00, 0.00, NULL),
(631, 12, 60, 0.00, 0.00, 0.00, 0.00, NULL),
(632, 12, 61, 0.00, 0.00, 0.00, 0.00, NULL),
(633, 12, 62, 0.00, 0.00, 0.00, 0.00, NULL),
(634, 12, 63, 0.00, 0.00, 0.00, 0.00, NULL),
(635, 12, 64, 0.00, 0.00, 0.00, 0.00, NULL),
(636, 12, 65, 3000.00, 0.00, 0.00, 0.00, NULL),
(637, 12, 66, 0.00, 0.00, 0.00, 0.00, NULL),
(638, 12, 67, 0.00, 0.00, 0.00, 0.00, NULL),
(639, 12, 69, 0.00, 0.00, 0.00, 0.00, NULL),
(640, 12, 70, 0.00, 0.00, 0.00, 0.00, NULL),
(641, 12, 71, 0.00, 0.00, 0.00, 0.00, NULL),
(642, 12, 72, 80.00, 0.00, 0.00, 0.00, NULL),
(643, 12, 73, 0.00, 0.00, 0.00, 0.00, NULL),
(644, 12, 74, 0.00, 0.00, 0.00, 0.00, NULL),
(645, 12, 75, 0.00, 0.00, 0.00, 0.00, NULL),
(646, 12, 76, 0.00, 0.00, 0.00, 0.00, NULL),
(647, 12, 77, 0.00, 0.00, 0.00, 0.00, NULL),
(648, 12, 78, 0.00, 0.00, 0.00, 0.00, NULL),
(649, 12, 79, 0.00, 0.00, 0.00, 0.00, NULL),
(650, 12, 80, 0.00, 0.00, 0.00, 0.00, NULL),
(651, 12, 81, 0.00, 0.00, 0.00, 0.00, NULL),
(652, 12, 82, 0.00, 0.00, 0.00, 0.00, NULL),
(653, 12, 83, 0.00, 0.00, 0.00, 0.00, NULL),
(654, 12, 85, 0.00, 0.00, 0.00, 0.00, NULL),
(655, 12, 86, 0.00, 0.00, 0.00, 0.00, NULL),
(656, 12, 87, 0.00, 0.00, 0.00, 0.00, NULL),
(657, 12, 88, 0.00, 0.00, 0.00, 0.00, NULL),
(658, 12, 89, 0.00, 0.00, 0.00, 0.00, NULL),
(659, 12, 90, 0.00, 0.00, 0.00, 0.00, NULL),
(660, 12, 91, 0.00, 0.00, 0.00, 0.00, NULL),
(661, 12, 92, 0.00, 0.00, 0.00, 0.00, NULL),
(662, 12, 93, 0.00, 0.00, 0.00, 0.00, NULL),
(663, 12, 94, 0.00, 0.00, 0.00, 0.00, NULL),
(664, 12, 95, 0.00, 0.00, 0.00, 0.00, NULL),
(665, 12, 96, 0.00, 0.00, 0.00, 0.00, NULL),
(666, 12, 97, 0.00, 0.00, 0.00, 0.00, NULL),
(667, 12, 98, 0.00, 0.00, 0.00, 0.00, NULL),
(668, 12, 99, 0.00, 0.00, 0.00, 0.00, NULL),
(669, 12, 101, 0.00, 0.00, 0.00, 0.00, NULL),
(670, 12, 102, 0.00, 0.00, 0.00, 0.00, NULL),
(671, 12, 103, 0.00, 0.00, 0.00, 0.00, NULL),
(672, 12, 104, 0.00, 0.00, 0.00, 0.00, NULL),
(673, 12, 105, 0.00, 0.00, 0.00, 0.00, NULL),
(674, 12, 106, 0.00, 0.00, 0.00, 0.00, NULL),
(675, 12, 107, 0.00, 0.00, 0.00, 0.00, NULL),
(676, 12, 108, 0.00, 0.00, 0.00, 0.00, NULL),
(677, 12, 109, 0.00, 0.00, 0.00, 0.00, NULL),
(678, 12, 110, 0.00, 0.00, 0.00, 0.00, NULL),
(679, 12, 111, 0.00, 0.00, 0.00, 0.00, NULL),
(680, 12, 112, 0.00, 0.00, 0.00, 0.00, NULL),
(681, 12, 113, 0.00, 0.00, 0.00, 0.00, NULL),
(682, 12, 114, 0.00, 0.00, 0.00, 0.00, NULL),
(683, 12, 115, 0.00, 0.00, 0.00, 0.00, NULL),
(684, 12, 116, 0.00, 0.00, 0.00, 0.00, NULL),
(685, 12, 117, 0.00, 0.00, 0.00, 0.00, NULL),
(686, 12, 118, 0.00, 0.00, 0.00, 0.00, NULL),
(687, 12, 119, 0.00, 0.00, 0.00, 0.00, NULL),
(688, 12, 120, 0.00, 0.00, 0.00, 0.00, NULL),
(689, 12, 121, 0.00, 0.00, 0.00, 0.00, NULL),
(690, 12, 122, 0.00, 0.00, 0.00, 0.00, NULL),
(691, 12, 123, 0.00, 0.00, 0.00, 0.00, NULL),
(692, 12, 124, 0.00, 0.00, 0.00, 0.00, NULL),
(693, 12, 125, 0.00, 0.00, 0.00, 0.00, NULL),
(694, 12, 126, 0.00, 0.00, 0.00, 0.00, NULL),
(695, 12, 127, 0.00, 0.00, 0.00, 0.00, NULL),
(696, 12, 128, 0.00, 0.00, 0.00, 0.00, NULL),
(697, 12, 129, 0.00, 0.00, 0.00, 0.00, NULL),
(698, 12, 130, 0.00, 0.00, 0.00, 0.00, NULL),
(699, 12, 131, 0.00, 0.00, 0.00, 0.00, NULL),
(700, 12, 132, 0.00, 0.00, 0.00, 0.00, NULL),
(701, 12, 133, 0.00, 0.00, 0.00, 0.00, NULL),
(702, 12, 134, 0.00, 0.00, 0.00, 0.00, NULL),
(703, 12, 135, 0.00, 0.00, 0.00, 0.00, NULL),
(704, 12, 136, 0.50, 0.00, 0.00, 0.00, NULL),
(705, 12, 137, 0.00, 0.00, 0.00, 0.00, NULL),
(706, 12, 138, 0.00, 0.00, 0.00, 0.00, NULL),
(707, 12, 139, 0.00, 0.00, 0.00, 0.00, NULL),
(708, 12, 140, 0.50, 0.00, 0.00, 0.00, NULL),
(709, 12, 141, 0.00, 0.00, 0.00, 0.00, NULL),
(710, 12, 142, 0.00, 0.00, 0.00, 0.00, NULL),
(711, 12, 143, 0.00, 0.00, 0.00, 0.00, NULL),
(712, 12, 144, 0.00, 0.00, 0.00, 0.00, NULL),
(713, 12, 145, 0.00, 0.00, 0.00, 0.00, NULL),
(714, 12, 146, 0.00, 0.00, 0.00, 0.00, NULL),
(715, 12, 147, 0.00, 0.00, 0.00, 0.00, NULL),
(716, 12, 148, 0.00, 0.00, 0.00, 0.00, NULL),
(717, 12, 149, 0.00, 0.00, 0.00, 0.00, NULL),
(718, 12, 150, 0.00, 0.00, 0.00, 0.00, NULL),
(719, 12, 151, 0.00, 0.00, 0.00, 0.00, NULL),
(720, 12, 152, 0.00, 0.00, 0.00, 0.00, NULL),
(721, 12, 153, 0.00, 0.00, 0.00, 0.00, NULL),
(722, 12, 154, 0.00, 0.00, 0.00, 0.00, NULL),
(723, 12, 155, 0.00, 0.00, 0.00, 0.00, NULL),
(724, 12, 156, 0.00, 0.00, 0.00, 0.00, NULL),
(725, 12, 157, 0.00, 0.00, 0.00, 0.00, NULL),
(726, 12, 158, 0.00, 0.00, 0.00, 0.00, NULL),
(727, 12, 159, 0.00, 0.00, 0.00, 0.00, NULL),
(728, 12, 160, 0.00, 0.00, 0.00, 0.00, NULL),
(729, 12, 161, 0.00, 0.00, 0.00, 0.00, NULL),
(730, 12, 162, 0.00, 0.00, 0.00, 0.00, NULL),
(731, 12, 163, 0.00, 0.00, 0.00, 0.00, NULL),
(732, 12, 164, 0.00, 0.00, 0.00, 0.00, NULL),
(733, 12, 165, 0.00, 0.00, 0.00, 0.00, NULL),
(734, 12, 166, 0.00, 0.00, 0.00, 0.00, NULL),
(735, 12, 167, 0.00, 0.00, 0.00, 0.00, NULL),
(736, 12, 168, 0.00, 0.00, 0.00, 0.00, NULL),
(737, 12, 169, 0.00, 0.00, 0.00, 0.00, NULL),
(738, 12, 170, 0.00, 0.00, 0.00, 0.00, NULL),
(739, 12, 171, 0.00, 0.00, 0.00, 0.00, NULL),
(740, 12, 172, 0.00, 0.00, 0.00, 0.00, NULL),
(741, 12, 173, 0.00, 0.00, 0.00, 0.00, NULL);

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
(15, NULL, 1, '2025-09-17 22:44:49', NULL, 'pendiente', 'da8568fc0a77f206750d491dee1000a7'),
(16, NULL, 1, '2025-09-17 22:45:21', NULL, 'pendiente', '3fd4f355a33f96b8766a30f7f0462bfa'),
(17, NULL, 1, '2025-09-17 23:27:48', NULL, 'pendiente', 'a357371467689079d141472230d979e8'),
(18, NULL, 1, '2025-09-18 13:43:27', NULL, 'pendiente', '907b09f6fc6fd7b1b3974e9aef4309f2'),
(19, NULL, 1, '2025-09-18 14:10:50', NULL, 'pendiente', '71bb223e5c63d472cfe242151c375fc4'),
(20, NULL, 1, '2025-09-18 14:27:20', NULL, 'pendiente', '6f619c2fb321dafe5615cd9ea63107ff'),
(22, NULL, 1, '2025-09-18 14:28:42', NULL, 'pendiente', 'b1566d2d82d0b8ab9887da30dc87db1b'),
(23, NULL, 1, '2025-09-18 14:31:27', NULL, 'pendiente', '67d3704c31187498186ffac0cb29c9b2'),
(25, NULL, 1, '2025-09-18 14:37:58', NULL, 'pendiente', 'a8decbe9053be5df999edaf130fbb1c9'),
(26, NULL, 1, '2025-09-18 16:13:55', NULL, 'pendiente', '3c1906ad9cdfd4a9b3b1f33ccda75f09'),
(27, NULL, 1, '2025-09-18 16:18:12', NULL, 'pendiente', 'a9d32c1596c0d1042e37d2a3197a83c2'),
(28, NULL, 1, '2025-09-18 18:21:04', NULL, 'pendiente', '387e70779d36050f13c3286f4a0064c3'),
(29, NULL, 1, '2025-09-18 18:23:02', NULL, 'pendiente', 'a1b09e98868128bcdb98bf7cf8690bcf'),
(30, NULL, 1, '2025-09-18 21:43:23', NULL, 'pendiente', '59c2709cc700b049df5a9b9180b9425f'),
(31, NULL, 1, '2025-09-19 20:54:49', NULL, 'pendiente', '216b75837353c3e99906e8ed82b6e476');

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
(33, 30, 1, 5000.00, 'gramos', 0.00),
(34, 30, 10, 1200.00, 'gramos', 0.00),
(35, 30, 40, 800.00, 'gramos', 0.00),
(36, 30, 72, 75.00, 'pieza', 0.00),
(37, 31, 1, 4000.00, 'gramos', 0.00),
(38, 31, 10, 1000.00, 'gramos', 0.00),
(39, 31, 40, 1700.00, 'gramos', 0.00);

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
  `cantidad_actual` decimal(10,2) NOT NULL,
  `credito` tinyint(1) DEFAULT NULL,
  `pagado` tinyint(1) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `entradas_insumos`
--

INSERT INTO `entradas_insumos` (`id`, `insumo_id`, `proveedor_id`, `usuario_id`, `fecha`, `descripcion`, `cantidad`, `unidad`, `costo_total`, `referencia_doc`, `folio_fiscal`, `qr`, `cantidad_actual`, `credito`, `pagado`) VALUES
(56, 1, 14, 1, '2025-09-18 21:26:23', '', 5000.00, 'gramos', 150.00, '', '', 'archivos/qr/entrada_insumo_56.png', 0.00, NULL, NULL),
(57, 40, 14, 1, '2025-09-18 21:26:23', '', 500.00, 'gramos', 200.00, '', '', 'archivos/qr/entrada_insumo_57.png', 0.00, NULL, NULL),
(58, 10, 14, 1, '2025-09-18 21:26:23', '', 500.00, 'gramos', 150.00, '', '', 'archivos/qr/entrada_insumo_58.png', 0.00, NULL, NULL),
(59, 1, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 50.00, '', '', 'archivos/qr/entrada_insumo_59.png', 0.00, NULL, NULL),
(60, 10, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_60.png', 0.00, NULL, NULL),
(61, 40, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_61.png', 0.00, NULL, NULL),
(62, 1, 11, 1, '2025-09-18 21:30:48', '', 3000.00, 'gramos', 80.00, '', '', 'archivos/qr/entrada_insumo_62.png', 0.00, NULL, NULL),
(63, 40, 11, 1, '2025-09-18 21:30:48', '', 1000.00, 'gramos', 350.00, '', '', 'archivos/qr/entrada_insumo_63.png', 0.00, NULL, NULL),
(64, 10, 11, 1, '2025-09-18 21:30:48', '', 500.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_64.png', 0.00, NULL, NULL),
(65, 72, 16, 1, '2025-09-18 21:35:35', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_65.png', 5.00, NULL, NULL),
(66, 72, 16, 1, '2025-09-18 21:36:17', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_66.png', 25.00, NULL, NULL),
(67, 72, 16, 1, '2025-09-18 21:36:37', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_67.png', 50.00, NULL, NULL),
(68, 65, 13, 1, '2025-09-19 20:46:20', '', 3000.00, 'gramos', 40.00, '', '', 'archivos/qr/entrada_insumo_68.png', 3000.00, NULL, NULL),
(69, 140, 8, 1, '2025-09-19 20:47:11', '', 1.00, 'bulto', 80.00, '', '', 'archivos/qr/entrada_insumo_69.png', 0.50, NULL, NULL),
(70, 136, 8, 1, '2025-09-19 20:47:11', '', 1.00, 'paquete', 80.00, '', '', 'archivos/qr/entrada_insumo_70.png', 0.50, NULL, NULL),
(71, 16, 14, 1, '2025-09-19 21:18:44', '', 40000.00, 'gramos', 70.00, '', '', 'archivos/qr/entrada_insumo_71.png', 40000.00, NULL, NULL),
(72, 1, 10, 1, '2025-09-26 14:27:44', '', 99999.00, 'gramos', 90.00, '', '', 'archivos/qr/entrada_insumo_72.png', 99999.00, 0, NULL),
(73, 89, 10, 1, '2025-09-26 14:27:44', '', 99999.00, 'gramos', 99.00, '', '', 'archivos/qr/entrada_insumo_73.png', 99999.00, 0, NULL);

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
(1, 'Arroz', 'gramos', 99999.00, 'por_receta', 'ins_68717301313ad.jpg', 0.00),
(2, 'Alga', 'piezas', 0.00, 'por_receta', 'ins_6871716a72681.jpg', 0.00),
(3, 'Salmón fresco', 'gramos', 0.00, 'por_receta', 'ins_6871777fa2c56.png', 0.00),
(4, 'Refresco en lata', 'piezas', 0.00, 'unidad_completa', 'ins_6871731d075cb.webp', 0.00),
(7, 'Surimi', 'gramos', 0.00, 'uso_general', 'ins_688a521dcd583.jpg', 0.00),
(8, 'Tocino', 'gramos', 0.00, 'uso_general', 'ins_688a4dc84c002.jpg', 0.00),
(9, 'Pollo', 'gramos', 0.00, 'desempaquetado', 'ins_688a4e4bd5999.jpg', 0.00),
(10, 'Camarón', 'gramos', 0.00, 'desempaquetado', 'ins_688a4f5c873c6.jpg', 0.00),
(11, 'Queso Chihuahua', 'gramos', 0.00, 'unidad_completa', 'ins_688a4feca9865.jpg', 0.00),
(12, 'Philadelphia', 'gramos', 0.00, 'uso_general', 'ins_688a504f9cb40.jpg', 0.00),
(13, 'Arroz blanco', 'gramos', 0.00, 'por_receta', 'ins_689f82d674c65.jpg', 0.00),
(14, 'Carne', 'gramos', 0.00, 'uso_general', 'ins_688a528d1261a.jpg', 0.00),
(15, 'Queso Amarillo', 'piezas', 0.00, 'uso_general', 'ins_688a53246c1c2.jpg', 0.00),
(16, 'Ajonjolí', 'gramos', 40000.00, 'uso_general', 'ins_689f824a23343.jpg', 0.00),
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
(65, 'Limón', 'gramos', 3000.00, 'por_receta', 'ins_68add890ee640.jpg', 0.00),
(66, 'Queso Mix', 'gramos', 0.00, 'uso_general', 'ins_68ade1625f489.jpg', 0.00),
(67, 'Morrón', 'gramos', 0.00, 'por_receta', 'ins_68addcbc6d15a.jpg', 0.00),
(69, 'Pasta chukasoba', 'gramos', 0.00, 'por_receta', 'ins_68addd277fde6.jpg', 0.00),
(70, 'Pasta frita', 'gramos', 0.00, 'por_receta', 'ins_68addd91a005e.jpg', 0.00),
(71, 'Queso crema', 'gramos', 0.00, 'uso_general', 'ins_68ade11cdadcb.jpg', 0.00),
(72, 'Refresco embotellado', 'pieza', 80.00, 'unidad_completa', 'ins_68adfdd53f04e.jpg', 0.00),
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
(89, 'Aderezo', 'gramos', 99999.00, 'uso_general', 'ins_68adcc0771a3c.jpg', 0.00),
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
(136, 'Bolsa papel x 100pz', 'paquete', 0.50, 'unidad_completa', '', 0.00),
(137, 'rollo impresora mediano', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(138, 'rollo impresora grande', 'rollo', 0.00, 'unidad_completa', '', 0.00),
(139, 'tenedor fantasy mediano 25pz', 'paquete', 0.00, 'unidad_completa', '', 0.00),
(140, 'Bolsa basura 90x120 negra', 'bulto', 0.50, 'unidad_completa', '', 0.00),
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
(29, 1, 'bodega', 'Generacion QR', '2025-09-18 21:43:23', 31),
(30, 1, 'bodega', 'Devolucion QR', '2025-09-18 23:15:06', 31),
(31, 1, 'bodega', 'Generacion QR', '2025-09-19 20:54:49', 32);

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
  `tipo` enum('entrada','salida','ajuste','traspaso','merma','devolucion') DEFAULT 'entrada',
  `usuario_id` int(11) DEFAULT NULL,
  `usuario_destino_id` int(11) DEFAULT NULL,
  `insumo_id` int(11) DEFAULT NULL,
  `id_entrada` int(11) DEFAULT NULL,
  `cantidad` decimal(10,2) DEFAULT NULL,
  `observacion` text DEFAULT NULL,
  `fecha` datetime DEFAULT current_timestamp(),
  `qr_token` varchar(64) DEFAULT NULL,
  `id_qr` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `movimientos_insumos`
--

INSERT INTO `movimientos_insumos` (`id`, `tipo`, `usuario_id`, `usuario_destino_id`, `insumo_id`, `id_entrada`, `cantidad`, `observacion`, `fecha`, `qr_token`, `id_qr`) VALUES
(111, 'traspaso', 1, NULL, 1, 56, -5000.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(112, 'traspaso', 1, NULL, 10, 58, -500.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(113, 'traspaso', 1, NULL, 10, 60, -700.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(114, 'traspaso', 1, NULL, 40, 57, -500.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(115, 'traspaso', 1, NULL, 40, 61, -300.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(116, 'traspaso', 1, NULL, 72, 65, -50.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(117, 'traspaso', 1, NULL, 72, 66, -25.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31),
(118, 'devolucion', 1, NULL, 10, 58, 200.00, 'refresco golpeado camaron extra', '2025-09-18 23:15:06', '59c2709cc700b049df5a9b9180b9425f', 31),
(119, 'devolucion', 1, NULL, 72, 65, 5.00, 'refresco golpeado camaron extra', '2025-09-18 23:15:06', '59c2709cc700b049df5a9b9180b9425f', 31),
(120, 'salida', 1, NULL, 140, 69, -0.50, 'Retiro de entrada #69 (0.5 bulto)', '2025-09-20 04:49:22', '185ab598af58ba225da659d014194b4e', NULL),
(121, 'salida', 1, NULL, 136, 70, -0.50, 'Retiro de entrada #70 (0.5 paquete)', '2025-09-20 04:50:22', 'fdb782bb3b6d2a4e8b5b0a2385c44fb1', NULL),
(122, 'traspaso', 1, NULL, 1, 59, -1000.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(123, 'traspaso', 1, NULL, 1, 62, -3000.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(124, 'traspaso', 1, NULL, 10, 58, -200.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(125, 'traspaso', 1, NULL, 10, 60, -300.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(126, 'traspaso', 1, NULL, 10, 64, -500.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(127, 'traspaso', 1, NULL, 40, 61, -700.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32),
(128, 'traspaso', 1, NULL, 40, 63, -1000.00, 'Enviado por QR a sucursal', '2025-09-19 20:54:49', '216b75837353c3e99906e8ed82b6e476', 32);

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
(1, 'Suministros Sushi MX', NULL, NULL, NULL, NULL, '555-123-4567', NULL, NULL, 'Calle Soya #123, CDMX', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, NULL, 1, '2025-09-22 08:36:48', '2025-09-22 08:36:48'),
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
  `pdf_recepcion` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `qrs_insumo`
--

INSERT INTO `qrs_insumo` (`id`, `token`, `json_data`, `estado`, `creado_por`, `creado_en`, `expiracion`, `pdf_envio`, `pdf_recepcion`) VALUES
(31, '59c2709cc700b049df5a9b9180b9425f', '[{\"id\":1,\"nombre\":\"Arroz\",\"unidad\":\"gramos\",\"cantidad\":5000,\"precio_unitario\":0},{\"id\":10,\"nombre\":\"Camarón\",\"unidad\":\"gramos\",\"cantidad\":1200,\"precio_unitario\":0},{\"id\":40,\"nombre\":\"Atún fresco\",\"unidad\":\"gramos\",\"cantidad\":800,\"precio_unitario\":0},{\"id\":72,\"nombre\":\"Refresco embotellado\",\"unidad\":\"pieza\",\"cantidad\":75,\"precio_unitario\":0}]', 'pendiente', 1, '2025-09-18 21:43:23', NULL, 'archivos/bodega/pdfs/qr_59c2709cc700b049df5a9b9180b9425f.pdf', 'archivos/bodega/pdfs/recepcion_59c2709cc700b049df5a9b9180b9425f.pdf'),
(32, '216b75837353c3e99906e8ed82b6e476', '[{\"id\":1,\"nombre\":\"Arroz\",\"unidad\":\"gramos\",\"cantidad\":4000,\"precio_unitario\":0},{\"id\":10,\"nombre\":\"Camarón\",\"unidad\":\"gramos\",\"cantidad\":1000,\"precio_unitario\":0},{\"id\":40,\"nombre\":\"Atún fresco\",\"unidad\":\"gramos\",\"cantidad\":1700,\"precio_unitario\":0}]', 'pendiente', 1, '2025-09-19 20:54:49', NULL, 'archivos/bodega/pdfs/qr_216b75837353c3e99906e8ed82b6e476.pdf', NULL);

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

--
-- Volcado de datos para la tabla `recepciones_log`
--

INSERT INTO `recepciones_log` (`id`, `sucursal_id`, `qr_token`, `fecha_recepcion`, `usuario_id`, `json_recibido`, `estado`) VALUES
(1, NULL, '59c2709cc700b049df5a9b9180b9425f', '2025-09-18 23:15:06', 1, '{\"modo\":\"parcial\",\"items\":[{\"insumo_id\":10,\"cantidad\":200},{\"insumo_id\":72,\"cantidad\":5}],\"observacion\":\"refresco golpeado camaron extra\",\"devueltos\":{\"10\":200,\"72\":5}}', '');

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
(26, 'Cocina', '/vistas/cocina/cocina2.php', 'link', NULL, 4),
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
(82, 1, 39);

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
  ADD KEY `insumo_id` (`insumo_id`),
  ADD KEY `idx_mi_id_entrada` (`id_entrada`),
  ADD KEY `idx_mi_id_qr` (`id_qr`);

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=742;

--
-- AUTO_INCREMENT de la tabla `despachos`
--
ALTER TABLE `despachos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

--
-- AUTO_INCREMENT de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=40;

--
-- AUTO_INCREMENT de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=74;

--
-- AUTO_INCREMENT de la tabla `insumos`
--
ALTER TABLE `insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=174;

--
-- AUTO_INCREMENT de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

--
-- AUTO_INCREMENT de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=129;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=33;

--
-- AUTO_INCREMENT de la tabla `reabasto_alertas`
--
ALTER TABLE `reabasto_alertas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `recepciones_log`
--
ALTER TABLE `recepciones_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=83;

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
  ADD CONSTRAINT `fk_mi_id_entrada` FOREIGN KEY (`id_entrada`) REFERENCES `entradas_insumos` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mi_qr` FOREIGN KEY (`id_qr`) REFERENCES `qrs_insumo` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
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
