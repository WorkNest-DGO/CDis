-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 31-10-2025 a las 06:32:37
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
CREATE DATABASE IF NOT EXISTS `restaurante_cdis` DEFAULT CHARACTER SET utf32 COLLATE utf32_bin;
USE `restaurante_cdis`;

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_fix_autoincrement_ids` (IN `p_schema` VARCHAR(128))   BEGIN
  -- 1) DECLARACIONES
  DECLARE v_tbl VARCHAR(128);
  DECLARE v_coltype VARCHAR(128);
  DECLARE v_is_pk TINYINT;
  DECLARE v_has_pk TINYINT;
  DECLARE v_is_int TINYINT;
  DECLARE v_is_ai TINYINT;
  DECLARE v_nulls BIGINT;
  DECLARE v_total BIGINT;
  DECLARE v_dist BIGINT;
  DECLARE done INT DEFAULT 0;

  -- Cursor
  DECLARE cur CURSOR FOR
    SELECT c.TABLE_NAME, c.COLUMN_TYPE
    FROM information_schema.COLUMNS c
    WHERE c.TABLE_SCHEMA = p_schema
      AND c.COLUMN_NAME = 'id';

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  -- 2) INSTRUCCIONES
  DROP TEMPORARY TABLE IF EXISTS tmp_ai_fix_log;
  CREATE TEMPORARY TABLE tmp_ai_fix_log(
    table_name VARCHAR(128),
    action VARCHAR(64),
    note TEXT
  );

  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO v_tbl, v_coltype;
    IF done = 1 THEN LEAVE read_loop; END IF;

    -- ¿int/bigint/mediumint/smallint/tinyint?
    SET v_is_int = (
      SELECT CASE WHEN DATA_TYPE IN ('int','bigint','mediumint','smallint','tinyint') THEN 1 ELSE 0 END
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = p_schema AND TABLE_NAME = v_tbl AND COLUMN_NAME = 'id'
      LIMIT 1
    );

    SET v_is_ai = (
      SELECT CASE WHEN EXTRA LIKE '%auto_increment%' THEN 1 ELSE 0 END
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = p_schema AND TABLE_NAME = v_tbl AND COLUMN_NAME = 'id'
      LIMIT 1
    );

    SET v_is_pk = EXISTS(
      SELECT 1
      FROM information_schema.KEY_COLUMN_USAGE k
      WHERE k.TABLE_SCHEMA = p_schema
        AND k.TABLE_NAME  = v_tbl
        AND k.COLUMN_NAME = 'id'
        AND k.CONSTRAINT_NAME = 'PRIMARY'
    );

    SET v_has_pk = EXISTS(
      SELECT 1
      FROM information_schema.TABLE_CONSTRAINTS tc
      WHERE tc.TABLE_SCHEMA = p_schema
        AND tc.TABLE_NAME   = v_tbl
        AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
    );

    -- Si ya es AI, registrar y continuar
    IF v_is_ai = 1 THEN
      INSERT INTO tmp_ai_fix_log VALUES (v_tbl,'skip','id ya es AUTO_INCREMENT');
      ITERATE read_loop;
    END IF;

    -- Si no es entero, omitir
    IF v_is_int = 0 THEN
      INSERT INTO tmp_ai_fix_log VALUES (v_tbl,'skip','id no es entero');
      ITERATE read_loop;
    END IF;

    -- Caso A: id ya es PK -> solo MODIFICAR a AUTO_INCREMENT
    IF v_is_pk = 1 THEN
      SET @sql := CONCAT('ALTER TABLE `',p_schema,'`.`',v_tbl,'` ',
                         'MODIFY `id` ', v_coltype, ' NOT NULL AUTO_INCREMENT');
      PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
      INSERT INTO tmp_ai_fix_log VALUES (v_tbl,'modify','Se agregó AUTO_INCREMENT a id (ya era PK)');
      ITERATE read_loop;
    END IF;

    -- Caso B: tabla sin PK -> validar id (sin nulos/duplicados) y promoverla a PK + AI
    IF v_has_pk = 0 THEN
      -- SELECT dinámico: resultados a @user_vars y luego se asignan a locales
      SET @q := CONCAT('SELECT SUM(id IS NULL), COUNT(*), COUNT(DISTINCT id) INTO @u_nulls, @u_total, @u_dist FROM `',p_schema,'`.`',v_tbl,'`');
      PREPARE qs FROM @q; EXECUTE qs; DEALLOCATE PREPARE qs;
      SET v_nulls = IFNULL(@u_nulls,0);
      SET v_total = IFNULL(@u_total,0);
      SET v_dist  = IFNULL(@u_dist,0);

      IF IFNULL(v_nulls,0)=0 AND IFNULL(v_dist,0)=IFNULL(v_total,0) THEN
        -- Asegurar NOT NULL y luego PK + AI
        SET @sql1 := CONCAT('ALTER TABLE `',p_schema,'`.`',v_tbl,'` MODIFY `id` ', v_coltype, ' NOT NULL');
        SET @sql2 := CONCAT('ALTER TABLE `',p_schema,'`.`',v_tbl,'` ADD PRIMARY KEY (`id`)');
        SET @sql3 := CONCAT('ALTER TABLE `',p_schema,'`.`',v_tbl,'` MODIFY `id` ', v_coltype, ' NOT NULL AUTO_INCREMENT');
        PREPARE s1 FROM @sql1; EXECUTE s1; DEALLOCATE PREPARE s1;
        PREPARE s2 FROM @sql2; EXECUTE s2; DEALLOCATE PREPARE s2;
        PREPARE s3 FROM @sql3; EXECUTE s3; DEALLOCATE PREPARE s3;
        INSERT INTO tmp_ai_fix_log VALUES (v_tbl,'add_pk_ai','Se declaró PK(id) y AUTO_INCREMENT');
      ELSE
        INSERT INTO tmp_ai_fix_log VALUES (v_tbl,'skip',CONCAT('id nulos/duplicados (nulls=',v_nulls,', total=',v_total,', distinct=',v_dist,')'));
      END IF;

      ITERATE read_loop;
    END IF;

    -- Caso C: la tabla ya tiene otra PK distinta de id -> no tocar
    INSERT INTO tmp_ai_fix_log VALUES (v_tbl,'skip','Tabla tiene otra PRIMARY KEY distinta de id');

  END LOOP;

  CLOSE cur;

  -- Mostrar resultado
  SELECT * FROM tmp_ai_fix_log ORDER BY action, table_name;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_kardex_resumen` (IN `p_desde` DATETIME, IN `p_hasta` DATETIME, IN `p_insumo` INT)   BEGIN
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
ABS(COALESCE(m.mermas_raw,0)) AS mermas,
COALESCE(m.ajustes,0)        AS ajustes,
(b.inicial
   + COALESCE(e.entradas,0)
   + COALESCE(m.devoluciones,0)
   + COALESCE(e.otras_entradas,0)
   - COALESCE(m.salidas,0)
   - COALESCE(m.traspasos_salida,0)
   - ABS(COALESCE(m.mermas_raw,0))
   + COALESCE(m.ajustes,0)
) AS existencia_final
FROM base b
LEFT JOIN movs m     ON m.insumo_id = b.insumo_id
LEFT JOIN entradas e ON e.insumo_id = b.insumo_id;
END$$

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
(1, '2025-10-25 09:30:24', NULL, 1, NULL, NULL);

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
(1, 1, 1, 0.00, 0.00, 0.00, 0.00, NULL),
(2, 1, 2, 0.00, 0.00, 0.00, 0.00, NULL),
(3, 1, 3, 0.00, 0.00, 0.00, 0.00, NULL),
(4, 1, 4, 0.00, 0.00, 0.00, 0.00, NULL),
(5, 1, 7, 0.00, 0.00, 0.00, 0.00, NULL),
(6, 1, 8, 0.00, 0.00, 0.00, 0.00, NULL),
(7, 1, 9, 0.00, 0.00, 0.00, 0.00, NULL),
(8, 1, 10, 0.00, 0.00, 0.00, 0.00, NULL),
(9, 1, 11, 0.00, 0.00, 0.00, 0.00, NULL),
(10, 1, 12, 0.00, 0.00, 0.00, 0.00, NULL),
(11, 1, 13, 0.00, 0.00, 0.00, 0.00, NULL),
(12, 1, 14, 0.00, 0.00, 0.00, 0.00, NULL),
(13, 1, 15, 0.00, 0.00, 0.00, 0.00, NULL),
(14, 1, 16, 0.00, 0.00, 0.00, 0.00, NULL),
(15, 1, 17, 0.00, 0.00, 0.00, 0.00, NULL),
(16, 1, 18, 0.00, 0.00, 0.00, 0.00, NULL),
(17, 1, 19, 0.00, 0.00, 0.00, 0.00, NULL),
(18, 1, 20, 0.00, 0.00, 0.00, 0.00, NULL),
(19, 1, 21, 0.00, 0.00, 0.00, 0.00, NULL),
(20, 1, 22, 0.00, 0.00, 0.00, 0.00, NULL),
(21, 1, 23, 0.00, 0.00, 0.00, 0.00, NULL),
(22, 1, 24, 0.00, 0.00, 0.00, 0.00, NULL),
(23, 1, 25, 0.00, 0.00, 0.00, 0.00, NULL),
(24, 1, 26, 0.00, 0.00, 0.00, 0.00, NULL),
(25, 1, 27, 0.00, 0.00, 0.00, 0.00, NULL),
(26, 1, 28, 0.00, 0.00, 0.00, 0.00, NULL),
(27, 1, 29, 0.00, 0.00, 0.00, 0.00, NULL),
(28, 1, 30, 0.00, 0.00, 0.00, 0.00, NULL),
(29, 1, 31, 0.00, 0.00, 0.00, 0.00, NULL),
(30, 1, 32, 0.00, 0.00, 0.00, 0.00, NULL),
(31, 1, 33, 0.00, 0.00, 0.00, 0.00, NULL),
(32, 1, 34, 0.00, 0.00, 0.00, 0.00, NULL),
(33, 1, 35, 0.00, 0.00, 0.00, 0.00, NULL),
(34, 1, 36, 0.00, 0.00, 0.00, 0.00, NULL),
(35, 1, 37, 0.00, 0.00, 0.00, 0.00, NULL),
(36, 1, 38, 0.00, 0.00, 0.00, 0.00, NULL),
(37, 1, 39, 0.00, 0.00, 0.00, 0.00, NULL),
(38, 1, 40, 0.00, 0.00, 0.00, 0.00, NULL),
(39, 1, 41, 0.00, 0.00, 0.00, 0.00, NULL),
(40, 1, 42, 0.00, 0.00, 0.00, 0.00, NULL),
(41, 1, 43, 0.00, 0.00, 0.00, 0.00, NULL),
(42, 1, 44, 0.00, 0.00, 0.00, 0.00, NULL),
(43, 1, 45, 0.00, 0.00, 0.00, 0.00, NULL),
(44, 1, 46, 0.00, 0.00, 0.00, 0.00, NULL),
(45, 1, 47, 0.00, 0.00, 0.00, 0.00, NULL),
(46, 1, 48, 0.00, 0.00, 0.00, 0.00, NULL),
(47, 1, 49, 0.00, 0.00, 0.00, 0.00, NULL),
(48, 1, 50, 0.00, 0.00, 0.00, 0.00, NULL),
(49, 1, 51, 0.00, 0.00, 0.00, 0.00, NULL),
(50, 1, 52, 0.00, 0.00, 0.00, 0.00, NULL),
(51, 1, 53, 0.00, 0.00, 0.00, 0.00, NULL),
(52, 1, 54, 0.00, 0.00, 0.00, 0.00, NULL),
(53, 1, 55, 0.00, 0.00, 0.00, 0.00, NULL),
(54, 1, 56, 0.00, 0.00, 0.00, 0.00, NULL),
(55, 1, 57, 0.00, 0.00, 0.00, 0.00, NULL),
(56, 1, 59, 0.00, 0.00, 0.00, 0.00, NULL),
(57, 1, 60, 0.00, 0.00, 0.00, 0.00, NULL),
(58, 1, 61, 0.00, 0.00, 0.00, 0.00, NULL),
(59, 1, 62, 0.00, 0.00, 0.00, 0.00, NULL),
(60, 1, 63, 0.00, 0.00, 0.00, 0.00, NULL),
(61, 1, 64, 0.00, 0.00, 0.00, 0.00, NULL),
(62, 1, 65, 0.00, 0.00, 0.00, 0.00, NULL),
(63, 1, 66, 0.00, 0.00, 0.00, 0.00, NULL),
(64, 1, 67, 0.00, 0.00, 0.00, 0.00, NULL),
(65, 1, 69, 0.00, 0.00, 0.00, 0.00, NULL),
(66, 1, 70, 0.00, 0.00, 0.00, 0.00, NULL),
(67, 1, 71, 0.00, 0.00, 0.00, 0.00, NULL),
(68, 1, 72, 0.00, 0.00, 0.00, 0.00, NULL),
(69, 1, 73, 0.00, 0.00, 0.00, 0.00, NULL),
(70, 1, 74, 0.00, 0.00, 0.00, 0.00, NULL),
(71, 1, 75, 0.00, 0.00, 0.00, 0.00, NULL),
(72, 1, 76, 0.00, 0.00, 0.00, 0.00, NULL),
(73, 1, 77, 0.00, 0.00, 0.00, 0.00, NULL),
(74, 1, 78, 0.00, 0.00, 0.00, 0.00, NULL),
(75, 1, 79, 0.00, 0.00, 0.00, 0.00, NULL),
(76, 1, 80, 0.00, 0.00, 0.00, 0.00, NULL),
(77, 1, 81, 0.00, 0.00, 0.00, 0.00, NULL),
(78, 1, 82, 0.00, 0.00, 0.00, 0.00, NULL),
(79, 1, 83, 0.00, 0.00, 0.00, 0.00, NULL),
(80, 1, 85, 0.00, 0.00, 0.00, 0.00, NULL),
(81, 1, 86, 0.00, 0.00, 0.00, 0.00, NULL),
(82, 1, 87, 0.00, 0.00, 0.00, 0.00, NULL),
(83, 1, 88, 0.00, 0.00, 0.00, 0.00, NULL),
(84, 1, 89, 0.00, 0.00, 0.00, 0.00, NULL),
(85, 1, 90, 0.00, 0.00, 0.00, 0.00, NULL),
(86, 1, 91, 0.00, 0.00, 0.00, 0.00, NULL),
(87, 1, 92, 0.00, 0.00, 0.00, 0.00, NULL),
(88, 1, 93, 0.00, 0.00, 0.00, 0.00, NULL),
(89, 1, 94, 0.00, 0.00, 0.00, 0.00, NULL),
(90, 1, 95, 0.00, 0.00, 0.00, 0.00, NULL),
(91, 1, 96, 0.00, 0.00, 0.00, 0.00, NULL),
(92, 1, 97, 0.00, 0.00, 0.00, 0.00, NULL),
(93, 1, 98, 0.00, 0.00, 0.00, 0.00, NULL),
(94, 1, 99, 0.00, 0.00, 0.00, 0.00, NULL),
(95, 1, 101, 0.00, 0.00, 0.00, 0.00, NULL),
(96, 1, 102, 0.00, 0.00, 0.00, 0.00, NULL),
(97, 1, 103, 0.00, 0.00, 0.00, 0.00, NULL),
(98, 1, 104, 0.00, 0.00, 0.00, 0.00, NULL),
(99, 1, 105, 0.00, 0.00, 0.00, 0.00, NULL),
(100, 1, 106, 0.00, 0.00, 0.00, 0.00, NULL),
(101, 1, 107, 0.00, 0.00, 0.00, 0.00, NULL),
(102, 1, 108, 0.00, 0.00, 0.00, 0.00, NULL),
(103, 1, 109, 0.00, 0.00, 0.00, 0.00, NULL),
(104, 1, 110, 0.00, 0.00, 0.00, 0.00, NULL),
(105, 1, 111, 0.00, 0.00, 0.00, 0.00, NULL),
(106, 1, 112, 0.00, 0.00, 0.00, 0.00, NULL),
(107, 1, 113, 0.00, 0.00, 0.00, 0.00, NULL),
(108, 1, 114, 0.00, 0.00, 0.00, 0.00, NULL),
(109, 1, 115, 0.00, 0.00, 0.00, 0.00, NULL),
(110, 1, 116, 0.00, 0.00, 0.00, 0.00, NULL),
(111, 1, 117, 0.00, 0.00, 0.00, 0.00, NULL),
(112, 1, 118, 0.00, 0.00, 0.00, 0.00, NULL),
(113, 1, 119, 0.00, 0.00, 0.00, 0.00, NULL),
(114, 1, 120, 0.00, 0.00, 0.00, 0.00, NULL),
(115, 1, 121, 0.00, 0.00, 0.00, 0.00, NULL),
(116, 1, 122, 0.00, 0.00, 0.00, 0.00, NULL),
(117, 1, 123, 0.00, 0.00, 0.00, 0.00, NULL),
(118, 1, 124, 0.00, 0.00, 0.00, 0.00, NULL),
(119, 1, 125, 0.00, 0.00, 0.00, 0.00, NULL),
(120, 1, 126, 0.00, 0.00, 0.00, 0.00, NULL),
(121, 1, 127, 0.00, 0.00, 0.00, 0.00, NULL),
(122, 1, 128, 0.00, 0.00, 0.00, 0.00, NULL),
(123, 1, 129, 0.00, 0.00, 0.00, 0.00, NULL),
(124, 1, 130, 0.00, 0.00, 0.00, 0.00, NULL),
(125, 1, 131, 0.00, 0.00, 0.00, 0.00, NULL),
(126, 1, 132, 0.00, 0.00, 0.00, 0.00, NULL),
(127, 1, 133, 0.00, 0.00, 0.00, 0.00, NULL),
(128, 1, 134, 0.00, 0.00, 0.00, 0.00, NULL),
(129, 1, 135, 0.00, 0.00, 0.00, 0.00, NULL),
(130, 1, 136, 0.00, 0.00, 0.00, 0.00, NULL),
(131, 1, 137, 0.00, 0.00, 0.00, 0.00, NULL),
(132, 1, 138, 0.00, 0.00, 0.00, 0.00, NULL),
(133, 1, 139, 0.00, 0.00, 0.00, 0.00, NULL),
(134, 1, 140, 0.00, 0.00, 0.00, 0.00, NULL),
(135, 1, 141, 0.00, 0.00, 0.00, 0.00, NULL),
(136, 1, 142, 0.00, 0.00, 0.00, 0.00, NULL),
(137, 1, 143, 0.00, 0.00, 0.00, 0.00, NULL),
(138, 1, 144, 0.00, 0.00, 0.00, 0.00, NULL),
(139, 1, 145, 0.00, 0.00, 0.00, 0.00, NULL),
(140, 1, 146, 0.00, 0.00, 0.00, 0.00, NULL),
(141, 1, 147, 0.00, 0.00, 0.00, 0.00, NULL),
(142, 1, 148, 0.00, 0.00, 0.00, 0.00, NULL),
(143, 1, 149, 0.00, 0.00, 0.00, 0.00, NULL),
(144, 1, 150, 0.00, 0.00, 0.00, 0.00, NULL),
(145, 1, 151, 0.00, 0.00, 0.00, 0.00, NULL),
(146, 1, 152, 0.00, 0.00, 0.00, 0.00, NULL),
(147, 1, 153, 0.00, 0.00, 0.00, 0.00, NULL),
(148, 1, 154, 0.00, 0.00, 0.00, 0.00, NULL),
(149, 1, 155, 0.00, 0.00, 0.00, 0.00, NULL),
(150, 1, 156, 0.00, 0.00, 0.00, 0.00, NULL),
(151, 1, 157, 0.00, 0.00, 0.00, 0.00, NULL),
(152, 1, 158, 0.00, 0.00, 0.00, 0.00, NULL),
(153, 1, 159, 0.00, 0.00, 0.00, 0.00, NULL),
(154, 1, 160, 0.00, 0.00, 0.00, 0.00, NULL),
(155, 1, 161, 0.00, 0.00, 0.00, 0.00, NULL),
(156, 1, 162, 0.00, 0.00, 0.00, 0.00, NULL),
(157, 1, 163, 0.00, 0.00, 0.00, 0.00, NULL),
(158, 1, 164, 0.00, 0.00, 0.00, 0.00, NULL),
(159, 1, 165, 0.00, 0.00, 0.00, 0.00, NULL),
(160, 1, 166, 0.00, 0.00, 0.00, 0.00, NULL),
(161, 1, 167, 0.00, 0.00, 0.00, 0.00, NULL),
(162, 1, 168, 0.00, 0.00, 0.00, 0.00, NULL),
(163, 1, 169, 0.00, 0.00, 0.00, 0.00, NULL),
(164, 1, 170, 0.00, 0.00, 0.00, 0.00, NULL),
(165, 1, 171, 0.00, 0.00, 0.00, 0.00, NULL),
(166, 1, 172, 0.00, 0.00, 0.00, 0.00, NULL),
(167, 1, 173, 0.00, 0.00, 0.00, 0.00, NULL),
(168, 1, 174, 0.00, 0.00, 0.00, 0.00, NULL),
(169, 1, 175, 0.00, 0.00, 0.00, 0.00, NULL),
(170, 1, 176, 0.00, 0.00, 0.00, 0.00, NULL),
(171, 1, 177, 0.00, 0.00, 0.00, 0.00, NULL),
(172, 1, 178, 0.00, 0.00, 0.00, 0.00, NULL),
(173, 1, 179, 0.00, 0.00, 0.00, 0.00, NULL),
(174, 1, 180, 0.00, 0.00, 0.00, 0.00, NULL),
(175, 1, 181, 0.00, 0.00, 0.00, 0.00, NULL),
(176, 1, 182, 0.00, 0.00, 0.00, 0.00, NULL),
(177, 1, 183, 0.00, 0.00, 0.00, 0.00, NULL),
(178, 1, 184, 0.00, 0.00, 0.00, 0.00, NULL),
(179, 1, 185, 0.00, 0.00, 0.00, 0.00, NULL),
(180, 1, 186, 0.00, 0.00, 0.00, 0.00, NULL),
(181, 1, 187, 0.00, 0.00, 0.00, 0.00, NULL),
(182, 1, 188, 0.00, 0.00, 0.00, 0.00, NULL),
(183, 1, 189, 0.00, 0.00, 0.00, 0.00, NULL),
(184, 1, 190, 0.00, 0.00, 0.00, 0.00, NULL),
(185, 1, 191, 0.00, 0.00, 0.00, 0.00, NULL),
(186, 1, 192, 0.00, 0.00, 0.00, 0.00, NULL),
(187, 1, 193, 0.00, 0.00, 0.00, 0.00, NULL),
(188, 1, 194, 0.00, 0.00, 0.00, 0.00, NULL),
(189, 1, 195, 0.00, 0.00, 0.00, 0.00, NULL),
(190, 1, 196, 0.00, 0.00, 0.00, 0.00, NULL),
(191, 1, 197, 0.00, 0.00, 0.00, 0.00, NULL),
(192, 1, 198, 0.00, 0.00, 0.00, 0.00, NULL),
(193, 1, 199, 0.00, 0.00, 0.00, 0.00, NULL),
(194, 1, 200, 0.00, 0.00, 0.00, 0.00, NULL),
(195, 1, 201, 0.00, 0.00, 0.00, 0.00, NULL),
(196, 1, 202, 0.00, 0.00, 0.00, 0.00, NULL),
(197, 1, 203, 0.00, 0.00, 0.00, 0.00, NULL),
(198, 1, 204, 0.00, 0.00, 0.00, 0.00, NULL),
(199, 1, 205, 0.00, 0.00, 0.00, 0.00, NULL),
(200, 1, 206, 0.00, 0.00, 0.00, 0.00, NULL),
(201, 1, 207, 0.00, 0.00, 0.00, 0.00, NULL),
(202, 1, 208, 0.00, 0.00, 0.00, 0.00, NULL),
(203, 1, 209, 0.00, 0.00, 0.00, 0.00, NULL),
(204, 1, 210, 0.00, 0.00, 0.00, 0.00, NULL),
(205, 1, 211, 0.00, 0.00, 0.00, 0.00, NULL),
(206, 1, 212, 0.00, 0.00, 0.00, 0.00, NULL),
(207, 1, 213, 0.00, 0.00, 0.00, 0.00, NULL),
(208, 1, 214, 0.00, 0.00, 0.00, 0.00, NULL),
(209, 1, 215, 0.00, 0.00, 0.00, 0.00, NULL),
(210, 1, 216, 0.00, 0.00, 0.00, 0.00, NULL),
(211, 1, 217, 0.00, 0.00, 0.00, 0.00, NULL),
(212, 1, 218, 0.00, 0.00, 0.00, 0.00, NULL),
(213, 1, 219, 0.00, 0.00, 0.00, 0.00, NULL),
(214, 1, 220, 0.00, 0.00, 0.00, 0.00, NULL),
(215, 1, 221, 0.00, 0.00, 0.00, 0.00, NULL),
(216, 1, 222, 0.00, 0.00, 0.00, 0.00, NULL),
(217, 1, 223, 0.00, 0.00, 0.00, 0.00, NULL),
(218, 1, 224, 0.00, 0.00, 0.00, 0.00, NULL),
(219, 1, 225, 0.00, 0.00, 0.00, 0.00, NULL),
(220, 1, 226, 0.00, 0.00, 0.00, 0.00, NULL),
(221, 1, 227, 0.00, 0.00, 0.00, 0.00, NULL),
(222, 1, 228, 0.00, 0.00, 0.00, 0.00, NULL),
(223, 1, 229, 0.00, 0.00, 0.00, 0.00, NULL),
(224, 1, 230, 0.00, 0.00, 0.00, 0.00, NULL);

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

