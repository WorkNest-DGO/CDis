<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
// Base app dinamica y ruta relativa para validacion
$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__app_base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
$path_actual = preg_replace('#^' . preg_quote($__app_base, '#') . '#', '', ($__sn ?: $_SERVER['PHP_SELF']));
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Catalogo de Areas (reque_tipos)';
ob_start();
?>
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Catálogo de Áreas (reque_tipos)</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Áreas</a>
            </div>
        </div>
    </div>
</div>

<div class="container mt-4">
  <div class="row g-4">
    <div class="col-lg-7">
      <div class="bg-dark p-3 rounded">
        <div class="d-flex justify-content-between align-items-center mb-2">
          <h5 class="m-0 text-white">Lista</h5>
          <div class="d-flex gap-2">
            <input type="text" id="filtro" placeholder="Buscar..." class="form-control form-control-sm" style="max-width:200px;">
            <button id="btnNuevo" class="btn custom-btn-sm">Nuevo</button>
          </div>
        </div>
        <div class="table-responsive">
          <table class="styled-table" id="tablaRequeTipos">
            <thead>
              <tr>
                <th>ID</th>
                <th>Nombre</th>
                <th>Activo</th>
                <th>Acciones</th>
              </tr>
            </thead>
            <tbody></tbody>
          </table>
        </div>
      </div>
    </div>
    <div class="col-lg-5">
      <form id="formRequeTipo" class="bg-dark p-3 rounded">
        <input type="hidden" id="rt_id">
        <div class="mb-3">
          <label class="text-white" for="rt_nombre">Nombre</label>
          <input type="text" id="rt_nombre" class="form-control" required>
        </div>
        <div class="form-check form-switch mb-3">
          <input class="form-check-input" type="checkbox" id="rt_activo" checked>
          <label class="form-check-label text-white" for="rt_activo">Activo</label>
        </div>
        <div class="d-flex gap-2">
          <button type="submit" class="btn custom-btn">Guardar</button>
          <button type="button" id="btnEliminar" class="btn btn-danger">Eliminar</button>
        </div>
        <div id="estado" class="mt-2" style="font-size:.9rem; color:#ccc;"></div>
      </form>
    </div>
  </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="reque_tipos.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>

