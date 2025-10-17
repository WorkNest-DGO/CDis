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
                <div style="color:black" class="col-md-6">
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
                            <button type="button" id="btn-retirar" class="btn btn-sm btn-outline-danger ms-2" disabled aria-disabled="true" title="Requiere corte abierto">Retirar</button>
                            <span id="corte-required-msg" class="small text-warning" style="display:none;">Requiere corte abierto</span>
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
                        <div class="print-controls mb-2">
                          <select class="sel-impresora"><option value="">(Selecciona impresora)</option></select>
                        </div>
                        <button id="entrada-qr-imprimir" type="button" class="btn custom-btn d-none">Imprimir QR</button>
                        <div id="retiro-qr-container" class="mt-4 d-none">
                            <h5 class="text-dark">Última salida registrada</h5>
                            <p id="retiro-qr-info" class="text-muted small mb-1">—</p>
                            <p class="text-muted small mb-2">Token: <code id="retiro-qr-token">—</code></p>
                            <p class="text-muted small mb-2">URL de consulta: <code id="retiro-qr-consulta-text">—</code></p>
                            <img id="retiro-qr-img" src="" alt="Código QR de salida" class="img-fluid mx-auto mb-2 d-none" style="max-width: 220px;">
                            <div class="print-controls mb-2">
                              <select class="sel-impresora"><option value="">(Selecciona impresora)</option></select>
                            </div>
                            <button id="retiro-qr-imprimir" type="button" class="btn btn-sm custom-btn d-none">Imprimir QR de salida</button>
                            <a id="retiro-qr-consulta" href="#" class="btn btn-sm btn-outline-primary mt-2 d-none" target="_blank" rel="noopener">Abrir detalles del retiro</a>
                        </div>
                    </div>
                </div>
            </div>
            <hr>
            <div>
                <h5>Descripción</h5>
                <p id="entrada-descripcion" class="mb-3">-</p>
            </div>
            <div class="mt-4" id="historial-retiros-section">
                <h5 class="text-dark">Historial de retiros</h5>
                <div class="print-controls mb-2">
                    <label class="text-muted small mb-1">Impresora</label>
                    <select class="sel-impresora form-select form-select-sm"><option value="">(Selecciona impresora)</option></select>
                </div>
                <p id="historial-retiros-mensaje" class="text-muted small">Selecciona una entrada para consultar el historial de retiros.</p>
                <div id="historial-retiros-wrapper" class="table-responsive d-none">
                    <table style="color:black" class="table table-sm table-hover table-bordered align-middle mb-0">
                        <thead class="table-light">
                            <tr>
                                <th scope="col">Fecha</th>
                                <th scope="col">Cantidad</th>
                                <th scope="col">Usuario</th>
                                <th scope="col">Observación</th>
                                <th scope="col" class="text-nowrap">QR</th>
                            </tr>
                        </thead>
                        <tbody id="historial-retiros-body"></tbody>
                    </table>
                </div>
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
    const retiroQrContainer = document.getElementById('retiro-qr-container');
    const retiroQrInfo = document.getElementById('retiro-qr-info');
    const retiroQrToken = document.getElementById('retiro-qr-token');
    const retiroQrImg = document.getElementById('retiro-qr-img');
    const retiroQrImprimirBtn = document.getElementById('retiro-qr-imprimir');
    const retiroQrConsultaText = document.getElementById('retiro-qr-consulta-text');
    const retiroQrConsultaLink = document.getElementById('retiro-qr-consulta');
    const historialMensaje = document.getElementById('historial-retiros-mensaje');
    const historialWrapper = document.getElementById('historial-retiros-wrapper');
    const historialBody = document.getElementById('historial-retiros-body');
    const imprimirQrBtn = document.getElementById('entrada-qr-imprimir');
    let entradaActual = null;

    function obtenerIdEntradaValido(valor) {
        if (valor === null || typeof valor === 'undefined') {
            return null;
        }
        var numero = parseInt(String(valor), 10);
        if (!Number.isFinite(numero) || numero <= 0) {
            return null;
        }
        return numero;
    }

