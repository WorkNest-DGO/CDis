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
let proveedoresCatalogo = [];
// Bajo stock: datos y estado de paginación/filtro
let bajoStockData = [];
let bajoStockFiltro = '';
let bsPagina = 1;
let bsPageSize = 15;
// Historial entradas: datos y estado de paginación/filtro
let historialData = [];
let histFiltro = '';
let histPagina = 1;
let histPageSize = 15;

// Watch corte abierto (long poll-lite): recarga si cambia el estado
async function watchCorteLoop(){
  try{
    const r = await fetch('../../api/insumos/cortes_almacen.php?accion=listar', { cache:'no-store' });
    const j = await r.json();
    let abierto = false;
    if (j && j.success && Array.isArray(j.resultado)){
      abierto = j.resultado.some(c => c && (c.fecha_fin === null || String(c.fecha_fin).trim() === ''));
    }
    // Alternar dinámicamente secciones sin recargar
    const sec = document.getElementById('sec-reg-entrada');
    const al  = document.getElementById('alert-sin-corte');
    if (sec) sec.style.display = abierto ? '' : 'none';
    if (al)  al.style.display  = abierto ? 'none' : '';
  }catch(e){ /* noop */ }
  setTimeout(watchCorteLoop, 8000);
}
const usuarioId = 1; // En entorno real se obtendrí­a de la sesión
const itemsPorPagina = 12;
let paginaActual = 1;
let ultimaEntradaIds = [];


async function cargarProveedores() {
    try {
        const resp = await fetch('../../api/insumos/listar_proveedores.php');
        const data = await resp.json();
        if (data.success) {
            proveedoresCatalogo = Array.isArray(data.resultado) ? data.resultado : [];
            const select = document.getElementById('proveedor');
            if (!select) {
                return;
            }
            select.innerHTML = '<option value="">--Selecciona--</option>';
            proveedoresCatalogo.forEach(p => {
                const opt = document.createElement('option');
                opt.value = p.id;
                opt.textContent = p.nombre;
                select.appendChild(opt);
            });
            try { inicializarBuscadorProveedor(select); } catch(e) {}
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
        try { inicializarBuscadorInsumo(sel); } catch(e) {}
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
        if (input.classList.contains('buscador-insumo')) {
            delete input.dataset.autocompleteInitialized;
        }
    });
    // limpiar lista de sugerencias si existe
    const listaAuto = qs(nueva, '.lista-insumos');
    if (listaAuto) { listaAuto.innerHTML = ''; listaAuto.style.display = 'none'; }
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

// Autocompletado para insumo_id similar a ventas (buscador-producto)
function inicializarBuscadorInsumo(select) {
    if (!select) return;
    const cont = select.closest('.selector-insumo');
    if (!cont) return;
    const input = cont.querySelector('.buscador-insumo');
    const lista = cont.querySelector('.lista-insumos');
    if (!input || !lista || input.dataset.autocompleteInitialized) return;
    input.dataset.autocompleteInitialized = 'true';

    input.addEventListener('input', () => {
        const val = (typeof normalizarTexto === 'function') ? normalizarTexto(input.value) : String(input.value || '').toLowerCase();
        lista.innerHTML = '';
        if (!val) {
            lista.style.display = 'none';
            return;
        }
        const coincidencias = (catalogo || [])
            .filter(i => {
                const nom = (i && i.nombre) ? i.nombre : '';
                const norm = (typeof normalizarTexto === 'function') ? normalizarTexto(nom) : String(nom).toLowerCase();
                return norm.includes(val);
            })
            .slice(0, 50);
        coincidencias.forEach(i => {
            const li = document.createElement('li');
            li.className = 'list-group-item list-group-item-action';
            li.textContent = i.nombre;
            li.addEventListener('click', () => {
                input.value = i.nombre;
                select.value = i.id;
                // Disparar change para actualizar Unidad/Tipo y cualquier otro efecto
                try { select.dispatchEvent(new Event('change')); } catch(_) {}
                lista.innerHTML = '';
                lista.style.display = 'none';
            });
            lista.appendChild(li);
        });
        lista.style.display = coincidencias.length ? 'block' : 'none';
    });

    // Cerrar lista al hacer click fuera
    document.addEventListener('click', (e) => {
        if (!cont.contains(e.target)) {
            lista.style.display = 'none';
        }
    });

    // Si el select ya tiene valor (ej. edición), rellenar el input
    if (select.value) {
        const item = (catalogo || []).find(c => String(c.id) === String(select.value));
        if (item && input) input.value = item.nombre || '';
    }
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
            bajoStockData = Array.isArray(data.resultado) ? data.resultado : [];
            bsPagina = 1;
            renderBajoStock();
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar insumos de bajo stock');
    }
}

