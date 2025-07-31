let catalogo = [];
let filtrado = [];
const usuarioId = 1; // En entorno real se obtendría de la sesión
const itemsPorPagina = 12;
let paginaActual = 1;

async function cargarProveedores() {
    try {
        const resp = await fetch('../../api/insumos/listar_proveedores.php');
        const data = await resp.json();
        if (data.success) {
            const select = document.getElementById('proveedor');
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
            actualizarSelectsProducto();
            mostrarCatalogo(1);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar insumos');
    }
}

function actualizarSelectsProducto() {
    document.querySelectorAll('select.producto').forEach(sel => {
        sel.innerHTML = '<option value="">--Selecciona--</option>';
        catalogo.forEach(p => {
            const opt = document.createElement('option');
            opt.value = p.id;
            opt.textContent = p.nombre;
            opt.dataset.unidad = p.unidad;
            sel.appendChild(opt);
        });
        sel.addEventListener('change', () => mostrarTipoEnFila(sel));
    });
}

function filtrarCatalogo() {
    const termino = document.getElementById('buscarInsumo').value.toLowerCase();
    filtrado = catalogo.filter(i => i.nombre.toLowerCase().includes(termino));
    mostrarCatalogo(1);
}

function mostrarTipoEnFila(select) {
    const id = parseInt(select.value);
    const fila = select.closest('tr');
    const tipoCell = fila.querySelector('.tipo');
    const unidadCell = fila.querySelector('.unidad');
    const unidadesInput = fila.querySelector('.unidades');
    const cantidadInput = fila.querySelector('.cantidad');
    const precioInput = fila.querySelector('.precio');
    const encontrado = catalogo.find(c => c.id == id);
    if (encontrado) {
        tipoCell.textContent = encontrado.tipo_control;
        unidadCell.textContent = encontrado.unidad;
        if (encontrado.tipo_control === 'desempaquetado') {
            unidadesInput.style.display = '';
        } else {
            unidadesInput.style.display = 'none';
            unidadesInput.value = '';
        }

        if (encontrado.tipo_control === 'unidad_completa' || encontrado.tipo_control === 'desempaquetado') {
            cantidadInput.step = 1;
            cantidadInput.min = 1;
        } else {
            cantidadInput.step = '0.01';
            cantidadInput.min = 0;
        }

        if (encontrado.tipo_control === 'no_controlado') {
            cantidadInput.disabled = true;
            precioInput.disabled = true;
        } else {
            cantidadInput.disabled = false;
            precioInput.disabled = false;
        }
    } else {
        tipoCell.textContent = '';
        unidadCell.textContent = '';
        unidadesInput.style.display = 'none';
        unidadesInput.value = '';
        cantidadInput.disabled = false;
        precioInput.disabled = false;
    }
}

function calcularTotal() {
    let total = 0;
    document.querySelectorAll('#tablaProductos tbody tr').forEach(f => {
        const cantidad = parseFloat(f.querySelector('.cantidad').value) || 0;
        const precio = parseFloat(f.querySelector('.precio').value) || 0;
        total += cantidad * precio;
    });
    const totalEl = document.getElementById('total');
    if (totalEl) {
        totalEl.textContent = total.toFixed(2);
    }
}

function agregarFila() {
    const tbody = document.querySelector('#tablaProductos tbody');
    const base = tbody.querySelector('tr');
    const nueva = base.cloneNode(true);
    nueva.querySelectorAll('input').forEach(i => i.value = '');
    const unidadCell = nueva.querySelector('.unidad');
    if (unidadCell) unidadCell.textContent = '';
    nueva.querySelector('.cantidad').addEventListener('input', calcularTotal);
    nueva.querySelector('.precio').addEventListener('input', calcularTotal);
    tbody.appendChild(nueva);
    actualizarSelectsProducto();
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
    const nombre = prompt('Nombre del proveedor:');
    if (!nombre) return;
    const telefono = prompt('Teléfono:') || '';
    const direccion = prompt('Dirección:') || '';
    try {
        const resp = await fetch('../../api/insumos/agregar_proveedor.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ nombre, telefono, direccion })
        });
        const data = await resp.json();
        if (data.success) {
            alert('Proveedor agregado');
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
    form.style.display = 'block';
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
}

function cerrarFormulario() {
    document.getElementById('formInsumo').style.display = 'none';
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

async function registrarEntrada() {
    const proveedor_id = parseInt(document.getElementById('proveedor').value);
    if (isNaN(proveedor_id)) {
        alert('Selecciona un proveedor');
        return;
    }
    const filas = document.querySelectorAll('#tablaProductos tbody tr');
    const productos = [];
    filas.forEach(f => {
        const insumo_id = parseInt(f.querySelector('.producto').value);
        const cantidad = parseInt(f.querySelector('.cantidad').value);
        const precio_unitario = parseFloat(f.querySelector('.precio').value) || 0;
        const unidades = parseFloat(f.querySelector('.unidades').value) || 0;
        if (!isNaN(insumo_id) && !isNaN(cantidad)) {
            const obj = { insumo_id, cantidad, precio_unitario };
            if (unidades > 0) obj.unidades = unidades;
            productos.push(obj);
        }
    });
    const payload = { proveedor_id, usuario_id: usuarioId, productos };
    try {
        const resp = await fetch('../../api/insumos/crear_entrada.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await resp.json();
        if (data.success) {
            alert('Entrada registrada');
            cargarHistorial();
            document.querySelectorAll('#tablaProductos tbody tr').forEach((f, i) => {
                if (i > 0) f.remove();
                f.querySelectorAll('input').forEach(inp => inp.value = '');
                const uCell = f.querySelector('.unidad');
                if (uCell) uCell.textContent = '';
            });
            calcularTotal();
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al registrar entrada');
    }
}

async function cargarHistorial() {
    try {
        const resp = await fetch('../../api/insumos/listar_entradas.php');
        const data = await resp.json();
        if (data.success) {
            const tbody = document.querySelector('#historial tbody');
            tbody.innerHTML = '';
            data.resultado.forEach(e => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${e.proveedor}</td>
                    <td>${e.fecha}</td>
                    <td>${e.total}</td>
                    <td>${e.producto}</td>
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
    document.getElementById('agregarFila').addEventListener('click', agregarFila);
    document.getElementById('registrarEntrada').addEventListener('click', registrarEntrada);
    document.getElementById('btnNuevoProveedor').addEventListener('click', nuevoProveedor);
    const btnNuevoInsumo = document.getElementById('btnNuevoInsumo');
    if (btnNuevoInsumo) {
        btnNuevoInsumo.addEventListener('click', nuevoInsumo);
    }
    const form = document.getElementById('formInsumo');
    if (form) {
        form.addEventListener('submit', guardarInsumo);
        document.getElementById('cancelarInsumo').addEventListener('click', cerrarFormulario);
    }
    const buscador = document.getElementById('buscarInsumo');
    if (buscador) {
        buscador.addEventListener('input', filtrarCatalogo);
    }
    document.querySelectorAll('.cantidad').forEach(i => i.addEventListener('input', calcularTotal));
    document.querySelectorAll('.precio').forEach(i => i.addEventListener('input', calcularTotal));
    calcularTotal();
});


