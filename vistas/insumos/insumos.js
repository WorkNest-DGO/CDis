// Helpers Bootstrap modal
function showModal(selector) {
    try {
        if (window.jQuery && typeof $(selector)?.modal === 'function') {
            $(selector).modal('show');
            return;
        }
    } catch (e) {}
    const el = document.querySelector(selector);
    if (!el) return;
    el.classList.add('show');
    el.style.display = 'block';
    document.body.classList.add('modal-open');
    const bd = document.createElement('div');
    bd.className = 'modal-backdrop fade show';
    document.body.appendChild(bd);
}

function hideModal(selector) {
    try {
        if (window.jQuery && typeof $(selector)?.modal === 'function') {
            $(selector).modal('hide');
            return;
        }
    } catch (e) {}
    const el = document.querySelector(selector);
    if (!el) return;
    el.classList.remove('show');
    el.style.display = 'none';
    document.body.classList.remove('modal-open');
    document.querySelectorAll('.modal-backdrop').forEach(b => b.remove());
}

const qs = (root, sel) => (root || document).querySelector(sel);
const qsa = (root, sel) => Array.from((root || document).querySelectorAll(sel));

function markError(el, msg) {
    if (!el) {
        console.warn(msg);
        return;
    }
    el.classList.add('is-invalid');
    try {
        el.focus({ preventScroll: true });
    } catch (e) {}
    console.warn(msg);
}

function clearError(el) {
    if (el) {
        el.classList.remove('is-invalid');
    }
}
const formatMoneda = (valor) => {
    const num = Number(String(valor).replace(',', '.'));
    return Number.isFinite(num) ? num.toFixed(2) : (valor ?? '');
};

function formatFechaEntrada(fechaStr) {
    if (!fechaStr) {
        return '';
    }
    const texto = String(fechaStr).trim();
    if (!texto) {
        return '';
    }
    const normalizado = texto.replace(' ', 'T').replace(/\.\d+$/, '');
    const fecha = new Date(normalizado);
    if (!Number.isNaN(fecha.getTime())) {
        try {
            return fecha.toLocaleString('es-MX', {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
            });
        } catch (e) {
            const yyyy = fecha.getFullYear();
            const mm = String(fecha.getMonth() + 1).padStart(2, '0');
            const dd = String(fecha.getDate()).padStart(2, '0');
            const hh = String(fecha.getHours()).padStart(2, '0');
            const min = String(fecha.getMinutes()).padStart(2, '0');
            return `${dd}/${mm}/${yyyy} ${hh}:${min}`;
        }
    }
    return texto;
}


function showAppMsg(msg) {
    const body = document.querySelector('#appMsgModal .modal-body');
    if (body) body.textContent = String(msg);
    showModal('#appMsgModal');
}
window.alert = showAppMsg;

let catalogo = [];
let filtrado = [];
const usuarioId = 1; // En entorno real se obtendrÃ­a de la sesiÃ³n
const itemsPorPagina = 12;
let paginaActual = 1;
let ultimaEntradaIds = [];


