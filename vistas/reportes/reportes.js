const usuarioId = 1; // En producción usar id de sesión

async function cargarUsuarios() {
    const sel = document.getElementById('filtroUsuario');
    if (!sel) return;
    const r = await fetch('../../api/usuarios/listar_usuarios.php');
    const d = await r.json();
    sel.innerHTML = '<option value="">--Todos--</option>';
    if (d.success) {
        d.resultado.forEach(u => {
            const opt = document.createElement('option');
            opt.value = u.id;
            opt.textContent = u.nombre;
            sel.appendChild(opt);
        });
    }
}

async function cargarHistorial() {
    const tbody = document.querySelector('#tablaCortes tbody');
    tbody.innerHTML = '<tr><td colspan="11">Cargando...</td></tr>';
    try {
        const params = new URLSearchParams();
        const u = document.getElementById('filtroUsuario').value;
        const i = document.getElementById('filtroInicio').value;
        const f = document.getElementById('filtroFin').value;
        if (u) params.append('usuario_id', u);
        if (i) params.append('inicio', i);
        if (f) params.append('fin', f);
        const resp = await fetch('../../api/corte_caja/listar_cortes.php?' + params.toString());
        const data = await resp.json();
        if (data.success) {
            tbody.innerHTML = '';
            data.resultado.forEach(c => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${c.id}</td>
                    <td>${c.usuario}</td>
                    <td>${c.fecha_inicio}</td>
                    <td>${c.fecha_fin || ''}</td>
                    <td>${c.total !== null ? c.total : ''}</td>
                    <td>${c.efectivo || ''}</td>
                    <td>${c.boucher || ''}</td>
                    <td>${c.cheque || ''}</td>
                    <td>${c.fondo_inicial || ''}</td>
                    <td>${c.observaciones || ''}</td>
                    <td><button class="btn custom-btn" data-id="${c.id}">Ver detalle</button></td>
                `;
                tbody.appendChild(tr);
            });
            tbody.querySelectorAll('button.detalle').forEach(btn => {
                btn.addEventListener('click', () => verDetalle(btn.dataset.id));
            });
        } else {
            tbody.innerHTML = '<tr><td colspan="7">Error al cargar</td></tr>';
        }
    } catch (err) {
        console.error(err);
        tbody.innerHTML = '<tr><td colspan="7">Error</td></tr>';
    }
}

async function verDetalle(corteId) {
    const modal = document.getElementById('modal');
    modal.innerHTML = 'Cargando...';
    modal.style.display = 'block';
    try {
        const resp = await fetch('../../api/corte_caja/listar_ventas_por_corte.php?corte_id=' + corteId);
        const data = await resp.json();
        if (data.success) {
            let html = `<h3>Ventas del corte ${corteId}</h3>`;
            html += '<table border="1"><thead><tr><th>ID</th><th>Fecha</th><th>Total</th><th>Propina</th><th>Tipo</th></tr></thead><tbody>';
            data.resultado.forEach(v => {
                html += `<tr><td>${v.id}</td><td>${v.fecha}</td><td>${v.total}</td><td>${v.propina}</td><td>${v.tipo_entrega}</td></tr>`;
            });
            html += '</tbody></table><button class="btn custom-btn" id="cerrarModal">Cerrar</button>';
            modal.innerHTML = html;
            document.getElementById('cerrarModal').addEventListener('click', () => {
                modal.style.display = 'none';
            });
        } else {
            modal.innerHTML = data.mensaje;
        }
    } catch (err) {
        console.error(err);
        modal.innerHTML = 'Error al obtener detalle';
    }
}

async function resumenActual() {
    const modal = document.getElementById('modal');
    modal.innerHTML = 'Cargando...';
    modal.style.display = 'block';
    try {
        const resp = await fetch('../../api/corte_caja/resumen_corte_actual.php?usuario_id=' + usuarioId);
        const data = await resp.json();
        if (!data.success || !data.resultado.abierto) {
            modal.style.display = 'none';
            alert('No hay corte abierto');
            return;
        }
        const r = data.resultado;
        let html = `<h3>Resumen del corte ${r.corte_id}</h3>`;
        html += `<p>Ventas totales: $${r.total}</p>`;
        html += `<p>Número de ventas: ${r.num_ventas}</p>`;
        html += `<p>Total en propinas: $${r.propinas}</p>`;
        if (r.metodos_pago && r.metodos_pago.length) {
            html += '<h4>Métodos de pago</h4><ul>';
            r.metodos_pago.forEach(m => {
                html += `<li>${m.metodo}: $${m.total}</li>`;
            });
            html += '</ul>';
        }
        html += '<button class="btn custom-btn" id="cerrarModal">Cerrar</button>';
        modal.innerHTML = html;
        document.getElementById('cerrarModal').addEventListener('click', () => {
            modal.style.display = 'none';
        });
    } catch (err) {
        console.error(err);
        modal.innerHTML = 'Error al obtener resumen';
    }
}

document.addEventListener('DOMContentLoaded', () => {
    cargarUsuarios();
    cargarHistorial();
    document.getElementById('btnResumen').addEventListener('click', resumenActual);
    const btn = document.getElementById('aplicarFiltros');
    if (btn) btn.addEventListener('click', cargarHistorial);
    const imp = document.getElementById('btnImprimir');
    if (imp) imp.addEventListener('click', () => window.print());
});
