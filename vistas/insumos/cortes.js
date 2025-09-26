const usuarioId = 1; // reemplazar con id de sesión en producción
let detalles = [];
let corteActual = null;
let pagina = 1;

// Referencias UI
const selCortes = document.getElementById('listaCortes');
const btnBuscar = document.getElementById('btnBuscar');
const filtroInsumo = document.getElementById('filtroInsumo');
const pageSizeSel = document.getElementById('registrosPagina');
const tbodyResumen = document.querySelector('#tablaResumen tbody');

function getPageSize() {
  return parseInt(pageSizeSel?.value || '15', 10);
}

function buildQuery(params) {
  const usp = new URLSearchParams();
  Object.entries(params || {}).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== '') usp.set(k, v);
  });
  const q = usp.toString();
  return q ? ('?' + q) : '';
}

function getBaseParams() {
  const desde = document.getElementById('buscarDesde')?.value || '';
  const hasta = document.getElementById('buscarHasta')?.value || '';
  if (!desde && !hasta) return { abiertos: 1 };
  const p = {};
  if (desde) p.desde = desde;
  if (hasta) p.hasta = hasta;
  return p;
}

function updateExportButtons() {
  const hasSel = !!corteActual;
  const b1 = document.getElementById('btnExportarCsv');
  const b2 = document.getElementById('btnExportarPdf');
  if (b1) b1.disabled = !hasSel;
  if (b2) b2.disabled = !hasSel;
}

async function abrirCorte() {
  try {
    const resp = await fetch('../../api/insumos/cortes_almacen.php', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ accion: 'abrir', usuario_id: usuarioId })
    });
    const data = await resp.json();
    if (data.success) {
      alert('Corte abierto ID: ' + data.resultado.corte_id);
      await cargarCortes(false);
    } else {
      alert(data.mensaje || 'No se pudo abrir');
    }
  } catch (err) { console.error(err); alert('Error al abrir corte'); }
}

function cerrarCorte() {
  document.getElementById('formObservaciones').style.display = 'block';
}

async function guardarCierre() {
  const obs = document.getElementById('observaciones').value;
  const corteId = selCortes?.value || prompt('ID de corte a cerrar');
  if (!corteId) return;
  try {
    const resp = await fetch('../../api/insumos/cortes_almacen.php', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ accion: 'cerrar', corte_id: corteId, usuario_id: usuarioId, observaciones: obs })
    });
    const data = await resp.json();
    if (data.success) {
      document.getElementById('formObservaciones').style.display = 'none';
      await cargarCortes(true);
      if (selCortes?.value) await cargarDetalleCorte(selCortes.value);
    } else {
      alert(data.mensaje || 'No se pudo cerrar');
    }
  } catch (err) { console.error(err); alert('Error al cerrar'); }
}

