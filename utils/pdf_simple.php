<?php
function pdf_simple_escape($text) {
    if (!is_string($text)) {
        $text = strval($text);
    }
    // Convertir a Windows-1252 (compatible con Helvetica Type1) para acentos correctos
    $converted = @iconv('UTF-8', 'Windows-1252//TRANSLIT', $text);
    if ($converted === false) {
        // Fallback a utf8_decode (convierte UTF-8 -> ISO-8859-1)
        $converted = function_exists('utf8_decode') ? utf8_decode($text) : $text;
    }
    // Escapar caracteres especiales de cadenas PDF
    return str_replace(['\\', '(', ')'], ['\\\\', '\\(', '\\)'], $converted);
}

function generar_pdf_simple($archivo, $titulo, array $lineas) {
    $y = 760;
    $contenido = "BT\n/F1 16 Tf\n50 $y Td\n(" . pdf_simple_escape($titulo) . ") Tj\nET\n";
    $y -= 30;
    foreach ($lineas as $l) {
        $l = pdf_simple_escape($l);
        $contenido .= "BT\n/F1 12 Tf\n50 $y Td\n($l) Tj\nET\n";
        $y -= 14;
    }

    $objs = [];
    $objs[] = "<< /Type /Catalog /Pages 2 0 R >>";
    $objs[] = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>";
    $objs[] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>";
    $objs[] = "<< /Length " . strlen($contenido) . " >>\nstream\n" . $contenido . "endstream";
    $objs[] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>";

    $pdf = "%PDF-1.4\n";
    $pos = [];
    foreach ($objs as $i => $o) {
        $pos[$i + 1] = strlen($pdf);
        $pdf .= ($i + 1) . " 0 obj\n" . $o . "\nendobj\n";
    }
    $xref = strlen($pdf);
    $pdf .= "xref\n0 " . (count($objs) + 1) . "\n0000000000 65535 f \n";
    for ($i = 1; $i <= count($objs); $i++) {
        $pdf .= sprintf("%010d 00000 n \n", $pos[$i]);
    }
    $pdf .= "trailer\n<< /Size " . (count($objs) + 1) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF";

    // Ensure destination directory exists before saving the PDF
    $directorio = dirname($archivo);
    if (!file_exists($directorio)) {
        mkdir($directorio, 0777, true);
    }

    file_put_contents($archivo, $pdf);
}


function generar_pdf_con_imagen($archivo, $titulo, array $lineas, $imagen, $x = 150, $y_img = 10, $w = 40, $h = 40) {
    $y = 760;
    $contenido = "BT\n/F1 16 Tf\n50 $y Td\n(" . pdf_simple_escape($titulo) . ") Tj\nET\n";
    $y -= 30;
    foreach ($lineas as $l) {
        $l = pdf_simple_escape($l);
        $contenido .= "BT\n/F1 12 Tf\n50 $y Td\n($l) Tj\nET\n";
        $y -= 14;
    }
    if (file_exists($imagen)) {
        $contenido .= "q\n$w 0 0 $h $x $y_img cm\n/Im1 Do\nQ\n";
    }

    $objs = [];
    $objs[] = "<< /Type /Catalog /Pages 2 0 R >>";
    $objs[] = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>";
    $resources = "<< /Font << /F1 5 0 R >>";
    if (file_exists($imagen)) {
        $resources .= " /XObject << /Im1 6 0 R >>";
    }
    $resources .= " >>";
    $objs[] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources $resources >>";
    $objs[] = "<< /Length " . strlen($contenido) . " >>\nstream\n" . $contenido . "endstream";
    $objs[] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>";
    if (file_exists($imagen)) {
        list($imgW, $imgH) = getimagesize($imagen);
        $img = imagecreatefrompng($imagen);
        ob_start();
        imagejpeg($img);
        $imgData = ob_get_clean();
        imagedestroy($img);
        $objs[] = "<< /Type /XObject /Subtype /Image /Width $imgW /Height $imgH /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length " . strlen($imgData) . " >>\nstream\n" . $imgData . "endstream";
    }

    $pdf = "%PDF-1.4\n";
    $pos = [];
    foreach ($objs as $i => $o) {
        $pos[$i + 1] = strlen($pdf);
        $pdf .= ($i + 1) . " 0 obj\n" . $o . "\nendobj\n";
    }
    $xref = strlen($pdf);
    $pdf .= "xref\n0 " . (count($objs) + 1) . "\n0000000000 65535 f \n";
    for ($i = 1; $i <= count($objs); $i++) {
        $pdf .= sprintf("%010d 00000 n \n", $pos[$i]);
    }
    $pdf .= "trailer\n<< /Size " . (count($objs) + 1) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF";
    // Ensure destination directory exists before saving the PDF
    $directorio = dirname($archivo);
    if (!file_exists($directorio)) {
        mkdir($directorio, 0777, true);
    }
    file_put_contents($archivo, $pdf);
}


/**
 * Genera un PDF para envío de insumos con:
 * - Título
 * - Encabezado con líneas (fecha, entregado por)
 * - Código QR debajo del título (alineado a la derecha por defecto)
 * - Detalle de insumos en dos columnas: izquierda (insumo y cantidad solicitada)
 *   y derecha (tabla ligera de lotes consumidos)
 *
 * Parámetros:
 *  - $archivo: ruta destino del PDF
 *  - $titulo: título del documento
 *  - $headerLines: array de strings para el encabezado (bajo el título)
 *  - $imagen: ruta al PNG con el QR
 *  - $items: array de items donde cada item es [
 *        'left' => 'Texto izquierda',
 *        'right' => [ 'Línea 1', 'Línea 2', ... ]
 *    ]
 */