function solicitarImpresionQrEntrada(entradaId, printerIp) {
        var idValido = obtenerIdEntradaValido(entradaId);
        if (!idValido) {
            return Promise.reject(new Error('No hay un QR disponible para imprimir.'));
        }
    var url = '../../api/insumos/imprimir_qrs_entrada.php';
    try {
        if (printerIp && String(printerIp).trim() !== '') {
            url += ('?printer_ip=' + encodeURIComponent(String(printerIp).trim()));
        } else {
            var selHist = document.querySelector('#historial-retiros-section .sel-impresora');
            var sel = selHist || document.querySelector('.print-controls .sel-impresora');
            if (sel && sel.value) { url += ('?printer_ip=' + encodeURIComponent(sel.value)); }
        }
    } catch(e) {}
        return fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'same-origin',
            body: JSON.stringify({ entrada_ids: [idValido] })
        })
            .then(function (response) {
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status);
                }
                return response.json();
            })
            .then(function (payload) {
                if (!payload || payload.success !== true) {
                    throw new Error(payload && payload.mensaje ? payload.mensaje : 'No se pudo imprimir');
                }
                var resultado = payload.resultado || {};
                var impresos = (typeof resultado.impresos !== 'undefined') ? resultado.impresos : null;
                return { impresos: impresos, payload: payload };
            });
    }

    if (imprimirQrBtn) {
        imprimirQrBtn.addEventListener('click', function () {
            var entradaId = obtenerIdEntradaValido(this.dataset.entradaId || '');
            if (!entradaId) {
                alert('No hay un QR disponible para imprimir.');
                return;
            }
            var btn = this;
            var originalText = btn.textContent;
            btn.disabled = true;
            btn.textContent = 'Imprimiendo...';
            var restaurarBoton = function () {
                btn.disabled = false;
                btn.textContent = originalText;
            };
            solicitarImpresionQrEntrada(entradaId)
                .then(function (info) {
                    restaurarBoton();
                    if (info && info.impresos !== null && typeof info.impresos !== 'undefined') {
                        alert('Solicitud de impresión enviada (' + info.impresos + ' QR).');
                    } else {
                        alert('Solicitud de impresión enviada correctamente.');
                    }
                })
                .catch(function (error) {
                    console.error(error);
                    restaurarBoton();
                    alert('No fue posible imprimir el QR: ' + error.message);
                });
        });
    }

    if (retiroQrImprimirBtn) {
        retiroQrImprimirBtn.addEventListener('click', function () {
            var movimientoIdAttr = this.dataset.movimientoId || '';
            var movimientoId = parseInt(movimientoIdAttr, 10);
            if (!Number.isFinite(movimientoId) || movimientoId <= 0) {
                alert('No hay un QR de salida disponible para imprimir.');
                return;
            }
            var btn = this;
            var originalText = btn.textContent;
            btn.disabled = true;
            btn.textContent = 'Imprimiendo...';
            var restaurarBoton = function () {
                btn.disabled = false;
                btn.textContent = originalText;
            };
            var urlSalida = '../../api/insumos/imprimir_qrs_salida.php';
            try { var sel2 = document.querySelector('#retiro-qr-container .sel-impresora'); if (sel2 && sel2.value) { urlSalida += ('?printer_ip=' + encodeURIComponent(sel2.value)); } } catch(e) {}
            fetch(urlSalida, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'same-origin',
                body: JSON.stringify({ movimiento_ids: [movimientoId] })
            })
                .then(function (response) {
                    if (!response.ok) {
                        throw new Error('HTTP ' + response.status);
                    }
                    return response.json();
                })
                .then(function (payload) {
                    if (!payload || payload.success !== true) {
                        throw new Error(payload && payload.mensaje ? payload.mensaje : 'No se pudo imprimir');
                    }
                    var resultado = payload.resultado || {};
                    var impresos = (typeof resultado.impresos !== 'undefined') ? resultado.impresos : null;
                    var faltantes = Array.isArray(resultado.sin_qr) ? resultado.sin_qr : [];
                    restaurarBoton();
                    var mensaje = impresos !== null ? ('Solicitud de impresión enviada (' + impresos + ' QR).') : 'Solicitud de impresión enviada correctamente.';
                    if (faltantes.length > 0) {
                        mensaje += '\nSin QR disponible para: ' + faltantes.join(', ');
                    }
                    alert(mensaje);
                })
                .catch(function (error) {
                    console.error(error);
                    restaurarBoton();
                    alert('No fue posible imprimir el QR de salida: ' + error.message);
                });
        });
    }

    function formatNumber(value, opts) {
        if (value === null || value === undefined || value === '') {
            return '';
        }
        const num = Number(value);
        if (!Number.isFinite(num)) {
            return String(value);
        }
        const options = Object.assign({ minimumFractionDigits: 2, maximumFractionDigits: 2 }, opts || {});
        return num.toLocaleString('es-MX', options);
    }

    function resolverRuta(ruta) {
        if (!ruta) {
            return '';
        }
        let path = String(ruta).trim();
        if (!path) {
            return '';
        }
        if (/^https?:/i.test(path)) {
            return path;
        }
        path = path.replace(/^[\/\\]+/, '');
        if (!path) {
            return '';
        }
        return '../../' + path;
    }

    function mostrarMensajeHistorial(texto, esError) {
        if (!historialMensaje) {
            return;
        }
        historialMensaje.textContent = texto;
        if (esError) {
            historialMensaje.classList.add('text-danger');
        } else {
            historialMensaje.classList.remove('text-danger');
        }
        historialMensaje.classList.remove('d-none');
    }

    function limpiarHistorialTabla() {
        if (historialBody) {
            historialBody.innerHTML = '';
        }
        if (historialWrapper) {
            historialWrapper.classList.add('d-none');
        }
    }

    function renderHistorial(movimientos) {
        limpiarHistorialTabla();
        if (!historialBody) {
            return;
        }
        if (!Array.isArray(movimientos) || movimientos.length === 0) {
            mostrarMensajeHistorial('Sin retiros registrados para esta entrada.');
            return;
        }
        const fragment = document.createDocumentFragment();
        movimientos.forEach(function (movimiento) {
            const tr = document.createElement('tr');

            const fechaTd = document.createElement('td');
            fechaTd.textContent = movimiento && movimiento.fecha ? String(movimiento.fecha) : '-';
            tr.appendChild(fechaTd);

            const cantidadTd = document.createElement('td');
            const unidadMovimiento = movimiento && (movimiento.unidad || movimiento.insumo_unidad) ? String(movimiento.unidad || movimiento.insumo_unidad) : '';
            const valorCantidad = (movimiento && typeof movimiento.retirado !== 'undefined' && movimiento.retirado !== null) ? movimiento.retirado : (movimiento ? movimiento.cantidad : null);
            let textoCantidad = '-';
            if (valorCantidad !== null && typeof valorCantidad !== 'undefined') {
                const cantidadNumero = Number(valorCantidad);
                if (Number.isFinite(cantidadNumero)) {
                    textoCantidad = formatNumber(cantidadNumero, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
                } else {
                    textoCantidad = String(valorCantidad);
                }
                if (unidadMovimiento) {
                    textoCantidad += ' ' + unidadMovimiento;
                }
            }
            cantidadTd.textContent = textoCantidad;
            tr.appendChild(cantidadTd);

            const usuarioTd = document.createElement('td');
            let usuarioTexto = '-';
            if (movimiento) {
                if (movimiento.usuario_nombre) {
                    usuarioTexto = String(movimiento.usuario_nombre);
                    if (movimiento.usuario_id) {
                        usuarioTexto += ' (ID ' + movimiento.usuario_id + ')';
                    }
                } else if (movimiento.usuario_id) {
                    usuarioTexto = 'ID ' + movimiento.usuario_id;
                }
            }
            usuarioTd.textContent = usuarioTexto;
            tr.appendChild(usuarioTd);

            const observacionTd = document.createElement('td');
            observacionTd.textContent = movimiento && movimiento.observacion ? String(movimiento.observacion) : '-';
            tr.appendChild(observacionTd);

            const qrTd = document.createElement('td');
            qrTd.className = 'text-nowrap';
            const acciones = document.createElement('div');
            acciones.className = 'd-flex flex-column gap-1';
            let tieneAccion = false;

            const rutaQr = movimiento ? resolverRuta(movimiento.qr_imagen) : '';
            if (rutaQr) {
                const linkQr = document.createElement('a');
                linkQr.href = rutaQr;
                linkQr.target = '_blank';
                linkQr.rel = 'noopener';
                linkQr.className = 'btn btn-sm btn-outline-primary';
                linkQr.textContent = 'Ver QR';
                const entradaIdRelacionado = obtenerIdEntradaValido((movimiento && (movimiento.entrada_id || movimiento.id_entrada)) || (entradaActual && entradaActual.id));
                if (entradaIdRelacionado) {
                    linkQr.dataset.entradaId = String(entradaIdRelacionado);
                }
                linkQr.addEventListener('click', function () {
                    const idEntrada = obtenerIdEntradaValido(this.dataset.entradaId || (movimiento && (movimiento.entrada_id || movimiento.id_entrada)) || (entradaActual && entradaActual.id));
                    if (!idEntrada) {
                        return;
                    }
                    solicitarImpresionQrEntrada(idEntrada)
                        .then(function (info) {
                            if (info && info.impresos !== null && typeof info.impresos !== 'undefined') {
                                alert('Solicitud de impresión enviada (' + info.impresos + ' QR).');
                            } else {
                                alert('Solicitud de impresión enviada correctamente.');
                            }
                        })
                        .catch(function (error) {
                            console.error(error);
                            alert('No fue posible imprimir el QR: ' + error.message);
                        });
                });
                acciones.appendChild(linkQr);
                tieneAccion = true;
            }

            const consultaUrl = movimiento && movimiento.qr_consulta_url ? String(movimiento.qr_consulta_url) : '';
            if (consultaUrl) {
                const linkConsulta = document.createElement('a');
                linkConsulta.href = consultaUrl;
                linkConsulta.target = '_blank';
                linkConsulta.rel = 'noopener';
                linkConsulta.className = 'btn btn-sm btn-outline-secondary';
                linkConsulta.textContent = 'Detalle';
                acciones.appendChild(linkConsulta);
                tieneAccion = true;
            }

            if (movimiento && movimiento.qr_token) {
                const tokenWrap = document.createElement('div');
                tokenWrap.className = 'small text-muted';
                tokenWrap.appendChild(document.createTextNode('Token: '));
                const codeEl = document.createElement('code');
                codeEl.textContent = String(movimiento.qr_token);
                tokenWrap.appendChild(codeEl);
                acciones.appendChild(tokenWrap);
                tieneAccion = true;
            }

            if (!tieneAccion) {
                acciones.textContent = '—';
            }
            qrTd.appendChild(acciones);
            tr.appendChild(qrTd);

            fragment.appendChild(tr);
        });
        historialBody.appendChild(fragment);
        if (historialWrapper) {
            historialWrapper.classList.remove('d-none');
        }
        mostrarMensajeHistorial('Se encontraron ' + movimientos.length + ' retiros registrados.');
    }

    function cargarHistorialRetiros(entradaId) {
        if (!entradaId) {
            limpiarHistorialTabla();
            mostrarMensajeHistorial('Selecciona una entrada para consultar el historial de retiros.');
            return;
        }
        mostrarMensajeHistorial('Cargando historial de retiros...');
        fetch('../../api/insumos/listar_movimientos_entrada.php?entrada_id=' + encodeURIComponent(entradaId), { credentials: 'same-origin' })
            .then(function (response) {
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status);
                }
                return response.json();
            })
            .then(function (payload) {
                if (!payload || payload.success !== true) {
                    throw new Error(payload && payload.mensaje ? payload.mensaje : 'Sin datos');
                }
                const movimientos = Array.isArray(payload.resultado) ? payload.resultado : [];
                renderHistorial(movimientos);
                if (movimientos.length > 0) {
                    mostrarQrRetiro(movimientos[0]);
                } else {
                    limpiarQrRetiro();
                }
            })
            .catch(function (error) {
                limpiarHistorialTabla();
                mostrarMensajeHistorial('No fue posible obtener el historial de retiros: ' + error.message, true);
            });
    }

    function limpiarQrRetiro() {
        if (retiroQrContainer) {
            retiroQrContainer.classList.add('d-none');
        }
        if (retiroQrInfo) {
            retiroQrInfo.textContent = '—';
        }
        if (retiroQrToken) {
            retiroQrToken.textContent = '—';
        }
        if (retiroQrConsultaText) {
            retiroQrConsultaText.textContent = '—';
        }
        if (retiroQrImg) {
            retiroQrImg.src = '';
            retiroQrImg.classList.add('d-none');
        }
        if (retiroQrImprimirBtn) {
            retiroQrImprimirBtn.classList.add('d-none');
            retiroQrImprimirBtn.disabled = false;
            retiroQrImprimirBtn.textContent = 'Imprimir QR de salida';
            delete retiroQrImprimirBtn.dataset.movimientoId;
        }
        if (retiroQrConsultaLink) {
            retiroQrConsultaLink.href = '#';
            retiroQrConsultaLink.classList.add('d-none');
        }
    }

    function mostrarQrRetiro(datos) {
        if (!retiroQrContainer) {
            return;
        }
        if (!datos || (!datos.qr_imagen && !datos.qr_consulta_url && !datos.qr_token)) {
            limpiarQrRetiro();
            return;
        }
        const unidadMovimiento = datos && (datos.unidad || datos.insumo_unidad) ? String(datos.unidad || datos.insumo_unidad) : '';
        const valorCantidad = (datos && typeof datos.retirado !== 'undefined' && datos.retirado !== null) ? datos.retirado : (datos ? datos.cantidad : null);
        let descripcion = '';
        if (valorCantidad !== null && typeof valorCantidad !== 'undefined') {
            const cantidadNumero = Number(valorCantidad);
            if (Number.isFinite(cantidadNumero)) {
                descripcion = 'Cantidad retirada: ' + formatNumber(cantidadNumero, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + (unidadMovimiento ? ' ' + unidadMovimiento : '');
            } else {
                descripcion = 'Cantidad retirada: ' + valorCantidad + (unidadMovimiento ? ' ' + unidadMovimiento : '');
            }
        }
        if (datos.fecha) {
            descripcion += (descripcion ? ' — ' : '') + 'Fecha: ' + datos.fecha;
        }
        if (retiroQrInfo) {
            retiroQrInfo.textContent = descripcion || '—';
        }
        if (retiroQrToken) {
            retiroQrToken.textContent = datos.qr_token || '—';
        }
        if (retiroQrConsultaText) {
            retiroQrConsultaText.textContent = datos.qr_consulta_url || '—';
        }
        const ruta = resolverRuta(datos.qr_imagen);
        if (retiroQrImg) {
            if (ruta) {
                retiroQrImg.src = ruta;
                retiroQrImg.classList.remove('d-none');
            } else {
                retiroQrImg.src = '';
                retiroQrImg.classList.add('d-none');
            }
        }
        const movimientoIdOrigen = (datos && typeof datos.id !== 'undefined') ? datos.id : (datos && typeof datos.movimiento_id !== 'undefined' ? datos.movimiento_id : null);
        const movimientoIdNumero = movimientoIdOrigen !== null ? parseInt(movimientoIdOrigen, 10) : NaN;
        const tieneQrDisponible = !!(datos && (datos.qr_token || datos.qr_imagen));
        if (retiroQrImprimirBtn) {
            if (tieneQrDisponible && Number.isFinite(movimientoIdNumero) && movimientoIdNumero > 0) {
                retiroQrImprimirBtn.dataset.movimientoId = String(movimientoIdNumero);
                retiroQrImprimirBtn.disabled = false;
                retiroQrImprimirBtn.textContent = 'Imprimir QR de salida';
                retiroQrImprimirBtn.classList.remove('d-none');
            } else {
                retiroQrImprimirBtn.classList.add('d-none');
                retiroQrImprimirBtn.disabled = false;
                retiroQrImprimirBtn.textContent = 'Imprimir QR de salida';
                delete retiroQrImprimirBtn.dataset.movimientoId;
            }
        }
        if (retiroQrConsultaLink) {
            const consultaUrl = datos.qr_consulta_url ? String(datos.qr_consulta_url) : '';
            if (consultaUrl) {
                retiroQrConsultaLink.href = consultaUrl;
                retiroQrConsultaLink.classList.remove('d-none');
            } else {
                retiroQrConsultaLink.href = '#';
                retiroQrConsultaLink.classList.add('d-none');
            }
        }
        retiroQrContainer.classList.remove('d-none');
    }
    if (!id) {
        statusEl.classList.remove('alert-info');
        statusEl.classList.add('alert-warning');
        statusEl.textContent = 'Selecciona una entrada del listado para ver el detalle.';
        limpiarHistorialTabla();
        mostrarMensajeHistorial('Selecciona una entrada para consultar el historial de retiros.');
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
            limpiarQrRetiro();
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
            var qrEmpty = document.getElementById('entrada-sin-qr');
            if (qrPath) {
                var absoluteQr = resolverRuta(qrPath);
                qrImg.src = absoluteQr;
                qrImg.classList.remove('d-none');
                if (imprimirQrBtn) {
                    imprimirQrBtn.classList.remove('d-none');
                    imprimirQrBtn.disabled = false;
                    imprimirQrBtn.textContent = 'Imprimir QR';
                    imprimirQrBtn.dataset.entradaId = data && data.id ? String(data.id) : '';
                }
                if (qrEmpty) {
                    qrEmpty.classList.add('d-none');
                }
            } else {
                qrImg.classList.add('d-none');
                qrImg.src = '';
                if (imprimirQrBtn) {
                    imprimirQrBtn.classList.add('d-none');
                    imprimirQrBtn.disabled = false;
                    imprimirQrBtn.textContent = 'Imprimir QR';
                    delete imprimirQrBtn.dataset.entradaId;
                }
                if (qrEmpty) {
                    qrEmpty.classList.remove('d-none');
                }
            }
            cargarHistorialRetiros(data.id);
        })
        .catch(function (error) {
            statusEl.classList.remove('alert-info');
            statusEl.classList.add('alert-danger');
            statusEl.textContent = 'No fue posible obtener la información de la entrada: ' + error.message;
            detalleEl.classList.add('d-none');
            limpiarHistorialTabla();
            mostrarMensajeHistorial('No se pudo cargar el historial de retiros porque la entrada no está disponible.', true);
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
            // Evitar abrir si el botón está deshabilitado
            if (e.target.hasAttribute('disabled')) return;
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
            body: JSON.stringify({ entrada_id: parseInt(entradaActual.id), retirar: val, tipo: (document.getElementById('tipo-retiro') ? document.getElementById('tipo-retiro').value : 'salida') })
        }).then(r=>r.json()).then(function(data){
            if (data && data.success) {
                const info = data.resultado || {};
                const nuevo = (max - val);
                entradaActual.cantidad_actual = nuevo;
                const el = document.getElementById('entrada-cantidad-actual');
                if (el) el.textContent = formatNumber(nuevo, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
                mostrarQrRetiro(info);
                if (entradaActual && entradaActual.id) {
                    cargarHistorialRetiros(entradaActual.id);
                }
                cerrarModalRetiro();
                alert('Retiro registrado');
            } else {
                alert((data && (data.mensaje||data.error))||'Error al retirar');
            }
        }).catch(function(err){ console.error(err); alert('Error de comunicación'); });
    }

    // =============================
    // Corte abierto: habilitar Retirar (pseudo long-poll)
    // =============================
    async function hayCorteAbierto(){
        try{
            const resp = await fetch('../../api/insumos/cortes_almacen.php?accion=listar', { cache: 'no-store' });
            const data = await resp.json();
            if (data && data.success && Array.isArray(data.resultado)){
                return data.resultado.some(c => c && (c.fecha_fin === null || String(c.fecha_fin).trim() === ''));
            }
        }catch(_){ /* noop */ }
        return false;
    }

    function setRetirarEnabled(enabled){
        const btn = document.getElementById('btn-retirar');
        const msg = document.getElementById('corte-required-msg');
        if (!btn) return;
        if (enabled){
            btn.removeAttribute('disabled');
            btn.removeAttribute('aria-disabled');
            btn.title = '';
            if (msg) msg.style.display = 'none';
        } else {
            btn.setAttribute('disabled','disabled');
            btn.setAttribute('aria-disabled','true');
            btn.title = 'Requiere corte abierto';
            if (msg) msg.style.display = '';
        }
    }

    (async function longPollCorte(){
        while(true){
            const abierto = await hayCorteAbierto();
            setRetirarEnabled(abierto);
            await new Promise(r => setTimeout(r, 12000));
        }
    })();
})();
</script>
<script>
// Carga de impresoras para selects en esta vista
function cargarImpresoras($sel){
  fetch('/rest2/CDI/api/impresoras/listar.php', { cache: 'no-store' })
    .then(r=>r.json()).then(j=>{
      const data = j && (j.resultado || j.data) || [];
      if(!$sel) return;
      $sel.innerHTML = '<option value="">(Selecciona impresora)</option>';
      (data||[]).forEach(p=>{
        const opt = document.createElement('option');
        opt.value = p.ip;
        opt.textContent = ((p.lugar||'') + ' — ' + p.ip).trim();
        $sel.appendChild(opt);
      });
    }).catch(console.error);
}
document.addEventListener('DOMContentLoaded',()=>{
  document.querySelectorAll('.sel-impresora').forEach(cargarImpresoras);
});
</script>
<!-- Modal Retiro -->
<div class="modal fade" id="modalRetiro" tabindex="-1" role="dialog" aria-hidden="true">
    <div style="color:black" class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <h5 style="color:black" class="modal-title">Retirar de esta entrada</h5>
                <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            </div>
            <div class="modal-body">
            <div class="form-group">
                    <label for="retirar-cantidad">Retirar</label>
                    <input type="number" step="0.01" min="0" id="retirar-cantidad" class="form-control" placeholder="Cantidad a retirar">
                </div>
                <div class="form-group mt-2">
                    <label for="tipo-retiro">Tipo</label>
                    <select id="tipo-retiro" class="form-control">
                        <option value="salida" selected>Salida</option>
                        <option value="traspaso">Traspaso</option>
                        <option value="merma">Merma</option>
                    </select>
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
