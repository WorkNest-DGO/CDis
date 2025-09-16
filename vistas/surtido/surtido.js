// Utiles generales
function fmtNum(n, dec = 2) {
  if (n === null || n === undefined || n === '') return '';
  const num = Number(n);
  if (Number.isNaN(num)) return String(n);
  return num.toLocaleString('es-MX', { minimumFractionDigits: dec, maximumFractionDigits: dec });
}

function fmtDateTime(s) {
  if (!s) return '';
  try {
    const d = new Date(s.replace(' ', 'T'));
    if (Number.isNaN(d.getTime())) return s;
    return d.toLocaleString('es-MX');
  } catch { return s; }
}

function mondayThisWeek() {
  const d = new Date();
  const day = d.getDay(); // 0=Sun..6=Sat
  const diff = (day === 0 ? -6 : 1) - day; // to Monday
  const m = new Date(d);
  m.setDate(d.getDate() + diff);
  m.setHours(0,0,0,0);
  return m;
}

function sundayThisWeek() {
  const m = mondayThisWeek();
  const s = new Date(m);
  s.setDate(m.getDate() + 6);
  s.setHours(0,0,0,0);
  return s;
}

function toYMD(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth()+1).padStart(2,'0');
  const day = String(d.getDate()).padStart(2,'0');
  return `${y}-${m}-${day}`;
}

// Estado y referencias
const state = {
  desde: toYMD(mondayThisWeek()),
  hasta: toYMD(sundayThisWeek()),
  entradas: { page: 1, pageSize: 10, q: '' },
  lead:    { page: 1, pageSize: 10, q: '', incluir: 0 },
  rpi:     { page: 1, pageSize: 10, q: '', incluir: 0 },
  selectedInsumo: 0,
};

// Render paginadores
function renderPaginador(elemId, total, pageSize, page, onChange) {
  const ul = document.getElementById(elemId);
  if (!ul) return;
  ul.innerHTML = '';
  const totalPaginas = Math.max(1, Math.ceil(total / pageSize));
  const mkLi = (label, targetPage, disabled=false, active=false) => {
    const li = document.createElement('li');
    li.className = 'page-item' + (disabled ? ' disabled' : '') + (active ? ' active' : '');
    const a = document.createElement('a');
    a.className = 'page-link';
    a.href = '#';
    a.textContent = label;
    a.addEventListener('click', (e) => { e.preventDefault(); if (!disabled && !active) onChange(targetPage); });
    li.appendChild(a); ul.appendChild(li);
  };
  mkLi('Anterior', Math.max(1, page-1), page<=1);
  for (let i=1; i<=totalPaginas; i++) { mkLi(String(i), i, false, i===page); }
  mkLi('Siguiente', Math.min(totalPaginas, page+1), page>=totalPaginas);
}

