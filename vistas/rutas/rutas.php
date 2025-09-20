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
$title = 'Rutas';
ob_start();
?>

<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Rutas</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Rutas</a>
            </div>
        </div>
    </div>
</div>
<!-- Page Header End -->

<div class="container mt-5 mb-5">
    <div class="d-flex justify-content-end mb-3">
        <button class="btn custom-btn" id="btnAgregar">Agregar</button>
    </div>
    <div class="filtros-container mb-2">
        <label for="buscarRuta" class="me-2">Buscar:</label>
        <input type="text" id="buscarRuta" class="form-control" placeholder="Nombre, path o grupo">
    </div>
        <div class="row mt-2">
        <div class="col-12">
            <ul id="paginadorRutas" class="pagination justify-content-center"></ul>
        </div>
    </div>
    <div class="table-responsive">
        <table id="tablaRutas" class="styled-table">
            <thead>
                <tr>
                    <th>Nombre</th>
                    <th>Path</th>
                    <th>Tipo</th>
                    <th>Grupo</th>
                    <th>Orden</th>
                    <th>Acciones</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>

</div>

<div class="modal fade" id="modalRuta" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form id="formRuta">
                <div class="modal-header">
                    <h5 class="modal-title">Ruta</h5>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                </div>
                <div class="modal-body">
                    <input type="hidden" id="nombreOriginal">
                    <div class="form-group">
                        <label for="nombre">Nombre:</label>
                        <input type="text" id="nombre" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label for="path">Path:</label>
                        <input type="text" id="path" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label for="tipo">Tipo:</label>
                        <select id="tipo" class="form-control">
                            <option value="link">link</option>
                            <option value="dropdown">dropdown</option>
                            <option value="dropdown-item">dropdown-item</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="grupo">Grupo:</label>
                        <input type="text" id="grupo" class="form-control">
                    </div>
                    <div class="form-group">
                        <label for="orden">Orden:</label>
                        <input type="number" id="orden" class="form-control" value="0">
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="submit" class="btn custom-btn">Guardar</button>
                    <button type="button" class="btn custom-btn" data-dismiss="modal">Cancelar</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Modal global de mensajes -->
<div class="modal fade" id="appMsgModal" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">Mensaje</h5>
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
<script src="rutas.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