async function cargarProveedores() {
    try {
        const resp = await fetch('../../api/insumos/listar_proveedores.php');
        const data = await resp.json();
        if (data.success) {
            const select = document.getElementById('proveedor');
            if (!select) {
                return;
            }
            select.innerHTML = '<option value="">--Selecciona--</option>';
            data.resultado.forEach(p => {
                const opt = document.createElement('option');
                opt.value = p.id;
                opt.textContent = p.nombre;
                select.appendChild(opt);
            });
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar proveedores');
    }
}

async function cargarInsumos() {
    try {
        const resp = await fetch('../../api/insumos/listar_insumos.php');
        const data = await resp.json();
        if (data.success) {
            catalogo = data.resultado;
            filtrado = catalogo;
            poblarSelectsInsumo();
            mostrarCatalogo(1);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar insumos');
    }
}

function poblarSelectsInsumo(root = document) {
    const selects = qsa(root, 'select[name="insumo_id"], select.insumo_id');
    selects.forEach(sel => {
        const current = sel.value;
        sel.innerHTML = '<option value="">--Selecciona--</option>';
        catalogo.forEach(p => {
            const opt = document.createElement('option');
            opt.value = p.id;
            opt.textContent = p.nombre;
            opt.dataset.unidad = p.unidad || '';
            opt.dataset.tipo = p.tipo_control || '';
            if (String(p.id) === String(current)) {
                opt.selected = true;
            }
            sel.appendChild(opt);
        });
        if (current && sel.value !== current) {
            sel.value = current;
        }
        mostrarTipoEnFila(sel.closest('tr'));
    });
}


function filtrarCatalogo() {
    const input = document.getElementById('buscarInsumo');
    if (!input) {
        return;
    }
    const termino = input.value.toLowerCase();
    filtrado = catalogo.filter(i => i.nombre.toLowerCase().includes(termino));
    mostrarCatalogo(1);
}

function mostrarTipoEnFila(fila) {
    if (!fila) return;
    const unidadField = qs(fila, '[name="unidad"], .unidad, .unidades');
    if (!unidadField) {
        console.warn('No se encontró el campo de unidad en la fila', fila);
        return;
    }
    const selectInsumo = qs(fila, '[name="insumo_id"], .insumo_id');
    const tipoCell = qs(fila, '.tipo');
    const cantidadInput = qs(fila, '.cantidad');
    const costoInput = qs(fila, '.costo_total, .precio');
    const seleccionado = catalogo.find(c => String(c.id) === String(selectInsumo ? selectInsumo.value : ''));
    if (seleccionado) {
        if (tipoCell) tipoCell.textContent = seleccionado.tipo_control || '';
        if (unidadField.tagName === 'INPUT') {
            unidadField.value = seleccionado.unidad || '';
        } else {
            unidadField.textContent = seleccionado.unidad || '';
        }
        if (cantidadInput) {
            if (seleccionado.tipo_control === 'unidad_completa' || seleccionado.tipo_control === 'desempaquetado') {
                cantidadInput.step = '1';
                cantidadInput.min = '1';
            } else {
                cantidadInput.step = '0.01';
                cantidadInput.min = '0';
            }
            cantidadInput.disabled = seleccionado.tipo_control === 'no_controlado';
        }
        if (costoInput) {
            costoInput.disabled = seleccionado.tipo_control === 'no_controlado';
        }
    } else {
        if (tipoCell) tipoCell.textContent = '';
        if (unidadField.tagName === 'INPUT') {
            unidadField.value = '';
        } else {
            unidadField.textContent = '';
        }
        if (cantidadInput) {
            cantidadInput.disabled = false;
        }
        if (costoInput) {
            costoInput.disabled = false;
        }
    }
}
function actualizarSelectsProducto(e) {
    const fila = e && e.target ? e.target.closest('tr') : null;
    if (!fila) return;
    mostrarTipoEnFila(fila);
}




function calcularTotal() {
    let total = 0;
    qsa(document, '#tablaProductos tbody tr').forEach(fila => {
        const costoInput = qs(fila, '.costo_total, .precio');
        const monto = parseFloat(costoInput ? costoInput.value.replace(',', '.') : '0') || 0;
        total += monto;
    });
    const totalEl = document.getElementById('total');
    if (totalEl) {
        totalEl.textContent = total.toFixed(2);
    }
}


function agregarFila() {
    const tbody = qs(document, '#tablaProductos tbody');
    if (!tbody) return;
    const base = tbody.querySelector('tr');
    if (!base) return;
    const nueva = base.cloneNode(true);
    qsa(nueva, 'input').forEach(input => {
        input.value = '';
        clearError(input);
    });
    qsa(nueva, 'select').forEach(select => {
        select.value = '';
        clearError(select);
    });
    const tipoCell = qs(nueva, '.tipo');
    if (tipoCell) tipoCell.textContent = '-';
    tbody.appendChild(nueva);
    poblarSelectsInsumo(nueva);
    mostrarTipoEnFila(nueva);
}



function mostrarCatalogo(pagina = paginaActual) {
    const tbody = document.querySelector('#listaInsumos tbody');
    if (tbody) {
        tbody.innerHTML = '';
    }
    const cont = document.getElementById('catalogoInsumos');
    if (cont) cont.innerHTML = '';

    paginaActual = pagina;
    const inicio = (pagina - 1) * itemsPorPagina;
    const fin = inicio + itemsPorPagina;

    filtrado.slice(inicio, fin).forEach(i => {
        if (cont) {
            const col = document.createElement('div');
            col.className = 'col-md-3';
            col.innerHTML = `
                <div class="blog-item">
                    <div class="blog-img">
                    <img src="../../uploads/${i.imagen}" >
                    </div>
                    <div class="blog-content">
                        <h2 style="color: black;" class="blog-title">${i.nombre}</h2>
                        <div class="blog-meta">
                            <p class="card-text">Unidad: ${i.unidad}<br>Existencia: ${i.existencia}</p>
                            <div>
                            <a class="btn custom-btn editar"   data-id="${i.id}">Editar</a>
                            <a class="btn custom-btn eliminar"  data-id="${i.id}">Eliminar</a>
                            </div>
                        </div>

                    </div>
                </div>`;
            cont.appendChild(col);
        }
    });

    if (cont) {
        cont.querySelectorAll('a.editar').forEach(btn => {
            btn.addEventListener('click', () => editarInsumo(btn.dataset.id));
        });
        cont.querySelectorAll('a.eliminar').forEach(btn => {
            btn.addEventListener('click', () => eliminarInsumo(btn.dataset.id));
        });
    }

    renderPaginador();
}

function renderPaginador() {
    const pag = document.getElementById('paginador');
    if (!pag) return;
    pag.innerHTML = '';

    const totalPaginas = Math.ceil(filtrado.length / itemsPorPagina) || 1;

    const prevLi = document.createElement('li');
    prevLi.className = 'page-item' + (paginaActual === 1 ? ' disabled' : '');
    const prevLink = document.createElement('a');
    prevLink.className = 'page-link';
    prevLink.href = '#';
    prevLink.textContent = 'Anterior';
    prevLink.addEventListener('click', (e) => {
        e.preventDefault();
        if (paginaActual > 1) mostrarCatalogo(paginaActual - 1);
    });
    prevLi.appendChild(prevLink);
    pag.appendChild(prevLi);

    for (let i = 1; i <= totalPaginas; i++) {
        const li = document.createElement('li');
        li.className = 'page-item' + (i === paginaActual ? ' active' : '');
        const a = document.createElement('a');
        a.className = 'page-link';
        a.href = '#';
        a.textContent = i;
        a.addEventListener('click', (e) => {
            e.preventDefault();
            mostrarCatalogo(i);
        });
        li.appendChild(a);
        pag.appendChild(li);
    }

    const nextLi = document.createElement('li');
    nextLi.className = 'page-item' + (paginaActual === totalPaginas ? ' disabled' : '');
    const nextLink = document.createElement('a');
    nextLink.className = 'page-link';
    nextLink.href = '#';
    nextLink.textContent = 'Siguiente';
    nextLink.addEventListener('click', (e) => {
        e.preventDefault();
        if (paginaActual < totalPaginas) mostrarCatalogo(paginaActual + 1);
    });
    nextLi.appendChild(nextLink);
    pag.appendChild(nextLi);
}

async function cargarBajoStock() {
    try {
        const resp = await fetch('../../api/insumos/listar_bajo_stock.php');
        const data = await resp.json();
        if (data.success) {
            mostrarBajoStock(data.resultado);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar insumos de bajo stock');
    }
}

function mostrarBajoStock(lista) {
    const tbody = document.querySelector('#bajoStock tbody');
    if (!tbody) return;
    tbody.innerHTML = '';
    lista.forEach(i => {
        const tr = document.createElement('tr');
        if (parseFloat(i.existencia) < 20) {
            tr.style.backgroundColor = '#f8d7da';
        }
        tr.innerHTML = `<td>${i.id}</td><td>${i.nombre}</td><td>${i.unidad}</td><td>${i.existencia}</td>`;
        tbody.appendChild(tr);
    });
}

async function nuevoProveedor() {
    const form = document.getElementById('formProveedor');
    if (form) form.reset();
    showModal('#modalProveedor');
}

async function guardarProveedor(ev) {
    ev.preventDefault();
    const nombre = document.getElementById('provNombre').value.trim();
    const telefono = document.getElementById('provTelefono').value.trim();
    const direccion = document.getElementById('provDireccion').value.trim();
    const telefono2 = (document.getElementById('provTelefono2')?.value || '').trim();
    const correo = (document.getElementById('provCorreo')?.value || '').trim();
    const rfc = (document.getElementById('provRFC')?.value || '').trim();
    const razon_social = (document.getElementById('provRazonSocial')?.value || '').trim();
    const regimen_fiscal = (document.getElementById('provRegimenFiscal')?.value || '').trim();
    const correo_facturacion = (document.getElementById('provCorreoFact')?.value || '').trim();
    const contacto_nombre = (document.getElementById('provContactoNombre')?.value || '').trim();
    const contacto_puesto = (document.getElementById('provContactoPuesto')?.value || '').trim();
    const dias_credito = parseInt((document.getElementById('provDiasCredito')?.value || '0'), 10) || 0;
    const limite_credito = parseFloat((document.getElementById('provLimiteCredito')?.value || '0').replace(',', '.')) || 0;
    const banco = (document.getElementById('provBanco')?.value || '').trim();
    const clabe = (document.getElementById('provClabe')?.value || '').trim();
    const cuenta_bancaria = (document.getElementById('provCuenta')?.value || '').trim();
    const sitio_web = (document.getElementById('provSitioWeb')?.value || '').trim();
    const observacion = (document.getElementById('provObservacion')?.value || '').trim();
    if (!nombre) {
        alert('Nombre requerido');
        return;
    }
    try {
        const resp = await fetch('../../api/insumos/agregar_proveedor.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                nombre,
                telefono,
                telefono2,
                correo,
                direccion,
                rfc,
                razon_social,
                regimen_fiscal,
                correo_facturacion,
                contacto_nombre,
                contacto_puesto,
                dias_credito,
                limite_credito,
                banco,
                clabe,
                cuenta_bancaria,
                sitio_web,
                observacion,
                activo: 1
            })
        });
        const data = await resp.json();
        if (data.success) {
            alert('Proveedor agregado');
            hideModal('#modalProveedor');
            document.querySelectorAll('.modal-backdrop').forEach(b => b.remove());
            document.body.classList.remove('modal-open');
            cargarProveedores();
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al agregar proveedor');
    }
}

function nuevoInsumo() {
    abrirFormulario(null);
}

function editarInsumo(id) {
    abrirFormulario(id);
}

async function eliminarInsumo(id) {
    if (!confirm('¿Eliminar insumo?')) return;
    try {
        const resp = await fetch('../../api/insumos/eliminar_insumo.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: parseInt(id) })
        });
        const data = await resp.json();
        if (data.success) {
            cargarInsumos();
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al eliminar');
    }
}

function abrirFormulario(id) {
    const form = document.getElementById('formInsumo');
    document.getElementById('insumoId').value = id || '';
    if (id) {
        const ins = catalogo.find(i => i.id == id);
        if (!ins) return;
        document.getElementById('nombre').value = ins.nombre;
        document.getElementById('unidad').value = ins.unidad;
        document.getElementById('existencia').value = ins.existencia;
        document.getElementById('tipo_control').value = ins.tipo_control;
    } else {
        form.reset();
        document.getElementById('existencia').value = 0;
    }
    showModal('#modalInsumo');
}

function cerrarFormulario() {
    hideModal('#modalInsumo');
}

async function guardarInsumo(ev) {
    ev.preventDefault();
    const id = document.getElementById('insumoId').value;
    const fd = new FormData();
    fd.append('nombre', document.getElementById('nombre').value);
    fd.append('unidad', document.getElementById('unidad').value);
    fd.append('existencia', document.getElementById('existencia').value);
    fd.append('tipo_control', document.getElementById('tipo_control').value);
    const img = document.getElementById('imagen').files[0];
    if (img) fd.append('imagen', img);
    if (id) fd.append('id', id);
    const url = id ? '../../api/insumos/actualizar_insumo.php' : '../../api/insumos/agregar_insumo.php';
    try {
        const resp = await fetch(url, { method: 'POST', body: fd });
        const data = await resp.json();
        if (data.success) {
            cerrarFormulario();
            cargarInsumos();
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al guardar');
    }
}

async function registrarEntrada(e) {
    if (e && typeof e.preventDefault === 'function') {
        e.preventDefault();
    }
    const form = (e && e.target && e.target.closest('form')) || qs(document, '#form-entrada, form[name="form-entrada"]');
    if (!form) {
        console.error('No se encontró el formulario de entrada');
        return;
    }
    const proveedorField = qs(form, '[name="proveedor_id"]');
    if (!proveedorField || !String(proveedorField.value).trim()) {
        markError(proveedorField, 'Selecciona un proveedor');
        // Mostrar en modal flotante como el resto de mensajes
        alert('Selecciona un proveedor');
        return;
    }
    clearError(proveedorField);

    const filas = qsa(form, '#tablaProductos tbody tr');
    const productos = [];
    const resumenProductos = [];
    let filasInvalidas = 0;

    filas.forEach((fila, index) => {
        const insumoEl = qs(fila, '[name="insumo_id"], .insumo_id');
        const cantidadEl = qs(fila, '[name="cantidad"], .cantidad');
        const unidadEl = qs(fila, '[name="unidad"], .unidad');
        const costoEl = qs(fila, '[name="costo_total"], .costo_total');
        if (!insumoEl || !cantidadEl || !unidadEl || !costoEl) {
            return;
        }
        const insumoVal = String(insumoEl.value).trim();
        const cantidadVal = String(cantidadEl.value).replace(',', '.').trim();
        const costoVal = String(costoEl.value).replace(',', '.').trim();
        const unidadVal = unidadEl.tagName === 'INPUT' ? unidadEl.value.trim() : unidadEl.textContent.trim();
        const filaVacia = !insumoVal && !cantidadVal && !costoVal;

        if (filaVacia) {
            return;
        }

        if (!insumoVal || !cantidadVal || !costoVal || !unidadVal) {
            filasInvalidas++;
            markError(insumoEl, `Completa el insumo en la fila ${index + 1}`);
            markError(cantidadEl, `Completa la cantidad en la fila ${index + 1}`);
            markError(costoEl, `Completa el costo en la fila ${index + 1}`);
            markError(unidadEl, `Falta la unidad en la fila ${index + 1}`);
            return;
        }

        const insumoId = parseInt(insumoVal, 10);
        const cantidad = parseFloat(cantidadVal);
        const costoTotal = parseFloat(costoVal);

        if (!Number.isFinite(insumoId) || insumoId <= 0 || !Number.isFinite(cantidad) || cantidad <= 0 || !Number.isFinite(costoTotal) || costoTotal <= 0) {
            filasInvalidas++;
            markError(cantidadEl, `Valores inválidos en la fila ${index + 1}`);
            markError(costoEl, `Valores inválidos en la fila ${index + 1}`);
            return;
        }

        clearError(insumoEl);
        clearError(cantidadEl);
        clearError(costoEl);
        clearError(unidadEl);

        const descripcionFila = qs(fila, '[name="descripcion"]');
        const referenciaFila = qs(fila, '[name="referencia_doc"]');
        const folioFila = qs(fila, '[name="folio_fiscal"]');
        const qrFila = qs(fila, '[name="qr"]');

        const catalogoItem = catalogo.find(item => Number(item.id) === insumoId);
        const nombreCompuesto = catalogoItem && catalogoItem.nombre ? `${catalogoItem.id} - ${catalogoItem.nombre}` : `ID ${insumoId}`;
        resumenProductos.push({
            insumo_id: insumoId,
            nombre: nombreCompuesto,
            cantidad,
            unidad: unidadVal
        });


        productos.push({
            insumo_id: insumoId,
            cantidad,
            unidad: unidadVal,
            costo_total: costoTotal,
            descripcion: descripcionFila ? descripcionFila.value.trim() : '',
            referencia_doc: referenciaFila ? referenciaFila.value.trim() : '',
            folio_fiscal: folioFila ? folioFila.value.trim() : '',
            qr: qrFila ? qrFila.value.trim() : ''
        });
    });

    if (filasInvalidas > 0) {
        console.warn('Corrige las filas con datos incompletos o inválidos');
        return;
    }

    if (productos.length === 0) {
        markError(qs(form, '[name="insumo_id"]'), 'Agrega al menos un insumo');
        return;
    }

    try {
        const formData = new FormData();
        formData.append('proveedor_id', proveedorField.value);
        formData.append('usuario_id', String(usuarioId));
        const tipoPago = qs(form, '[name="credito"]:checked');
        formData.append('credito', tipoPago ? String(tipoPago.value) : '0');
        const descripcionGeneral = qs(form, '[name="descripcion"]');
        const referenciaGeneral = qs(form, '[name="referencia_doc"]');
        const folioGeneral = qs(form, '[name="folio_fiscal"]');
        const qrGeneral = qs(form, '[name="qr"]');
        if (descripcionGeneral && descripcionGeneral.value) {
            formData.append('descripcion', descripcionGeneral.value.trim());
        }
        if (referenciaGeneral && referenciaGeneral.value) {
            formData.append('referencia_doc', referenciaGeneral.value.trim());
        }
        if (folioGeneral && folioGeneral.value) {
            formData.append('folio_fiscal', folioGeneral.value.trim());
        }
        if (qrGeneral && qrGeneral.value) {
            formData.append('qr', qrGeneral.value.trim());
        }
        formData.append('productos', JSON.stringify(productos));

        const resp = await fetch('../../api/insumos/crear_entrada.php', { method: 'POST', body: formData });
        if (!resp.ok) {
            throw new Error(`HTTP ${resp.status}`);
        }        const data = await resp.json().catch(() => ({}));
        if (!data || data.success !== true) {
            const mensajeError = data && (data.error || data.mensaje) ? (data.error || data.mensaje) : 'No se pudo registrar la entrada';
            alert(mensajeError);
            return;
        }
        mostrarResumenEntrada(Array.isArray(data.entradas) ? data.entradas : [], resumenProductos);
        console.log('Entrada registrada', data);
        qsa(form, '.is-invalid').forEach(clearError);
        const filas = qsa(form, '#tablaProductos tbody tr');
        filas.forEach((fila, index) => {
            if (index > 0) {
                fila.remove();
            } else {
                qsa(fila, 'input').forEach(input => input.value = '');
                const tipoCell = qs(fila, '.tipo');
                if (tipoCell) tipoCell.textContent = '-';
                const unidadField = qs(fila, '[name="unidad"], .unidad');
                if (unidadField) {
                    if (unidadField.tagName === 'INPUT') {
                        unidadField.value = '';
                    } else {
                        unidadField.textContent = '';
                    }
                }
            }
        });
        form.reset();
        poblarSelectsInsumo(form);
        calcularTotal();
        cargarHistorial();
    } catch (err) {
        console.error('Error registrando entrada:', err);
    }
}



async function cargarHistorial() {
    try {
        const resp = await fetch('../../api/insumos/listar_entradas.php');
        const data = await resp.json();
        if (data.success) {
            const tbody = document.querySelector('#historial tbody');
            if (!tbody) return;
            tbody.innerHTML = '';
            data.resultado.forEach(e => {
                const tr = document.createElement('tr');
                const proveedor = e.proveedor ?? '';
                const fecha = e.fecha ?? '';
                const costoTotal = formatMoneda(e.costo_total ?? e.total ?? '');
                const cantidadActual = e.cantidad_actual ?? '';
                const unidad = e.unidad ? (' ' + e.unidad) : '';
                const total = formatMoneda(e.total ?? e.costo_total ?? '');
                const producto = e.producto ?? '';
                tr.innerHTML = `
                    <td>${proveedor}</td>
                    <td>${fecha}</td>
                    <td>${costoTotal}</td>
                    <td>${cantidadActual}${unidad}</td>
                    <td>${total}</td>
                    <td>${producto}</td>
                `;
                tbody.appendChild(tr);
            });
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar historial');
    }
}



document.addEventListener('DOMContentLoaded', () => {
    cargarProveedores();
    cargarInsumos();
    cargarBajoStock();
    cargarHistorial();

    const btnAgregar = document.getElementById('agregarFila');
    if (btnAgregar) {
        btnAgregar.addEventListener('click', agregarFila);
    }

    const formEntrada = qs(document, '#form-entrada, form[name="form-entrada"]');
    if (formEntrada) {
        formEntrada.addEventListener('submit', registrarEntrada);
    }

    const btnRegistrar = qs(document, '#btn-registrar, [data-action="registrar-entrada"]');
    if (btnRegistrar) {
        btnRegistrar.addEventListener('click', registrarEntrada);
    }

    const btnNuevoProveedor = document.getElementById('btnNuevoProveedor');
    if (btnNuevoProveedor) {
        btnNuevoProveedor.addEventListener('click', nuevoProveedor);
    }

    const btnNuevoInsumo = document.getElementById('btnNuevoInsumo');
    if (btnNuevoInsumo) {
        btnNuevoInsumo.addEventListener('click', nuevoInsumo);
    }

    document.addEventListener('change', e => {
        if (e.target && e.target.matches('[name="insumo_id"], .insumo_id')) {
            actualizarSelectsProducto(e);
        }
    });

    document.addEventListener('input', e => {
        if (e.target && e.target.matches('.cantidad, .costo_total, .precio')) {
            calcularTotal();
        }
    });

    const formProv = document.getElementById('formProveedor');
    if (formProv) {
        formProv.addEventListener('submit', guardarProveedor);
        const cancelar = document.getElementById('cancelarProveedor');
        if (cancelar) {
            cancelar.addEventListener('click', () => {
                hideModal('#modalProveedor');
                document.querySelectorAll('.modal-backdrop').forEach(b => b.remove());
                document.body.classList.remove('modal-open');
            });
        }
        const modal = document.getElementById('modalProveedor');
        if (modal) {
            modal.addEventListener('hidden.bs.modal', () => {
                document.querySelectorAll('.modal-backdrop').forEach(b => b.remove());
                document.body.classList.remove('modal-open');
            });
        }
    }

    const formInsumo = document.getElementById('formInsumo');
    if (formInsumo) {
        formInsumo.addEventListener('submit', guardarInsumo);
        const cancelarInsumo = document.getElementById('cancelarInsumo');
        if (cancelarInsumo) {
            cancelarInsumo.addEventListener('click', cerrarFormulario);
        }
    }

    const buscador = document.getElementById('buscarInsumo');
    if (buscador) {
        buscador.addEventListener('input', filtrarCatalogo);
    }

    calcularTotal();
});

// Modal de resumen: renderiza tarjetas con QR, nombre (id - nombre) y cantidad
function mostrarResumenEntrada(entradas, resumenProductos) {
    const cont = document.getElementById('resumenEntradasLista');
    if (!cont) return;
    cont.innerHTML = '';

    const ids = [];
    const count = Math.min(entradas.length, (resumenProductos && resumenProductos.length) || entradas.length);
    for (let i = 0; i < count; i++) {
        const ent = entradas[i] || {};
        const res = (resumenProductos && resumenProductos[i]) || {};
        const eid = ent.id;
        if (eid) ids.push(eid);
        const qr = ent.qr ? String(ent.qr) : '';
        const imgSrc = qr ? ('../../' + qr.replace(/^\/+/, '')) : '';
        const nombre = res && res.nombre ? res.nombre : (res && res.insumo_id ? ('ID ' + res.insumo_id) : '');
        const cant = (res && typeof res.cantidad !== 'undefined') ? res.cantidad : '';
        const unidad = (res && res.unidad) ? res.unidad : '';
        const fechaTexto = formatFechaEntrada(ent && ent.fecha ? ent.fecha : '');
        const cantidadTexto = (cant !== '' ? `Cantidad: ${cant}${unidad ? ' ' + unidad : ''}` : '');
        const loteTexto = eid ? `Lote: ${eid}` : '';

        const col = document.createElement('div');
        col.className = 'col-12 col-sm-6 col-md-4 col-lg-3';
        col.innerHTML = `
            <div class="card h-100 text-center" data-entrada-id="${eid ?? ''}">
                <div class="card-body d-flex flex-column align-items-center justify-content-start">
                    ${imgSrc ? `<img src="${imgSrc}" alt="QR" style="width:180px;height:180px;object-fit:contain;"/>` : ''}
                    <div class="mt-2" style="font-size: 0.9rem;">
                        ${nombre ? `<div><strong>${nombre}</strong></div>` : ''}
                        ${cantidadTexto ? `<div>${cantidadTexto}</div>` : ''}
                        ${fechaTexto ? `<div class="text-muted" style="font-size:0.8rem;">Fecha: ${fechaTexto}</div>` : ''}
                        ${loteTexto ? `<div class="text-muted" style="font-size:0.8rem;">${loteTexto}</div>` : ''}
                    </div>
                </div>
            </div>`;
        cont.appendChild(col);
    }

    const btnImp = document.getElementById('btnImprimirResumen');
    if (btnImp) {
        btnImp.dataset.ids = ids.join(',');
        if (!btnImp.dataset.bound) {
            btnImp.addEventListener('click', imprimirResumenQRs);
            btnImp.dataset.bound = '1';
        }
    }

    showModal('#modalResumenEntrada');
}

async function imprimirResumenQRs() {
    const btn = document.getElementById('btnImprimirResumen');
    const idsStr = btn && btn.dataset.ids ? btn.dataset.ids : '';
    const entradaIds = idsStr ? idsStr.split(',').map(s => parseInt(s, 10)).filter(n => Number.isFinite(n) && n > 0) : [];
    if (!entradaIds.length) {
        alert('No hay entradas para imprimir');
        return;
    }
    try {
        const resp = await fetch('../../api/insumos/imprimir_qrs_entrada.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ entrada_ids: entradaIds })
        });
        const data = await resp.json();
        if (data && data.success) {
            alert(`Enviados a impresión: ${data.resultado.impresos}`);
        } else {
            alert((data && (data.mensaje || data.error)) || 'Error al imprimir');
        }
    } catch (err) {
        console.error(err);
        alert('Error de comunicación al imprimir');
    }
}