function renderBajoStock(){
    const input = document.getElementById('buscarBajoStock');
    bajoStockFiltro = (input && input.value ? String(input.value).toLowerCase() : '');
    const sizeSel = document.getElementById('bsPageSize');
    if (sizeSel) bsPageSize = parseInt(sizeSel.value, 10) || 15;
    const tbody = document.querySelector('#bajoStock tbody');
    if (!tbody) return;
    // filtrar
    const lista = (bajoStockData || []).filter(i => {
        if (!bajoStockFiltro) return true;
        const hay = (
            String(i.id).includes(bajoStockFiltro) ||
            (i.nombre || '').toLowerCase().includes(bajoStockFiltro) ||
            (i.unidad || '').toLowerCase().includes(bajoStockFiltro) ||
            String(i.existencia || '').toLowerCase().includes(bajoStockFiltro)
        );
        return !!hay;
    });
    // paginar
    const total = lista.length;
    const totalPag = Math.max(1, Math.ceil(total / bsPageSize));
    if (bsPagina > totalPag) bsPagina = totalPag;
    const ini = (bsPagina - 1) * bsPageSize;
    const fin = ini + bsPageSize;
    const pageItems = lista.slice(ini, fin);
    // pintar filas
    tbody.innerHTML = '';
    pageItems.forEach(i => {
        const tr = document.createElement('tr');
        if (parseFloat(i.existencia) < 20) {
            tr.style.backgroundColor = '#f8d7da';
        }
        tr.innerHTML = `<td>${i.id}</td><td>${i.nombre}</td><td>${i.unidad}</td><td>${i.existencia}</td>`;
        tbody.appendChild(tr);
    });
    // paginador
    const pag = document.getElementById('bsPaginador');
    if (pag) {
        pag.innerHTML = '';
        const makeLi = (txt, disabled, onClick) => {
            const li = document.createElement('li');
            li.className = 'page-item' + (disabled ? ' disabled' : '');
            const a = document.createElement('a');
            a.className = 'page-link';
            a.href = '#';
            a.textContent = txt;
            if (!disabled) a.addEventListener('click', (e)=>{ e.preventDefault(); onClick(); });
            li.appendChild(a);
            return li;
        };
        pag.appendChild(makeLi('Anterior', bsPagina<=1, ()=>{ bsPagina=Math.max(1, bsPagina-1); renderBajoStock(); }));
        for (let p=1; p<= totalPag; p++){
            const li = document.createElement('li');
            li.className = 'page-item' + (p===bsPagina ? ' active' : '');
            const a = document.createElement('a'); a.className='page-link'; a.href='#'; a.textContent=String(p);
            a.addEventListener('click', (e)=>{ e.preventDefault(); bsPagina=p; renderBajoStock(); });
            li.appendChild(a); pag.appendChild(li);
        }
        pag.appendChild(makeLi('Siguiente', bsPagina>=totalPag, ()=>{ bsPagina=Math.min(totalPag, bsPagina+1); renderBajoStock(); }));
    }
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
        // Existencia es informativa al editar: no permitir cambios manuales
        const exEl = document.getElementById('existencia');
        if (exEl) {
            exEl.value = ins.existencia;
            exEl.readOnly = true;
        }
        const minEl = document.getElementById('minimo_stock');
        if (minEl) {
            minEl.value = (typeof ins.minimo_stock !== 'undefined' && ins.minimo_stock !== null) ? ins.minimo_stock : '';
        }
        const reqEl = document.getElementById('reque_id');
        if (reqEl) {
            reqEl.value = (ins.reque_id || '');
        }
        document.getElementById('tipo_control').value = ins.tipo_control;
    } else {
        form.reset();
        // Nuevo insumo: existencia solo lectura y en 0
        const exEl = document.getElementById('existencia');
        if (exEl) {
            exEl.readOnly = true;
            exEl.value = 0;
        }
        const minEl = document.getElementById('minimo_stock');
        if (minEl) {
            minEl.value = '';
        }
        const reqEl = document.getElementById('reque_id');
        if (reqEl) {
            reqEl.value = '';
        }
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
    // En altas y ediciones no se permite modificar existencia manualmente desde el formulario
    fd.append('existencia', document.getElementById('existencia').value || '0');
    fd.append('tipo_control', document.getElementById('tipo_control').value);
    const minEl = document.getElementById('minimo_stock');
    const reqEl = document.getElementById('reque_id');
    if (minEl) fd.append('minimo_stock', minEl.value || '0');
    if (reqEl) fd.append('reque_id', reqEl.value || '');
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


        const prod = {
            insumo_id: insumoId,
            cantidad,
            unidad: unidadVal,
            costo_total: costoTotal
        };
        const descVal = descripcionFila ? descripcionFila.value.trim() : '';
        const refVal  = referenciaFila ? referenciaFila.value.trim() : '';
        const folVal  = folioFila ? folioFila.value.trim() : '';
        const qrVal   = qrFila ? qrFila.value.trim() : '';
        if (descVal) prod.descripcion = descVal;
        if (refVal)  prod.referencia_doc = refVal;
        if (folVal)  prod.folio_fiscal = folVal;
        if (qrVal)   prod.qr = qrVal;
        productos.push(prod);
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
        // Enviar el tipo de pago como texto: 'efectivo' | 'credito' | 'transferencia'
        const tipoPagoEl = qs(form, '[name="credito"]:checked');
        const tipoPagoVal = (tipoPagoEl && tipoPagoEl.value) ? String(tipoPagoEl.value) : 'efectivo';
        formData.append('credito', tipoPagoVal);
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

        const resp = await fetch('../../api/insumos/crear_entrada.php', { method: 'POST', body: formData, headers: { 'Accept': 'application/json' } });
        let data = null;
        if (!resp.ok) {
            const ct = resp.headers.get('content-type') || '';
            if (ct.includes('application/json')) {
                data = await resp.json().catch(() => null);
                const msg = data && (data.error || data.mensaje || data.message);
                throw new Error(`HTTP ${resp.status}${msg ? ': ' + msg : ''}`);
            } else {
                const txt = await resp.text().catch(() => '');
                throw new Error(`HTTP ${resp.status}${txt ? ': ' + txt : ''}`);
            }
        }
        if (!data) {
            data = await resp.json().catch(() => ({}));
        }
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
            historialData = Array.isArray(data.resultado) ? data.resultado : [];
            histPagina = 1;
            renderHistorial();
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar historial');
    }
}

