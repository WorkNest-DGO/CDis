<?php 
require __DIR__ . '/../../vendor/autoload.php';

use Mike42\Escpos\Printer;
use Mike42\Escpos\PrintConnectors\FilePrintConnector;
use Mike42\Escpos\EscposImage;
use Mike42\Escpos\GdEscposImage;
use Mike42\Escpos\PrintConnectors\WindowsPrintConnector;
//$connector = new WindowsPrintConnector("smb://ip_maquina/nombre_impresora");
$connector = new WindowsPrintConnector("smb://FUED/80");

$printer = new Printer($connector);

//$printer = new Printer($connector,$profile);
$printer -> initialize();

$qrCode= $_GET['qrName'];
	
$filename="../../archivos/qr/18362aae1efb507ecc36dda10b8975a0.png";
$filename=$qrCode;
if (!file_exists($filename)|| !is_readable($filename) ) {
            throw new Exception("File '$filename' does not exist, or is not readable.");
        }
	$qrCode = EscposImage::load($filename, true);
	$printer -> bitImage($qrCode);
	$printer -> feed();


$printer ->cut();
$printer ->close();
echo "enviado";

 ?>