// Cargar Entradas Insumos
async function cargarEntradas() {
  const { page, pageSize, q } = state.entradas;
  const url = new URL('../../api/surtido/entradas_insumos.php', document.baseURI);
  url.searchParams.set('page', page);
  url.searchParams.set('pageSize', pageSize);
  url.searchParams.set('q', q);
  url.searchParams.set('desde', state.desde);
  url.searchParams.set('hasta', state.hasta);
  try {
    const resp = await fetch(url);
    const data = await resp.json();
    if (!data.success) throw new Error(data.mensaje || 'Error de API');
    const { rows, total } = data.resultado;
    const tb = document.getElementById('tbodyEntradas');
    tb.innerHTML = '';
    rows.forEach(r => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${fmtDateTime(r.fecha)}</td>
        <td>${r.insumo ?? ''}</td>
        <td>${r.unidad ?? ''}</td>
        <td class="text-right">${fmtNum(r.cantidad, 2)}</td>
        <td class="text-right">${fmtNum(r.costo_total, 2)}</td>
        <td class="text-right">${fmtNum(r.valor_unitario, 4)}</td>
        <td>${r.proveedor ?? ''}</td>
        <td>${r.usuario ?? ''}</td>
        <td>${r.descripcion ?? ''}</td>
        <td>${r.referencia_doc ?? ''}</td>
        <td>${r.folio_fiscal ?? ''}</td>`;
      tb.appendChild(tr);
    });
    renderPaginador('paginadorEntradas', total, pageSize, page, (p)=>{ state.entradas.page = p; cargarEntradas(); });
  } catch (e) {
    console.error(e);
    alert('Error al cargar entradas');
  }
}

// Cargar Lead Time
async function cargarLead() {
  const { page, pageSize, q, incluir } = state.lead;
  const url = new URL('../../api/surtido/leadtime_insumos.php', document.baseURI);
  url.searchParams.set('page', page);
  url.searchParams.set('pageSize', pageSize);
  url.searchParams.set('q', q);
  url.searchParams.set('desde', state.desde);
  url.searchParams.set('hasta', state.hasta);
  url.searchParams.set('incluir_ceros', incluir);
  try {
    const resp = await fetch(url);
    const data = await resp.json();
    if (!data.success) throw new Error(data.mensaje || 'Error de API');
    const { rows, total } = data.resultado;
    const tb = document.getElementById('tbodyLead');
    tb.innerHTML = '';
    rows.forEach(r => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${r.insumo ?? ''}</td>
        <td class="text-right">${fmtNum(r.pares_evaluados || 0, 0)}</td>
        <td class="text-right">${r.avg_dias_reabasto != null ? fmtNum(r.avg_dias_reabasto, 2) : ''}</td>
        <td class="text-right">${r.min_dias != null ? fmtNum(r.min_dias, 0) : ''}</td>
        <td class="text-right">${r.max_dias != null ? fmtNum(r.max_dias, 0) : ''}</td>
        <td>${r.ultima_entrada ? r.ultima_entrada : ''}</td>
        <td>${r.proxima_estimada ? r.proxima_estimada : ''}</td>
        <td class="text-right">${r.dias_restantes != null ? fmtNum(r.dias_restantes, 0) : ''}</td>`;
      tb.appendChild(tr);
    });
    renderPaginador('paginadorLead', total, pageSize, page, (p)=>{ state.lead.page = p; cargarLead(); });
  } catch (e) {
    console.error(e);
    alert('Error al cargar lead time');
  }
}

