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

- **[victory-gta6](https://github.com/fxceless/victory-gta6)** by fxceless is the upstream project this repository continues, with its history kept.
- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its contributors is the base of the loader, runtime services, Direct3D 12 back end and shader recompiler.
- **[XCL](https://github.com/ivall/xcl)** by ivall and its contributors (GPL-2.0-only) was used as a reference for how the same game behaves under another layer. Fixes inspired by it were written anew in VIctory's code.
- The guard over every view of a memory page is code by **myokex** ([victory-amd](https://github.com/myokex/victory-amd), commit `c6dc4d8`), which adapts pull request #115 by Spexivus, its correction by joroyt and a part of VIctory #1122 by tightfall. The read-beside fix for kernel reads into title memory is by **Joshua Odom** (commit `10ea38e` of the same fork family).
- Logo: ["Grand Theft Auto VI" icon by SlyDevil](https://www.steamgriddb.com/icon/122618) on SteamGridDB.
- The victory-gta6 changes were developed with [Claude Code](https://claude.com/claude-code).

Grand Theft Auto and all related names are trademarks of their owners. This project is not affiliated with or endorsed by them.

## Licencia

GPL-3.0-or-later, like victory-gta6 and VIctory. See [LICENSE](LICENSE).
