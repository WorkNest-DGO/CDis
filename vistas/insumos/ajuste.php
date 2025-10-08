<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Validar ruta contra permisos de sesión
$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__app_base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
$path_actual = preg_replace('#^' . preg_quote($__app_base, '#') . '#', '', ($__sn ?: $_SERVER['PHP_SELF']));
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Ajuste de Insumos';
ob_start();
?>
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Ajuste de Insumos</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Ajustes</a>
            </div>
        </div>
    </div>
    </div>

<div class="container mt-4">
    <div class="card p-3" style="color:black">
        <div class="row g-3 align-items-end">
            <div class="col-md-4">
                <label for="selInsumo" class="form-label">Insumo</label>
                <select id="selInsumo" class="form-select form-select-sm">
                    <option value="">Seleccione insumo...</option>
                </select>
            </div>
            <div class="col-md-4">
                <label for="selEntrada" class="form-label">Lote / Entrada</label>
                <select id="selEntrada" class="form-select form-select-sm" disabled>
                    <option value="">Seleccione entrada...</option>
                </select>
            </div>
            <div class="col-md-4">
                <label class="form-label">Cantidad actual del lote</label>
                <input type="text" id="txtCantidadActual" class="form-control form-control-sm" value="" readonly>
            </div>
            <div class="col-md-3">
                <label for="txtAjuste" class="form-label">Ajuste (+ suma / - resta)</label>
                <input type="number" step="0.01" id="txtAjuste" class="form-control form-control-sm" placeholder="Ej. 5 o -2.5">
            </div>
            <div class="col-md-6">
                <label for="txtObs" class="form-label">Observación</label>
                <input type="text" id="txtObs" class="form-control form-control-sm" maxlength="255" placeholder="Motivo del ajuste">
            </div>
            <div class="col-md-3 text-end">
                <button class="btn custom-btn" id="btnAplicar">Aplicar ajuste</button>
            </div>
        </div>
        <div id="estadoAjuste" class="mt-2" style="font-size:0.9rem; color:#666;"></div>
    </div>

    <div class="mt-4">
        <div class="table-responsive">
            <table class="styled-table" id="tablaEntradas">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Fecha</th>
                        <th>Descripción</th>
                        <th>Cantidad</th>
                        <th>Cantidad actual</th>
                        <th>Unidad</th>
                        <th>Proveedor</th>
                    </tr>
                </thead>
                <tbody></tbody>
            </table>
        </div>
    </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="ajuste.js" defer></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

