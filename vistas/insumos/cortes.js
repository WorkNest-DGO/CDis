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
    const desde = document.getElementById('buscarDesde')?.value || '';
    const hasta = document.getElementById('buscarHasta')?.value || '';
    const lista = document.getElementById('listaCortes');
    lista.innerHTML = '<option value="">Buscando...</option>';
    try {
        const url = new URL('../../api/insumos/listar_cortes_almacen.php', window.location.href);
        if (desde) url.searchParams.set('desde', desde);
        if (hasta) url.searchParams.set('hasta', hasta);
        const resp = await fetch(url.toString());
        const data = await resp.json();
        lista.innerHTML = '<option value="">Seleccione corte...</option>';
        if (data.success) {
            data.resultado.forEach(c => {
                const hora = (c.fecha_inicio || '').split(' ')[1] || '';
                const abierto = c.abierto_por || (c.usuario_abre_id ? `U:${c.usuario_abre_id}` : '');
                const opt = document.createElement('option');
                opt.value = c.id;
                opt.textContent = `${c.id}${hora ? ' - ' + hora : ''}${abierto ? ' - ' + abierto : ''}`;
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
        const url = new URL('../../api/insumos/listar_cortes_almacen_detalle.php', window.location.href);
        url.searchParams.set('corte_id', id);
        const resp = await fetch(url.toString());
        const data = await resp.json();
        if (data.success) {
            corteActual = id;
            try {
                const respIns = await fetch('../../api/insumos/listar_insumos.php');
                const dataIns = await respIns.json();
                const map = {};
                if (dataIns.success) {
                    dataIns.resultado.forEach(it => { map[it.id] = { nombre: it.nombre, unidad: it.unidad }; });
                }
                detalles = data.resultado.map(d => {
                    const meta = map[d.insumo_id] || { nombre: `ID ${d.insumo_id}`, unidad: '' };
                    return {
                        insumo: meta.nombre,
                        unidad: meta.unidad,
                        existencia_inicial: d.existencia_inicial,
                        entradas: d.entradas,
                        salidas: d.salidas,
                        mermas: d.mermas,
                        existencia_final: d.existencia_final
                    };
                });
            } catch (e) {
                detalles = data.resultado.map(d => ({
                    insumo: `ID ${d.insumo_id}`,
                    unidad: '',
                    existencia_inicial: d.existencia_inicial,
                    entradas: d.entradas,
                    salidas: d.salidas,
                    mermas: d.mermas,
                    existencia_final: d.existencia_final
                }));
            }
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

function exportarCsv() {
    if (!detalles.length) {
        alert('No hay datos para exportar');
        return;
    }
    const filtro = document.getElementById('filtroInsumo')?.value.toLowerCase() || '';
    const filas = detalles.filter(d => d.insumo.toLowerCase().includes(filtro));
    if (!filas.length) {
        alert('No hay datos para exportar');
        return;
    }
    const escapeCsv = valor => {
        const texto = valor === null || valor === undefined ? '' : String(valor);
        const necesitaComillas = texto.includes('"') || texto.includes(',') || texto.includes('\n');
        return necesitaComillas ? `"${texto.replace(/"/g, '""')}"` : texto;
    };
    const filasCsv = filas.map(d => [
        d.insumo,
        d.existencia_inicial,
        d.entradas,
        d.salidas,
        d.mermas,
        d.existencia_final
    ]);
    const encabezados = ['Insumo', 'Inicial', 'Entradas', 'Salidas', 'Mermas', 'Final'];
    const csv = [encabezados, ...filasCsv]
        .map(fila => fila.map(escapeCsv).join(','))
        .join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const enlace = document.createElement('a');
    const fecha = new Date().toISOString().slice(0, 10);
    enlace.href = url;
    enlace.download = `corte_${corteActual || 'sin_id'}_${fecha}.csv`;
    document.body.appendChild(enlace);
    enlace.click();
    document.body.removeChild(enlace);
    URL.revokeObjectURL(url);
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
    // Autocargar y recargar al cambiar el rango de fechas
    const desdeInput = document.getElementById('buscarDesde');
    const hastaInput = document.getElementById('buscarHasta');
    const hoy = new Date();
    const yyyy = hoy.getFullYear();
    const mm = String(hoy.getMonth() + 1).padStart(2, '0');
    const dd = String(hoy.getDate()).padStart(2, '0');
    if (desdeInput && !desdeInput.value) desdeInput.value = `${yyyy}-${mm}-${dd}`;
    if (hastaInput && !hastaInput.value) hastaInput.value = `${yyyy}-${mm}-${dd}`;
    if (desdeInput) desdeInput.addEventListener('change', buscarCortes);
    if (hastaInput) hastaInput.addEventListener('change', buscarCortes);
    buscarCortes();
    document.getElementById('listaCortes')?.addEventListener('change', e => cargarDetalle(e.target.value));
    document.getElementById('filtroInsumo')?.addEventListener('input', () => { pagina = 1; renderTabla(); });
    document.getElementById('registrosPagina')?.addEventListener('change', () => { pagina = 1; renderTabla(); });
    document.getElementById('btnExportarCsv')?.addEventListener('click', exportarCsv);
    document.getElementById('btnExportarPdf')?.addEventListener('click', exportarPdf);
    document.getElementById('prevPagina')?.addEventListener('click', () => cambiarPagina(-1));
    document.getElementById('nextPagina')?.addEventListener('click', () => cambiarPagina(1));
});


