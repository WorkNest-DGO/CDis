let catalogo = [];
let filtrado = [];
const itemsPorPagina = 12;
let paginaActual = 1;

async function cargarInsumos() {
    try {
        const resp = await fetch('../../api/insumos/listar_insumos.php');
        const data = await resp.json();
        if (data.success) {
            catalogo = data.resultado;
            filtrado = catalogo;
            mostrarCatalogo(1);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar insumos');
    }
}

function filtrarCatalogo() {
    const termino = document.getElementById('buscarInsumo').value.toLowerCase();
    filtrado = catalogo.filter(i => i.nombre.toLowerCase().includes(termino));
    mostrarCatalogo(1);
}

function mostrarCatalogo(pagina = paginaActual) {
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
                            <a class="btn custom-btn editar" data-id="${i.id}">Editar</a>
                            <a class="btn custom-btn eliminar" data-id="${i.id}">Eliminar</a>
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

document.addEventListener('DOMContentLoaded', () => {
    cargarInsumos();
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
});
