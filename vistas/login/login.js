document.addEventListener('DOMContentLoaded', function () {
  const formLogin = document.getElementById("sign-in");

  const slideBoard = document.querySelector(".sliding-board");
  const singUp = document.querySelector(".singUp");
  const singIn = document.querySelector(".singIn");

  const slidingState = document.querySelector(".main");

  singIn.addEventListener("click", function () {
    slideBoard.classList.add("sliding");
    slidingState.classList.replace("sing-up", "sing-in");
  });

  singUp.addEventListener("click", function () {
    slideBoard.classList.remove("sliding");
    slidingState.classList.replace("sing-in", "sing-up");
  });

  formLogin?.addEventListener("submit", function (e) {
    e.preventDefault();
    const usuario = document.getElementById("usuario").value.trim();
    const contrasena = document.getElementById("contrasena").value.trim();

    fetch("auth/login.php", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ usuario, contrasena })
    })
      .then(response => response.json())
      .then(data => {
        console.log("Respuesta:", data);
        if (data.success) {
          window.location.href = "vistas/index.php";
        } else {
          mensaje.textContent = data.mensaje || "Credenciales incorrectas";
        }
      })
      .catch(error => {
        console.error("Error en login:", error);
        mensaje.textContent = "Error en la solicitud";
      });
  });

});
