const usuarioId = 1; // reemplazar con id de sesión en producción
let detalles = [];
let corteActual = null;
let pagina = 1;
let pageSize = 15;

async function abrirCorte() {
    try {
        const resp = await fetch('../../api/insumos/cortes_almacen.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ accion: 'abrir', usuario_id: usuarioId })
        });
        const data = await resp.json();
        if (data.success) {
            alert('Corte abierto ID: ' + data.resultado.corte_id);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al abrir corte');
    }
}

function cerrarCorte() {
    document.getElementById('formObservaciones').style.display = 'block';
}

async function guardarCierre() {
    const obs = document.getElementById('observaciones').value;
    const corteId = prompt('ID de corte a cerrar');
    if (!corteId) return;
    try {
        const resp = await fetch('../../api/insumos/cortes_almacen.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ accion: 'cerrar', corte_id: corteId, usuario_id: usuarioId, observaciones: obs })
        });
        const data = await resp.json();
        if (data.success) {
            corteActual = corteId;
            detalles = data.resultado.detalles;
            pagina = 1;
            renderTabla();
            document.getElementById('formObservaciones').style.display = 'none';
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cerrar');
    }
}

async function buscarCortes() {
    const fecha = document.getElementById('buscarFecha').value;
    const lista = document.getElementById('listaCortes');
    lista.innerHTML = '<option value="">Buscando...</option>';
    try {
        const resp = await fetch(`../../api/insumos/cortes_almacen.php?accion=listar&fecha=${fecha}`);
        const data = await resp.json();
        lista.innerHTML = '<option value="">Seleccione corte...</option>';
        if (data.success) {
            data.resultado.forEach(c => {
                const hora = c.fecha_inicio.split(' ')[1];
                const opt = document.createElement('option');
                opt.value = c.id;
                opt.textContent = `${c.id} - ${hora} - ${c.abierto_por}`;
                lista.appendChild(opt);
            });
        }
    } catch (err) {
        console.error(err);
        lista.innerHTML = '<option value="">Error</option>';
    }
}

async function cargarDetalle(id) {
    if (!id) return;
    try {
        const resp = await fetch(`../../api/insumos/cortes_almacen.php?accion=detalle&corte_id=${id}`);
        const data = await resp.json();
        if (data.success) {
            corteActual = id;
            detalles = data.resultado;
            pagina = 1;
            renderTabla();
        }
    } catch (err) {
        console.error(err);
    }
}

function renderTabla() {
    const filtro = document.getElementById('filtroInsumo').value.toLowerCase();
    const tbody = document.querySelector('#tablaResumen tbody');
    tbody.innerHTML = '';
    pageSize = parseInt(document.getElementById('registrosPagina').value, 10);
    const filtrados = detalles.filter(d => d.insumo.toLowerCase().includes(filtro));
    const inicio = (pagina - 1) * pageSize;
    const paginados = filtrados.slice(inicio, inicio + pageSize);
    paginados.forEach(d => {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${d.insumo}</td><td>${d.existencia_inicial}</td><td>${d.entradas}</td><td>${d.salidas}</td><td>${d.mermas}</td><td>${d.existencia_final}</td>`;
        tbody.appendChild(tr);
    });
}

async function exportarExcel() {
    if (!corteActual) {
        alert('Seleccione un corte');
        return;
    }
    try {
        const resp = await fetch(`../../api/insumos/cortes_almacen.php?action=exportarExcel&id=${corteActual}`);
        const data = await resp.json();
        if (data.success) {
            window.open(data.resultado.archivo, '_blank');
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('No se pudo exportar');
    }
}

async function exportarPdf() {
    if (!corteActual) {
        alert('Seleccione un corte');
        return;
    }
    try {
        const resp = await fetch('../../api/insumos/cortes_almacen.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ accion: 'exportar_pdf', corte_id: corteActual })
        });
        const data = await resp.json();
        if (data.success) {
            window.open(data.resultado.archivo, '_blank');
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('No se pudo exportar');
    }
}

function cambiarPagina(delta) {
    const total = detalles.filter(d => d.insumo.toLowerCase().includes(document.getElementById('filtroInsumo').value.toLowerCase())).length;
    const maxPagina = Math.ceil(total / pageSize);
    pagina += delta;
    if (pagina < 1) pagina = 1;
    if (pagina > maxPagina) pagina = maxPagina;
    renderTabla();
}

document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('btnAbrirCorte')?.addEventListener('click', abrirCorte);
    document.getElementById('btnCerrarCorte')?.addEventListener('click', cerrarCorte);
    document.getElementById('guardarCierre')?.addEventListener('click', guardarCierre);
    document.getElementById('btnBuscar')?.addEventListener('click', buscarCortes);
    document.getElementById('listaCortes')?.addEventListener('change', e => cargarDetalle(e.target.value));
    document.getElementById('filtroInsumo')?.addEventListener('input', () => { pagina = 1; renderTabla(); });
    document.getElementById('registrosPagina')?.addEventListener('change', () => { pagina = 1; renderTabla(); });
    document.getElementById('btnExportarExcel')?.addEventListener('click', exportarExcel);
    document.getElementById('btnExportarPdf')?.addEventListener('click', exportarPdf);
    document.getElementById('prevPagina')?.addEventListener('click', () => cambiarPagina(-1));
    document.getElementById('nextPagina')?.addEventListener('click', () => cambiarPagina(1));
});
