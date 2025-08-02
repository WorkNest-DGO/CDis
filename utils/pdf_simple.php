<?php
function pdf_simple_escape($text) {
    return str_replace(['\\', '(', ')'], ['\\\\', '\\(', '\\)'], $text);
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
?>