function renderHistorial(){
    const input = document.getElementById('buscarHistorial');
    histFiltro = (input && input.value ? String(input.value).toLowerCase() : '');
    const sizeSel = document.getElementById('histPageSize');
    if (sizeSel) histPageSize = parseInt(sizeSel.value, 10) || 15;
    const tbody = document.querySelector('#historial tbody');
    if (!tbody) return;
    // filtrar
    const lista = (historialData || []).filter(e => {
        if (!histFiltro) return true;
        const proveedor = (e.proveedor || '').toLowerCase();
        const fecha = (e.fecha || '').toLowerCase();
        const producto = (e.producto || '').toLowerCase();
        const total = String(e.total ?? e.costo_total ?? '').toLowerCase();
        const cant = String(e.cantidad_actual ?? '').toLowerCase();
        const uni = (e.unidad || '').toLowerCase();
        const ref = (e.referencia_doc || '').toLowerCase();
        const fol = (e.folio_fiscal || '').toLowerCase();
        return proveedor.includes(histFiltro) || fecha.includes(histFiltro) || producto.includes(histFiltro) || total.includes(histFiltro) || cant.includes(histFiltro) || uni.includes(histFiltro) || ref.includes(histFiltro) || fol.includes(histFiltro);
    });
    // paginar
    const total = lista.length;
    const totalPag = Math.max(1, Math.ceil(total / histPageSize));
    if (histPagina > totalPag) histPagina = totalPag;
    const ini = (histPagina - 1) * histPageSize;
    const fin = ini + histPageSize;
    const pageItems = lista.slice(ini, fin);
    // pintar filas
    tbody.innerHTML = '';
    pageItems.forEach(e => {
        const tr = document.createElement('tr');
        const proveedor = e.proveedor ?? '';
        const fecha = e.fecha ?? '';
        const costoTotal = formatMoneda(e.costo_total ?? e.total ?? '');
        const cantidadActual = e.cantidad_actual ?? '';
        const unidad = e.unidad ? (' ' + e.unidad) : '';
        const totalTxt = formatMoneda(e.total ?? e.costo_total ?? '');
        const producto = e.producto ?? '';
        const referencia = e.referencia_doc ?? '';
        const folio = e.folio_fiscal ?? '';
        tr.innerHTML = `
            <td>${proveedor}</td>
            <td>${fecha}</td>
            <td>${costoTotal}</td>
            <td>${cantidadActual}${unidad}</td>
            <td>${totalTxt}</td>
            <td>${producto}</td>
            <td>${referencia}</td>
            <td>${folio}</td>
        `;
        tbody.appendChild(tr);
    });
    // paginador
    const pag = document.getElementById('histPaginador');
    if (pag) {
        pag.innerHTML = '';
        const makeLi = (txt, disabled, onClick) => {
            const li = document.createElement('li');
            li.className = 'page-item' + (disabled ? ' disabled' : '');
            const a = document.createElement('a');
            a.className = 'page-link';
            a.href = '#';
            a.textContent = txt;
            if (!disabled) a.addEventListener('click', (e)=>{ e.preventDefault(); onClick(); });
            li.appendChild(a);
            return li;
        };
        pag.appendChild(makeLi('Anterior', histPagina<=1, ()=>{ histPagina=Math.max(1, histPagina-1); renderHistorial(); }));
        for (let p=1; p<= totalPag; p++){
            const li = document.createElement('li');
            li.className = 'page-item' + (p===histPagina ? ' active' : '');
            const a = document.createElement('a'); a.className='page-link'; a.href='#'; a.textContent=String(p);
            a.addEventListener('click', (e)=>{ e.preventDefault(); histPagina=p; renderHistorial(); });
            li.appendChild(a); pag.appendChild(li);
        }
        pag.appendChild(makeLi('Siguiente', histPagina>=totalPag, ()=>{ histPagina=Math.min(totalPag, histPagina+1); renderHistorial(); }));
    }
}



