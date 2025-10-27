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
$title = 'Cortes Almacén';
ob_start();
?>
<div class="page-header">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Cortes de Almacén</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="">Cortes</a>
            </div>
        </div>
    </div>
</div>
<div class="container mt-4 ">
    <div class="mb-3">
        <button class="btn custom-btn me-2" id="btnAbrirCorte">Abrir corte</button>
        <button class="btn custom-btn me-2" id="btnCerrarCorte">Cerrar corte</button>
         <div id="formObservaciones" class="mb-3" style="display:none;">
        <textarea id="observaciones" class="form-control mb-2" placeholder="Observaciones"></textarea>
        <button class="btn custom-btn" id="guardarCierre">Guardar cierre</button>
    </div>
    </div>
</div>
<div style="display: none;" class="container mt-4 hidden">
    <button class="btn custom-btn me-2" id="btnExportarExcel">Exportar a Excel</button>
        <button class="btn custom-btn" id="btnExportarPdf">Exportar a PDF</button>
   
    <div class="mb-3">
        <label for="buscarFecha">Fecha:</label>
        <input type="date" id="buscarFecha" class="form-control-sm">
        <button class="btn custom-btn-sm" id="btnBuscar">Buscar</button>
    </div>
    <div class="mb-3">
        <select id="listaCortes" class="form-select form-select-sm">
            <option value="">Seleccione corte...</option>
        </select>
    </div>
    <div class="row mb-2">
        <div class="col-md-6 mb-2">
            <input type="text" id="filtroInsumo" class="form-control form-control-sm" placeholder="Buscar insumo">
        </div>
        <div class="col-md-3">
            <select id="registrosPagina" class="form-select form-select-sm">
                <option value="15">15</option>
                <option value="25">25</option>
                <option value="50">50</option>
            </select>
        </div>
        <div class="col-md-3">
            <button class="btn custom-btn w-100" id="btnActualizarCorte">Actualizar</button>
        </div>
    </div>
    <div class="table-responsive">
        <table id="tablaResumen" class="styled-table">
            <thead>
                <tr>
                    <th>Insumo</th>
                    <th>Inicial</th>
                    <th>Entradas</th>
                    <th>Salidas</th>
                    <th>Mermas</th>
                    <th>Final</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
        <div id="totMermas" class="text-white mt-2"></div>
        <div class="d-flex justify-content-between mt-2">
            <button class="btn custom-btn-sm" id="prevPagina">&lt;</button>
            <button class="btn custom-btn-sm" id="nextPagina">&gt;</button>
        </div>
    </div>
</div>

<!-- Reporte: Entradas/Salidas de Insumos -->
<div class="container mt-5" id="reporteEntradasSalidas">
    <div class="row mb-3">
        <div class="col-12">
            <h3>Reporte de Entradas/Salidas de Insumos</h3>
        </div>
    </div>
    <div style="color:black" class="card p-3 mb-3">
        <div class="row g-2 align-items-end">
            <div class="col-md-3">
                <label class="form-label" for="modoReporte">Ver por</label>
                <select id="modoReporte" class="form-select form-select-sm">
                    <option value="range">Rango de fechas</option>
                    <option value="corte">Corte</option>
                </select>
            </div>
            <div class="col-md-3" id="grpDesde">
                <label class="form-label" for="dateFrom">Desde</label>
                <input type="date" id="dateFrom" class="form-control form-control-sm" />
            </div>
            <div class="col-md-3" id="grpHasta">
                <label class="form-label" for="dateTo">Hasta</label>
                <input type="date" id="dateTo" class="form-control form-control-sm" />
            </div>
            <div class="col-md-4" id="grpCorte" style="display:none;">
                <label class="form-label" for="selCorte">Corte</label>
                <select id="selCorte" class="form-select form-select-sm">
                    <option value="">Seleccione corte...</option>
                </select>
            </div>
            <div class="col-md-3">
                <div class="form-check mt-4">
                    <input type="checkbox" id="chkDevoEnEntradas" class="form-check-input" />
                    <label class="form-check-label" for="chkDevoEnEntradas">Agrupar devoluciones dentro de Entradas</label>
                </div>
            </div>
            <div class="col-md-3">
                <button class="btn custom-btn" id="btnGenerarReporte">Generar</button>
            </div>
            <div class="col-md-6 text-end">
                <button class="btn custom-btn me-2" id="btnExportCsv">Exportar CSV</button>
                <button class="btn custom-btn" id="btnExportPdf">Exportar PDF</button>
            </div>
        </div>
        <div class="mt-2" id="estadoReporte" style="font-size: 0.9rem; color: #666; display:none;"></div>
    </div>
    <div class="row mb-2 align-items-end">
        <div class="col-md-6 mb-2">
            <label for="reporteFiltroInsumo" class="form-label">Buscar insumo</label>
            <input type="text" id="reporteFiltroInsumo" class="form-control form-control-sm" placeholder="Filtrar por nombre de insumo">
        </div>
        <div class="col-md-3 mb-2">
            <label for="reportePageSize" class="form-label">Registros por página</label>
            <select id="reportePageSize" class="form-select form-select-sm">
                <option value="25">25</option>
                <option value="50">50</option>
                <option value="100">100</option>
            </select>
        </div>
        <div class="col-md-3 mb-2">
            <div class="d-flex gap-2 align-items-center mt-4">
                <button type="button" class="btn custom-btn-sm" id="reportePrev">&lt;</button>
                <span id="reportePageInfo" style="min-width:110px; display:inline-block; text-align:center; color:#000;">Página 1/1</span>
                <button type="button" class="btn custom-btn-sm" id="reporteNext">&gt;</button>
            </div>
        </div>
    </div>
    <div class="table-responsive">
        <table id="tablaEntradasSalidas" class="styled-table">
            <thead>
                <tr>
                    <th>Insumo</th>
                    <th>Unidad</th>
                    <th>Inicial</th>
                    <th>Entradas(Compras)</th>
                    <th>Devoluciones</th>
                    <th>Otras entradas</th>
                    <th>Salidas</th>
                    <th>Traspasos (salida)</th>
                    <th>Mermas</th>
                    <th>Ajustes (-)</th>
                    <th>Ajustes (+)</th>
                    <th>Final</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
    </div>
</div>

<!-- Modal Detalle por lotes y QR -->
<div id="modalDetalle" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.35); z-index:9999;">
    <div style="max-width:900px; margin:40px auto; background:#fff; border-radius:6px; overflow:hidden; box-shadow:0 2px 8px rgba(0,0,0,0.2);">
        <div style="display:flex; justify-content:space-between; align-items:center; padding:10px 16px; background:#f5f5f5;">
            <strong>Detalle por lotes y QR</strong>
            <button id="modalDetalleCerrar" class="btn custom-btn-sm">Cerrar</button>
        </div>
        <div style="padding:12px; max-height:70vh; overflow:auto;">
            <table class="styled-table" id="tablaDetalleLotes">
                <thead>
                    <tr>
                        <th>Fecha</th>
                        <th>ID Entrada</th>
                        <th>Saldo inicial</th>
                        <th>Entradas</th>
                        <th>Salidas</th>
                        <th>Mermas</th>
                        <th>Ajustes</th>
                        <th>Saldo final</th>
                        <th>QR</th>
                    </tr>
                </thead>
                <tbody></tbody>
            </table>
        </div>
    </div>
    
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script src="cortes.js"></script>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
