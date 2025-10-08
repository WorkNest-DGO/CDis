async function cargarInsumos() {
    const sel = document.getElementById('selInsumo');
    if (!sel) return;
    sel.innerHTML = '<option value="">Cargando...</option>';
    try {
        const r = await fetch('../../api/insumos/listar_insumos.php', { cache: 'no-store' });
        const j = await r.json();
        sel.innerHTML = '<option value="">Seleccione insumo...</option>';
        if (j && j.success && Array.isArray(j.resultado)) {
            j.resultado.forEach(it => {
                const opt = document.createElement('option');
                opt.value = it.id;
                opt.textContent = `${it.id} - ${it.nombre}`;
                sel.appendChild(opt);
            });
        }
    } catch (e) {
        console.error(e);
        sel.innerHTML = '<option value="">Error al cargar</option>';
    }
}

async function cargarEntradas(insumoId) {
    const sel = document.getElementById('selEntrada');
    const tbody = document.querySelector('#tablaEntradas tbody');
    const txtAct = document.getElementById('txtCantidadActual');
    if (txtAct) txtAct.value = '';
    if (tbody) tbody.innerHTML = '';
    if (!sel) return;
    if (!insumoId) {
        sel.innerHTML = '<option value="">Seleccione insumo primero...</option>';
        sel.disabled = true;
        return;
    }
    sel.disabled = true;
    sel.innerHTML = '<option value="">Cargando...</option>';
    try {
        const url = `../../api/insumos/consultar_entrada_insumo.php?insumo_id=${encodeURIComponent(insumoId)}`;
        const r = await fetch(url, { cache: 'no-store' });
        const j = await r.json();
        sel.innerHTML = '<option value="">Seleccione entrada...</option>';
        if (j && j.success) {
            const lista = Array.isArray(j.resultado) ? j.resultado : [j.resultado];
            lista.forEach(ei => {
                const opt = document.createElement('option');
                opt.value = ei.id;
                const f = (ei.fecha || '').substring(0, 16);
                opt.textContent = `#${ei.id} · ${f} · actual: ${Number(ei.cantidad_actual || 0).toFixed(2)} ${ei.unidad || ''}`;
                opt.dataset.cantidadActual = ei.cantidad_actual;
                opt.dataset.unidad = ei.unidad || '';
                sel.appendChild(opt);

                if (tbody) {
                    const tr = document.createElement('tr');
                    tr.innerHTML = `<td>${ei.id}</td><td>${(ei.fecha||'').substring(0,16)}</td><td>${ei.descripcion||''}</td><td>${Number(ei.cantidad||0).toFixed(2)}</td><td>${Number(ei.cantidad_actual||0).toFixed(2)}</td><td>${ei.unidad||''}</td><td>${ei.proveedor_nombre||''}</td>`;
                    tbody.appendChild(tr);
                }
            });
            sel.disabled = false;
        } else {
            sel.innerHTML = '<option value="">Sin entradas</option>';
            sel.disabled = true;
        }
    } catch (e) {
        console.error(e);
        sel.innerHTML = '<option value="">Error al cargar</option>';
        sel.disabled = true;
    }
}

function onEntradaChange() {
    const sel = document.getElementById('selEntrada');
    const txtAct = document.getElementById('txtCantidadActual');
    if (!sel || !txtAct) return;
    const opt = sel.options[sel.selectedIndex];
    const val = opt ? (opt.dataset.cantidadActual || '') : '';
    txtAct.value = val !== '' ? Number(val).toFixed(2) : '';
}

async function aplicarAjuste() {
    const estado = document.getElementById('estadoAjuste');
    const ins = document.getElementById('selInsumo');
    const ent = document.getElementById('selEntrada');
    const cantEl = document.getElementById('txtAjuste');
    const obsEl = document.getElementById('txtObs');
    if (estado) estado.textContent = '';
    const insumoId = ins && ins.value ? parseInt(ins.value, 10) : 0;
    const entradaId = ent && ent.value ? parseInt(ent.value, 10) : 0;
    const delta = cantEl && cantEl.value !== '' ? parseFloat(cantEl.value) : NaN;
    if (!entradaId || !Number.isFinite(delta) || Math.abs(delta) < 1e-9) {
        if (estado) estado.textContent = 'Seleccione entrada y una cantidad válida (puede ser negativa o positiva).';
        return;
    }
    try {
        const resp = await fetch('../../api/insumos/registrar_ajuste.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ entrada_id: entradaId, cantidad: delta, observacion: obsEl ? obsEl.value.trim() : '' })
        });
        const data = await resp.json();
        if (!data || data.success !== true) {
            if (estado) estado.textContent = data && (data.mensaje || data.error) ? (data.mensaje || data.error) : 'No se pudo registrar el ajuste';
            return;
        }
        if (estado) estado.textContent = 'Ajuste aplicado correctamente';
        // Actualizar UI: cantidad actual mostrada y opción del select
        const nuevo = data.resultado && data.resultado.cantidad_nueva !== undefined ? Number(data.resultado.cantidad_nueva) : null;
        if (nuevo !== null && ent && ent.selectedIndex >= 0) {
            const opt = ent.options[ent.selectedIndex];
            opt.dataset.cantidadActual = String(nuevo);
            onEntradaChange();
            // Refrescar tabla simple: recargar entradas del insumo
            if (insumoId) cargarEntradas(insumoId);
        }
        cantEl.value = '';
        if (obsEl) obsEl.value = '';
    } catch (e) {
        console.error(e);
        if (estado) estado.textContent = 'Error de red al registrar el ajuste';
    }
}

document.addEventListener('DOMContentLoaded', () => {
    cargarInsumos();
    document.getElementById('selInsumo')?.addEventListener('change', (ev) => cargarEntradas(ev.target.value));
    document.getElementById('selEntrada')?.addEventListener('change', onEntradaChange);
    document.getElementById('btnAplicar')?.addEventListener('click', aplicarAjuste);
});