document.addEventListener('DOMContentLoaded', () => {
    cargarProveedores();
    cargarInsumos();
    cargarBajoStock();
    cargarHistorial();
    // Buscadores y selects de paginado
    const bsSearch = document.getElementById('buscarBajoStock');
    if (bsSearch) bsSearch.addEventListener('input', ()=>{ bsPagina=1; renderBajoStock(); });
    const bsSize = document.getElementById('bsPageSize');
    if (bsSize) bsSize.addEventListener('change', ()=>{ bsPagina=1; renderBajoStock(); });

    const histSearch = document.getElementById('buscarHistorial');
    if (histSearch) histSearch.addEventListener('input', ()=>{ histPagina=1; renderHistorial(); });
    const histSize = document.getElementById('histPageSize');
    if (histSize) histSize.addEventListener('change', ()=>{ histPagina=1; renderHistorial(); });

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

    // Al seleccionar proveedor, mostrar observación informativa en modal
    const selProv = document.getElementById('proveedor');
    if (selProv) {
        selProv.addEventListener('change', async (e) => {
            try {
                const val = e && e.target ? e.target.value : '';
                const id = parseInt(val, 10);
                if (!Number.isFinite(id) || id <= 0) return;
                const resp = await fetch(`../../api/insumos/obtener_proveedor.php?id=${id}`, { cache: 'no-store' });
                const data = await resp.json();
                const obs = (data && data.success && data.resultado && data.resultado.observacion) ? String(data.resultado.observacion).trim() : '';
                if (obs) {
                    const box = document.getElementById('provObsBox');
                    if (box) box.textContent = obs;
                    showModal('#modalProvObs');
                }
            } catch (err) {
                console.error('No se pudo cargar la observación del proveedor', err);
            }
        });
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
    // Iniciar watcher de corte abierto
    try { watchCorteLoop(); } catch(e) {}
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
        let url = '../../api/insumos/imprimir_qrs_entrada.php';
        try {
            const sel = document.getElementById('selImpresoraResumen');
            if (sel && sel.value) { url += ('?printer_ip=' + encodeURIComponent(sel.value)); }
        } catch(e) {}
        const resp = await fetch(url, {
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

// Cargar impresoras en el modal de resumen
function cargarImpresoras($sel){
  // Usar ruta relativa al módulo para evitar romper cuando la app
  // está bajo un subdirectorio (p. ej. /rest2/)
  fetch('../../api/impresoras/listar.php', { cache: 'no-store' })
    .then(r => r.json())
    .then(j => {
      const data = j && (j.resultado || j.data) || [];
      if (!$sel) return;
      $sel.innerHTML = '<option value="">(Selecciona impresora)</option>';
      (data || []).forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.ip;
        opt.textContent = ((p.lugar || '') + ' - ' + p.ip).trim();
        $sel.appendChild(opt);
      });
    })
    .catch(console.error);
}
document.addEventListener('DOMContentLoaded',()=>{
  const sel = document.getElementById('selImpresoraResumen');
  if (sel) cargarImpresoras(sel);
});

// Autocompletado para proveedor (lista + coincidencia) usando proveedoresCatalogo
function inicializarBuscadorProveedor(select) {
    if (!select) return;
    const cont = select.closest('.selector-proveedor');
    if (!cont) return;
    const input = cont.querySelector('.buscador-proveedor');
    const lista = cont.querySelector('.lista-proveedores');
    if (!input || !lista || input.dataset.autocompleteInitialized) return;
    input.dataset.autocompleteInitialized = 'true';

    // Si ya hay un valor seleccionado, reflejar nombre en el input
    if (select.value) {
        const prov = (proveedoresCatalogo || []).find(p => String(p.id) === String(select.value));
        if (prov) input.value = prov.nombre || '';
    }

    input.addEventListener('input', () => {
        const val = (typeof normalizarTexto === 'function') ? normalizarTexto(input.value) : String(input.value || '').toLowerCase();
        lista.innerHTML = '';
        if (!val) {
            lista.style.display = 'none';
            return;
        }
        const arr = Array.isArray(proveedoresCatalogo) ? proveedoresCatalogo : [];
        const coincidencias = arr.filter(p => {
            const nom = p && p.nombre ? p.nombre : '';
            const norm = (typeof normalizarTexto === 'function') ? normalizarTexto(nom) : String(nom).toLowerCase();
            return norm.includes(val);
        }).slice(0, 50);
        coincidencias.forEach(p => {
            const li = document.createElement('li');
            li.className = 'list-group-item list-group-item-action';
            li.textContent = p.nombre;
            li.addEventListener('click', () => {
                input.value = p.nombre;
                select.value = p.id;
                try { select.dispatchEvent(new Event('change')); } catch(_) {}
                lista.innerHTML = '';
                lista.style.display = 'none';
            });
            lista.appendChild(li);
        });
        lista.style.display = coincidencias.length ? 'block' : 'none';
    });

    document.addEventListener('click', (e) => {
        if (!cont.contains(e.target)) {
            lista.style.display = 'none';
        }
    });
}

// === Override buscador de insumos: comportamiento más tolerante (Enter/blur, bubbling) ===
function inicializarBuscadorInsumo(select) {
    if (!select) return;
    const cont = select.closest('.selector-insumo');
    if (!cont) return;
    const input = cont.querySelector('.buscador-insumo');
    const lista = cont.querySelector('.lista-insumos');
    if (!input || !lista || input.dataset.autocompleteInitialized) return;
    input.dataset.autocompleteInitialized = 'true';

    let ultimasCoincidencias = [];
    function renderLista(coincidencias) {
        lista.innerHTML = '';
        coincidencias.forEach(i => {
            const li = document.createElement('li');
            li.className = 'list-group-item list-group-item-action';
            li.textContent = i.nombre;
            li.addEventListener('click', () => { commitSeleccion(i); });
            lista.appendChild(li);
        });
        lista.style.display = coincidencias.length ? 'block' : 'none';
    }
    function buscarCoincidencias(term) {
        const val = (typeof normalizarTexto === 'function') ? normalizarTexto(term) : String(term || '').toLowerCase();
        if (!val) { ultimasCoincidencias = []; renderLista([]); return; }
        ultimasCoincidencias = (catalogo || [])
            .filter(i => {
                const nom = (i && i.nombre) ? i.nombre : '';
                const norm = (typeof normalizarTexto === 'function') ? normalizarTexto(nom) : String(nom).toLowerCase();
                return norm.includes(val);
            })
            .slice(0, 50);
        renderLista(ultimasCoincidencias);
    }
    function commitSeleccion(item) {
        if (!item) return;
        input.value = item.nombre || '';
        select.value = item.id;
        try { select.dispatchEvent(new Event('change', { bubbles: true })); } catch (_) {}
        lista.innerHTML = '';
        lista.style.display = 'none';
    }
    input.addEventListener('input', () => { buscarCoincidencias(input.value); });
    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            const term = input.value.trim();
            if (!term) return;
            const normTerm = (typeof normalizarTexto === 'function') ? normalizarTexto(term) : term.toLowerCase();
            let item = (catalogo || []).find(it => ((typeof normalizarTexto === 'function') ? normalizarTexto(it.nombre) : String(it.nombre || '').toLowerCase()) === normTerm);
            if (!item && /^\d+$/.test(term)) { const idNum = parseInt(term, 10); item = (catalogo || []).find(it => parseInt(it.id, 10) === idNum); }
            if (!item) { if (!ultimasCoincidencias.length) buscarCoincidencias(term); item = ultimasCoincidencias[0]; }
            if (item) commitSeleccion(item);
        }
    });
    input.addEventListener('blur', () => {
        if (select.value) return;
        const term = input.value.trim();
        if (!term) return;
        const normTerm = (typeof normalizarTexto === 'function') ? normalizarTexto(term) : term.toLowerCase();
        let item = (catalogo || []).find(it => ((typeof normalizarTexto === 'function') ? normalizarTexto(it.nombre) : String(it.nombre || '').toLowerCase()) === normTerm);
        if (!item) { if (!ultimasCoincidencias.length) buscarCoincidencias(term); if (ultimasCoincidencias.length === 1) item = ultimasCoincidencias[0]; }
        if (item) commitSeleccion(item);
    });
    document.addEventListener('click', (e) => { if (!cont.contains(e.target)) { lista.style.display = 'none'; } });
    if (select.value) {
        const item = (catalogo || []).find(c => String(c.id) === String(select.value));
        if (item && input) input.value = item.nombre || '';
    }
}
