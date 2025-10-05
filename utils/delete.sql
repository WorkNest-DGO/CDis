-- Reset operativo para CDIS (respeta llaves foráneas y orden de dependencia)
SET FOREIGN_KEY_CHECKS = 0;

-- Hijas primero (dependientes)
DELETE FROM despachos_detalle;
ALTER TABLE despachos_detalle AUTO_INCREMENT = 1;

DELETE FROM cortes_almacen_detalle;
ALTER TABLE cortes_almacen_detalle AUTO_INCREMENT = 1;

DELETE FROM mermas_insumo;
ALTER TABLE mermas_insumo AUTO_INCREMENT = 1;

DELETE FROM movimientos_insumos;
ALTER TABLE movimientos_insumos AUTO_INCREMENT = 1;

DELETE FROM reabasto_alertas;
ALTER TABLE reabasto_alertas AUTO_INCREMENT = 1;

DELETE FROM reabasto_metricas;
ALTER TABLE reabasto_metricas AUTO_INCREMENT = 1;

DELETE FROM recepciones_log;
ALTER TABLE recepciones_log AUTO_INCREMENT = 1;

-- mermas_insumo depende de qrs_insumo, así que primero borramos mermas y después qrs
DELETE FROM qrs_insumo;
ALTER TABLE qrs_insumo AUTO_INCREMENT = 1;

-- mermas_insumo también depende de entradas_insumos, así que entradas después de mermas
DELETE FROM entradas_insumos;
ALTER TABLE entradas_insumos AUTO_INCREMENT = 1;

-- Otros operativos
DELETE FROM logs_accion;
ALTER TABLE logs_accion AUTO_INCREMENT = 1;

DELETE FROM procesos_insumos;
ALTER TABLE procesos_insumos AUTO_INCREMENT = 1;

-- Padre de despachos_detalle
DELETE FROM despachos;
ALTER TABLE despachos AUTO_INCREMENT = 1;

-- Catálogo operativo independiente (si deseas conservar productos, comenta estas dos líneas)
DELETE FROM productos;
ALTER TABLE productos AUTO_INCREMENT = 1;

-- Padre con múltiples dependientes: borrar al final
DELETE FROM cortes_almacen;
ALTER TABLE cortes_almacen AUTO_INCREMENT = 1;

SET FOREIGN_KEY_CHECKS = 1;
