function showAppMsg(msg) {
    const body = document.querySelector('#appMsgModal .modal-body');
    if (body) body.textContent = String(msg);
    showModal('#appMsgModal');
}
window.alert = showAppMsg;

let usuarios = [];

async function cargarUsuarios() {
    try {
        const resp = await fetch('../../api/usuarios/listar_usuarios.php');
        const data = await resp.json();
        const tbody = document.querySelector('#tablaUsuarios tbody');
        tbody.innerHTML = '';
        if (data.success) {
            usuarios = data.usuarios || [];
            usuarios.forEach(u => {
                const tr = document.createElement('tr');
                tr.innerHTML = `<td>${u.id}</td><td>${u.nombre}</td><td>${u.usuario}</td><td>${u.rol}</td><td>${u.activo == 1 ? 'Sí' : 'No'}</td>`;
                const tdAcc = document.createElement('td');
                const btnE = document.createElement('button');
                btnE.className = 'btn custom-btn me-2';
                btnE.textContent = 'Editar';
                btnE.onclick = () => editarUsuario(u.id);
                const btnD = document.createElement('button');
                btnD.className = 'btn custom-btn';
                btnD.textContent = 'Eliminar';
                btnD.onclick = () => eliminarUsuario(u.id);
                tdAcc.appendChild(btnE);
                tdAcc.appendChild(btnD);
                tr.appendChild(tdAcc);
                tbody.appendChild(tr);
            });
        } else {
            alert(data.mensaje);
        }
    } catch (err) {
        console.error(err);
        alert('Error al cargar usuarios');
    }
}

document.getElementById('btnAgregar').onclick = () => {
    document.getElementById('formUsuario').reset();
    document.getElementById('usuarioId').value = '';
    showModal('#modalUsuario');
};

document.getElementById('formUsuario').onsubmit = async ev => {
    ev.preventDefault();
    const id = document.getElementById('usuarioId').value;
    const payload = {
        nombre: document.getElementById('nombre').value,
        usuario: document.getElementById('usuario').value,
        contrasena: document.getElementById('contrasena').value,
        rol: document.getElementById('rol').value,
        activo: parseInt(document.getElementById('activo').value)
    };
    let url;
    if (id) {
        payload.id = parseInt(id);
        url = '../../api/usuarios/editar_usuario.php';
    } else {
        url = '../../api/usuarios/agregar_usuario.php';
    }
    try {
        const resp = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await resp.json();
        alert(data.mensaje);
        if (data.success) {
            hideModal('#modalUsuario');
            cargarUsuarios();
        }
    } catch (err) {
        console.error(err);
        alert('Error al guardar usuario');
    }
};

function editarUsuario(id) {
    const u = usuarios.find(x => x.id == id);
    if (!u) return;
    document.getElementById('usuarioId').value = u.id;
    document.getElementById('nombre').value = u.nombre;
    document.getElementById('usuario').value = u.usuario;
    document.getElementById('contrasena').value = '';
    document.getElementById('rol').value = u.rol;
    document.getElementById('activo').value = u.activo;
    showModal('#modalUsuario');
}

async function eliminarUsuario(id) {
    if (!confirm('¿Eliminar usuario?')) return;
    try {
        const resp = await fetch('../../api/usuarios/eliminar_usuario.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id })
        });
        const data = await resp.json();
        alert(data.mensaje);
        if (data.success) cargarUsuarios();
    } catch (err) {
        console.error(err);
        alert('Error al eliminar usuario');
    }
}

window.addEventListener('DOMContentLoaded', cargarUsuarios);

// Paginador + buscador (20 por página) para Usuarios
(function(){
  let ALL = [];
  let FIL = [];
  let PAGE = 1;
  const PP = 20;

  function render(){
    const tbody = document.querySelector('#tablaUsuarios tbody');
    const pag = document.getElementById('paginadorUsuarios');
    if (!tbody || !pag) return;
    const total = Math.max(1, Math.ceil(FIL.length / PP));
    if (PAGE > total) PAGE = total;
    const ini = (PAGE - 1) * PP, fin = ini + PP;
    ALL.forEach(tr => tr.style.display = 'none');
    FIL.forEach((tr, idx) => tr.style.display = (idx>=ini && idx<fin) ? '' : 'none');

    pag.innerHTML = '';
    const prevLi = document.createElement('li');
    prevLi.className = 'page-item' + (PAGE === 1 ? ' disabled' : '');
    const prevA = document.createElement('a'); prevA.className='page-link'; prevA.href='#'; prevA.textContent='Anterior';
    prevA.addEventListener('click', e => { e.preventDefault(); if (PAGE>1){ PAGE--; render(); }});
    prevLi.appendChild(prevA); pag.appendChild(prevLi);
    for (let i=1;i<=total;i++){
      const li=document.createElement('li'); li.className='page-item'+(i===PAGE?' active':'');
      const a=document.createElement('a'); a.className='page-link'; a.href='#'; a.textContent=String(i);
      a.addEventListener('click', e=>{ e.preventDefault(); PAGE=i; render(); });
      li.appendChild(a); pag.appendChild(li);
    }
    const nextLi = document.createElement('li');
    nextLi.className = 'page-item' + (PAGE === total ? ' disabled' : '');
    const nextA = document.createElement('a'); nextA.className='page-link'; nextA.href='#'; nextA.textContent='Siguiente';
    nextA.addEventListener('click', e => { e.preventDefault(); if (PAGE<total){ PAGE++; render(); }});
    nextLi.appendChild(nextA); pag.appendChild(nextLi);
  }

  function init(){
    ALL = Array.from(document.querySelectorAll('#tablaUsuarios tbody tr'));
    FIL = ALL.slice(); PAGE = 1; render();
  }

  const tbody = document.querySelector('#tablaUsuarios tbody');
  if (tbody) {
    const obs = new MutationObserver(() => { init(); });
    obs.observe(tbody, { childList: true });
  }
  const buscar = document.getElementById('buscarUsuario');
  if (buscar) {
    let t; buscar.addEventListener('input', e => {
      clearTimeout(t);
      t = setTimeout(() => {
        const q = (e.target.value || '').toLowerCase();
        FIL = ALL.filter(tr => tr.innerText.toLowerCase().includes(q));
        PAGE = 1; render();
      }, 250);
    });
  }
})();