// Cargar Resumen por insumo (todos)
async function cargarResumenInsumo() {
  const { page, pageSize, q, incluir } = state.rpi;
  const url = new URL('../../api/surtido/resumen_por_insumo.php', document.baseURI);
  url.searchParams.set('page', page);
  url.searchParams.set('pageSize', pageSize);
  url.searchParams.set('q', q);
  url.searchParams.set('desde', state.desde);
  url.searchParams.set('hasta', state.hasta);
  url.searchParams.set('incluir_ceros', incluir);
  try {
    const resp = await fetch(url);
    const data = await resp.json();
    if (!data.success) throw new Error(data.mensaje || 'Error de API');
    const { rows, total } = data.resultado;
    const tb = document.getElementById('tbodyResumenInsumo');
    tb.innerHTML = '';
    rows.forEach(r => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${r.insumo ?? ''}</td>
        <td class="text-right">${fmtNum(r.compras_evaluadas || 0, 0)}</td>
        <td class="text-right">${fmtNum(r.monto_total || 0, 2)}</td>
        <td class="text-right">${fmtNum(r.costo_medio || 0, 2)}</td>
        <td class="text-right">${fmtNum(r.costo_promedio_unitario || 0, 4)}</td>
        <td class="text-right">${fmtNum(r.cantidad_total || 0, 2)}</td>
        <td>${r.primera_compra ? r.primera_compra : ''}</td>
        <td>${r.ultima_compra ? r.ultima_compra : ''}</td>`;
      tb.appendChild(tr);
    });
    renderPaginador('paginadorResumenInsumo', total, pageSize, page, (p)=>{ state.rpi.page = p; cargarResumenInsumo(); });
  } catch (e) {
    console.error(e);
    alert('Error al cargar resumen por insumo');
  }
}

// Cargar Resumen Global
async function cargarResumenGlobal() {
  const url = new URL('../../api/surtido/resumen_compras_global.php', document.baseURI);
  url.searchParams.set('desde', state.desde);
  url.searchParams.set('hasta', state.hasta);
  try {
    const resp = await fetch(url);
    const data = await resp.json();
    if (!data.success) throw new Error(data.mensaje || 'Error de API');
    const row = data.resultado.row || {};
    const tb = document.getElementById('tbodyResumenGlobal');
    tb.innerHTML = '';
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${fmtNum(row.compras_evaluadas || 0, 0)}</td>
      <td class="text-right">${fmtNum(row.monto_total || 0, 2)}</td>
      <td class="text-right">${fmtNum(row.costo_medio || 0, 2)}</td>
      <td class="text-right">${fmtNum(row.costo_promedio_unitario || 0, 4)}</td>
      <td class="text-right">${fmtNum(row.cantidad_total || 0, 2)}</td>
      <td>${row.primera_compra ? row.primera_compra : ''}</td>
      <td>${row.ultima_compra ? row.ultima_compra : ''}</td>`;
    tb.appendChild(tr);
  } catch (e) {
    console.error(e);
    alert('Error al cargar resumen global');
  }
}

// Cargar select de insumos
async function cargarSelectInsumos() {
  try {
    const resp = await fetch('../../api/insumos/listar_insumos.php');
    const data = await resp.json();
    if (!data.success) throw new Error(data.mensaje || 'Error de API');
    const sel = document.getElementById('selectInsumo');
    sel.innerHTML = '';
    const opt0 = document.createElement('option'); opt0.value = '0'; opt0.textContent = 'Seleccione un insumo'; sel.appendChild(opt0);
    (data.resultado || []).forEach(i => {
      const opt = document.createElement('option'); opt.value = i.id; opt.textContent = i.nombre; sel.appendChild(opt);
    });
  } catch(e) {
    console.error(e);
  }
}

// Consultar resumen por un insumo
async function cargarResumenInsumoUno() {
  const insumo_id = Number(document.getElementById('selectInsumo').value || '0');
  if (!insumo_id) { alert('Seleccione un insumo'); return; }
  const url = new URL('../../api/surtido/resumen_compras_insumo.php', document.baseURI);
  url.searchParams.set('insumo_id', String(insumo_id));
  url.searchParams.set('desde', state.desde);
  url.searchParams.set('hasta', state.hasta);
  try {
    const resp = await fetch(url);
    const data = await resp.json();
    if (!data.success) throw new Error(data.mensaje || 'Error de API');
    const row = data.resultado.row || {};
    const tb = document.getElementById('tbodyResumenInsumoUno');
    tb.innerHTML = '';
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${row.insumo || ''}</td>
      <td class="text-right">${fmtNum(row.compras_evaluadas || 0, 0)}</td>
      <td class="text-right">${fmtNum(row.monto_total || 0, 2)}</td>
      <td class="text-right">${fmtNum(row.costo_medio || 0, 2)}</td>
      <td class="text-right">${fmtNum(row.costo_promedio_unitario || 0, 4)}</td>`;
    tb.appendChild(tr);
  } catch (e) {
    console.error(e);
    alert('Error al cargar resumen por insumo');
  }
}

// Inicialización
document.addEventListener('DOMContentLoaded', () => {
  // Set default dates
  document.getElementById('filtroDesde').value = state.desde;
  document.getElementById('filtroHasta').value = state.hasta;

  document.getElementById('btnAplicar').addEventListener('click', () => {
    const d = document.getElementById('filtroDesde').value;
    const h = document.getElementById('filtroHasta').value;
    if (!d || !h) { alert('Seleccione fechas'); return; }
    state.desde = d; state.hasta = h;
    // reset pages
    state.entradas.page = 1; state.lead.page = 1; state.rpi.page = 1;
    cargarEntradas();
    cargarLead();
    cargarResumenInsumo();
    cargarResumenGlobal();
    // Si hay insumo seleccionado, refrescar su resumen
    const sel = document.getElementById('selectInsumo');
    if (sel && Number(sel.value)) cargarResumenInsumoUno();
  });

  // Buscadores
  document.getElementById('buscarEntradas').addEventListener('input', (e) => {
    state.entradas.q = e.target.value.trim(); state.entradas.page = 1; cargarEntradas();
  });
  document.getElementById('buscarLead').addEventListener('input', (e) => {
    state.lead.q = e.target.value.trim(); state.lead.page = 1; cargarLead();
  });
  document.getElementById('buscarResumenInsumo').addEventListener('input', (e) => {
    state.rpi.q = e.target.value.trim(); state.rpi.page = 1; cargarResumenInsumo();
  });
  document.getElementById('ltIncluirCeros').addEventListener('change', (e) => {
    state.lead.incluir = e.target.checked ? 1 : 0; state.lead.page = 1; cargarLead();
  });
  document.getElementById('rpIncluirCeros').addEventListener('change', (e) => {
    state.rpi.incluir = e.target.checked ? 1 : 0; state.rpi.page = 1; cargarResumenInsumo();
  });
  document.getElementById('btnConsultarInsumo').addEventListener('click', () => cargarResumenInsumoUno());

  // Cargar datos iniciales
  cargarSelectInsumos();
  cargarEntradas();
  cargarLead();
  cargarResumenInsumo();
  cargarResumenGlobal();
});

