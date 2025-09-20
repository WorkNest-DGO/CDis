-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 19-09-2025 a las 06:41:30
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
(11, '2025-09-16 10:48:12', NULL, 1, NULL, NULL);

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
(408, 11, 1, 25750.00, 0.00, 0.00, 0.00, NULL),
(409, 11, 2, 29988.50, 0.00, 0.00, 0.00, NULL),
(410, 11, 3, 30000.00, 0.00, 0.00, 0.00, NULL),
(411, 11, 4, 29999.00, 0.00, 0.00, 0.00, NULL),
(412, 11, 7, 30000.00, 0.00, 0.00, 0.00, NULL),
(413, 11, 8, 29650.00, 0.00, 0.00, 0.00, NULL),
(414, 11, 9, 29970.00, 0.00, 0.00, 0.00, NULL),
(415, 11, 10, 29910.00, 0.00, 0.00, 0.00, NULL),
(416, 11, 11, 30000.00, 0.00, 0.00, 0.00, NULL),
(417, 11, 12, 29390.00, 0.00, 0.00, 0.00, NULL),
(418, 11, 13, 30000.00, 0.00, 0.00, 0.00, NULL),
(419, 11, 14, 29820.00, 0.00, 0.00, 0.00, NULL),
(420, 11, 15, 29998.00, 0.00, 0.00, 0.00, NULL),
(421, 11, 16, 29994.00, 0.00, 0.00, 0.00, NULL),
(422, 11, 17, 30000.00, 0.00, 0.00, 0.00, NULL),
(423, 11, 18, 30000.00, 0.00, 0.00, 0.00, NULL),
(424, 11, 19, 30000.00, 0.00, 0.00, 0.00, NULL),
(425, 11, 20, 30000.00, 0.00, 0.00, 0.00, NULL),
(426, 11, 21, 29975.00, 0.00, 0.00, 0.00, NULL),
(427, 11, 22, 30000.00, 0.00, 0.00, 0.00, NULL),
(428, 11, 23, 29990.00, 0.00, 0.00, 0.00, NULL),
(429, 11, 24, 29400.00, 0.00, 0.00, 0.00, NULL),
(430, 11, 25, 30000.00, 0.00, 0.00, 0.00, NULL),
(431, 11, 26, 30000.00, 0.00, 0.00, 0.00, NULL),
(432, 11, 27, 30000.00, 0.00, 0.00, 0.00, NULL),
(433, 11, 28, 30000.00, 0.00, 0.00, 0.00, NULL),
(434, 11, 29, 30000.00, 0.00, 0.00, 0.00, NULL),
(435, 11, 30, 30000.00, 0.00, 0.00, 0.00, NULL),
(436, 11, 31, 30000.00, 0.00, 0.00, 0.00, NULL),
(437, 11, 32, 30000.00, 0.00, 0.00, 0.00, NULL),
(438, 11, 33, 29870.00, 0.00, 0.00, 0.00, NULL),
(439, 11, 34, 30000.00, 0.00, 0.00, 0.00, NULL),
(440, 11, 35, 30000.00, 0.00, 0.00, 0.00, NULL),
(441, 11, 36, 29260.00, 0.00, 0.00, 0.00, NULL),
(442, 11, 37, 30000.00, 0.00, 0.00, 0.00, NULL),
(443, 11, 38, 30000.00, 0.00, 0.00, 0.00, NULL),
(444, 11, 39, 30000.00, 0.00, 0.00, 0.00, NULL),
(445, 11, 40, 30000.00, 0.00, 0.00, 0.00, NULL),
(446, 11, 41, 30000.00, 0.00, 0.00, 0.00, NULL),
(447, 11, 42, 30000.00, 0.00, 0.00, 0.00, NULL),
(448, 11, 43, 30000.00, 0.00, 0.00, 0.00, NULL),
(449, 11, 44, 30000.00, 0.00, 0.00, 0.00, NULL),
(450, 11, 45, 29970.00, 0.00, 0.00, 0.00, NULL),
(451, 11, 46, 29970.00, 0.00, 0.00, 0.00, NULL),
(452, 11, 47, 30000.00, 0.00, 0.00, 0.00, NULL),
(453, 11, 48, 29940.00, 0.00, 0.00, 0.00, NULL),
(454, 11, 49, 30000.00, 0.00, 0.00, 0.00, NULL),
(455, 11, 50, 30000.00, 0.00, 0.00, 0.00, NULL),
(456, 11, 51, 30000.00, 0.00, 0.00, 0.00, NULL),
(457, 11, 52, 30000.00, 0.00, 0.00, 0.00, NULL),
(458, 11, 53, 30000.00, 0.00, 0.00, 0.00, NULL),
(459, 11, 54, 30000.00, 0.00, 0.00, 0.00, NULL),
(460, 11, 55, 30000.00, 0.00, 0.00, 0.00, NULL),
(461, 11, 56, 30000.00, 0.00, 0.00, 0.00, NULL),
(462, 11, 57, 30000.00, 0.00, 0.00, 0.00, NULL),
(463, 11, 59, 30000.00, 0.00, 0.00, 0.00, NULL),
(464, 11, 60, 30000.00, 0.00, 0.00, 0.00, NULL),
(465, 11, 61, 29880.00, 0.00, 0.00, 0.00, NULL),
(466, 11, 62, 30000.00, 0.00, 0.00, 0.00, NULL),
(467, 11, 63, 29990.00, 0.00, 0.00, 0.00, NULL),
(468, 11, 64, 30000.00, 0.00, 0.00, 0.00, NULL),
(469, 11, 65, 30000.00, 0.00, 0.00, 0.00, NULL),
(470, 11, 66, 29360.00, 0.00, 0.00, 0.00, NULL),
(471, 11, 67, 30000.00, 0.00, 0.00, 0.00, NULL),
(472, 11, 69, 30000.00, 0.00, 0.00, 0.00, NULL),
(473, 11, 70, 30000.00, 0.00, 0.00, 0.00, NULL),
(474, 11, 71, 30000.00, 0.00, 0.00, 0.00, NULL),
(475, 11, 72, 29987.00, 0.00, 0.00, 0.00, NULL),
(476, 11, 73, 30000.00, 0.00, 0.00, 0.00, NULL),
(477, 11, 74, 30000.00, 0.00, 0.00, 0.00, NULL),
(478, 11, 75, 30000.00, 0.00, 0.00, 0.00, NULL),
(479, 11, 76, 30000.00, 0.00, 0.00, 0.00, NULL),
(480, 11, 77, 30000.00, 0.00, 0.00, 0.00, NULL),
(481, 11, 78, 29980.00, 0.00, 0.00, 0.00, NULL),
(482, 11, 79, 30000.00, 0.00, 0.00, 0.00, NULL),
(483, 11, 80, 29970.00, 0.00, 0.00, 0.00, NULL),
(484, 11, 81, 29970.00, 0.00, 0.00, 0.00, NULL),
(485, 11, 82, 30000.00, 0.00, 0.00, 0.00, NULL),
(486, 11, 83, 30000.00, 0.00, 0.00, 0.00, NULL),
(487, 11, 85, 30000.00, 0.00, 0.00, 0.00, NULL),
(488, 11, 86, 30000.00, 0.00, 0.00, 0.00, NULL),
(489, 11, 87, 29620.00, 0.00, 0.00, 0.00, NULL),
(490, 11, 88, 30000.00, 0.00, 0.00, 0.00, NULL),
(491, 11, 89, 30000.00, 0.00, 0.00, 0.00, NULL),
(492, 11, 90, 29285.00, 0.00, 0.00, 0.00, NULL),
(493, 11, 91, 30000.00, 0.00, 0.00, 0.00, NULL),
(494, 11, 92, 30000.00, 0.00, 0.00, 0.00, NULL),
(495, 11, 93, 30000.00, 0.00, 0.00, 0.00, NULL),
(496, 11, 94, 29880.00, 0.00, 0.00, 0.00, NULL),
(497, 11, 95, 30000.00, 0.00, 0.00, 0.00, NULL),
(498, 11, 96, 30000.00, 0.00, 0.00, 0.00, NULL),
(499, 11, 97, 30000.00, 0.00, 0.00, 0.00, NULL),
(500, 11, 98, 30000.00, 0.00, 0.00, 0.00, NULL),
(501, 11, 99, 29990.00, 0.00, 0.00, 0.00, NULL),
(502, 11, 101, 30000.00, 0.00, 0.00, 0.00, NULL),
(503, 11, 102, 30000.00, 0.00, 0.00, 0.00, NULL),
(504, 11, 103, 30000.00, 0.00, 0.00, 0.00, NULL),
(505, 11, 104, 29996.00, 0.00, 0.00, 0.00, NULL),
(506, 11, 105, 30000.00, 0.00, 0.00, 0.00, NULL),
(507, 11, 106, 30000.00, 0.00, 0.00, 0.00, NULL),
(508, 11, 107, 30000.00, 0.00, 0.00, 0.00, NULL),
(509, 11, 108, 30000.00, 0.00, 0.00, 0.00, NULL),
(510, 11, 109, 30000.00, 0.00, 0.00, 0.00, NULL),
(511, 11, 110, 30000.00, 0.00, 0.00, 0.00, NULL),
(512, 11, 111, 30000.00, 0.00, 0.00, 0.00, NULL),
(513, 11, 112, 30000.00, 0.00, 0.00, 0.00, NULL),
(514, 11, 113, 30000.00, 0.00, 0.00, 0.00, NULL),
(515, 11, 114, 30000.00, 0.00, 0.00, 0.00, NULL),
(516, 11, 115, 30000.00, 0.00, 0.00, 0.00, NULL),
(517, 11, 116, 30000.00, 0.00, 0.00, 0.00, NULL),
(518, 11, 117, 30000.00, 0.00, 0.00, 0.00, NULL),
(519, 11, 118, 30000.00, 0.00, 0.00, 0.00, NULL),
(520, 11, 119, 30000.00, 0.00, 0.00, 0.00, NULL),
(521, 11, 120, 0.00, 0.00, 0.00, 0.00, NULL),
(522, 11, 121, 0.00, 0.00, 0.00, 0.00, NULL),
(523, 11, 122, 0.00, 0.00, 0.00, 0.00, NULL),
(524, 11, 123, 0.00, 0.00, 0.00, 0.00, NULL),
(525, 11, 124, 0.00, 0.00, 0.00, 0.00, NULL),
(526, 11, 125, 0.00, 0.00, 0.00, 0.00, NULL),
(527, 11, 126, 0.00, 0.00, 0.00, 0.00, NULL),
(528, 11, 127, 0.00, 0.00, 0.00, 0.00, NULL),
(529, 11, 128, 0.00, 0.00, 0.00, 0.00, NULL),
(530, 11, 129, 0.00, 0.00, 0.00, 0.00, NULL),
(531, 11, 130, 0.00, 0.00, 0.00, 0.00, NULL),
(532, 11, 131, 0.00, 0.00, 0.00, 0.00, NULL),
(533, 11, 132, 0.00, 0.00, 0.00, 0.00, NULL),
(534, 11, 133, 0.00, 0.00, 0.00, 0.00, NULL),
(535, 11, 134, 0.00, 0.00, 0.00, 0.00, NULL),
(536, 11, 135, 0.00, 0.00, 0.00, 0.00, NULL),
(537, 11, 136, 0.00, 0.00, 0.00, 0.00, NULL),
(538, 11, 137, 0.00, 0.00, 0.00, 0.00, NULL),
(539, 11, 138, 0.00, 0.00, 0.00, 0.00, NULL),
(540, 11, 139, 0.00, 0.00, 0.00, 0.00, NULL),
(541, 11, 140, 0.00, 0.00, 0.00, 0.00, NULL),
(542, 11, 141, 0.00, 0.00, 0.00, 0.00, NULL),
(543, 11, 142, 0.00, 0.00, 0.00, 0.00, NULL),
(544, 11, 143, 0.00, 0.00, 0.00, 0.00, NULL),
(545, 11, 144, 0.00, 0.00, 0.00, 0.00, NULL),
(546, 11, 145, 0.00, 0.00, 0.00, 0.00, NULL),
(547, 11, 146, 0.00, 0.00, 0.00, 0.00, NULL),
(548, 11, 147, 0.00, 0.00, 0.00, 0.00, NULL),
(549, 11, 148, 0.00, 0.00, 0.00, 0.00, NULL),
(550, 11, 149, 0.00, 0.00, 0.00, 0.00, NULL),
(551, 11, 150, 0.00, 0.00, 0.00, 0.00, NULL),
(552, 11, 151, 0.00, 0.00, 0.00, 0.00, NULL),
(553, 11, 152, 0.00, 0.00, 0.00, 0.00, NULL),
(554, 11, 153, 0.00, 0.00, 0.00, 0.00, NULL),
(555, 11, 154, 0.00, 0.00, 0.00, 0.00, NULL),
(556, 11, 155, 0.00, 0.00, 0.00, 0.00, NULL),
(557, 11, 156, 0.00, 0.00, 0.00, 0.00, NULL),
(558, 11, 157, 0.00, 0.00, 0.00, 0.00, NULL),
(559, 11, 158, 0.00, 0.00, 0.00, 0.00, NULL),
(560, 11, 159, 0.00, 0.00, 0.00, 0.00, NULL),
(561, 11, 160, 0.00, 0.00, 0.00, 0.00, NULL),
(562, 11, 161, 0.00, 0.00, 0.00, 0.00, NULL),
(563, 11, 162, 0.00, 0.00, 0.00, 0.00, NULL),
(564, 11, 163, 0.00, 0.00, 0.00, 0.00, NULL),
(565, 11, 164, 0.00, 0.00, 0.00, 0.00, NULL),
(566, 11, 165, 0.00, 0.00, 0.00, 0.00, NULL),
(567, 11, 166, 0.00, 0.00, 0.00, 0.00, NULL),
(568, 11, 167, 0.00, 0.00, 0.00, 0.00, NULL),
(569, 11, 168, 0.00, 0.00, 0.00, 0.00, NULL),
(570, 11, 169, 0.00, 0.00, 0.00, 0.00, NULL),
(571, 11, 170, 0.00, 0.00, 0.00, 0.00, NULL),
(572, 11, 171, 0.00, 0.00, 0.00, 0.00, NULL),
(573, 11, 172, 0.00, 0.00, 0.00, 0.00, NULL),
(574, 11, 173, 0.00, 0.00, 0.00, 0.00, NULL);

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
(30, NULL, 1, '2025-09-18 21:43:23', NULL, 'pendiente', '59c2709cc700b049df5a9b9180b9425f');

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
(36, 30, 72, 75.00, 'pieza', 0.00);

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
(56, 1, 14, 1, '2025-09-18 21:26:23', '', 5000.00, 'gramos', 150.00, '', '', 'archivos/qr/entrada_insumo_56.png', 0.00),
(57, 40, 14, 1, '2025-09-18 21:26:23', '', 500.00, 'gramos', 200.00, '', '', 'archivos/qr/entrada_insumo_57.png', 0.00),
(58, 10, 14, 1, '2025-09-18 21:26:23', '', 500.00, 'gramos', 150.00, '', '', 'archivos/qr/entrada_insumo_58.png', 0.00),
(59, 1, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 50.00, '', '', 'archivos/qr/entrada_insumo_59.png', 1000.00),
(60, 10, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_60.png', 300.00),
(61, 40, 9, 1, '2025-09-18 21:29:39', '', 1000.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_61.png', 700.00),
(62, 1, 11, 1, '2025-09-18 21:30:48', '', 3000.00, 'gramos', 80.00, '', '', 'archivos/qr/entrada_insumo_62.png', 3000.00),
(63, 40, 11, 1, '2025-09-18 21:30:48', '', 1000.00, 'gramos', 350.00, '', '', 'archivos/qr/entrada_insumo_63.png', 1000.00),
(64, 10, 11, 1, '2025-09-18 21:30:48', '', 500.00, 'gramos', 180.00, '', '', 'archivos/qr/entrada_insumo_64.png', 500.00),
(65, 72, 16, 1, '2025-09-18 21:35:35', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_65.png', 0.00),
(66, 72, 16, 1, '2025-09-18 21:36:17', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_66.png', 25.00),
(67, 72, 16, 1, '2025-09-18 21:36:37', '', 50.00, 'pieza', 200.00, '', '', 'archivos/qr/entrada_insumo_67.png', 50.00);

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
(1, 'Arroz', 'gramos', 4000.00, 'por_receta', 'ins_68717301313ad.jpg', 0.00),
(2, 'Alga', 'piezas', 0.00, 'por_receta', 'ins_6871716a72681.jpg', 0.00),
(3, 'Salmón fresco', 'gramos', 0.00, 'por_receta', 'ins_6871777fa2c56.png', 0.00),
(4, 'Refresco en lata', 'piezas', 0.00, 'unidad_completa', 'ins_6871731d075cb.webp', 0.00),
(7, 'Surimi', 'gramos', 0.00, 'uso_general', 'ins_688a521dcd583.jpg', 0.00),
(8, 'Tocino', 'gramos', 0.00, 'uso_general', 'ins_688a4dc84c002.jpg', 0.00),
(9, 'Pollo', 'gramos', 0.00, 'desempaquetado', 'ins_688a4e4bd5999.jpg', 0.00),
(10, 'Camarón', 'gramos', 800.00, 'desempaquetado', 'ins_688a4f5c873c6.jpg', 0.00),
(11, 'Queso Chihuahua', 'gramos', 0.00, 'unidad_completa', 'ins_688a4feca9865.jpg', 0.00),
(12, 'Philadelphia', 'gramos', 0.00, 'uso_general', 'ins_688a504f9cb40.jpg', 0.00),
(13, 'Arroz blanco', 'gramos', 0.00, 'por_receta', 'ins_689f82d674c65.jpg', 0.00),
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
(40, 'Atún fresco', 'gramos', 1700.00, 'por_receta', 'ins_688a5ce18adc5.jpg', 0.00),
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
(72, 'Refresco embotellado', 'pieza', 75.00, 'unidad_completa', 'ins_68adfdd53f04e.jpg', 0.00),
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
  `referencia_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `logs_accion`
--

INSERT INTO `logs_accion` (`id`, `usuario_id`, `modulo`, `accion`, `fecha`, `referencia_id`) VALUES
(29, 1, 'bodega', 'Generacion QR', '2025-09-18 21:43:23', 31);

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
(117, 'traspaso', 1, NULL, 72, 66, -25.00, 'Enviado por QR a sucursal', '2025-09-18 21:43:23', '59c2709cc700b049df5a9b9180b9425f', 31);

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
(3, 'Abastos OXX', '81-5555-0001', 'Parque Industrial, Monterrey, NL'),
(4, 'La patita', NULL, ''),
(5, 'Sams', NULL, NULL),
(6, 'inix', NULL, NULL),
(7, 'mercado libre', NULL, NULL),
(8, 'Centauro', NULL, NULL),
(9, 'Fruteria los hermanos', NULL, NULL),
(10, 'Carmelita', NULL, NULL),
(11, 'Fruteria trebol', NULL, NULL),
(12, 'Gabriel', NULL, NULL),
(13, 'Limon nuevo', NULL, NULL),
(14, 'CPSmart', NULL, NULL),
(15, 'Quimicos San Ismael', NULL, NULL),
(16, 'Coca Cola', NULL, NULL),
(17, 'Cerveceria Modelo', NULL, NULL);

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
(31, '59c2709cc700b049df5a9b9180b9425f', '[{\"id\":1,\"nombre\":\"Arroz\",\"unidad\":\"gramos\",\"cantidad\":5000,\"precio_unitario\":0},{\"id\":10,\"nombre\":\"Camarón\",\"unidad\":\"gramos\",\"cantidad\":1200,\"precio_unitario\":0},{\"id\":40,\"nombre\":\"Atún fresco\",\"unidad\":\"gramos\",\"cantidad\":800,\"precio_unitario\":0},{\"id\":72,\"nombre\":\"Refresco embotellado\",\"unidad\":\"pieza\",\"cantidad\":75,\"precio_unitario\":0}]', 'pendiente', 1, '2025-09-18 21:43:23', NULL, 'archivos/bodega/pdfs/qr_59c2709cc700b049df5a9b9180b9425f.pdf', NULL);

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
(21, 'proveedores', '/vistas/insumos/proveedores.php', 'link', NULL, 5),
(23, 'HistorialR', '/vistas/bodega/historial_qr.php', 'link', NULL, 7);

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
(45, 1, 19),
(46, 1, 23);

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=575;

--
-- AUTO_INCREMENT de la tabla `despachos`
--
ALTER TABLE `despachos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=31;

--
-- AUTO_INCREMENT de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=37;

--
-- AUTO_INCREMENT de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=68;

--
-- AUTO_INCREMENT de la tabla `insumos`
--
ALTER TABLE `insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=174;

--
-- AUTO_INCREMENT de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=30;

--
-- AUTO_INCREMENT de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=118;

--
-- AUTO_INCREMENT de la tabla `productos`
--
ALTER TABLE `productos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `proveedores`
--
ALTER TABLE `proveedores`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=18;

--
-- AUTO_INCREMENT de la tabla `qrs_insumo`
--
ALTER TABLE `qrs_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT de la tabla `sucursales`
--
ALTER TABLE `sucursales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `usuario_ruta`
--
ALTER TABLE `usuario_ruta`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=47;

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
