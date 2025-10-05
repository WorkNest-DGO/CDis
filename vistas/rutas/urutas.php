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
$title = 'Asignar Rutas';
ob_start();
?>

<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Asignar Rutas a Usuarios</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Asignar Rutas</a>
            </div>
        </div>
    </div>
</div>
<!-- Page Header End -->

<div class="container mt-5 mb-5">
    <div class="form-group">
        <label for="usuarioSelect">Usuario:</label>
        <select id="usuarioSelect" class="form-control"></select>
    </div>
    <div class="table-responsive mt-3">
        <table id="tablaRutasUsuario" class="styled-table">
            <thead>
                <tr>
                    <th>Nombre</th>
                    <th>Path</th>
                    <th>Tipo</th>
                    <th>Grupo</th>
                    <th>Orden</th>
                    <th>Asignado</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>
    <div class="d-flex justify-content-end mt-3">
        <button class="btn custom-btn" id="btnGuardar">Guardar</button>
    </div>
</div>

<!-- Modal global de mensajes -->
<div class="modal fade" id="appMsgModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div style="color:black" class="modal-content">
            <div  class="modal-header">
                <h5  style="color:black"class="modal-title">Mensaje</h5>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body"></div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
            </div>
        </div>
    </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="../../utils/js/modal-lite.js"></script>
<script src="usuario_ruta.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
