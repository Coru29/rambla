<p align="center">
  <img src="Packaging/AppIcon-preview.png" width="160" alt="Ícono de Rambla: atardecer en la rambla de Montevideo con una fila de ventanas">
</p>

<h1 align="center">Rambla</h1>

<p align="center">
  Un <b>gestor de ventanas con scroll horizontal</b> para macOS, gratis y open source.<br>
  Tus ventanas en fila a lo largo de un paseo horizontal sin fin, como la rambla de Montevideo.
</p>

<p align="center"><a href="https://rambla-mac.vercel.app"><b>rambla-mac.vercel.app</b></a> · <a href="docs/MANUAL.md"><b>Manual de uso</b></a> · <a href="README.md">Read in English</a></p>

<p align="center">
  <a href="https://github.com/Coru29/rambla/actions/workflows/ci.yml"><img src="https://github.com/Coru29/rambla/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-lightgrey" alt="macOS 14+">
</p>

---

Cada ventana es una columna de una tira horizontal que sigue más allá de los bordes de la pantalla. Abrir una ventana agrega una columna al lado de la que estás usando **sin achicar las demás**, y la tira se desliza para mostrarte lo que enfocás. Es la idea de [niri](https://github.com/YaLTeR/niri) y PaperWM, hecha como una app nativa y liviana de Mac, inspirada en [ChainYourMac](https://chainyourmac.com), que es paga.

## Qué hace

- **Una tira por pantalla y por escritorio**, con animaciones de resorte y su propio foco y scroll.
- **Las ventanas nuevas se abren al lado de la enfocada** y la tira se desliza hasta la ventana enfocada. Centrado: nunca, solo si no entra o siempre.
- **Anchos de columna**: prefijados (25/33/50/66/75 %), ancho completo, más ancha o más angosta, centrar y **fijar una columna** al borde izquierdo o derecho.
- **Pilas y pestañas**: varias ventanas en una columna, apiladas o en pestañas con una barra en la que se puede hacer click.
- **Trackpad**: deslizar con tres o cuatro dedos mueve la tira; un deslizamiento corto y rápido pasa a la columna siguiente. Hacia arriba, ancho completo; hacia abajo, vuelve.
- **Barra indicadora**: aparece al navegar con un ícono por columna; click para saltar, arrastrar para reordenar.
- **Mouse**: con ⌃⌘ apretado, la ruedita recorre las columnas; arrastrá una ventana sobre otra columna para reordenar, o cambiale el tamaño para fijar el ancho de su columna.
- Opcionales: **borde en la ventana enfocada**, **atenuar las inactivas**, el foco sigue al mouse y el mouse sigue al foco.
- **Reglas por app**: mosaico o flotante, ancho inicial y dónde se abren. Además, se puede activar o desactivar por pantalla.
- **Recuerda el layout** al reiniciar y puede arrancar con la Mac.
- **Convive con [Rectangle](https://rectangleapp.com)**: los atajos usan ⌃⌘, así que no chocan con los ⌃⌥ del set normal de Rectangle (con su set Spectacle chocan un par, y Rambla te avisa). Si Rectangle (u otra app) mueve una ventana, esa ventana sale de la tira y queda donde la pusieron. La página Mac de la configuración avisa si algún atajo choca con tu Rectangle.
- **Automatización**: enlaces `rambla://`, comando de terminal `rambla` y exportación de scripts para Raycast.
- **Español e inglés**: la interfaz sigue el idioma de tu Mac.
- **Liviana**: Swift nativo (AppKit, con la configuración en SwiftUI), sin Electron y sin polling. En reposo usa cerca de 0 % de CPU y ~12 MB de memoria.

## Privacidad

Rambla no recolecta datos y no tiene telemetría. No lee el contenido de las ventanas ni graba la pantalla. Su única conexión es una consulta a GitHub para ver si hay una versión nueva, al arrancar y una vez por día, que podés apagar en Configuración → General. Más detalles en [SECURITY.md](SECURITY.md).

## Requisitos

macOS 14 Sonoma o posterior, en Apple silicon, y el permiso de Accesibilidad.

## Instalación

1. Bajá **[Rambla.dmg](https://github.com/Coru29/rambla/releases/latest/download/Rambla.dmg)** de [Releases](https://github.com/Coru29/rambla/releases) (o compilalo, más abajo) y arrastrá **Rambla** a Aplicaciones.
2. Abrila y dale permiso en **Ajustes del Sistema → Privacidad y seguridad → Accesibilidad**.
3. Rambla no está notarizada por Apple. Si macOS dice que no puede verificar al desarrollador, hacé click derecho en la app → **Abrir**, o corré `xattr -dr com.apple.quarantine /Applications/Rambla.app`.

### Actualizaciones

Rambla revisa GitHub al arrancar y una vez por día. Cuando sale una versión nueva, su menú muestra **Actualizar a Rambla X…**: descarga el release, verifica que esté firmado con el mismo certificado, se reemplaza y se reinicia. El permiso de Accesibilidad se mantiene.

## Atajos por defecto

Todos se pueden cambiar en **Configuración → Atajos**.

| Atajo | Acción |
|---|---|
| ⌃⌘← / ⌃⌘→ (o ⌃⌘H / ⌃⌘L) | Enfocar la columna de la izquierda / derecha |
| ⌃⌘↑ / ⌃⌘↓ (o ⌃⌘K / ⌃⌘J) | Enfocar la ventana de arriba / abajo en una pila |
| ⌃⌘A / ⌃⌘E | Primera / última columna |
| ⌃⌘1 … ⌃⌘9 | Ir a la columna N |
| ⌃⌘⇧ + flechas (o H J K L) | Mover la columna o la ventana dentro de su pila |
| ⌃⌘N | Mandar la ventana a la siguiente pantalla |
| ⌃⌘R | Rotar entre los anchos prefijados |
| ⌃⌘M | Ancho completo (repetir para volver) |
| ⌃⌘C | Centrar la columna |
| ⌃⌘= / ⌃⌘- | Más ancha / más angosta |
| ⌃⌘⇧= / ⌃⌘⇧- | Más alta / más baja (en una pila) |
| ⌃⌘0 | Igualar alturas |
| ⌃⌘P / ⌃⌘⇧P | Fijar la columna al borde izquierdo / derecho |
| ⌃⌘[ / ⌃⌘] | Apilar en la columna de la izquierda / derecha |
| ⌃⌘⇧[ / ⌃⌘⇧] | Sacar de la pila hacia la izquierda / derecha |
| ⌃⌘⇧T | Alternar pila ⇄ pestañas |
| ⌃⌘T | Flotar / volver a la tira |

## Trackpad

macOS también recibe cada deslizamiento y Rambla no lo puede frenar. Y en **Ajustes del Sistema → Trackpad → Más gestos → Cambiar entre apps en pantalla completa**, la opción «3 dedos» deja activo también el de 4. Con el gesto de cuatro dedos (el que viene por defecto), tocá **«Apagarlo en macOS»** en **Configuración → Trackpad y mouse**: Rambla apaga solo el gesto de 4 dedos de macOS y el de 3 sigue cambiando de escritorio. La otra opción es elegir tres dedos en Rambla y poner el de macOS en «4 dedos». Rambla te avisa si chocan.

## Ajustes de macOS recomendados

Rambla los revisa en **Configuración → Mac**:

- **Las pantallas tienen Spaces separados**: activado (viene así).
- **Reorganizar Spaces automáticamente según el uso más reciente**: desactivado.
- **Stage Manager** y **arrastrar ventanas a los bordes para organizarlas**: desactivados.
- Con dos pantallas, lo mejor es poner la segunda **arriba o abajo** de la principal. Lado a lado también funciona, pero las ventanas solo pueden salir hasta la mitad hacia la otra pantalla antes de estacionarse.

## Automatización

```sh
open -g "rambla://focus-left"        # cualquier acción, ej. focus-3, cycle-width, toggle-pause
rambla focus-right                   # después de instalar el comando en Configuración → Automatización
rambla list                          # todas las acciones
```

En Configuración → Automatización también podés exportar un script de Raycast por acción.

## Compilar desde el código

Solo hacen falta las **Command Line Tools** de Xcode (Swift 6), no Xcode completo.

```sh
git clone https://github.com/Coru29/rambla && cd rambla
scripts/test.sh        # tests (Swift Testing)
scripts/build.sh       # build/Rambla.app
scripts/dmg.sh         # build/Rambla.dmg
scripts/install.sh     # copia a /Applications y la abre
scripts/e2e.sh         # pruebas en vivo con una app de prueba descartable (requiere el permiso de Accesibilidad)
```

La primera compilación crea una identidad de firma autofirmada local en `.signing/`, que nunca se sube al repo. Gracias a eso, macOS conserva el permiso de Accesibilidad entre compilaciones.

**Versiones y releases**: los commits siguen [Conventional Commits](https://www.conventionalcommits.org) y la versión sale de ellos (`feat` sube la menor, `fix` el parche y `!` la mayor). `scripts/release.sh` arma el DMG firmado, crea el tag y publica el release; las copias instaladas se actualizan solas en menos de un día. Más detalles en [CONTRIBUTING.md](CONTRIBUTING.md).

## Cómo funciona

- `RamblaCore` es una biblioteca Swift pura con el modelo (tiras y columnas), el motor de layout, las operaciones de la tira, las preferencias y las tablas de atajos. No usa AppKit y tiene tests unitarios.
- La app usa **un hilo por cada app gestionada** para las llamadas de Accesibilidad, así una app colgada nunca traba a las demás. Todo funciona por eventos (notificaciones de Accesibilidad y del sistema, atajos Carbon); los timers corren solo mientras hacen falta: una animación, la barra indicadora mientras apretás ⌃⌘, el chequeo del permiso hasta que lo das y la revisión diaria de actualizaciones.
- macOS devuelve a la pantalla las ventanas que quedan totalmente afuera. Por eso las ventanas fuera de la parte visible de la tira se **estacionan con 1 pt visible** en un borde. Al salir o pausar, todas vuelven a la pantalla.
- Las APIs privadas son las mínimas, las mismas que usan yabai y AeroSpace: IDs de ventana, Spaces y enfocar una ventana exacta. Se cargan en tiempo de ejecución, así que si falta un símbolo la app sigue funcionando en lugar de romperse. SIP queda activado.

## Créditos

Inspirada en [niri](https://github.com/YaLTeR/niri), [PaperWM](https://github.com/paperwm/PaperWM), [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon), [Paneru](https://github.com/karinushka/paneru) y [ChainYourMac](https://chainyourmac.com). Técnicas aprendidas de [yabai](https://github.com/koekeishiya/yabai), [AeroSpace](https://github.com/nikitabobko/AeroSpace) y [Rectangle](https://github.com/rxhanson/Rectangle).

## Licencia

[MIT](LICENSE)
