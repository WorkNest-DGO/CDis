<?php 
require_once __DIR__ . '/../../config/db.php';
require __DIR__ . '/../../vendor/autoload.php';

use Mike42\Escpos\Printer;
use Mike42\Escpos\PrintConnectors\FilePrintConnector;
use Mike42\Escpos\EscposImage;
use Mike42\Escpos\GdEscposImage;
use Mike42\Escpos\PrintConnectors\WindowsPrintConnector;
//$connector = new WindowsPrintConnector("smb://ip_maquina/nombre_impresora");
// Resolver impresora (POST 'printer_ip' o primera en BD)
$printerIp = isset($_POST['printer_ip']) ? trim((string)$_POST['printer_ip']) : '';
if ($printerIp === '' && isset($_GET['printer_ip'])) {
    $printerIp = trim((string)$_GET['printer_ip']);
}
if ($printerIp === '') {
    $sql = "SELECT ip FROM impresoras ORDER BY print_id ASC LIMIT 1";
    if ($st = $conn->prepare($sql)) {
        $st->execute();
        $st->bind_result($ip);
        if ($st->fetch() && $ip) {
            $printerIp = $ip;
        }
        $st->close();
    }
    if ($printerIp === '') {
        http_response_code(400);
        echo 'Error: No hay impresoras configuradas en BD.';
        exit;
    }
}
if (!preg_match('#^(smb://|\\\\)#i', $printerIp)) {
    http_response_code(400);
    echo 'Error: Impresora inválida: ' . $printerIp;
    exit;
}
$connector = new WindowsPrintConnector($printerIp);

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
