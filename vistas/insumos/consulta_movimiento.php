<?php
$__sn = isset($_SERVER['SCRIPT_NAME']) ? $_SERVER['SCRIPT_NAME'] : '';
$__pos = strpos($__sn, '/vistas/');
$__base = $__pos !== false ? substr($__sn, 0, $__pos) : rtrim(dirname($__sn), '/');
if ($__base === '.' || $__base === '/' || $__base === '\\') {
    $__base = '';
}
$baseUrl = rtrim($__base, '/');
$tokenPreset = isset($_GET['token']) ? trim((string) $_GET['token']) : '';
$idPreset = isset($_GET['id']) ? (int) $_GET['id'] : 0;
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Consulta de movimiento de insumo</title>
    <link href="<?= $baseUrl ? $baseUrl : '' ?>/utils/css/bootstrap.min.css" rel="stylesheet">
    <link href="<?= $baseUrl ? $baseUrl : '' ?>/utils/css/style1.css" rel="stylesheet">
    <style>
        body {
            background: #f7f8fa;
        }
        .consulta-header {
            text-align: center;
            margin-bottom: 2rem;
        }
        .consulta-header h1 {
            font-size: 1.75rem;
            font-weight: 700;
            color: #2c3e50;
        }
        .consulta-header p {
            color: #6c757d;
            margin-bottom: 0;
        }
        .card-info {
            border: none;
            border-radius: 1rem;
        }
        .card-info .card-body {
            padding: 2rem;
        }
        .info-label {
            font-weight: 600;
            color: #495057;
        }
        .texto-importante {
            font-size: 1.1rem;
            font-weight: 600;
            color: #1f3c88;
        }
        code {
            color: #c7254e;
            background-color: #f9f2f4;
            border-radius: 4px;
            padding: 2px 4px;
        }
        #mov-qr-img {
            max-width: 240px;
        }
    </style>
</head>
<body>
<div class="container py-4 py-md-5">
    <div class="consulta-header">
        <h1>Consulta de movimiento de insumo</h1>
        <p>Información vinculada al código QR de salida.</p>
    </div>

    <div id="mov-status" class="alert alert-info">Buscando información del movimiento...</div>

    <div id="mov-detalle" class="card card-info shadow-sm d-none">
        <div class="card-body">
            <h2 class="texto-importante mb-3">Movimiento <span id="mov-id">—</span></h2>
            <dl class="row">
                <dt class="col-sm-4 info-label">Tipo</dt>
                <dd class="col-sm-8" id="mov-tipo">—</dd>
                <dt class="col-sm-4 info-label">Fecha</dt>
                <dd class="col-sm-8" id="mov-fecha">—</dd>
                <dt class="col-sm-4 info-label">Insumo</dt>
                <dd class="col-sm-8" id="mov-insumo">—</dd>
                <dt class="col-sm-4 info-label">Cantidad</dt>
                <dd class="col-sm-8" id="mov-cantidad">—</dd>
                <dt class="col-sm-4 info-label">Usuario</dt>
                <dd class="col-sm-8" id="mov-usuario">—</dd>
                <dt class="col-sm-4 info-label">Usuario destino</dt>
                <dd class="col-sm-8" id="mov-usuario-destino">—</dd>
                <dt class="col-sm-4 info-label">Observación</dt>
                <dd class="col-sm-8" id="mov-observacion">—</dd>
            </dl>
            <div class="mt-3">
                <p class="mb-1 text-muted">Token del movimiento: <code id="mov-token">—</code></p>
                <p class="mb-1 text-muted">URL de consulta: <code id="mov-consulta-url">—</code></p>
            </div>
            <div id="mov-qr-section" class="text-center mt-4 d-none">
                <img id="mov-qr-img" src="" alt="Código QR del movimiento" class="img-fluid mb-2">
                <p class="small"><a id="mov-qr-link" href="#" target="_blank" rel="noopener">Descargar código QR</a></p>
            </div>
        </div>
    </div>

    <div class="text-center mt-4">
        <a class="btn btn-outline-secondary" href="<?= $baseUrl ? $baseUrl : '' ?>/index.php">Ir al inicio</a>
    </div>
</div>

