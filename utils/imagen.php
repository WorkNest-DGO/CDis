<?php



function procesarImagenInsumo(array $file, string $dir): ?string


{


    if (!isset($file['tmp_name']) || $file['error'] !== UPLOAD_ERR_OK) {


        return null;


    }


    if (!is_dir($dir)) {


        mkdir($dir, 0777, true);


    }


    $info = getimagesize($file['tmp_name']);


    if (!$info) {


        return null;


    }


    $mime = $info['mime'];


    switch ($mime) {


        case 'image/jpeg':


        case 'image/pjpeg':


            $src = imagecreatefromjpeg($file['tmp_name']);


            break;


        case 'image/png':


            $src = imagecreatefrompng($file['tmp_name']);


            break;


        default:


            return null;


    }


    if (!$src) {


        return null;


    }


    $width = imagesx($src);


    $height = imagesy($src);


    $size = 768;


    $dst = imagecreatetruecolor($size, $size);


    $white = imagecolorallocate($dst, 255, 255, 255);


    imagefill($dst, 0, 0, $white);


    $ratio = min($size / $width, $size / $height);


    $new_w = (int)($width * $ratio);


    $new_h = (int)($height * $ratio);


    $dst_x = (int)(($size - $new_w) / 2);


    $dst_y = (int)(($size - $new_h) / 2);


    imagecopyresampled($dst, $src, $dst_x, $dst_y, 0, 0, $new_w, $new_h, $width, $height);


    $nombre = uniqid('ins_');


    $archivoJpg = rtrim($dir, '/') . '/' . $nombre . '.jpg';


    if (@imagejpeg($dst, $archivoJpg, 85)) {


        imagedestroy($src);


        imagedestroy($dst);


        return $nombre . '.jpg';


    }


    $archivoPng = rtrim($dir, '/') . '/' . $nombre . '.png';


    if (@imagepng($dst, $archivoPng)) {


        imagedestroy($src);


        imagedestroy($dst);


        return $nombre . '.png';


    }


    imagedestroy($src);


    imagedestroy($dst);


    return null;


}

function procesarImagenProducto(array $file, string $dir): ?string
{
    if (!isset($file['tmp_name']) || $file['error'] !== UPLOAD_ERR_OK) {
        return null;
    }

    if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
    }

    $info = getimagesize($file['tmp_name']);
    if (!$info) {
        return null;
    }

    $mime = $info['mime'];
    switch ($mime) {
        case 'image/jpeg':
        case 'image/pjpeg':
            $src = imagecreatefromjpeg($file['tmp_name']);
            break;
        case 'image/png':
            $src = imagecreatefrompng($file['tmp_name']);
            break;
        default:
            return null;
    }

    if (!$src) {
        return null;
    }

    $width = imagesx($src);
    $height = imagesy($src);
    $size = 768;

    $dst = imagecreatetruecolor($size, $size);
    $white = imagecolorallocate($dst, 255, 255, 255);
    imagefill($dst, 0, 0, $white);

    $ratio = min($size / $width, $size / $height);
    $new_w = (int)($width * $ratio);
    $new_h = (int)($height * $ratio);
    $dst_x = (int)(($size - $new_w) / 2);
    $dst_y = (int)(($size - $new_h) / 2);

    imagecopyresampled($dst, $src, $dst_x, $dst_y, 0, 0, $new_w, $new_h, $width, $height);

    $nombre = uniqid('prod_');

    $archivoJpg = rtrim($dir, '/') . '/' . $nombre . '.jpg';
    if (@imagejpeg($dst, $archivoJpg, 85)) {
        imagedestroy($src);
        imagedestroy($dst);
        return $nombre . '.jpg';
    }

    $archivoPng = rtrim($dir, '/') . '/' . $nombre . '.png';
    if (@imagepng($dst, $archivoPng)) {
        imagedestroy($src);
        imagedestroy($dst);
        return $nombre . '.png';
    }

    imagedestroy($src);
    imagedestroy($dst);
    return null;
}


?>