async function cargarCortes(preserveSelection = true) {
  const lista = selCortes;
  const prev = lista.value;
  lista.innerHTML = '<option value="">Seleccione corte.</option>';
  try {
    const url = '../../api/insumos/listar_cortes_almacen.php' + buildQuery(getBaseParams());
    const r = await fetch(url, { credentials: 'same-origin' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const json = await r.json();
    const rows = Array.isArray(json) ? json : (json.resultado || json.rows || []);
    if (!rows.length) {
      const opt = document.createElement('option'); opt.textContent = 'No hay cortes'; opt.disabled = true; lista.appendChild(opt);
      corteActual = null; detalles = []; pagina = 1; renderTabla(); updateExportButtons(); return;
    }
    rows.forEach(c => {
      const opt = document.createElement('option');
      const fi = (c.fecha_inicio || '').replace('T', ' ').slice(0, 19);
      const abierto = !c.fecha_fin;
      opt.value = String(c.id);
      opt.textContent = `#${c.id} — ${fi}${abierto ? ' (abierto)' : ' (cerrado)'}`;
      lista.appendChild(opt);
    });
    if (preserveSelection && rows.some(c => String(c.id) === prev)) {
      lista.value = prev;
    } else {
      lista.selectedIndex = 1;
    }
    if (lista.value) { await cargarDetalleCorte(lista.value); } else { corteActual = null; detalles = []; pagina = 1; renderTabla(); }
  } catch (e) {
    console.error(e); alert('No se pudieron cargar los cortes.'); corteActual = null; detalles = []; pagina = 1; renderTabla();
  } finally { updateExportButtons(); }
}

async function cargarDetalleCorte(corteId) {
  if (!corteId) { corteActual = null; detalles = []; renderTabla(); updateExportButtons(); return; }
  try {
    const r = await fetch(`../../api/insumos/listar_cortes_almacen_detalle.php?corte_id=${encodeURIComponent(corteId)}`, { credentials: 'same-origin' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const json = await r.json();
    const rows = Array.isArray(json) ? json : (json.resultado || json.rows || []);
    detalles = rows.map(d => ({
      insumo: d.insumo ?? d.insumo_id,
      existencia_inicial: d.existencia_inicial,
      entradas: d.entradas,
      salidas: d.salidas,
      mermas: d.mermas,
      existencia_final: d.existencia_final
    }));
    corteActual = corteId; pagina = 1; renderTabla();
  } catch (e) { console.error(e); alert('No se pudo cargar el detalle del corte.'); }
  finally { updateExportButtons(); }
}

function renderTabla() {
  const filtro = (filtroInsumo?.value || '').toLowerCase();
  const tbody = tbodyResumen; tbody.innerHTML = '';
  const ps = getPageSize();
  const filtrados = detalles.filter(d => String(d.insumo ?? '').toLowerCase().includes(filtro));
  const inicio = (pagina - 1) * ps;
  const paginados = filtrados.slice(inicio, inicio + ps);
  if (!paginados.length) {
    const tr = document.createElement('tr'); const td = document.createElement('td');
    td.colSpan = 6; td.textContent = 'Sin resultados'; tr.appendChild(td); tbody.appendChild(tr); return;
  }
  paginados.forEach(d => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${d.insumo ?? ''}</td><td>${d.existencia_inicial ?? ''}</td><td>${d.entradas ?? ''}</td><td>${d.salidas ?? ''}</td><td>${d.mermas ?? ''}</td><td>${d.existencia_final ?? ''}</td>`;
    tbody.appendChild(tr);
  });
}

function exportarCsv() {
  if (!detalles.length) { alert('No hay datos para exportar'); return; }
  const filtro = (filtroInsumo?.value || '').toLowerCase();
  const filas = detalles.filter(d => String(d.insumo ?? '').toLowerCase().includes(filtro));
  if (!filas.length) { alert('No hay datos para exportar'); return; }
  const escapeCsv = valor => {
    const texto = valor === null || valor === undefined ? '' : String(valor);
    const necesitaComillas = texto.includes('"') || texto.includes(',') || texto.includes('\n');
    return necesitaComillas ? `"${texto.replace(/"/g, '""')}"` : texto;
  };
  const filasCsv = filas.map(d => [d.insumo, d.existencia_inicial, d.entradas, d.salidas, d.mermas, d.existencia_final]);
  const encabezados = ['Insumo', 'Inicial', 'Entradas', 'Salidas', 'Mermas', 'Final'];
  const csv = [encabezados, ...filasCsv].map(fila => fila.map(escapeCsv).join(',')).join('\r\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob); const enlace = document.createElement('a'); const fecha = new Date().toISOString().slice(0, 10);
  enlace.href = url; enlace.download = `corte_${corteActual || 'sin_id'}_${fecha}.csv`; document.body.appendChild(enlace); enlace.click(); document.body.removeChild(enlace); URL.revokeObjectURL(url);
}

async function exportarPdf() {
  if (!corteActual) { alert('Seleccione un corte'); return; }
  try {
    const resp = await fetch('../../api/insumos/cortes_almacen.php', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ accion: 'exportar_pdf', corte_id: corteActual }) });
    const data = await resp.json();
    if (data.success) { window.open(data.resultado.archivo, '_blank'); } else { alert(data.mensaje || 'No se pudo exportar'); }
  } catch (err) { console.error(err); alert('No se pudo exportar'); }
}

function cambiarPagina(delta) {
  const ps = getPageSize();
  const total = detalles.filter(d => String(d.insumo ?? '').toLowerCase().includes((filtroInsumo?.value || '').toLowerCase())).length;
  const maxPagina = Math.max(1, Math.ceil(total / ps));
  pagina += delta; if (pagina < 1) pagina = 1; if (pagina > maxPagina) pagina = maxPagina; renderTabla();
}

document.addEventListener('DOMContentLoaded', async () => {
  document.getElementById('btnAbrirCorte')?.addEventListener('click', abrirCorte);
  document.getElementById('btnCerrarCorte')?.addEventListener('click', cerrarCorte);
  document.getElementById('guardarCierre')?.addEventListener('click', guardarCierre);
  btnBuscar?.addEventListener('click', () => cargarCortes(false));
  selCortes?.addEventListener('change', e => { pagina = 1; const v = e.target.value; if (v) cargarDetalleCorte(v); else { corteActual = null; detalles = []; renderTabla(); updateExportButtons(); } });
  filtroInsumo?.addEventListener('input', () => { pagina = 1; renderTabla(); });
  pageSizeSel?.addEventListener('change', () => { pagina = 1; renderTabla(); });
  document.getElementById('btnExportarCsv')?.addEventListener('click', exportarCsv);
  document.getElementById('btnExportarPdf')?.addEventListener('click', exportarPdf);
  document.getElementById('prevPagina')?.addEventListener('click', () => cambiarPagina(-1));
  document.getElementById('nextPagina')?.addEventListener('click', () => cambiarPagina(1));
  await cargarCortes(false);
  if (selCortes && selCortes.value) { await cargarDetalleCorte(selCortes.value); }
  updateExportButtons();
});

