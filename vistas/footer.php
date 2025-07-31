<?php if (!isset($base_url)) { $base_url = '/CDI'; } ?>
        <!-- Footer Start -->
 <hr style="border-color:#fff;">     
<div class="footer">
    <div class="container">
        <div class="row">
            <!-- Contacto -->
            <div class="col-lg-7">
                <div class="row">
                    <div class="col-md-6">
                        <div class="footer-contact">
                            <h2>Contacto interno</h2>
                            <p><i class="fa fa-map-marker-alt"></i>Av. Principal #123, Ciudad, México</p>
                            <p><i class="fa fa-phone-alt"></i>+52 55 1234 5678</p>
                            <p><i class="fa fa-envelope"></i>soporte@sushitokyo.com</p>
                            <div class="footer-social">
                                <a href="#"><i class="fab fa-whatsapp"></i></a>
                                <a href="#"><i class="fab fa-telegram"></i></a>
                                <a href="#"><i class="fab fa-slack"></i></a>
                            </div>
                        </div>
                    </div>

                    <!-- Enlaces rápidos -->
                    <div class="col-md-6">
                        <div class="footer-link">
                            <h2>Accesos directos</h2>
                            <a href="index.php">Inicio</a>
                            <a href="ventas/ventas.php">Cobros</a>
                            <a href="corte_caja/corte.php">Cortes de Caja</a>
                            <a href="mesas/mesas.php">Mesas</a>
                            <a href="ayuda.php">Ayuda / Manual</a>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Información institucional -->
            <div class="col-lg-5">
                <div class="footer-newsletter">
                    <h2>Tokyo Sushi</h2>
                    <p>
                        Sistema de control de ingresos y cobros diseñado para nuestro equipo. Optimiza tu jornada, asegura cada cuenta y mantén el flujo operativo en orden.
                    </p>
                    <p class="mt-3"><strong>Versión:</strong> 1.0.0 | <strong>Área TI</strong></p>
                </div>
            </div>
        </div>
    </div>

    <!-- Créditos -->
    <div class="copyright">
        <div class="container">
            <p>Sistema de Cobro &copy; <?php echo date('Y'); ?> <a href="#">Tokyo Sushi</a>, Todos los derechos reservados.</p>
            <p>Desarrollado por el área de sistemas</p>
        </div>
    </div>
</div>
        <!-- Footer End -->

        <a href="#" class="back-to-top"><i class="fa fa-chevron-up"></i></a>

        <!-- JavaScript Libraries -->
        <script src="<?php echo $base_url; ?>/utils/js/jquery-3.7.js"></script>
        <script src="<?php echo $base_url; ?>/utils/js/bootstrap.min.js"></script>
        <script src="<?php echo $base_url; ?>/utils/lib/easing/easing.min.js"></script>
        <script src="<?php echo $base_url; ?>/utils/lib/owlcarousel/owl.carousel.min.js"></script>
        <script src="<?php echo $base_url; ?>/utils/lib/tempusdominus/js/moment.min.js"></script>
        <script src="<?php echo $base_url; ?>/utils/lib/tempusdominus/js/moment-timezone.min.js"></script>
        <script src="<?php echo $base_url; ?>/utils/lib/tempusdominus/js/tempusdominus-bootstrap-4.min.js"></script>
        
        <!-- Contact Javascript File -->
        <script src="<?php echo $base_url; ?>/utils/mail/jqBootstrapValidation.min.js"></script>
        <script src="<?php echo $base_url; ?>/utils/mail/contact.js"></script>

        <!-- Template Javascript -->
        <script src="<?php echo $base_url; ?>/utils/js/main.js"></script>
