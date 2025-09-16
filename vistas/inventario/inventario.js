function showAppMsg(msg) {
    const body = document.querySelector('#appMsgModal .modal-body');
    if (body) body.textContent = String(msg);
    showModal('#appMsgModal');
}
window.alert = showAppMsg;

let productos = [];
const itemsPorPaginaInv = 20;
let paginaActualInv = 1;

async function cargarProductos() {
    try {
        const resp = await fetch('../../api/inventario/listar_productos.php');
        const data = await resp.json();
        if (data.success) {
            productos = Array.isArray(data.resultado) ? data.resultado : [];
            renderTablaInventario(paginaActualInv);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar inventario');
    }
}

function renderTablaInventario(pagina = 1) {
    const tbody = document.querySelector('#tablaProductos tbody');
    if (!tbody) return;

    const totalPaginas = Math.max(1, Math.ceil(productos.length / itemsPorPaginaInv));
    paginaActualInv = Math.min(Math.max(1, pagina), totalPaginas);
    const inicio = (paginaActualInv - 1) * itemsPorPaginaInv;
    const fin = inicio + itemsPorPaginaInv;
    const visibles = productos.slice(inicio, fin);

    tbody.innerHTML = '';
    visibles.forEach(p => {
        const tr = document.createElement('tr');
        tr.classList.add('table-row');
        tr.innerHTML = `
            <td class="text-center">${p.id}</td>
            <td>${p.nombre}</td>
            <td>$${parseFloat(p.precio).toFixed(2)}</td>
            <td>
                <input type="number" class="existencia form-control" data-id="${p.id}" value="${p.existencia}" style="max-width:80px;">
            </td>
            <td>${p.descripcion || ''}</td>
            <td>${p.activo == 1 ? '<span class="badge bg-success">Sí</span>' : '<span class="badge bg-danger">No</span>'}</td>
            <td>
                <button class="actualizar btn custom-btn btn-sm" data-id="${p.id}">Editar existencia</button>
                <button class="eliminar btn custom-btn btn-sm ms-2" data-id="${p.id}">Eliminar</button>
            </td>
        `;
        tbody.appendChild(tr);
    });

    // Eventos visibles
    tbody.querySelectorAll('button.actualizar').forEach(btn => {
        btn.addEventListener('click', () => {
            const input = btn.closest('tr').querySelector('.existencia');
            actualizarExistencia(btn.dataset.id, input.value);
        });
    });
    tbody.querySelectorAll('button.eliminar').forEach(btn => {
        btn.addEventListener('click', () => eliminarProducto(btn.dataset.id));
    });

    renderPaginadorInventario(totalPaginas);
}

function renderPaginadorInventario(totalPaginas) {
    const pag = document.getElementById('paginadorInv');
    if (!pag) return;
    pag.innerHTML = '';

    const prevLi = document.createElement('li');
    prevLi.className = 'page-item' + (paginaActualInv === 1 ? ' disabled' : '');
    const prevA = document.createElement('a');
    prevA.className = 'page-link';
    prevA.href = '#';
    prevA.textContent = 'Anterior';
    prevA.addEventListener('click', (e) => {
        e.preventDefault();
        if (paginaActualInv > 1) renderTablaInventario(paginaActualInv - 1);
    });
    prevLi.appendChild(prevA);
    pag.appendChild(prevLi);

    for (let i = 1; i <= totalPaginas; i++) {
        const li = document.createElement('li');
        li.className = 'page-item' + (i === paginaActualInv ? ' active' : '');
        const a = document.createElement('a');
        a.className = 'page-link';
        a.href = '#';
        a.textContent = String(i);
        a.addEventListener('click', (e) => {
            e.preventDefault();
            renderTablaInventario(i);
        });
        li.appendChild(a);
        pag.appendChild(li);
    }

    const nextLi = document.createElement('li');
    nextLi.className = 'page-item' + (paginaActualInv === totalPaginas ? ' disabled' : '');
    const nextA = document.createElement('a');
    nextA.className = 'page-link';
    nextA.href = '#';
    nextA.textContent = 'Siguiente';
    nextA.addEventListener('click', (e) => {
        e.preventDefault();
        if (paginaActualInv < totalPaginas) renderTablaInventario(paginaActualInv + 1);
    });
    nextLi.appendChild(nextA);
    pag.appendChild(nextLi);
}


async function actualizarExistencia(id, valor) {
    try {
        const resp = await fetch('../../api/inventario/actualizar_existencia.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ producto_id: parseInt(id), nueva_existencia: parseInt(valor) })
        });
        if (!resp.ok) throw new Error('Respuesta no válida');
        const data = await resp.json();
        if (data && data.success) {
            mostrarConfirmacion('¡Cambiado exitosamente!');
            const pagina = paginaActualInv;
            await cargarProductos();
            renderTablaInventario(pagina);
        } else {
            mostrarModal('Error', (data && data.mensaje) || 'No se pudo actualizar');
        }
    } catch (err) {
        console.error(err);
        mostrarModal('Error', 'Error al conectar con el servidor');
    }
}

async function eliminarProducto(id) {
    if (!confirm('¿Eliminar producto?')) return;
    try {
        const resp = await fetch('../../api/inventario/eliminar_producto.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: parseInt(id) })
        });
        const data = await resp.json();
        if (data && data.success) {
            mostrarConfirmacion('Producto eliminado');
            const pagina = paginaActualInv;
            await cargarProductos();
            renderTablaInventario(pagina);
        } else {
            mostrarModal('Error', (data && data.mensaje) || 'No se pudo eliminar');
        }
    } catch (err) {
        console.error(err);
        mostrarModal('Error', 'Error al conectar con el servidor');
    }
}

function abrirModalAgregar() {
    showModal('#modalAgregar');
}

function cerrarModalAgregar() {
    hideModal('#modalAgregar');
    document.getElementById('formAgregar').reset();
}

document.getElementById('formAgregar').addEventListener('submit', async (e) => {
    e.preventDefault();
    const nombre = document.getElementById('nombreProducto').value;
    const precio = parseFloat(document.getElementById('precioProducto').value);
    const descripcion = document.getElementById('descripcionProducto').value;
    const existencia = parseInt(document.getElementById('existenciaProducto').value);

    const payload = { nombre, precio, descripcion, existencia };
    try {
        const resp = await fetch('../../api/inventario/agregar_producto.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await resp.json();
        if (data.success) {
            alert(data.resultado?.mensaje || 'Producto agregado');
            cerrarModalAgregar();
            cargarProductos();
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al agregar producto');
    }
});


function mostrarModal(titulo, mensaje) {
    document.getElementById('modalTitulo').textContent = titulo;
    document.getElementById('mensajeModal').textContent = mensaje;
    showModal('#modalAlerta');
}

function mostrarConfirmacion(mensaje) {
    const modal = document.getElementById('modalConfirmacion');
    modal.querySelector('.mensaje').textContent = mensaje;
    showModal('#modalConfirmacion');
}


document.addEventListener('DOMContentLoaded', () => {
    cargarProductos();
    document.getElementById('agregarProducto').addEventListener('click', abrirModalAgregar);
});