--
-- Volcado de datos para la tabla `despachos`
--

INSERT INTO `despachos` (`id`, `sucursal_id`, `usuario_id`, `fecha_envio`, `fecha_recepcion`, `estado`, `corte_id`, `qr_token`) VALUES
(1, NULL, 1, '2025-10-30 12:59:16', NULL, 'pendiente', NULL, '6d3f2fd0de824c84a95174569735f3eb'),
(2, NULL, 1, '2025-10-30 22:43:20', NULL, 'pendiente', NULL, '1f75bd0c9f630daf8f2af87b81c537cf'),
(3, NULL, 1, '2025-10-30 22:55:34', NULL, 'pendiente', NULL, '35c0d8b3af67aeccb34a7fb1c22c5d4f');

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

--
-- Volcado de datos para la tabla `despachos_detalle`
--

INSERT INTO `despachos_detalle` (`id`, `despacho_id`, `corte_id`, `insumo_id`, `cantidad`, `unidad`, `precio_unitario`) VALUES
(1, 1, NULL, 36, 5.00, 'kilo', 0.00),
(2, 2, NULL, 89, 1.00, 'gramo', 0.00),
(3, 3, NULL, 89, 0.10, 'gramo', 0.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `direccion_qr`
--

CREATE TABLE `direccion_qr` (
  `ip` varchar(255) NOT NULL,
  `nombre` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `direccion_qr`
--

INSERT INTO `direccion_qr` (`ip`, `nombre`) VALUES
('127.0.0.1', 'localhost'),
('120.0.0.2', 'CdiTier');

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
  `credito` enum('credito','efectivo','transferencia') DEFAULT NULL,
  `pagado` tinyint(1) DEFAULT NULL,
  `nota` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `entradas_insumos`
--

INSERT INTO `entradas_insumos` (`id`, `insumo_id`, `proveedor_id`, `usuario_id`, `fecha`, `corte_id`, `descripcion`, `cantidad`, `unidad`, `costo_total`, `referencia_doc`, `folio_fiscal`, `qr`, `cantidad_actual`, `credito`, `pagado`, `nota`) VALUES
(1, 36, 14, 1, '2025-10-25 09:31:59', 1, '', 10.00, 'kilo', 100.00, '', '', 'archivos/qr/entrada_insumo_1.png', 0.00, 'efectivo', NULL, 1),
(2, 231, 1, 1, '2025-10-25 09:33:20', 1, 'Procesado grupo pedido 1 hacia insumo 231', 800.00, 'gramos', 0.00, '', '', 'archivos/qr/entrada_insumo_2.png', 800.00, NULL, NULL, 0),
(3, 36, 11, 1, '2025-10-28 16:06:57', 1, '', 5.00, 'kilo', 5.00, '', '', 'archivos/qr/entrada_insumo_3.png', 4.00, 'efectivo', NULL, 2),
(4, 89, 11, 1, '2025-10-28 16:06:57', 1, '', 3.00, 'gramo', 4.00, '', '', 'archivos/qr/entrada_insumo_4.png', 1.90, 'efectivo', NULL, 2),
(5, 231, 1, 1, '2025-10-30 13:01:37', 1, 'Procesado grupo pedido 2 hacia insumo 231', 4.00, 'gramos', 2.00, '', '', 'archivos/qr/entrada_insumo_5.png', 4.00, NULL, NULL, 0);

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
-- Estructura de tabla para la tabla `impresoras`
--

CREATE TABLE `impresoras` (
  `print_id` int(11) NOT NULL,
  `lugar` varchar(255) NOT NULL,
  `ip` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `impresoras`
--

INSERT INTO `impresoras` (`print_id`, `lugar`, `ip`) VALUES
(1, 'pruebas', 'smb://FUED/pos58');

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
  `minimo_stock` decimal(10,2) DEFAULT 0.00,
  `reque_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `insumos`
--

INSERT INTO `insumos` (`id`, `nombre`, `unidad`, `existencia`, `tipo_control`, `imagen`, `minimo_stock`, `reque_id`) VALUES
(1, 'Arroz', 'kilo', 0.00, 'por_receta', 'ins_68717301313ad.jpg', 0.00, NULL),
(2, 'Alga', 'pieza', 0.00, 'por_receta', 'ins_6871716a72681.jpg', 0.00, NULL),
(3, 'Salmón fresco', 'kilo', 0.00, 'por_receta', 'ins_6871777fa2c56.png', 0.00, NULL),
(4, 'Refresco en lata', 'pieza', 0.00, 'unidad_completa', 'ins_6871731d075cb.webp', 0.00, NULL),
(7, 'Surimi', 'gramo', 0.00, 'uso_general', 'ins_688a521dcd583.jpg', 0.00, NULL),
(8, 'Tocino', 'gramo', 0.00, 'uso_general', 'ins_688a4dc84c002.jpg', 0.00, NULL),
(9, 'Pollo', 'kilo', 0.00, 'desempaquetado', 'ins_688a4e4bd5999.jpg', 0.00, NULL),
(10, 'Camarón', 'kilo', 0.00, 'desempaquetado', 'ins_688a4f5c873c6.jpg', 0.00, NULL),
(11, 'Queso Chihuahua', 'kilo', 0.00, 'unidad_completa', 'ins_688a4feca9865.jpg', 0.00, NULL),
(12, 'Philadelphia', 'kilo', 0.00, 'uso_general', 'ins_688a504f9cb40.jpg', 0.00, NULL),
(13, 'Arroz cocido', 'kilo', 0.00, 'por_receta', 'ins_689f82d674c65.jpg', 0.00, NULL),
(14, 'Carne', 'kilo', 0.00, 'uso_general', 'ins_688a528d1261a.jpg', 0.00, NULL),
(15, 'Queso Amarillo', 'pieza', 0.00, 'uso_general', 'ins_688a53246c1c2.jpg', 0.00, NULL),
(16, 'Ajonjolí', 'gramo', 0.00, 'uso_general', 'ins_689f824a23343.jpg', 0.00, NULL),
(17, 'Panko', 'gramo', 0.00, 'por_receta', 'ins_688a53da64b5f.jpg', 0.00, NULL),
(18, 'Salsa tampico', 'litro', 0.00, 'no_controlado', 'ins_688a54cf1872b.jpg', 0.00, NULL),
(19, 'Anguila', 'litro', 0.00, 'por_receta', 'ins_689f828638aa9.jpg', 0.00, NULL),
(20, 'BBQ', 'litro', 0.00, 'no_controlado', 'ins_688a557431fce.jpg', 0.00, NULL),
(21, 'Serrano', 'kilo', 0.00, 'uso_general', 'ins_688a55c66f09d.jpg', 0.00, NULL),
(22, 'Chile Morrón', 'kilo', 0.00, 'por_receta', 'ins_688a5616e8f25.jpg', 0.00, NULL),
(23, 'Kanikama', 'gramo', 0.00, 'por_receta', 'ins_688a5669e24a8.jpg', 0.00, NULL),
(24, 'Aguacate', 'kilo', 0.00, 'por_receta', 'ins_689f8254c2e71.jpg', 0.00, NULL),
(25, 'Dedos de queso', 'pieza', 0.00, 'unidad_completa', 'ins_688a56fda3221.jpg', 0.00, NULL),
(26, 'Mango', 'kilo', 0.00, 'por_receta', 'ins_688a573c762f4.jpg', 0.00, NULL),
(27, 'Tostadas', 'pieza', 0.00, 'uso_general', 'ins_688a57a499b35.jpg', 0.00, NULL),
(28, 'Papa', 'kilo', 0.00, 'por_receta', 'ins_688a580061ffd.jpg', 0.00, NULL),
(29, 'Cebolla Morada', 'kilo', 0.00, 'por_receta', 'ins_688a5858752a0.jpg', 0.00, NULL),
(30, 'Salsa de soya', 'litro', 0.00, 'no_controlado', 'ins_688a58cc6cb6c.jpg', 0.00, NULL),
(31, 'Naranja', 'kilo', 0.00, 'por_receta', 'ins_688a590bca275.jpg', 0.00, NULL),
(32, 'Chile Caribe', 'kilo', 0.00, 'por_receta', 'ins_688a59836c32e.jpg', 0.00, NULL),
(33, 'Pulpo', 'kilo', 0.00, 'por_receta', 'ins_688a59c9a1d0b.jpg', 0.00, NULL),
(34, 'Zanahoria', 'kilo', 0.00, 'por_receta', 'ins_688a5a0a3a959.jpg', 0.00, NULL),
(35, 'Apio', 'kilo', 0.00, 'por_receta', 'ins_688a5a52af990.jpg', 0.00, NULL),
(36, 'Pepino', 'kilo', 10.00, 'uso_general', 'ins_688a5aa0cbaf5.jpg', 0.00, NULL),
(37, 'Masago', 'gramo', 0.00, 'por_receta', 'ins_688a5b3f0dca6.jpg', 0.00, NULL),
(38, 'Nuez de la india', 'gramo', 0.00, 'por_receta', 'ins_688a5be531e11.jpg', 0.00, NULL),
(39, 'Cátsup', 'litro', 0.00, 'por_receta', 'ins_688a5c657eb83.jpg', 0.00, NULL),
(40, 'Atún fresco', 'kilo', 0.00, 'por_receta', 'ins_688a5ce18adc5.jpg', 0.00, NULL),
(41, 'Callo almeja', 'kilo', 0.00, 'por_receta', 'ins_688a5d28de8a5.jpg', 0.00, NULL),
(42, 'Calabacin', 'kilo', 0.00, 'por_receta', 'ins_688a5d6b2bca1.jpg', 0.00, NULL),
(43, 'Fideo chino transparente', 'gramo', 0.00, 'por_receta', 'ins_688a5dd3b406d.jpg', 0.00, NULL),
(44, 'Brócoli', 'kilo', 0.00, 'por_receta', 'ins_688a5e2736870.jpg', 0.00, NULL),
(45, 'Chile de árbol', 'kilo', 0.00, 'por_receta', 'ins_688a5e6f08ccd.jpg', 0.00, NULL),
(46, 'Pasta udon', 'gramo', 0.00, 'por_receta', 'ins_688a5eb627f38.jpg', 0.00, NULL),
(47, 'Huevo', 'pieza', 0.00, 'por_receta', 'ins_688a5ef9b575e.jpg', 0.00, NULL),
(48, 'Cerdo', 'kilo', 0.00, 'por_receta', 'ins_688a5f3915f5e.jpg', 0.00, NULL),
(49, 'Masa para gyozas', 'gramo', 0.00, 'por_receta', 'ins_688a5fae2e7f1.jpg', 0.00, NULL),
(50, 'Naruto', 'gramo', 0.00, 'por_receta', 'ins_688a5ff57f62d.jpg', 0.00, NULL),
(51, 'Atún ahumado', 'kilo', 0.00, 'por_receta', 'ins_68adcd62c5a19.jpg', 0.00, NULL),
(52, 'Cacahuate con salsa (salado)', 'kilo', 0.00, 'por_receta', 'ins_68adcf253bd1d.jpg', 0.00, NULL),
(53, 'Calabaza', 'kilo', 0.00, 'por_receta', 'ins_68add0ff781fb.jpg', 0.00, NULL),
(54, 'Camarón gigante para pelar', 'kilo', 0.00, 'por_receta', 'ins_68add3264c465.jpg', 0.00, NULL),
(55, 'Cebolla', 'kilo', 0.00, 'por_receta', 'ins_68add38beff59.jpg', 0.00, NULL),
(56, 'Chile en polvo', 'gramo', 0.00, 'por_receta', 'ins_68add4a750a0e.jpg', 0.00, NULL),
(57, 'Coliflor', 'kilo', 0.00, 'por_receta', 'ins_68add5291130e.jpg', 0.00, NULL),
(59, 'Dedos de surimi', 'pieza', 0.00, 'unidad_completa', 'ins_68add5c575fbb.jpg', 0.00, NULL),
(60, 'Fideos', 'gramo', 0.00, 'por_receta', 'ins_68add629d094b.jpg', 0.00, NULL),
(61, 'Fondo de res', 'litro', 0.00, 'no_controlado', 'ins_68add68d317d5.jpg', 0.00, NULL),
(62, 'Gravy Naranja', 'litro', 0.00, 'no_controlado', 'ins_68add7bb461b3.jpg', 0.00, NULL),
(63, 'Salsa Aguachil', 'litro', 0.00, 'no_controlado', 'ins_68ae000034b31.jpg', 0.00, NULL),
(64, 'Julianas de zanahoria', 'gramo', 0.00, 'por_receta', 'ins_68add82c9c245.jpg', 0.00, NULL),
(65, 'Limón', 'kilo', 0.00, 'por_receta', 'ins_68add890ee640.jpg', 0.00, NULL),
(66, 'Queso Mix', 'gramo', 0.00, 'uso_general', 'ins_68ade1625f489.jpg', 0.00, NULL),
(67, 'Chile morrón rojo', 'kilo', 0.00, 'por_receta', 'ins_68addcbc6d15a.jpg', 0.00, NULL),
(69, 'Pasta chukasoba', 'gramo', 0.00, 'por_receta', 'ins_68addd277fde6.jpg', 0.00, NULL),
(70, 'Pasta frita', 'gramo', 0.00, 'por_receta', 'ins_68addd91a005e.jpg', 0.00, NULL),
(71, 'Queso crema', 'kilo', 0.00, 'uso_general', 'ins_68ade11cdadcb.jpg', 0.00, NULL),
(72, 'Refresco embotellado', 'pieza', 0.00, 'unidad_completa', 'ins_68adfdd53f04e.jpg', 0.00, NULL),
(73, 'res', 'kilo', 0.00, 'uso_general', 'ins_68adfe2e49580.jpg', 0.00, NULL),
(74, 'Rodajas de naranja', 'pieza', 0.00, 'por_receta', 'ins_68adfeccd68d8.jpg', 0.00, NULL),
(75, 'Salmón', 'gramo', 0.00, 'por_receta', 'ins_68adffa2a2db0.jpg', 0.00, NULL),
(76, 'Salsa de anguila', 'litro', 0.00, 'no_controlado', 'ins_68ae005f1b3cd.jpg', 0.00, NULL),
(77, 'Salsa teriyaki (dulce)', 'litro', 0.00, 'no_controlado', 'ins_68ae00c53121a.jpg', 0.00, NULL),
(78, 'Salsas orientales', 'litro', 0.00, 'no_controlado', 'ins_68ae01341e7b1.jpg', 0.00, NULL),
(79, 'Shisimi', 'gramo', 0.00, 'uso_general', 'ins_68ae018d22a63.jpg', 0.00, NULL),
(80, 'Siracha', 'litro', 0.00, 'no_controlado', 'ins_68ae03413da26.jpg', 0.00, NULL),
(81, 'Tampico', 'litro', 0.00, 'uso_general', 'ins_68ae03f65bd71.jpg', 0.00, NULL),
(82, 'Tortilla de harina', 'pieza', 0.00, 'unidad_completa', 'ins_68ae04b46d24a.jpg', 0.00, NULL),
(83, 'Tostada', 'pieza', 0.00, 'unidad_completa', 'ins_68ae05924a02a.jpg', 0.00, NULL),
(85, 'Chile morron amarillo', 'kilo', 0.00, 'por_receta', 'ins_68ae061b1175b.jpg', 0.00, NULL),
(86, 'Sal con Ajo', 'gramo', 0.00, 'por_receta', 'ins_68adff6dbf111.jpg', 0.00, NULL),
(87, 'Aderezo Chipotle', 'mililitro', 0.00, 'por_receta', 'ins_68adcabeb1ee9.jpg', 0.00, 2),
(88, 'Mezcla de Horneado', 'gramo', 0.00, 'por_receta', 'ins_68addaa3e53f7.jpg', 0.00, NULL),
(89, 'Aderezo', 'gramo', 1.90, 'uso_general', 'ins_68adcc0771a3c.jpg', 0.00, 2),
(90, 'Camarón Empanizado', 'gramo', 0.00, 'por_receta', 'ins_68add1de1aa0e.jpg', 0.00, NULL),
(91, 'Pollo Empanizado', 'gramo', 0.00, 'por_receta', 'ins_68adde81c6be3.jpg', 0.00, NULL),
(92, 'Cebollín', 'kilo', 0.00, 'por_receta', 'ins_68add3e38d04b.jpg', 0.00, NULL),
(93, 'Aderezo Cebolla Dul.', 'mililitro', 0.00, 'uso_general', 'ins_68adcb8fa562e.jpg', 0.00, 1),
(94, 'Camaron Enchiloso', 'gramo', 0.00, 'por_receta', 'ins_68add2db69e2e.jpg', 0.00, NULL),
(95, 'Pastel chocoflan', 'pieza', 0.00, 'unidad_completa', 'ins_68adddfa22fe2.jpg', 0.00, NULL),
(96, 'Pay de queso', 'pieza', 0.00, 'unidad_completa', 'ins_68adde4fa8275.jpg', 0.00, NULL),
(97, 'Helado tempura', 'pieza', 0.00, 'unidad_completa', 'ins_68add7e53c6fe.jpg', 0.00, NULL),
(98, 'Postre especial', 'pieza', 0.00, 'unidad_completa', 'ins_68addee98fdf0.jpg', 0.00, NULL),
(99, 'Búfalo', 'mililitro', 0.00, 'no_controlado', 'ins_68adce63dd347.jpg', 0.00, NULL),
(101, 'Corona 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68add55a1e3b7.jpg', 0.00, NULL),
(102, 'Golden Light 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68add76481f22.jpg', 0.00, NULL),
(103, 'Negra Modelo', 'pieza', 0.00, 'unidad_completa', 'ins_68addc59c2ea9.jpg', 0.00, NULL),
(104, 'Modelo Especial', 'pieza', 0.00, 'unidad_completa', 'ins_68addb9d59000.jpg', 0.00, NULL),
(105, 'Bud Light', 'pieza', 0.00, 'unidad_completa', 'ins_68adcdf3295e8.jpg', 0.00, NULL),
(106, 'Stella Artois', 'pieza', 0.00, 'unidad_completa', 'ins_68ae0397afb2f.jpg', 0.00, NULL),
(107, 'Ultra 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68ae05466a8e2.jpg', 0.00, NULL),
(108, 'Michelob 1/2', 'pieza', 0.00, 'unidad_completa', 'ins_68addb2d00c85.jpg', 0.00, NULL),
(109, 'Alitas de pollo', 'pieza', 0.00, 'unidad_completa', 'ins_68adccf5a1147.jpg', 0.00, NULL),
(110, 'Ranch', 'mililitro', 0.00, 'no_controlado', 'ins_68adfcddef7e3.jpg', 0.00, NULL),
(111, 'Buffalo', 'mililitro', 0.00, 'no_controlado', '', 0.00, NULL),
(112, 'Chichimi', 'gramo', 0.00, 'no_controlado', 'ins_68add45bdb306.jpg', 0.00, NULL),
(113, 'Calpico', 'pieza', 0.00, 'unidad_completa', 'ins_68add19570673.jpg', 0.00, NULL),
(114, 'Vaina de soja', 'gramo', 0.00, 'uso_general', 'ins_68ae05de869d1.jpg', 0.00, NULL),
(115, 'Boneless', 'kilo', 0.00, 'por_receta', 'ins_68adcdbb6b5b4.jpg', 0.00, NULL),
(116, 'Agua members', 'pieza', 0.00, 'unidad_completa', 'ins_68adcc5feaee1.jpg', 0.00, 1),
(117, 'Agua mineral', 'pieza', 0.00, 'unidad_completa', 'ins_68adcca85ae2c.jpg', 0.00, NULL),
(118, 'Cilantro', 'gramo', 0.00, 'por_receta', 'ins_68add4edab118.jpg', 0.00, NULL),
(119, 'Té de jazmin', 'litro', 0.00, 'por_receta', 'ins_68ae0474dfc36.jpg', 0.00, NULL),
(120, 'bolsa camiseta 35x60', 'kilo', 0.00, 'unidad_completa', '', 0.00, 4),
(121, 'bolsa camiseta 25x50', 'kilo', 0.00, 'unidad_completa', '', 0.00, NULL),
(122, 'bolsa camiseta 25x40', 'kilo', 0.00, 'unidad_completa', '', 0.00, NULL),
(123, 'bolsa poliseda 15x25', 'rollo', 0.00, 'unidad_completa', '', 0.00, NULL),
(124, 'bolsa rollo 20x30', 'rollo', 0.00, 'unidad_completa', '', 0.00, NULL),
(125, 'bowls cpp1911-3', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(126, 'bowls cpp20', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(127, 'bowls cpp1911-3 tapa', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(128, 'bowls cpp20 tapa', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(129, 'baso termico 1l', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(130, 'bisagra 22x22', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(131, 'servilleta', 'paquete', 0.00, 'unidad_completa', '', 0.00, NULL),
(132, 'Papel aluminio 400', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(133, 'Vitafilim 14', 'rollo', 0.00, 'unidad_completa', '', 0.00, NULL),
(134, 'guante vinil', 'caja', 0.00, 'unidad_completa', '', 0.00, NULL),
(135, 'Popote 26cm', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(136, 'Bolsa papel x 100pz', 'paquete', 0.00, 'unidad_completa', '', 0.00, NULL),
(137, 'rollo impresora mediano', 'rollo', 0.00, 'unidad_completa', '', 0.00, NULL),
(138, 'rollo impresora grande', 'rollo', 0.00, 'unidad_completa', '', 0.00, NULL),
(139, 'tenedor fantasy mediano 25pz', 'paquete', 0.00, 'unidad_completa', '', 0.00, NULL),
(140, 'Bolsa basura 90x120 negra', 'bulto', 0.00, 'unidad_completa', '', 0.00, NULL),
(141, 'Ts2', 'tira', 0.00, 'unidad_completa', '', 0.00, NULL),
(142, 'Ts1', 'tira', 0.00, 'unidad_completa', '', 0.00, NULL),
(143, 'TS200', 'tira', 0.00, 'unidad_completa', '', 0.00, NULL),
(144, 'S100', 'tira', 0.00, 'unidad_completa', '', 0.00, NULL),
(145, 'Pet 1l c/tapa', 'bulto', 0.00, 'unidad_completa', '', 0.00, NULL),
(146, 'Pet 1/2l c/tapa', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(147, 'Cuchara mediana fantasy 50pz', 'paquete', 0.00, 'unidad_completa', '', 0.00, NULL),
(148, 'Charola 8x8', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(149, 'Charola 6x6', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(150, 'Charola 8x8 negra', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(151, 'Charola 6x6 negra', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(152, 'Polipapel', 'kilo', 0.00, 'unidad_completa', '', 0.00, NULL),
(153, 'Charola pastelera', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(154, 'Papel secante', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(155, 'Papel rollo higienico', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(156, 'Fabuloso 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00, NULL),
(157, 'Desengrasante 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00, NULL),
(158, 'Cloro 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00, NULL),
(159, 'Iorizante 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00, NULL),
(160, 'Windex 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00, NULL),
(161, 'quitacochambre 1l', 'litro', 0.00, 'unidad_completa', '', 0.00, NULL),
(162, 'Fibra metal', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(163, 'Esponja', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(164, 'Escoba', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(165, 'Recogedor', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(166, 'Trapeador', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(167, 'Cubeta 16l', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(168, 'Sanitas', 'paquete', 0.00, 'unidad_completa', '', 0.00, NULL),
(169, 'Jabon polvo 9k', 'bulto', 0.00, 'unidad_completa', '', 0.00, NULL),
(170, 'Shampoo trastes 20l', 'bidon', 0.00, 'unidad_completa', '', 0.00, NULL),
(171, 'Jaladores', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(172, 'Cofia', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(173, 'Trapo', 'pieza', 0.00, 'unidad_completa', '', 0.00, NULL),
(174, 'champinon', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(175, 'ejotes', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(176, 'Chile Caribe', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(177, 'Chile serrano', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(178, 'Col morada', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(179, 'mayonesa', 'pieza', 0.00, 'uso_general', '', 40.00, NULL),
(180, 'camaron cocido', 'kilo', 0.00, 'por_receta', '', 15.00, NULL),
(181, 'Refresco coca cola', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(182, 'giosas', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(183, 'Papa francesa kit', 'porcion', 0.00, 'por_receta', '', 0.00, NULL),
(184, 'carne de puerco', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(185, 'papa francesa grande', 'porcion', 0.00, 'por_receta', '', 0.00, NULL),
(186, 'Camaron gigante', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(187, 'sprite', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(188, 'sichimi', 'mililitro', 0.00, 'por_receta', '', 0.00, NULL),
(189, 'Charola 8x8 blancas', 'paquete', 0.00, 'por_receta', '', 0.00, NULL),
(190, 'Charola 6x6 blancas', 'paquete', 0.00, 'por_receta', '', 0.00, NULL),
(191, 'queso horneado', 'porcion', 0.00, 'por_receta', '', 0.00, NULL),
(192, 'fondo de poyo', 'litro', 0.00, 'por_receta', '', 0.00, NULL),
(193, 'carne cocida', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(194, 'tocino cocido', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(195, 'dobles', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(196, 'carne molida', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(197, 'domplings', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(198, 'salsa hoysin', 'bote', 0.00, 'por_receta', '', 0.00, NULL),
(199, 'salsa de champiñon', 'bote', 0.00, 'por_receta', '', 0.00, NULL),
(200, 'ajonjoli blanco', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(201, 'nort de poyo', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(202, 'sal', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(203, 'homdachi', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(204, 'sal de apio', 'bote', 0.00, 'por_receta', '', 0.00, NULL),
(205, 'ajo en polvo', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(206, 'pimienta', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(207, 'azucar', 'costal', 0.00, 'por_receta', '', 0.00, NULL),
(208, 'ajinomoto', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(209, 'paso 1', 'bote', 0.00, 'por_receta', '', 0.00, NULL),
(210, 'paso 2', 'bote', 0.00, 'por_receta', '', 0.00, NULL),
(211, 'guantes de hule', 'par', 0.00, 'por_receta', '', 0.00, NULL),
(212, 'cunre bocas', 'paquete', 0.00, 'por_receta', '', 0.00, NULL),
(213, 'guantes de cocina', 'paquete', 0.00, 'por_receta', '', 0.00, NULL),
(214, 'recojedor', 'piesa', 0.00, 'por_receta', '', 0.00, NULL),
(215, 'papele higienico', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(216, 'fanta', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(217, 'mindet', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(218, 'coca cola ligt', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(219, 'amper', 'pieza', 0.00, 'por_receta', '', 0.00, NULL),
(220, 'royo canaron', 'orden', 0.00, 'por_receta', '', 0.00, NULL),
(221, 'royo de poyo', 'orden', 0.00, 'por_receta', '', 0.00, NULL),
(222, 'royo de carne', 'orden', 0.00, 'por_receta', '', 0.00, NULL),
(223, 'pasta yurei', 'pauete', 0.00, 'por_receta', '', 0.00, NULL),
(224, 'costilla', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(225, 'espinazo', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(226, 'poyo( piena y muslo )', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(227, 'codillo de res', 'gramo', 0.00, 'por_receta', '', 0.00, NULL),
(228, 'papa gajo', 'porcion', 0.00, 'por_receta', '', 0.00, NULL),
(229, 'fecula de maiz', 'kilo', 0.00, 'por_receta', '', 0.00, NULL),
(230, 'galleta lara', 'costal', 0.00, 'por_receta', '', 0.00, NULL),
(231, 'juliana de pepino', 'gramos', 0.00, 'por_receta', '', 1000.00, NULL);

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

--
-- Volcado de datos para la tabla `logs_accion`
--

INSERT INTO `logs_accion` (`id`, `usuario_id`, `modulo`, `accion`, `fecha`, `referencia_id`, `corte_id`) VALUES
(1, 1, 'bodega', 'Generacion QR', '2025-10-30 12:59:16', 1, NULL),
(2, 1, 'bodega', 'Generacion QR', '2025-10-30 22:43:20', 2, NULL),
(3, 1, 'bodega', 'Generacion QR', '2025-10-30 22:55:34', 3, NULL);

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
(1, 'salida', 1, NULL, 36, 1, -1.00, 'Salida lote_origen proceso id 1', '2025-10-25 09:32:30', 1, NULL, NULL),
(2, 'merma', 1, NULL, 36, 2, 200.00, 'cascara - Merma del proceso id 1 (pedido 1)', '2025-10-25 09:33:20', 1, '81f3952af6e68b2d3ead975409577c74', NULL),
(3, 'traspaso', 1, NULL, 36, 1, -5.00, 'Enviado por QR a sucursal', '2025-10-30 12:59:16', NULL, '6d3f2fd0de824c84a95174569735f3eb', 1),
(4, 'salida', 1, NULL, 36, 1, -4.00, 'Salida lote_origen proceso id 2', '2025-10-30 13:01:14', 1, NULL, NULL),
(5, 'salida', 1, NULL, 36, 3, -1.00, 'Salida lote_origen proceso id 2', '2025-10-30 13:01:14', 1, NULL, NULL),
(6, 'merma', 1, NULL, 36, 5, 1.00, 'cascara - Merma del proceso id 2 (pedido 2)', '2025-10-30 13:01:37', 1, '2c6dec1fda479f98af74afbd483eb3c8', NULL),
(7, 'traspaso', 1, NULL, 89, 4, -1.00, 'Enviado por QR a sucursal', '2025-10-30 22:43:20', NULL, '1f75bd0c9f630daf8f2af87b81c537cf', 2),
(8, 'traspaso', 1, NULL, 89, 4, -0.10, 'Enviado por QR a sucursal', '2025-10-30 22:55:34', NULL, '35c0d8b3af67aeccb34a7fb1c22c5d4f', 3);

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
  `qr_path` varchar(255) DEFAULT NULL,
  `pedido` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `procesos_insumos`
--

INSERT INTO `procesos_insumos` (`id`, `insumo_origen_id`, `insumo_destino_id`, `cantidad_origen`, `unidad_origen`, `cantidad_resultante`, `unidad_destino`, `estado`, `observaciones`, `creado_por`, `preparado_por`, `listo_por`, `creado_en`, `actualizado_en`, `corte_id`, `entrada_insumo_id`, `mov_salida_id`, `qr_path`, `pedido`) VALUES
(1, 36, 231, 1.00, 'kilo', 800.00, 'gramos', 'entregado', 'cortar y pelar', 1, 1, 1, '2025-10-25 09:32:30', '2025-10-25 09:33:23', 1, 2, NULL, 'archivos/qr/entrada_insumo_2.png', 1),
(2, 36, 231, 5.00, 'kilo', 4.00, 'gramos', 'entregado', 'pelar y cortar', 1, 1, 1, '2025-10-30 13:01:14', '2025-10-30 13:01:45', 1, 5, NULL, 'archivos/qr/entrada_insumo_5.png', 2);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `procesos_insumos_origenes`
--

CREATE TABLE `procesos_insumos_origenes` (
  `id` int(11) NOT NULL,
  `proceso_id` int(11) NOT NULL,
  `insumo_id` int(11) NOT NULL,
  `cantidad_origen` decimal(10,2) NOT NULL,
  `unidad_origen` varchar(20) NOT NULL,
  `cantidad_resultante` decimal(10,2) DEFAULT NULL,
  `creado_en` datetime DEFAULT current_timestamp(),
  `actualizado_en` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `proveedores`
--

INSERT INTO `proveedores` (`id`, `nombre`, `rfc`, `razon_social`, `regimen_fiscal`, `correo_facturacion`, `telefono`, `telefono2`, `correo`, `direccion`, `contacto_nombre`, `contacto_puesto`, `dias_credito`, `limite_credito`, `banco`, `clabe`, `cuenta_bancaria`, `sitio_web`, `observacion`, `activo`, `fecha_alta`, `actualizado_en`) VALUES
(1, 'CDIs', NULL, NULL, NULL, NULL, '555-123-4567', NULL, NULL, 'Calle Soya #123, CDMX', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, 'los mejores ', 1, '2025-09-22 08:36:48', '2025-10-07 18:20:39'),
(2, 'Pescados del Pacífico', NULL, NULL, NULL, NULL, '618 453 5697', NULL, NULL, 'Calle Felipe Pescador 200-A, Zona Centro, 34000 Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, 'busca a final de la caja mete mal producto', 1, '2025-09-22 08:36:48', '2025-10-08 15:52:49'),
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
(16, 'Coca Cola', NULL, NULL, NULL, NULL, '+52 618 826 0330', NULL, NULL, 'Carr. Durango–Mezquital Km 3.0, Real del Mezquital, 34199 Durango, Dgo.', NULL, NULL, 0, 0.00, NULL, NULL, NULL, NULL, 'revisar fondo latas', 1, '2025-09-22 08:36:48', '2025-10-17 20:21:02'),
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
  `corte_id` int(11) DEFAULT NULL,
  `valida` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `qrs_insumo`
--

INSERT INTO `qrs_insumo` (`id`, `token`, `json_data`, `estado`, `creado_por`, `creado_en`, `expiracion`, `pdf_envio`, `pdf_recepcion`, `corte_id`, `valida`) VALUES
(1, '6d3f2fd0de824c84a95174569735f3eb', '[{\"id\":36,\"nombre\":\"Pepino\",\"unidad\":\"kilo\",\"cantidad\":5,\"precio_unitario\":0}]', 'pendiente', 1, '2025-10-30 12:59:16', NULL, 'archivos/bodega/pdfs/qr_6d3f2fd0de824c84a95174569735f3eb.pdf', NULL, NULL, NULL),
(2, '1f75bd0c9f630daf8f2af87b81c537cf', '[{\"id\":89,\"nombre\":\"Aderezo\",\"unidad\":\"gramo\",\"cantidad\":1,\"precio_unitario\":0}]', 'pendiente', 1, '2025-10-30 22:43:20', NULL, 'archivos/bodega/pdfs/qr_1f75bd0c9f630daf8f2af87b81c537cf.pdf', NULL, NULL, NULL),
(3, '35c0d8b3af67aeccb34a7fb1c22c5d4f', '[{\"id\":89,\"nombre\":\"Aderezo\",\"unidad\":\"gramo\",\"cantidad\":0.1,\"precio_unitario\":0}]', 'pendiente', 1, '2025-10-30 22:55:34', NULL, 'archivos/bodega/pdfs/qr_35c0d8b3af67aeccb34a7fb1c22c5d4f.pdf', NULL, NULL, NULL);

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
-- Estructura de tabla para la tabla `reque_tipos`
--

CREATE TABLE `reque_tipos` (
  `id` int(11) NOT NULL,
  `nombre` varchar(120) NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf32 COLLATE=utf32_bin;

--
-- Volcado de datos para la tabla `reque_tipos`
--

INSERT INTO `reque_tipos` (`id`, `nombre`, `activo`) VALUES
(1, 'Refrigerador', 1),
(2, 'Barra', 1),
(3, 'Plasticos y otros', 1),
(4, 'Articulos de limpieza', 1);

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
(15, 'Surtidos', '/vistas/surtido/surtido.php', 'link', NULL, 4),
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
(38, 'rastreo', '/vistas/insumos/entrada_insumo.php', 'link', '', 8),
(39, 'Pagos', '/vistas/insumos/entradas_pagos.php', 'link', NULL, 9),
(40, 'Ajustes', '/vistas/insumos/ajuste.php', 'dropdown-item', 'Productos', 17);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sedes`
--

CREATE TABLE `sedes` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `direccion` text NOT NULL,
  `rfc` varchar(20) NOT NULL,
  `telefono` varchar(20) NOT NULL,
  `correo` varchar(100) DEFAULT NULL,
  `web` varchar(100) DEFAULT NULL,
  `activo` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `sedes`
--

INSERT INTO `sedes` (`id`, `nombre`, `direccion`, `rfc`, `telefono`, `correo`, `web`, `activo`) VALUES
(1, 'Forestal', 'Blvd. Luis Donaldo Colosio #317, Fracc. La Forestal ', 'VEAJ9408188U9', '6183222352', 'ventas@tokyo.com', 'tokyosushiprime.com', 1),
(2, 'Domingo Arrieta', 'Chabacanos SN-5, El Naranjal, 34190 Durango, Dgo.', 'VEAJ9408188U9', '6181690319', 'ventas@tokyo.com', 'tokyosushiprime.com', 1);

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
(152, 5, 37),
(153, 2, 1),
(154, 2, 3),
(155, 2, 18),
(156, 2, 14),
(157, 2, 2),
(158, 2, 24),
(160, 2, 19),
(161, 2, 2),
(162, 2, 24),
(164, 2, 4),
(165, 2, 29),
(166, 2, 25),
(167, 2, 2),
(168, 2, 24),
(170, 2, 11),
(171, 2, 2),
(172, 2, 24),
(174, 2, 26),
(175, 2, 15),
(176, 2, 21),
(177, 2, 35),
(179, 2, 21),
(180, 2, 35),
(182, 2, 32),
(183, 2, 6),
(184, 2, 33),
(185, 2, 23),
(186, 2, 38),
(187, 2, 34),
(188, 2, 39),
(189, 2, 21),
(190, 2, 35),
(192, 2, 21),
(193, 2, 35),
(195, 2, 36),
(196, 2, 31),
(197, 2, 27),
(198, 2, 37),
(199, 2, 40),
(200, 3, 1),
(201, 3, 14),
(202, 3, 3);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_bajo_stock`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_bajo_stock` (
`insumo_id` int(11)
,`nombre` varchar(100)
,`existencia` decimal(10,2)
,`minimo_stock` decimal(10,2)
,`status_stock` varchar(4)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_compras_por_insumo`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_compras_por_insumo` (
`insumo_id` int(11)
,`nombre` varchar(100)
,`compras` bigint(21)
,`monto_total` decimal(32,2)
,`costo_prom_unit` decimal(37,4)
,`primera_compra` datetime
,`ultima_compra` datetime
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_compras_por_proveedor`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_compras_por_proveedor` (
`proveedor_id` int(11)
,`nombre` varchar(100)
,`compras` bigint(21)
,`monto_total` decimal(32,2)
,`costo_prom_unit` decimal(37,4)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_consumo_por_insumo`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_consumo_por_insumo` (
`insumo_id` int(11)
,`nombre` varchar(100)
,`salidas` decimal(32,2)
,`traspasos_salida` decimal(32,2)
,`mermas` decimal(32,2)
,`consumo` decimal(33,2)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_existencias_y_cobertura`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_existencias_y_cobertura` (
`insumo_id` int(11)
,`nombre` varchar(100)
,`existencia` decimal(10,2)
,`consumo_30d` decimal(33,2)
,`dias_cobertura` decimal(17,2)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_procesos_rendimiento`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_procesos_rendimiento` (
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
,`rendimiento` decimal(15,4)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vw_reabasto_alertas`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vw_reabasto_alertas` (
`insumo_id` int(11)
,`nombre` varchar(100)
,`proxima_estimada` date
,`status` enum('proxima','vencida')
,`dias_restantes` int(7)
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

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_bajo_stock`  AS SELECT `insumos`.`id` AS `insumo_id`, `insumos`.`nombre` AS `nombre`, `insumos`.`existencia` AS `existencia`, `insumos`.`minimo_stock` AS `minimo_stock`, CASE WHEN `insumos`.`existencia` <= `insumos`.`minimo_stock` THEN 'BAJO' ELSE 'OK' END AS `status_stock` FROM `insumos` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_compras_por_insumo`
--
DROP TABLE IF EXISTS `vw_compras_por_insumo`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_compras_por_insumo`  AS SELECT `i`.`id` AS `insumo_id`, `i`.`nombre` AS `nombre`, count(`ei`.`id`) AS `compras`, round(sum(`ei`.`costo_total`),2) AS `monto_total`, round(sum(`ei`.`costo_total`) / nullif(sum(`ei`.`cantidad`),0),4) AS `costo_prom_unit`, min(`ei`.`fecha`) AS `primera_compra`, max(`ei`.`fecha`) AS `ultima_compra` FROM (`insumos` `i` left join `entradas_insumos` `ei` on(`ei`.`insumo_id` = `i`.`id`)) GROUP BY `i`.`id`, `i`.`nombre` ORDER BY `i`.`nombre` ASC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_compras_por_proveedor`
--
DROP TABLE IF EXISTS `vw_compras_por_proveedor`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_compras_por_proveedor`  AS SELECT `p`.`id` AS `proveedor_id`, `p`.`nombre` AS `nombre`, count(`ei`.`id`) AS `compras`, round(sum(`ei`.`costo_total`),2) AS `monto_total`, round(sum(`ei`.`costo_total`) / nullif(sum(`ei`.`cantidad`),0),4) AS `costo_prom_unit` FROM (`entradas_insumos` `ei` left join `proveedores` `p` on(`p`.`id` = `ei`.`proveedor_id`)) GROUP BY `p`.`id`, `p`.`nombre` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_consumo_por_insumo`
--
DROP TABLE IF EXISTS `vw_consumo_por_insumo`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_consumo_por_insumo`  AS SELECT `i`.`id` AS `insumo_id`, `i`.`nombre` AS `nombre`, sum(case when `m`.`tipo` = 'salida' and `m`.`cantidad` < 0 then -`m`.`cantidad` else 0 end) AS `salidas`, sum(case when `m`.`tipo` = 'traspaso' and `m`.`cantidad` < 0 then -`m`.`cantidad` else 0 end) AS `traspasos_salida`, sum(case when `m`.`tipo` = 'merma' then abs(`m`.`cantidad`) else 0 end) AS `mermas`, sum(case when `m`.`tipo` = 'salida' and `m`.`cantidad` < 0 then -`m`.`cantidad` else 0 end) + sum(case when `m`.`tipo` = 'traspaso' and `m`.`cantidad` < 0 then -`m`.`cantidad` else 0 end) AS `consumo` FROM (`insumos` `i` left join `movimientos_insumos` `m` on(`m`.`insumo_id` = `i`.`id`)) GROUP BY `i`.`id`, `i`.`nombre` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_existencias_y_cobertura`
--
DROP TABLE IF EXISTS `vw_existencias_y_cobertura`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_existencias_y_cobertura`  AS WITH consumo_30 AS (SELECT `m`.`insumo_id` AS `insumo_id`, sum(case when `m`.`tipo` = 'salida' and `m`.`cantidad` < 0 then -`m`.`cantidad` else 0 end) + sum(case when `m`.`tipo` = 'traspaso' and `m`.`cantidad` < 0 then -`m`.`cantidad` else 0 end) AS `consumo_30d` FROM `movimientos_insumos` AS `m` WHERE `m`.`fecha` >= curdate() - interval 30 day GROUP BY `m`.`insumo_id`)  SELECT `i`.`id` AS `insumo_id`, `i`.`nombre` AS `nombre`, `i`.`existencia` AS `existencia`, coalesce(`c`.`consumo_30d`,0) AS `consumo_30d`, round(case when coalesce(`c`.`consumo_30d`,0) = 0 then NULL else `i`.`existencia` / (coalesce(`c`.`consumo_30d`,0) / 30.0) end,2) AS `dias_cobertura` FROM (`insumos` `i` left join `consumo_30` `c` on(`c`.`insumo_id` = `i`.`id`)))  ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_procesos_rendimiento`
--
DROP TABLE IF EXISTS `vw_procesos_rendimiento`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_procesos_rendimiento`  AS SELECT `v`.`id` AS `id`, `v`.`estado` AS `estado`, `v`.`insumo_origen_id` AS `insumo_origen_id`, `v`.`insumo_origen` AS `insumo_origen`, `v`.`cantidad_origen` AS `cantidad_origen`, `v`.`unidad_origen` AS `unidad_origen`, `v`.`insumo_destino_id` AS `insumo_destino_id`, `v`.`insumo_destino` AS `insumo_destino`, `v`.`cantidad_resultante` AS `cantidad_resultante`, `v`.`unidad_destino` AS `unidad_destino`, `v`.`creado_en` AS `creado_en`, `v`.`qr_path` AS `qr_path`, `v`.`entrada_insumo_id` AS `entrada_insumo_id`, `v`.`mov_salida_id` AS `mov_salida_id`, round(`v`.`cantidad_resultante` / nullif(`v`.`cantidad_origen`,0),4) AS `rendimiento` FROM `v_procesos_insumos` AS `v` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vw_reabasto_alertas`
--
DROP TABLE IF EXISTS `vw_reabasto_alertas`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vw_reabasto_alertas`  AS SELECT `a`.`insumo_id` AS `insumo_id`, `i`.`nombre` AS `nombre`, `a`.`proxima_estimada` AS `proxima_estimada`, `a`.`status` AS `status`, to_days(`a`.`proxima_estimada`) - to_days(curdate()) AS `dias_restantes` FROM (`reabasto_alertas` `a` join `insumos` `i` on(`i`.`id` = `a`.`insumo_id`)) ;

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
-- Indices de la tabla `impresoras`
--
ALTER TABLE `impresoras`
  ADD PRIMARY KEY (`print_id`);

--
-- Indices de la tabla `insumos`
--
ALTER TABLE `insumos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_insumo_reque` (`reque_id`);

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
  ADD KEY `ix_proc_corte` (`corte_id`),
  ADD KEY `idx_proc_pedido` (`pedido`);

--
-- Indices de la tabla `procesos_insumos_origenes`
--
ALTER TABLE `procesos_insumos_origenes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_proc_origenes_proceso` (`proceso_id`),
  ADD KEY `idx_proc_origenes_insumo` (`insumo_id`);

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
-- Indices de la tabla `reque_tipos`
--
ALTER TABLE `reque_tipos`
  ADD PRIMARY KEY (`id`);

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `cortes_almacen_detalle`
--
ALTER TABLE `cortes_almacen_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=225;

--
-- AUTO_INCREMENT de la tabla `despachos`
--
ALTER TABLE `despachos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `despachos_detalle`
--
ALTER TABLE `despachos_detalle`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `entradas_insumos`
--
ALTER TABLE `entradas_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `impresoras`
--
ALTER TABLE `impresoras`
  MODIFY `print_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `insumos`
--
ALTER TABLE `insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=232;

--
-- AUTO_INCREMENT de la tabla `logs_accion`
--
ALTER TABLE `logs_accion`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `mermas_insumo`
--
ALTER TABLE `mermas_insumo`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `movimientos_insumos`
--
ALTER TABLE `movimientos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT de la tabla `procesos_insumos`
--
ALTER TABLE `procesos_insumos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `procesos_insumos_origenes`
--
ALTER TABLE `procesos_insumos_origenes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

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
-- AUTO_INCREMENT de la tabla `reque_tipos`
--
ALTER TABLE `reque_tipos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `rutas`
--
ALTER TABLE `rutas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=41;

--
-- AUTO_INCREMENT de la tabla `sucursales`
--
ALTER TABLE `sucursales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `usuarios`
--
ALTER TABLE `usuarios`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `usuario_ruta`
--
ALTER TABLE `usuario_ruta`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=203;

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
-- Filtros para la tabla `insumos`
--
ALTER TABLE `insumos`
  ADD CONSTRAINT `fk_insumo_reque` FOREIGN KEY (`reque_id`) REFERENCES `reque_tipos` (`id`) ON UPDATE CASCADE;

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
