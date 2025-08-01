<?php
require_once __DIR__ . '/../../utils/cargar_permisos.php';
$path_actual = str_replace('/CDI', '', $_SERVER['PHP_SELF']);
if (!in_array($path_actual, $_SESSION['rutas_permitidas'])) {
    http_response_code(403);
    echo 'Acceso no autorizado';
    exit;
}
$title = 'Insumos';
ob_start();
?>



<!-- Page Header Start -->
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Ingredientes</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Inventario de ingredientes</a>
            </div>
        </div>
    </div>
</div>
<!-- Page Header End -->




<!-- Blog Start -->
<div class="blog">
    <div class="container">
        <div class="section-header text-center">
            <p>Insumos</p>
            <h2>Recuerda validar los datos antes de guardar altas</h2>

            <div class="d-flex justify-content-center mb-3">
                <a class="btn custom-btn me-2" type="button" id="btnNuevoInsumo">Nuevo insumo</a>
            </div>
            <div class="d-flex justify-content-center mb-3">
                <input type="text" id="buscarInsumo" class="form-control" placeholder="Buscar" style="text-align: right;">
            </div>
                <div class="row">
        <div class="col-12">
            <ul id="paginador" class="pagination justify-content-center"></ul>
        </div>
    </div>
        </div>
        <div class="row" id="catalogoInsumos"></div>

        <form id="formInsumo" class="custom-modal" style="display:none;">
            <input type="hidden" id="insumoId">
            <div>
                <label>Nombre:</label><br>
                <input type="text" id="nombre"><br>
                <label>Unidad:</label><br>
                <input type="text" id="unidad"><br>
                <label>Existencia:</label><br>
                <input type="number" step="0.01" id="existencia" value="0"><br>
                <label>Tipo:</label><br>
                <select id="tipo_control"><br>
                    <option value="por_receta">por_receta</option>
                    <option value="unidad_completa">unidad_completa</option>
                    <option value="uso_general">uso_general</option>
                    <option value="no_controlado">no_controlado</option>
                    <option value="desempaquetado">desempaquetado</option>
                </select><br><br>
                <input type="file" id="imagen"><br><br>
                <button class="btn custom-btn me-2" type="submit">Guardar</button>
                <button class="btn custom-btn me-2" type="button" id="cancelarInsumo">Cancelar</button>
            </div>
        </form>

    </div>

</div>
</div>
<!-- Blog End -->

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="insumos.js"></script>
</body>

</html>

<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
