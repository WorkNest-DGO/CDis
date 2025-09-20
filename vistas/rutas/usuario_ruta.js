function showAppMsg(msg) {
    const body = document.querySelector('#appMsgModal .modal-body');
    if (body) body.textContent = String(msg);
    showModal('#appMsgModal');
}
window.alert = showAppMsg;

async function cargarUsuarios() {
    try {
        const resp = await fetch('../../api/usuarios/listar_usuarios.php');
        const data = await resp.json();
        const sel = document.getElementById('usuarioSelect');
        sel.innerHTML = '';
        if (data.success) {
            (data.usuarios || []).forEach(u => {
                const opt = document.createElement('option');
                opt.value = u.nombre;
                opt.textContent = u.nombre;
                sel.appendChild(opt);
            });
            if (sel.value) cargarRutasUsuario(sel.value);
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar usuarios');
    }
}

document.getElementById('usuarioSelect').onchange = ev => {
    const usuario = ev.target.value;
    cargarRutasUsuario(usuario);
};

async function cargarRutasUsuario(usuario) {
    if (!usuario) return;
    try {
        const resp = await fetch(`../../api/rutas/listar_usuario_rutas.php?usuario=${encodeURIComponent(usuario)}`);
        const data = await resp.json();
        const tbody = document.querySelector('#tablaRutasUsuario tbody');
        tbody.innerHTML = '';
        if (data.success) {
            (data.resultado || []).forEach(r => {
                const tr = document.createElement('tr');
                tr.innerHTML = `<td>${r.nombre}</td><td>${r.path}</td><td>${r.tipo}</td><td>${r.grupo ?? ''}</td><td>${r.orden}</td>`;
                const tdCheck = document.createElement('td');
                const chk = document.createElement('input');
                chk.type = 'checkbox';
                chk.checked = !!r.asignado;
                chk.dataset.nombre = r.nombre;
                tdCheck.appendChild(chk);
                tr.appendChild(tdCheck);
                tbody.appendChild(tr);
            });
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar rutas');
    }
}

async function guardarRutasUsuario() {
    const usuario = document.getElementById('usuarioSelect').value;
    if (!usuario) return;
    const checks = document.querySelectorAll('#tablaRutasUsuario tbody input[type="checkbox"]');
    const rutas = Array.from(checks).filter(c => c.checked).map(c => c.dataset.nombre);
    try {
        const resp = await fetch('../../api/rutas/guardar_usuario_rutas.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ usuario, rutas })
        });
        const data = await resp.json();
        alert(data.mensaje);
        if (data.success) cargarRutasUsuario(usuario);
    } catch (err) {
        console.error(err);
        alert('Error al guardar rutas');
    }
}

document.getElementById('btnGuardar').onclick = guardarRutasUsuario;

window.addEventListener('DOMContentLoaded', cargarUsuarios);
