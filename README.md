<div align="center">
  <img src="assets/Leonida X.png" alt="Leonida X" width="900">
</div>

---

## ¿Cómo funciona?

Leonida X no recompila el juego ni convierte su código a una aplicación de Windows. Ejecuta el código x86-64 original dentro de un proceso de Windows y proporciona las partes de la plataforma Xbox Series que ese código espera encontrar. Por eso se describe con más precisión como una capa de compatibilidad que como un port tradicional.

Al iniciar, el loader prepara y carga el ejecutable del juego, resuelve sus dependencias y conecta las funciones que necesita. Cuando el juego solicita servicios propios de la consola —por ejemplo, archivos, memoria, audio, controles o guardados— Leonida X los implementa o los adapta a los servicios disponibles en Windows. Los datos del juego, las partidas y los archivos generados permanecen en el equipo del usuario; el repositorio no incluye el juego.

La parte gráfica también necesita una adaptación. Leonida X representa los objetos y comandos de la interfaz gráfica de Xbox mediante Direct3D 12 en Windows. Cuando el juego crea una canalización gráfica, el proyecto traduce los shaders de la consola al formato que usa el PC. Esa traducción se guarda en una caché local para reutilizarla; después de ciertos cambios, la primera ejecución puede tener tirones mientras se reconstruye.

En resumen, el juego aporta su código y sus recursos; Leonida X aporta la carga, los servicios de plataforma y la traducción gráfica necesarios para ejecutarlo en Windows. El proyecto está en desarrollo y todavía tiene limitaciones importantes de rendimiento y renderizado, así que la compatibilidad no significa que la experiencia ya sea equivalente a la de una consola.

## Créditos

- Leonida: gracias por existir, aunque fue por cierto tiempo, fuiste un pilar muy grande para poder crear este proyecto, muchas gracias :)

Grand Theft Auto and all related names are trademarks of their owners. This project is not affiliated with or endorsed by them.

## Licencia

GPL-3.0-or-later, like victory-gta6 and VIctory. See [LICENSE](LICENSE).
