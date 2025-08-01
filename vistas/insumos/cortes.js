const usuarioId = 1; // reemplazar con id de sesión en producción

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

async function cerrarCorte() {
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
            renderResumen(data.resultado.detalles);
            document.getElementById('formObservaciones').style.display = 'none';
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cerrar');
    }
}

function renderResumen(detalles) {
    const tbody = document.querySelector('#tablaResumen tbody');
    tbody.innerHTML = '';
    detalles.forEach(d => {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${d.insumo}</td><td>${d.inicial}</td><td>${d.entradas}</td><td>${d.salidas}</td><td>${d.mermas}</td><td>${d.final}</td>`;
        tbody.appendChild(tr);
    });
}

document.addEventListener('DOMContentLoaded', () => {
    const a = document.getElementById('btnAbrirCorte');
    if (a) a.addEventListener('click', abrirCorte);
    const c = document.getElementById('btnCerrarCorte');
    if (c) c.addEventListener('click', cerrarCorte);
    const g = document.getElementById('guardarCierre');
    if (g) g.addEventListener('click', guardarCierre);
});
