<?php

$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__app_base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
$path_actual = preg_replace('#^' . preg_quote($__app_base, '#') . '#', '', ($__sn ?: $_SERVER['PHP_SELF']));


$title = 'Detalle de entrada';
ob_start();
?>
<div class="page-header mb-0">
    <div class="container">
        <div class="row">
            <div class="col-12">
                <h2>Detalle de entrada</h2>
            </div>
            <div class="col-12">
                <a href="../../index.php">Inicio</a>
                <a href="insumos.php">Insumos</a>
                <a href="">Detalle de entrada</a>
            </div>
        </div>
    </div>
</div>

<div class="container mt-4 mb-5">
    <div class="mb-3" style="max-width:600px;">
        <label for="selector-entradas" class="form-label text-white">Seleccionar entrada</label>
        <select id="selector-entradas" class="form-control">
            <option value="">-- Selecciona una entrada --</option>
        </select>
    </div>
    <div id="entrada-status" class="alert alert-info">Cargando información de la entrada...</div>
    <div id="entrada-detalle" class="card d-none shadow">
        <div class="card-body">
            <h3 class="card-title text-dark">Entrada #<span id="entrada-id"></span></h3>
            <p class="text-muted mb-4">Registrada el <span id="entrada-fecha"></span></p>
            <div class="row g-4">
                <div class="col-md-6">
                    <dl class="row mb-0">
                        <dt class="col-sm-5">Insumo</dt>
                        <dd class="col-sm-7" id="entrada-insumo">-</dd>
                        <dt class="col-sm-5">Proveedor</dt>
                        <dd class="col-sm-7" id="entrada-proveedor">-</dd>
                        <dt class="col-sm-5">Usuario (ID)</dt>
                        <dd class="col-sm-7" id="entrada-usuario">-</dd>
                        <dt class="col-sm-5">Cantidad recibida</dt>
                        <dd class="col-sm-7" id="entrada-cantidad">-</dd>
                        <dt class="col-sm-5">Unidad</dt>
                        <dd class="col-sm-7" id="entrada-unidad">-</dd>
                        <dt class="col-sm-5">Cantidad actual</dt>
                        <dd class="col-sm-7 d-flex align-items-center gap-2">
                            <span id="entrada-cantidad-actual">-</span>
                            <button type="button" id="btn-retirar" class="btn btn-sm btn-outline-danger ms-2">Retirar</button>
                        </dd>
                        <dt class="col-sm-5">Costo total</dt>
                        <dd class="col-sm-7" id="entrada-costo-total">-</dd>
                        <dt class="col-sm-5">Valor unitario</dt>
                        <dd class="col-sm-7" id="entrada-valor-unitario">-</dd>
                        <dt class="col-sm-5">Referencia</dt>
                        <dd class="col-sm-7" id="entrada-referencia">-</dd>
                        <dt class="col-sm-5">Folio fiscal</dt>
                        <dd class="col-sm-7" id="entrada-folio">-</dd>
                    </dl>
                </div>
                <div class="col-md-6 text-center">
                    <div class="border rounded p-3 h-100 d-flex flex-column justify-content-center">
                        <img id="entrada-qr" src="" alt="Código QR" class="img-fluid mx-auto mb-3 d-none" style="max-width: 260px;">
                        <p id="entrada-sin-qr" class="text-muted">No se encontró un código QR asociado.</p>
                        <a id="entrada-qr-link" href="#" class="btn custom-btn d-none" target="_blank" rel="noopener">Abrir QR</a>
                    </div>
                </div>
            </div>
            <hr>
            <div>
                <h5>Descripción</h5>
                <p id="entrada-descripcion" class="mb-3">-</p>
            </div>
            <div>
                <h6 class="text-muted">Consulta del API</h6>
                <a id="entrada-api-url" href="#" target="_blank" rel="noopener" class="small text-break"></a>
            </div>
        </div>
    </div>
</div>