<script>
(function () {
    const baseUrl = <?= json_encode($baseUrl); ?>;
    const tokenPreset = <?= json_encode($tokenPreset); ?>;
    const idPreset = <?= json_encode($idPreset); ?>;

    const statusEl = document.getElementById('mov-status');
    const detalleEl = document.getElementById('mov-detalle');
    const idEl = document.getElementById('mov-id');
    const tipoEl = document.getElementById('mov-tipo');
    const fechaEl = document.getElementById('mov-fecha');
    const insumoEl = document.getElementById('mov-insumo');
    const cantidadEl = document.getElementById('mov-cantidad');
    const usuarioEl = document.getElementById('mov-usuario');
    const usuarioDestinoEl = document.getElementById('mov-usuario-destino');
    const observacionEl = document.getElementById('mov-observacion');
    const tokenEl = document.getElementById('mov-token');
    const urlEl = document.getElementById('mov-consulta-url');
    const qrSection = document.getElementById('mov-qr-section');
    const qrImg = document.getElementById('mov-qr-img');
    const qrLink = document.getElementById('mov-qr-link');

    function limpiar() {
        detalleEl.classList.add('d-none');
        if (qrSection) {
            qrSection.classList.add('d-none');
        }
        if (qrImg) {
            qrImg.src = '';
        }
        if (qrLink) {
            qrLink.href = '#';
        }
    }

    function formatearNumero(valor) {
        if (valor === null || valor === undefined) {
            return null;
        }
        const numero = Number(valor);
        if (!Number.isFinite(numero)) {
            return String(valor);
        }
        return numero.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    function normalizarRuta(ruta) {
        if (!ruta) {
            return '';
        }
        if (/^https?:/i.test(ruta)) {
            return ruta;
        }
        let sanitized = String(ruta).replace(/^\/+/, '');
        const prefix = baseUrl ? baseUrl : '';
        return prefix + '/' + sanitized;
    }

    const params = new URLSearchParams(window.location.search);
    const token = params.get('token') || tokenPreset || '';
    const id = params.get('id') || (idPreset ? String(idPreset) : '');

    if (!token && !id) {
        statusEl.classList.remove('alert-info');
        statusEl.classList.add('alert-warning');
        statusEl.textContent = 'Proporciona un token o un identificador de movimiento para consultar la información.';
        limpiar();
        return;
    }

    const apiBase = (baseUrl ? baseUrl : '') + '/api/insumos/consultar_movimiento_insumo.php';
    const query = token ? ('?token=' + encodeURIComponent(token)) : ('?id=' + encodeURIComponent(id));
    const consultaUrl = apiBase + query;

    fetch(consultaUrl, { credentials: 'same-origin' })
        .then(function (response) {
            if (!response.ok) {
                throw new Error('HTTP ' + response.status);
            }
            return response.json();
        })
        .then(function (payload) {
            if (!payload || payload.success !== true || !payload.resultado) {
                throw new Error(payload && payload.mensaje ? payload.mensaje : 'Sin información');
            }
            const data = payload.resultado;
            statusEl.classList.remove('alert-info');
            statusEl.classList.remove('alert-danger');
            statusEl.classList.add('alert-success');
            statusEl.textContent = 'Movimiento localizado correctamente.';

            const tipoLegible = data.tipo_descripcion || data.tipo || '—';
            if (idEl) {
                idEl.textContent = data.id != null ? String(data.id) : '—';
            }
            if (tipoEl) {
                tipoEl.textContent = tipoLegible;
            }
            if (fechaEl) {
                fechaEl.textContent = data.fecha ? String(data.fecha) : '—';
            }
            if (insumoEl) {
                const nombre = data.insumo_nombre ? String(data.insumo_nombre) : '—';
                insumoEl.textContent = nombre;
            }
            if (cantidadEl) {
                let cantidadTexto = '—';
                const cantidad = formatearNumero(data.cantidad);
                if (cantidad !== null) {
                    cantidadTexto = cantidad;
                    if (data.insumo_unidad) {
                        cantidadTexto += ' ' + data.insumo_unidad;
                    }
                }
                cantidadEl.textContent = cantidadTexto;
            }
            if (usuarioEl) {
                const nombre = data.usuario_nombre ? String(data.usuario_nombre) : '—';
                usuarioEl.textContent = nombre;
            }
            if (usuarioDestinoEl) {
                const nombre = data.usuario_destino_nombre ? String(data.usuario_destino_nombre) : '—';
                usuarioDestinoEl.textContent = nombre;
            }
            if (observacionEl) {
                observacionEl.textContent = data.observacion ? String(data.observacion) : '—';
            }
            if (tokenEl) {
                tokenEl.textContent = data.qr_token ? String(data.qr_token) : '—';
            }
            if (urlEl) {
                urlEl.textContent = data.qr_consulta_url ? String(data.qr_consulta_url) : (window.location.href);
            }

            if (qrSection && (data.qr_imagen || data.qr_consulta_url)) {
                const ruta = normalizarRuta(data.qr_imagen);
                if (ruta) {
                    qrImg.src = ruta;
                    qrLink.href = ruta;
                    qrSection.classList.remove('d-none');
                } else {
                    qrImg.src = '';
                    qrLink.href = '#';
                    qrSection.classList.add('d-none');
                }
            }

            detalleEl.classList.remove('d-none');
        })
        .catch(function (error) {
            statusEl.classList.remove('alert-info');
            statusEl.classList.add('alert-danger');
            statusEl.textContent = 'No fue posible obtener la información del movimiento: ' + error.message;
            limpiar();
        });
})();
</script>
</body>
</html>
