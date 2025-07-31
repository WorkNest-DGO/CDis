
-- Base de Datos CDIS adaptada
-- Fecha de creación: 2025-07-31

CREATE DATABASE IF NOT EXISTS CDIS CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE CDIS;

-- Tabla: usuarios
CREATE TABLE usuarios (
  id INT(11) NOT NULL PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  usuario VARCHAR(50) NOT NULL,
  contrasena VARCHAR(255) NOT NULL,
  rol ENUM('cajero','mesero','admin','repartidor','cocinero') NOT NULL,
  activo TINYINT(1) DEFAULT 1,
  UNIQUE KEY (usuario)
);

INSERT INTO usuarios (id, nombre, usuario, contrasena, rol, activo) VALUES
(1, 'Administrador', 'admin', 'admin', 'admin', 1);

-- Tabla: proveedores
CREATE TABLE proveedores (
  id INT(11) NOT NULL PRIMARY KEY,
  nombre VARCHAR(100),
  telefono VARCHAR(20),
  direccion TEXT
);

INSERT INTO proveedores (id, nombre, telefono, direccion) VALUES
(1, 'Suministros Sushi MX', '555-123-4567', 'Calle Soya #123, CDMX'),
(2, 'Pescados del Pacífico', '555-987-6543', 'Av. Mar #456, CDMX');

-- Tabla: insumos (funciona como bodega en CDIS)
CREATE TABLE insumos (
  id INT(11) NOT NULL PRIMARY KEY,
  nombre VARCHAR(100),
  unidad VARCHAR(20),
  existencia DECIMAL(10,2),
  tipo_control ENUM('por_receta','unidad_completa','uso_general','no_controlado','desempaquetado') DEFAULT 'por_receta',
  imagen VARCHAR(255),
  minimo_stock DECIMAL(10,2) DEFAULT 0
);

-- Tabla: productos (referenciado si lo requiere el inventario)
CREATE TABLE productos (
  id INT(11) NOT NULL PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  precio DECIMAL(10,2) NOT NULL,
  descripcion TEXT,
  existencia INT DEFAULT 0,
  activo TINYINT(1) DEFAULT 1,
  imagen VARCHAR(255)
);

-- Tabla: entradas_insumo
CREATE TABLE entradas_insumo (
  id INT(11) NOT NULL PRIMARY KEY,
  proveedor_id INT(11),
  usuario_id INT(11),
  fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
  total DECIMAL(10,2),
  FOREIGN KEY (proveedor_id) REFERENCES proveedores(id),
  FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Tabla: entradas_detalle
CREATE TABLE entradas_detalle (
  id INT(11) NOT NULL PRIMARY KEY,
  entrada_id INT(11),
  insumo_id INT(11) NOT NULL,
  cantidad INT(11),
  precio_unitario DECIMAL(10,2),
  subtotal DECIMAL(10,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
  FOREIGN KEY (entrada_id) REFERENCES entradas_insumo(id),
  FOREIGN KEY (insumo_id) REFERENCES insumos(id)
);

-- Tabla: movimientos_insumos
CREATE TABLE movimientos_insumos (
  id INT(11) NOT NULL PRIMARY KEY,
  tipo ENUM('entrada','salida','ajuste','traspaso') DEFAULT 'entrada',
  usuario_id INT(11),
  usuario_destino_id INT(11),
  insumo_id INT(11),
  cantidad DECIMAL(10,2),
  observacion TEXT,
  fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
  qr_token VARCHAR(64),
  FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
  FOREIGN KEY (insumo_id) REFERENCES insumos(id)
);

-- Tabla: logs_accion
CREATE TABLE logs_accion (
  id INT(11) NOT NULL PRIMARY KEY,
  usuario_id INT(11),
  modulo VARCHAR(50),
  accion VARCHAR(100),
  fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
  referencia_id INT(11)
);

-- Tabla: qrs_insumo
CREATE TABLE qrs_insumo (
  id INT(11) NOT NULL PRIMARY KEY,
  token VARCHAR(64) NOT NULL,
  json_data TEXT,
  estado ENUM('pendiente','confirmado','anulado') DEFAULT 'pendiente',
  creado_por INT(11),
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  expiracion DATETIME,
  pdf_envio VARCHAR(255),
  pdf_recepcion VARCHAR(255)
);

-- Tabla: sucursales
CREATE TABLE sucursales (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  ubicacion VARCHAR(255),
  token_acceso VARCHAR(64) UNIQUE,
  activo TINYINT(1) DEFAULT 1
);

-- Tabla: despachos
CREATE TABLE despachos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  sucursal_id INT,
  usuario_id INT,
  fecha_envio DATETIME DEFAULT CURRENT_TIMESTAMP,
  fecha_recepcion DATETIME,
  estado ENUM('pendiente','recibido','cancelado') DEFAULT 'pendiente',
  qr_token VARCHAR(64),
  FOREIGN KEY (sucursal_id) REFERENCES sucursales(id),
  FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Tabla: despachos_detalle
CREATE TABLE despachos_detalle (
  id INT AUTO_INCREMENT PRIMARY KEY,
  despacho_id INT,
  insumo_id INT,
  cantidad DECIMAL(10,2),
  unidad VARCHAR(20),
  precio_unitario DECIMAL(10,2),
  subtotal DECIMAL(10,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
  FOREIGN KEY (despacho_id) REFERENCES despachos(id),
  FOREIGN KEY (insumo_id) REFERENCES insumos(id)
);

-- Tabla: recepciones_log
CREATE TABLE recepciones_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  sucursal_id INT,
  qr_token VARCHAR(64),
  fecha_recepcion DATETIME DEFAULT CURRENT_TIMESTAMP,
  usuario_id INT,
  json_recibido TEXT,
  estado ENUM('exitoso', 'error') DEFAULT 'exitoso',
  FOREIGN KEY (sucursal_id) REFERENCES sucursales(id),
  FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Vista opcional para bajo stock
CREATE VIEW vw_bajo_stock AS
SELECT * FROM insumos WHERE existencia <= minimo_stock;

-- Fin del script
