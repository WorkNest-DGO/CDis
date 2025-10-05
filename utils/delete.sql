
SET FOREIGN_KEY_CHECKS = 0;


DELETE FROM despachos_detalle;
ALTER TABLE despachos_detalle AUTO_INCREMENT = 1;

DELETE FROM cortes_almacen_detalle;
ALTER TABLE cortes_almacen_detalle AUTO_INCREMENT = 1;

DELETE FROM movimientos_insumos;
ALTER TABLE movimientos_insumos AUTO_INCREMENT = 1;

DELETE FROM reabasto_alertas;
ALTER TABLE reabasto_alertas AUTO_INCREMENT = 1;

DELETE FROM reabasto_metricas;
ALTER TABLE reabasto_metricas AUTO_INCREMENT = 1;

DELETE FROM qrs_insumo;
ALTER TABLE qrs_insumo AUTO_INCREMENT = 1;

DELETE FROM recepciones_log;
ALTER TABLE recepciones_log AUTO_INCREMENT = 1;

DELETE FROM entradas_insumos;
ALTER TABLE entradas_insumos AUTO_INCREMENT = 1;


DELETE FROM despachos;
ALTER TABLE despachos AUTO_INCREMENT = 1;

DELETE FROM cortes_almacen;
ALTER TABLE cortes_almacen AUTO_INCREMENT = 1;

DELETE FROM productos;
ALTER TABLE productos AUTO_INCREMENT = 1;

-- 4) Misceláneo
DELETE FROM logs_accion;
ALTER TABLE logs_accion AUTO_INCREMENT = 1;

SET FOREIGN_KEY_CHECKS = 1;
