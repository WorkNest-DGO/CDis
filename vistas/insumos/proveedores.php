<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Base app dinámica y ruta relativa para validación
$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__app_base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
$path_actual = preg_replace('#^' . preg_quote($__app_base, '#') . '#', '', ($__sn ?: $_SERVER['PHP_SELF']));
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Proveedores';
ob_start();
?>
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Proveedores</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Proveedores</a>
            </div>
        </div>
    </div>
    </div>

<div class="container mt-4">
    <div class="bg-dark p-4 rounded">
        <div class="row g-3 align-items-end">
            <div class="col-md-8">
                <label class="text-white" for="selProveedor">Seleccionar proveedor</label>
                <select id="selProveedor" class="form-control"></select>
            </div>
            <div class="col-md-4 d-flex gap-2">
                <button id="btnNuevo" class="btn custom-btn me-2" type="button">Nuevo</button>
                <a class="btn btn-secondary" href="../../api/insumos/exportar_proveedores_excel.php">Exportar a Excel</a>
            </div>
        </div>
    </div>
</div>

<div class="container mt-4">
    <form id="formProveedor" class="bg-dark p-4 rounded">
        <input type="hidden" id="proveedorId">
        <div class="row g-3">
            <div class="col-md-6">
                <label class="text-white" for="nombre">Nombre</label>
                <input type="text" id="nombre" class="form-control" required>
            </div>
            <div class="col-md-3">
                <label class="text-white" for="rfc">RFC</label>
                <input type="text" id="rfc" class="form-control">
            </div>
            <div class="col-md-3">
                <label class="text-white" for="regimen_fiscal">Régimen fiscal</label>
                <input type="text" id="regimen_fiscal" class="form-control" placeholder="601, 603, ...">
            </div>

            <div class="col-md-6">
                <label class="text-white" for="razon_social">Razón social</label>
                <input type="text" id="razon_social" class="form-control">
            </div>
            <div class="col-md-6">
                <label class="text-white" for="correo_facturacion">Correo facturación</label>
                <input type="email" id="correo_facturacion" class="form-control">
            </div>

            <div class="col-md-3">
                <label class="text-white" for="telefono">Teléfono</label>
                <input type="text" id="telefono" class="form-control">
            </div>
            <div class="col-md-3">
                <label class="text-white" for="telefono2">Teléfono 2</label>
                <input type="text" id="telefono2" class="form-control">
            </div>
            <div class="col-md-6">
                <label class="text-white" for="correo">Correo</label>
                <input type="email" id="correo" class="form-control">
            </div>

            <div class="col-12">
                <label class="text-white" for="direccion">Dirección</label>
                <textarea id="direccion" class="form-control" rows="2"></textarea>
            </div>

            <div class="col-md-6">
                <label class="text-white" for="contacto_nombre">Contacto nombre</label>
                <input type="text" id="contacto_nombre" class="form-control">
            </div>
            <div class="col-md-6">
                <label class="text-white" for="contacto_puesto">Contacto puesto</label>
                <input type="text" id="contacto_puesto" class="form-control">
            </div>

            <div class="col-md-3">
                <label class="text-white" for="dias_credito">Días crédito</label>
                <input type="number" id="dias_credito" class="form-control" value="0" min="0">
            </div>
            <div class="col-md-3">
                <label class="text-white" for="limite_credito">Límite crédito</label>
                <input type="number" step="0.01" id="limite_credito" class="form-control" value="0.00">
            </div>
            <div class="col-md-3">
                <label class="text-white" for="banco">Banco</label>
                <input type="text" id="banco" class="form-control">
            </div>
            <div class="col-md-3">
                <label class="text-white" for="clabe">CLABE</label>
                <input type="text" id="clabe" class="form-control" maxlength="18">
            </div>

            <div class="col-md-6">
                <label class="text-white" for="cuenta_bancaria">Cuenta bancaria</label>
                <input type="text" id="cuenta_bancaria" class="form-control">
            </div>
            <div class="col-md-6">
                <label class="text-white" for="sitio_web">Sitio web</label>
                <input type="url" id="sitio_web" class="form-control" placeholder="https://...">
            </div>

            <div class="col-12">
                <label class="text-white" for="observacion">Observación</label>
                <textarea id="observacion" class="form-control" rows="2"></textarea>
            </div>

            <div class="col-md-3 form-check form-switch mt-2">
                <input class="form-check-input" type="checkbox" id="activo" checked>
                <label class="form-check-label text-white" for="activo">Activo</label>
            </div>
        </div>
        <div class="mt-4 d-flex gap-2">
            <button id="btnGuardar" class="btn custom-btn me-2" type="submit">Guardar</button>
            <button id="btnEliminar" class="btn btn-danger" type="button">Eliminar</button>
        </div>
    </form>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="proveedores.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