function generar_pdf_envio_qr_detallado($archivo, $titulo, array $headerLines, $imagen, array $items) {
    // Configuración de página en puntos (Letter: 612x792)
    $pageW = 612; $pageH = 792;
    $marginL = 50; $marginR = 50; $marginB = 40;
    $leftX = $marginL;                      // Columna izquierda
    $rightX = $pageW - $marginR - 220;      // Columna derecha (~40% ancho)
    $lineHeight = 14;

    // Posición y tamaño del QR (debajo del título, alineado a la derecha)
    $qrW = 120; $qrH = 120;                 // ~42mm aprox
    $qrX = $pageW - $marginR - $qrW;        // derecha
    $qrY = 600;                             // bajo el título

    // Construcción del contenido (una sola página)
    $yTitle = 760;
    $contenido = "BT\n/F1 16 Tf\n{$leftX} $yTitle Td\n(" . pdf_simple_escape($titulo) . ") Tj\nET\n";

    // Encabezado bajo el título
    $y = $yTitle - 24;
    foreach ($headerLines as $l) {
        $l = pdf_simple_escape($l);
        $contenido .= "BT\n/F1 12 Tf\n{$leftX} $y Td\n($l) Tj\nET\n";
        $y -= $lineHeight;
    }

    // Incrustar la imagen QR, si existe
    if (file_exists($imagen)) {
        $contenido .= "q\n$qrW 0 0 $qrH $qrX $qrY cm\n/Im1 Do\nQ\n";
    }

    // Punto de inicio para el detalle: bajo el QR
    $yDetail = $qrY - 20;

    // Render de items (dos columnas) con cabeceras de grupo opcionales
    foreach ($items as $it) {
        // Cabecera de grupo: texto centrado y en mayor tamaño
        if (isset($it['section']) && is_string($it['section']) && $it['section'] !== '') {
            if ($yDetail < $marginB + ($lineHeight * 3)) {
                $yDetail = $marginB + ($lineHeight * 3);
            }
            $secText = (string)$it['section'];
            $secFont = 14;
            $approxW = strlen($secText) * ($secFont * 0.6);
            $secX = (int)max($marginL, min($pageW - $marginR - 10, ($pageW - $approxW) / 2));
            $contenido .= "BT\n/F1 $secFont Tf\n{$secX} {$yDetail} Td\n(" . pdf_simple_escape($secText) . ") Tj\nET\n";
            $yDetail -= ($lineHeight + 8);
            continue;
        }
        $leftText = isset($it['left']) ? (string)$it['left'] : '';
        $rightLines = isset($it['right']) && is_array($it['right']) ? $it['right'] : [];

        // Si nos acercamos al borde inferior, no hay paginado: cortar a margen
        if ($yDetail < $marginB + ($lineHeight * 4)) {
            $yDetail = $marginB + ($lineHeight * 4);
        }

        // Izquierda (una línea)
        $contenido .= "BT\n/F1 12 Tf\n{$leftX} $yDetail Td\n(" . pdf_simple_escape($leftText) . ") Tj\nET\n";

        // Derecha (varias líneas)
        $yRight = $yDetail;
        foreach ($rightLines as $rl) {
            $contenido .= "BT\n/F1 11 Tf\n{$rightX} $yRight Td\n(" . pdf_simple_escape($rl) . ") Tj\nET\n";
            $yRight -= $lineHeight;
        }

        // Altura consumida por el bloque
        $blockLines = max(1, count($rightLines));
        $blockHeight = $blockLines * $lineHeight;
        $yDetail -= max($lineHeight, $blockHeight) + 8; // separador
    }

    // Objetos PDF
    $objs = [];
    $objs[] = "<< /Type /Catalog /Pages 2 0 R >>"; // 1
    $objs[] = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"; // 2

    // Recursos
    $resources = "<< /Font << /F1 5 0 R >>";
    $hasImg = file_exists($imagen);
    if ($hasImg) {
        $resources .= " /XObject << /Im1 6 0 R >>";
    }
    $resources .= " >>";

    // Página
    $objs[] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageW $pageH] /Contents 4 0 R /Resources $resources >>"; // 3

    // Contenido
    $objs[] = "<< /Length " . strlen($contenido) . " >>\nstream\n" . $contenido . "endstream"; // 4

    // Fuente
    $objs[] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"; // 5

    // Imagen (si hay)
    if ($hasImg) {
        list($imgW, $imgH) = getimagesize($imagen);
        $img = imagecreatefrompng($imagen);
        ob_start();
        imagejpeg($img);
        $imgData = ob_get_clean();
        imagedestroy($img);
        $objs[] = "<< /Type /XObject /Subtype /Image /Width $imgW /Height $imgH /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length " . strlen($imgData) . " >>\nstream\n" . $imgData . "endstream"; // 6
    }

    // Ensamblado PDF
    $pdf = "%PDF-1.4\n";
    $pos = [];
    foreach ($objs as $i => $o) {
        $pos[$i + 1] = strlen($pdf);
        $pdf .= ($i + 1) . " 0 obj\n" . $o . "\nendobj\n";
    }
    $xref = strlen($pdf);
    $pdf .= "xref\n0 " . (count($objs) + 1) . "\n0000000000 65535 f \n";
    for ($i = 1; $i <= count($objs); $i++) {
        $pdf .= sprintf("%010d 00000 n \n", $pos[$i]);
    }
    $pdf .= "trailer\n<< /Size " . (count($objs) + 1) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF";

    // Asegurar directorio
    $directorio = dirname($archivo);
    if (!file_exists($directorio)) {
        mkdir($directorio, 0777, true);
    }
    file_put_contents($archivo, $pdf);
}
?>

