async function cargarProductos() {
    try {
        const resp = await fetch('../../api/inventario/listar_productos.php');
        const data = await resp.json();
        if (data.success) {
            const tbody = document.querySelector('#tablaProductos tbody');
            tbody.innerHTML = '';
            data.resultado.forEach(p => {
                const tr = document.createElement('tr');
                tr.classList.add('table-row'); // Clase opcional para filas si deseas estilizar más
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

            // Vincular evento a botones
            tbody.querySelectorAll('button.actualizar').forEach(btn => {
                btn.addEventListener('click', () => {
                    const input = btn.closest('tr').querySelector('.existencia');
                    actualizarExistencia(btn.dataset.id, input.value);
                });
            });
            tbody.querySelectorAll('button.eliminar').forEach(btn => {
                btn.addEventListener('click', () => eliminarProducto(btn.dataset.id));
            });
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar inventario');
    }
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
            cargarProductos();
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
            cargarProductos();
        } else {
            mostrarModal('Error', (data && data.mensaje) || 'No se pudo eliminar');
        }
    } catch (err) {
        console.error(err);
        mostrarModal('Error', 'Error al conectar con el servidor');
    }
}


function abrirModalAgregar() {
    document.getElementById('modalAgregar').style.display = 'flex';
}
function agregarProducto() {
    abrirModalAgregar();
}
function cerrarModal() {
    document.getElementById('modalAgregar').style.display = 'none';
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
            cerrarModal();
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
    const modal = document.getElementById('modalAlerta');
    const mensajeEl = document.getElementById('mensajeModal');

    mensajeEl.innerText = mensaje;
    modal.style.display = 'flex';

    document.getElementById('cerrarModal').onclick = () => {
        modal.style.display = 'none';
    };
}

function mostrarConfirmacion(mensaje) {
    const $modal = $('#modalConfirmacion');
    $modal.find('.mensaje').text(mensaje);
    $modal.modal('show');
}


document.addEventListener('DOMContentLoaded', () => {
    cargarProductos();
    document.getElementById('agregarProducto').addEventListener('click', agregarProducto);
});

