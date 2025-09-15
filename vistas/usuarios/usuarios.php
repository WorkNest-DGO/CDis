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
$title = 'Usuarios';
ob_start();
?>

<!-- Page Header Start -->
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Usuarios</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Usuarios</a>
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
        <label for="buscarUsuario" class="me-2">Buscar:</label>
        <input type="text" id="buscarUsuario" class="form-control" placeholder="Nombre, usuario o rol">
    </div>
        <div class="row mt-2">
        <div class="col-12">
            <ul id="paginadorUsuarios" class="pagination justify-content-center"></ul>
        </div>
    </div>
    <div class="table-responsive">
        <table id="tablaUsuarios" class="styled-table">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Nombre</th>
                    <th>Usuario</th>
                    <th>Rol</th>
                    <th>Activo</th>
                    <th>Acciones</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>

</div>

<div class="modal fade" id="modalUsuario" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <form id="formUsuario">
                <div class="modal-header">
                    <h5 class="modal-title">Usuario</h5>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
                </div>
                <div class="modal-body">
                    <input type="hidden" id="usuarioId">
                    <div class="form-group">
                        <label for="nombre">Nombre:</label>
                        <input type="text" id="nombre" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label for="usuario">Usuario:</label>
                        <input type="text" id="usuario" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label for="contrasena">Contraseña:</label>
                        <input type="password" id="contrasena" class="form-control">
                    </div>
                    <div class="form-group">
                        <label for="rol">Rol:</label>
                        <select id="rol" class="form-control">
                            <option value="cajero">cajero</option>
                            <option value="mesero">mesero</option>
                            <option value="admin">admin</option>
                            <option value="repartidor">repartidor</option>
                            <option value="cocinero">cocinero</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="activo">Activo:</label>
                        <select id="activo" class="form-control">
                            <option value="1">Sí</option>
                            <option value="0">No</option>
                        </select>
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
<script src="usuarios.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