<?php require_once __DIR__ . '/../footer.php'; ?>
<script>
(function () {
    const statusEl = document.getElementById('entrada-status');
    const detalleEl = document.getElementById('entrada-detalle');
    const params = new URLSearchParams(window.location.search);
    const id = params.get('id');
    const apiLink = document.getElementById('entrada-api-url');
    let entradaActual = null;
    if (!id) {
        statusEl.classList.remove('alert-info');
        statusEl.classList.add('alert-warning');
        statusEl.textContent = 'Selecciona una entrada del listado para ver el detalle.';
    }

    const apiUrl = id ? ('../../api/insumos/consultar_entrada_insumo.php?id=' + encodeURIComponent(id)) : '';
    if (apiUrl) {
        apiLink.textContent = apiUrl;
        apiLink.href = apiUrl;
    }

    if (id) fetch(apiUrl, { credentials: 'same-origin' })
        .then(function (response) {
            if (!response.ok) {
                throw new Error('HTTP ' + response.status);
            }
            return response.json();
        })
        .then(function (payload) {
            if (!payload || payload.success !== true || !payload.resultado) {
                throw new Error(payload && payload.mensaje ? payload.mensaje : 'Sin datos');
            }
            const data = payload.resultado;
            entradaActual = data;
            statusEl.classList.remove('alert-info');
            statusEl.classList.add('alert-success');
            statusEl.textContent = 'Entrada localizada correctamente.';
            detalleEl.classList.remove('d-none');

            const setText = function (id, value) {
                const el = document.getElementById(id);
                if (el) {
                    el.textContent = value !== null && value !== undefined && value !== '' ? String(value) : '-';
                }
            };
            const formatNumber = function (value, opts) {
                const num = Number(value);
                if (!Number.isFinite(num)) {
                    return value;
                }
                const options = Object.assign({ minimumFractionDigits: 2, maximumFractionDigits: 2 }, opts || {});
                return num.toLocaleString('es-MX', options);
            };

            setText('entrada-id', data.id);
            setText('entrada-fecha', data.fecha);
            setText('entrada-insumo', data.insumo_nombre || data.insumo_id || '-');
            setText('entrada-proveedor', data.proveedor_nombre || data.proveedor_id || '-');
            setText('entrada-usuario', data.usuario_id);
            setText('entrada-cantidad', formatNumber(data.cantidad, { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
            setText('entrada-unidad', data.unidad);
            setText('entrada-cantidad-actual', formatNumber(data.cantidad_actual, { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
            setText('entrada-costo-total', formatNumber(data.costo_total, { style: 'currency', currency: 'MXN' }));
            setText('entrada-valor-unitario', formatNumber(data.valor_unitario, { style: 'currency', currency: 'MXN', minimumFractionDigits: 4, maximumFractionDigits: 4 }));
            setText('entrada-referencia', data.referencia_doc);
            setText('entrada-folio', data.folio_fiscal);
            setText('entrada-descripcion', data.descripcion);

            var qrPath = data.qr ? String(data.qr).trim() : '';
            var qrImg = document.getElementById('entrada-qr');
            var qrLink = document.getElementById('entrada-qr-link');
            var qrEmpty = document.getElementById('entrada-sin-qr');
            if (qrPath) {
                var absoluteQr = qrPath.match(/^https?:/i) ? qrPath : '../../' + qrPath.replace(/^\/+/g, '');
                qrImg.src = absoluteQr;
                qrImg.classList.remove('d-none');
                qrLink.href = absoluteQr;
                qrLink.classList.remove('d-none');
                if (qrEmpty) {
                    qrEmpty.classList.add('d-none');
                }
            } else {
                qrImg.classList.add('d-none');
                qrLink.classList.add('d-none');
                if (qrEmpty) {
                    qrEmpty.classList.remove('d-none');
                }
            }
        })
        .catch(function (error) {
            statusEl.classList.remove('alert-info');
            statusEl.classList.add('alert-danger');
            statusEl.textContent = 'No fue posible obtener la información de la entrada: ' + error.message;
            detalleEl.classList.add('d-none');
        });
    // Desplegable con listado de entradas (GET a la tabla)
    const selector = document.getElementById('selector-entradas');
    function renderSelector(items) {
        if (!selector) return;
        const actual = (new URLSearchParams(window.location.search)).get('id') || '';
        selector.innerHTML = '<option value="">-- Selecciona una entrada --</option>';
        items.forEach(function(e){
            const opt = document.createElement('option');
            opt.value = e.id;
            const fecha = e.fecha || '';
            const cant = (e.cantidad || '') + (e.unidad ? (' ' + e.unidad) : '');
            const nombre = e.producto || ('ID ' + (e.insumo_id || ''));
            opt.textContent = nombre + ' — Entrada #' + e.id + ' — ' + fecha + ' — ' + cant;
            if (String(e.id) === String(actual)) opt.selected = true;
            selector.appendChild(opt);
        });
    }
    function cargarEntradasLista(){
        fetch('../../api/insumos/listar_entradas.php?limit=500')
            .then(r=>r.json())
            .then(function(data){ if (data && data.success) { renderSelector(data.resultado || []); } })
            .catch(function(){});
    }
    if (selector) {
        selector.addEventListener('change', function(){
            if (this.value) window.location.search = '?id=' + encodeURIComponent(this.value);
        });
        cargarEntradasLista();
    }

    // Acciones de retiro
    document.addEventListener('click', function(e){
        if (e.target && e.target.id === 'btn-retirar') {
            abrirModalRetiro();
        }
    });

    function abrirModalRetiro(){
        const modal = document.getElementById('modalRetiro');
        if (!modal) return;
        const lbl = modal.querySelector('#lbl-valor-unitario');
        const vu = (entradaActual && typeof entradaActual.valor_unitario !== 'undefined') ? entradaActual.valor_unitario : '';
        lbl.textContent = 'Valor unitario: ' + (vu !== '' ? Number(vu).toLocaleString('es-MX', { style:'currency', currency:'MXN', minimumFractionDigits:4, maximumFractionDigits:4 }) : '-');
        const max = (entradaActual && entradaActual.cantidad_actual) ? parseFloat(entradaActual.cantidad_actual) : null;
        const inp = modal.querySelector('#retirar-cantidad');
        if (inp) { inp.value = ''; if (max !== null) { inp.max = String(max); } }
        try { if (window.jQuery) { $(modal).modal('show'); return; } } catch(e){}
        modal.classList.add('show'); modal.style.display='block';
        const bd = document.createElement('div'); bd.className='modal-backdrop fade show'; document.body.appendChild(bd);
    }

    function cerrarModalRetiro(){
        const modal = document.getElementById('modalRetiro');
        if (!modal) return;
        try { if (window.jQuery) { $(modal).modal('hide'); return; } } catch(e){}
        modal.classList.remove('show'); modal.style.display='none';
        document.querySelectorAll('.modal-backdrop').forEach(b=>b.remove());
    }

    window.confirmarRetiro = function(){
        if (!entradaActual || !entradaActual.id) return;
        const inp = document.getElementById('retirar-cantidad');
        const val = parseFloat(String(inp.value).replace(',', '.'));
        if (!Number.isFinite(val) || val <= 0) { alert('Cantidad a retirar inválida'); return; }
        const max = parseFloat(entradaActual.cantidad_actual || '0');
        if (val > max) { alert('No puedes retirar más de la cantidad actual'); return; }
        fetch('../../api/insumos/descontar_entrada.php', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ entrada_id: parseInt(entradaActual.id), retirar: val })
        }).then(r=>r.json()).then(function(data){
            if (data && data.success) {
                const nuevo = (max - val);
                entradaActual.cantidad_actual = nuevo;
                const el = document.getElementById('entrada-cantidad-actual');
                if (el) el.textContent = Number(nuevo).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
                alert('Retiro registrado');
                cerrarModalRetiro();
            } else {
                alert((data && (data.mensaje||data.error))||'Error al retirar');
            }
        }).catch(function(err){ console.error(err); alert('Error de comunicación'); });
    }
})();
</script>
<!-- Modal Retiro -->
<div class="modal fade" id="modalRetiro" tabindex="-1" role="dialog" aria-hidden="true">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">Retirar de esta entrada</h5>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body">
                <div class="form-group">
                    <label for="retirar-cantidad">Retirar</label>
                    <input type="number" step="0.01" min="0" id="retirar-cantidad" class="form-control" placeholder="Cantidad a retirar">
                </div>
                <p id="lbl-valor-unitario" class="text-muted mb-0">Valor unitario: -</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-dismiss="modal">Cerrar</button>
                <button type="button" class="btn custom-btn" onclick="confirmarRetiro()">Confirmar</button>
            </div>
        </div>
    </div>
</div>
</body>
</html>
<?php
$content = ob_get_clean();
include __DIR__ . '/../nav.php';
?>
