# Rambla — diseño

> El proyecto empezó como "Scroll" (nombre de la carpeta) y el 2026-10-21 pasó a llamarse **Rambla** al publicarse como open source.

Fecha: 2026-10-21 · Estado: aprobado por el usuario en el chat ("perfecto, tal cual, hacelo")

## Intención

El usuario quiere un clon gratis de [ChainYourMac](https://chainyourmac.com), un gestor de ventanas con scroll horizontal, para su Mac. Tiene que convivir con Rectangle, gastar lo mínimo de recursos, instalarse desde un DMG y configurarse por completo desde la interfaz. El usuario no quiere pagar USD 20 por algo que se puede construir.

## Objetivos

- Paridad funcional con ChainYourMac 2.3: lista de funciones en "Comportamiento".
- Convivencia con Rectangle, que el usuario tiene abierto y usa con sus atajos.
- Recursos mínimos: 0 % de CPU en reposo, todo por eventos y sin polling, y menos de ~40 MB de memoria con la configuración cerrada.
- Instalación por DMG, con un único permiso de Accesibilidad que sobrevive a las actualizaciones.

## No-objetivos

- Licencias, pagos, cuentas o telemetría.
- Auto-actualización (Sparkle). Las versiones nuevas se compilan localmente.
- Notarización o Developer ID.
- Intel: se compila solo arm64, porque un binario universal requiere Xcode.
- Animaciones a nivel compositor, que requieren desactivar SIP.

## Anti-objetivos (sería un fracaso aunque "funcione")

- Que se pelee con Rectangle, por ejemplo que una ventana vuelva sola a la tira después de que Rectangle la acomodó.
- Que deje ventanas perdidas o inaccesibles fuera de pantalla al salir, pausar o fallar.
- Que use CPU en reposo o haga polling.
- Que los atajos choquen con los de Rectangle del usuario o con atajos estándar de macOS.
- Que pida el permiso de Accesibilidad de nuevo en cada actualización.

## Entorno del usuario (verificado el 2026-10-21)

- MacBook Pro M5, macOS 26.6.2, pantalla integrada de 1512×982 pt. A veces conecta un monitor de 2560×1440.
- Rectangle está abierto con el set de atajos ⌃⌥ ("recomendado"), ⌃⌥⇧↑, ⌃⌥⌘←/→ para cambiar de pantalla y los personalizados ⌃⌥Z, ⌃⌥N y ⌃⌥B. Tiene las snap areas activadas y gap 5.
- Solo Command Line Tools (Swift 6.3.3), sin Xcode. Swift Testing está disponible y XCTest no.
- Trackpad: macOS usa el swipe horizontal de 3 y de 4 dedos para cambiar de escritorio (las dos claves en 2).
- "Las pantallas tienen Spaces separados": activado (default). "Reorganizar Spaces automáticamente": activado (default). Stage Manager y tiling por arrastre de macOS: apagados.
- Las APIs privadas que se usan funcionan en este macOS (probado): `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSManagedDisplayGetCurrentSpace`, `SLSCopySpacesForWindows`, `_SLPSSetFrontProcessWithOptions` y `SLPSPostEventRecordTo`.
- La firma con un certificado autofirmado en un keychain propio funciona sin prompts y da un requisito designado estable (`identifier … and certificate leaf = H"…"`).

## Comportamiento

### Modelo

- Cada par (pantalla, escritorio) tiene su propia **tira**: una lista ordenada de **columnas**. Cada columna tiene 1 o más ventanas, apiladas en vertical o en pestañas.
- La tira tiene una columna enfocada (y una ventana activa dentro de ella) y un desplazamiento horizontal (`scroll`).
- **Viewport**: es el `visibleFrame` de la pantalla (sin barra de menú ni Dock) menos el margen exterior. Las columnas fijadas lo reducen.
- Entre columnas va el gap interior y alrededor el margen exterior. Los dos son configurables desde 0.

### Qué ventanas entran a la tira

- Entran las que tienen rol `AXWindow`, subrol `AXStandardWindow` y tamaño modificable, y pertenecen a apps "regulares" (con ícono en el Dock). Además no tienen que estar en pantalla completa nativa.
- Quedan flotando, sin que se las toque: diálogos, paneles flotantes, hojas, Quick Look, Picture in Picture, ventanas no redimensionables y las ventanas de la propia app Rambla.
- Reglas por app (bundle id):
  - comportamiento: Mosaico (default) o Flotante
  - ancho inicial opcional
  - posición al abrir: junto a la enfocada (default), al principio o al final
- Las pantallas desactivadas en Configuración → Pantallas no se gestionan.
- Al iniciar, las ventanas existentes se ordenan según el estado guardado si coincide. Si no, por su posición x actual.

### Ventanas nuevas

- Una ventana nueva entra como columna a la derecha de la columna enfocada, en la tira de la pantalla donde aparece. Después se enfoca y la tira se desliza hasta mostrarla.
- Ancho: el propio de la ventana, limitado al rango [25 %, 100 %] del viewport. Se puede cambiar a un preset fijo en General, y la regla de la app tiene prioridad.
- Alto: todo el alto del viewport, salvo con "Mantener altura original", que conserva la altura de apertura alineada arriba.

### Foco y scroll

- Cuando cambia la ventana enfocada (por atajo, click, ⌘Tab, Dock o Mission Control), la tira se desliza con una animación de resorte hasta que la columna enfocada queda entera a la vista.
- Modos de centrado:
  - **Nunca** (default): scroll mínimo, alineando la columna al borde que corresponda.
  - **Solo si no entra**: si toda la tira entra en el viewport, no se mueve. Si no entra, centra la enfocada.
  - **Siempre**: centra la enfocada.
- Las columnas parcialmente visibles asoman por los bordes.
- macOS reubica por su cuenta las ventanas que quedan totalmente fuera de pantalla (verificado: las devuelve con 40 pt visibles) y no deja bajar la barra de título debajo del Dock. Por eso las que quedarían afuera se **estacionan** con 1 pt visible en un borde lateral: el de su lado o, si hay otra pantalla de ese lado, el opuesto. Si hay una pantalla vecina en un lado, una ventana puede salir hacia ese lado como máximo la mitad. Pasado ese punto, se estaciona.
- Si el botón del mouse está apretado al cambiar el foco (el usuario va a arrastrar), el scroll espera a que lo suelte.

### Acciones y atajos por defecto

Modificador base **⌃⌘** y **⌃⌘⇧** para la variante "mover". Ninguno choca con los atajos de Rectangle del usuario (⌃⌥, ⌃⌥⇧ y ⌃⌥⌘). Se evitan los atajos de sistema ⌃⌘F (pantalla completa), ⌃⌘Q (bloquear), ⌃⌘D (diccionario) y ⌃⌘Espacio (emojis). Cada acción admite hasta 2 atajos y todos se pueden cambiar.

| Acción (id para URL/CLI) | Qué hace | Atajos por defecto |
|---|---|---|
| `focus-left` / `focus-right` | Enfoca la columna de al lado | ⌃⌘← / ⌃⌘→, ⌃⌘H / ⌃⌘L |
| `focus-up` / `focus-down` | Ventana anterior o siguiente de la pila o pestaña | ⌃⌘↑ / ⌃⌘↓, ⌃⌘K / ⌃⌘J |
| `focus-first` / `focus-last` | Primera o última columna | ⌃⌘A / ⌃⌘E |
| `focus-1` … `focus-9` | Salta a la columna N | ⌃⌘1 … ⌃⌘9 |
| `move-left` / `move-right` | Mueve la columna | ⌃⌘⇧← / ⌃⌘⇧→, ⌃⌘⇧H / ⌃⌘⇧L |
| `move-up` / `move-down` | Mueve la ventana dentro de la pila | ⌃⌘⇧↑ / ⌃⌘⇧↓, ⌃⌘⇧K / ⌃⌘⇧J |
| `send-next-display` | Manda la ventana a la siguiente pantalla | ⌃⌘N |
| `cycle-width` | Rota el ancho entre los presets | ⌃⌘R |
| `full-width` | Ancho completo, alternando con el anterior | ⌃⌘M |
| `center` | Centra la columna enfocada | ⌃⌘C |
| `wider` / `narrower` | ± paso de ancho (5 %) | ⌃⌘= / ⌃⌘- |
| `taller` / `shorter` | ± alto (en pila: su proporción) | ⌃⌘⇧= / ⌃⌘⇧- |
| `equalize-heights` | Iguala las alturas de la pila | ⌃⌘0 |
| `pin-left` / `pin-right` | Fija o suelta la columna en el borde | ⌃⌘P / ⌃⌘⇧P |
| `stack-left` / `stack-right` | Mete la ventana en la columna de al lado | ⌃⌘[ / ⌃⌘] |
| `pop-left` / `pop-right` | Saca la ventana de la pila a una columna nueva | ⌃⌘⇧[ / ⌃⌘⇧] |
| `toggle-tabbed` | Alterna la columna entre pila y pestañas | ⌃⌘⇧T |
| `toggle-float` | Flota la ventana o la vuelve a la tira | ⌃⌘T |
| `close-window` | Cierra la ventana enfocada | (sin atajo) |
| `toggle-pause` | Pausa o reanuda Rambla | (sin atajo) |

- **Ancho completo**: la columna ocupa el 100 % del viewport. Repetir la acción restaura el ancho anterior.
- **Rotar ancho**: pasa al primer preset mayor que el ancho actual (con tolerancia de 1 %) y, si no hay ninguno, vuelve al primero. Los presets por defecto son 25, 33.3, 50, 66.7 y 75 %, y se pueden editar.
- **Fijar a un borde**: la columna queda pegada al borde izquierdo o derecho del viewport y a todo el alto, fuera del scroll. Hay una sola columna fijada por lado. Si se fija otra en el mismo lado, la anterior vuelve a la tira junto a la enfocada. Repetir la acción la suelta.
- **Pestañas**: todas las ventanas de la columna comparten el marco, debajo de una barra de pestañas propia (ícono y título, click para cambiar). Solo la activa se ve, al frente.
- **Flotar**: la ventana sale de la tira, se centra en su pantalla con su tamaño (máximo 80 % del viewport) y se eleva. Si está flotando, vuelve a la tira junto a la columna enfocada.
- Con Rambla en pausa, los atajos se liberan, salvo `toggle-pause` si tiene uno asignado.

### Trackpad

- Un swipe horizontal de N dedos (3 o 4, default 4) desplaza la tira siguiendo los dedos. Al soltar, la tira se asienta alineando el borde de columna más cercano y enfoca la columna más visible.
- La dirección es natural (el contenido sigue a los dedos) y la sensibilidad es configurable.
- macOS también recibe el gesto y no se puede bloquear. Configuración → Mac avisa si el gesto de escritorios de macOS usa la misma cantidad de dedos y ofrece abrir Ajustes del Trackpad.

### Barra indicadora

- Es un panel esmerilado centrado abajo, encima del Dock, con un ícono de app por columna. Una pila muestra varios íconos chicos, la columna enfocada se resalta y las columnas visibles quedan marcadas.
- Aparece al navegar o mover con atajos y al deslizar, y se desvanece a los ~0,8 s. Sigue visible mientras se mantengan apretados los modificadores del último atajo.
- Un click en un ícono enfoca esa columna y arrastrar un ícono reordena.
- Se puede desactivar.

### Arrastrar con el mouse

- Si se arrastra una ventana por su título y se suelta sobre otra columna, se mueve a esa posición: antes o después, según el lado de la columna destino. Si se suelta sobre el mismo lugar, vuelve.
- Si se suelta en otra pantalla, pasa a la tira de esa pantalla.
- Si se redimensiona con el mouse, se adopta el ancho nuevo de la columna. En una pila, se adopta también la proporción de alto.

### Convivencia con Rectangle

- Los atajos por defecto usan ⌃⌘, sin ningún choque con los del usuario.
- Si una ventana de la tira cambia de posición sin arrastre del mouse y sin que Rambla la haya movido, sale de la tira y queda flotando donde la dejaron. Esto cubre Rectangle, doble click en el título o zoom. Con `toggle-float` vuelve a la tira. Si solo cambió el tamaño y la esquina superior izquierda quedó igual, fue la propia app y se adopta el ancho.
- Si al terminar un arrastre otra app reacomoda la ventana en los ~200 ms siguientes (las snap areas de Rectangle), la ventana también sale de la tira.
- Configuración → Mac muestra "Rectangle detectado — convivencia activa" y lista los atajos de Rambla que coincidan con los de Rectangle. Para eso combina sus preferencias guardadas con su tabla de atajos por defecto.
- La opción "Si otra app mueve una ventana, sacarla de la tira" está activada por defecto.

### Indicadores de foco (los dos apagados por defecto)

- **Borde de foco**: una ventana overlay transparente dibuja un borde redondeado alrededor de la ventana enfocada, ordenada justo encima de ella. El color y el grosor son configurables.
- **Atenuar inactivas**: un overlay negro translúcido por pantalla, ordenado justo debajo de la ventana enfocada. La intensidad es configurable.

### Mouse

- **El mouse sigue al foco** (apagado): al enfocar con atajos, el puntero va al centro de la ventana.
- **El foco sigue al mouse** (apagado): si el puntero se queda 120 ms sobre una ventana de la tira totalmente visible, se enfoca sin desplazar la tira.

### Pantallas, escritorios y estados especiales

- Cada pantalla y cada escritorio tiene su propia tira, con su foco y su scroll.
- Ante un cambio de escritorio, la conexión o desconexión de pantallas o el reposo y despertar, se reconcilia el estado. Durante 2 s, los movimientos que haga macOS no cuentan como externos.
- **Pantalla completa nativa**: la ventana sale de la tira y reingresa al volver.
- Si la app está oculta (⌘H), la ventana minimizada o es una pestaña nativa inactiva, su columna se **colapsa**. No ocupa lugar y reaparece en el mismo sitio al volver.
- **Pestañas nativas** (Finder, Terminal): si aparece una ventana nueva de la misma app con el mismo marco que una que acaba de ocultarse, se agrupa en la misma columna (best effort).
- Si una ventana se pasa a otro escritorio desde Mission Control, se la mueve a la tira de ese escritorio en la próxima reconciliación.

### Persistencia

- Se guardan el orden de columnas, los anchos, las pilas, las pestañas, las columnas fijadas y las flotantes, en `~/Library/Application Support/Rambla/state.json`, 1 s después de cada cambio.
- Al reiniciar Rambla se restauran por ID de ventana. Al reiniciar la Mac, por app + título (best effort).
- Las preferencias van en UserDefaults (`io.github.coru29.Rambla`).
- Arrancar con la Mac usa `SMAppService.mainApp`.

### Salir, pausar y recuperación

- Al salir, pausar o recibir SIGTERM/SIGINT, las ventanas estacionadas vuelven al área visible de su pantalla con el mismo tamaño (centradas en x).
- Al reanudar, se reconstruyen las tiras según las posiciones actuales.
- El menú tiene "Traer todas las ventanas" (recuperación) y "Reacomodar" (reconciliar y volver a aplicar el layout).

### Barra de menú

- Ícono: SF Symbol `rectangle.split.3x1`, atenuado en pausa. El menú tiene:
  - estado (Activo / En pausa)
  - Pausar/Reanudar
  - Configuración…
  - Reacomodar
  - Traer todas las ventanas
  - Flotar/volver la ventana actual
  - Mostrar registro
  - Salir

### Configuración (SwiftUI, ventana con barra lateral)

| Sección | Qué incluye |
|---|---|
| General | activo, arrancar con la Mac, animaciones (con velocidad), centrado, ancho de ventanas nuevas, mantener altura original, gaps (interior y exterior), presets de ancho, paso de ajuste, sacar de la tira lo que mueva otra app |
| Atajos | todas las acciones agrupadas (Navegar, Tamaño, Pilas, Otros), con hasta 2 grabadores cada una, "Restaurar predeterminados", aviso de conflicto con Rectangle y aviso si el registro del atajo falla |
| Trackpad | activado, dedos (3/4), sensibilidad, dirección natural, aviso de conflicto con el gesto de macOS |
| Apariencia | barra indicadora (sí/no), borde de foco (sí/no, color, grosor), atenuar inactivas (sí/no, intensidad), el mouse sigue al foco, el foco sigue al mouse |
| Apps | lista de reglas: app, comportamiento, ancho inicial, posición al abrir. Para agregar, se elige entre las apps abiertas o con un selector de .app |
| Pantallas | pantallas conectadas con un interruptor cada una |
| Mac | chequeos con ✓/⚠︎ y botones para abrir el panel de Ajustes que corresponda: Accesibilidad, Spaces separados, reorganizar Spaces (recomendado apagado), Stage Manager, tiling por arrastre de macOS, gesto del trackpad, Rectangle |
| Automatización | ejemplos de URL, instalar el comando `rambla`, exportar scripts de Raycast |
| Acerca de | versión, registro |

- Mientras la configuración está abierta, la app aparece en el Dock y en ⌘Tab (política `.regular`). Al cerrarla vuelve a `.accessory`.

### Automatización

- URL scheme `rambla://<acción>`, por ejemplo `rambla://focus-left`, `rambla://focus-3` o `rambla://toggle-pause`.
- Comando de terminal `rambla <acción>`. Es el mismo binario en modo CLI: si recibe una acción como argumento, la publica por `DistributedNotificationCenter` y termina sin abrir la interfaz. `rambla list` imprime las acciones.
- Un botón instala `/usr/local/bin/rambla` (un script que llama al binario) y pide la contraseña si hace falta.
- Otro botón exporta scripts de Raycast (un `.sh` por acción con `open -g rambla://…`) a la carpeta que se elija.

## Arquitectura

### Proceso y hilos

- Es una app AppKit con `LSUIElement`, en Swift 6.3 con modo de lenguaje 5, **sin dependencias externas**. La configuración está hecha en SwiftUI.
- **Hilo principal**: modelo, layout, decisiones y UI.
- **Un hilo por app gestionada** (`AppWorker`) con su propio run loop. Ahí viven su `AXObserver` y todas las llamadas AX a esa app, así una app colgada no traba al resto.
  - Las escrituras de marcos se agrupan (la última gana).
  - El timeout de mensajería AX es de 1 s.
  - El worker recuerda el último marco aplicado u observado de cada ventana y solo avisa al hilo principal lo relevante: marco distinto, ventana creada o destruida, cambio de foco, minimizada o restaurada, cambio de título.
- **Animación**: un timer de 60 Hz que corre solo mientras hay algo animándose.
- El gesto, el arrastre y el foco que sigue al mouse instalan monitores o taps solo si la función está activada.

### Módulos

- **RamblaCore** es una biblioteca pura, sin AppKit, con tests. Contiene:
  - geometría
  - modelo (`Strip`, `Column`, `Width`)
  - layout: marcos objetivo, estacionamiento, límites de asomo con pantallas vecinas, barras de pestañas y columnas fijadas
  - reglas de scroll y centrado
  - todas las operaciones de la tira
  - cálculo del lugar de soltado
  - asentamiento del gesto
  - resorte
  - serialización de estado
  - acciones y atajos por defecto
  - tabla de atajos de Rectangle y detección de conflictos
  - preferencias (Codable)
- **Rambla** (la app) contiene:
  - AX: wrappers, `AppWorker` y privadas
  - `WindowManager`: estado global, reconciliación y eventos
  - `Animator`
  - `Hotkeys`: Carbon `RegisterEventHotKey` y un grabador propio que nombra las teclas según el layout con `UCKeyTranslate` (AZERTY, QWERTZ, Dvorak)
  - `Gestures`: `CGEventTap` listen-only de eventos `gesture` con `NSTouch`
  - `DragTracker`: monitores globales de mouse
  - overlays: indicador, barras de pestañas, borde y atenuado
  - UI de configuración
  - persistencia
  - chequeos de Mac
  - CLI y URL

### APIs privadas

- `_AXUIElementGetWindow` da el ID de ventana a partir de un `AXUIElement`.
- Las funciones de Spaces de SkyLight (`SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSManagedDisplayGetCurrentSpace` y `SLSCopySpacesForWindows`) se cargan con `dlsym`. Si faltan, se usa una tira por pantalla.
- `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo`, igual que yabai y AeroSpace, enfocan una ventana exacta a pesar de la activación cooperativa de macOS 14+. Si faltan, se usa `AXRaise` + `kAXMain` + `NSRunningApplication.activate()`.

### Coordenadas

- Todo el modelo usa coordenadas globales de AX: origen arriba a la izquierda de la pantalla principal, con y hacia abajo. La conversión a coordenadas de Cocoa se hace solo en los overlays.

### Aplicación de marcos

- Si cambia el tamaño, se hace como Rectangle: set size, después set position y, si el tamaño real difiere, set size otra vez. Si cambia solo la posición, se hace un único set position.
- Si la app tiene `AXEnhancedUserInterface` activo, se desactiva durante el movimiento y después se restaura.
- Se lee el marco real con `AXUIElementCopyMultipleAttributeValues`. Si la app impone un ancho mínimo, el modelo lo adopta como ancho efectivo y recalcula las posiciones.
- **Animación**: resorte críticamente amortiguado (respuesta de ~0,25 s, ajustable con la velocidad) por ventana en x e y. El tamaño se aplica al principio. Al cambiar el objetivo, la animación sigue desde la posición y la velocidad actuales. Sin animaciones, se aplica de una.

### Cambios externos

- Cuando llega una notificación de movimiento o cambio de tamaño, el worker lee el marco. Si coincide con el último (±2 pt), la ignora. Si no, se la pasa al hilo principal con el marco y si el botón izquierdo está apretado.
- **Con el mouse apretado** es un arrastre o redimensionado del usuario. Esa ventana queda congelada (sin escrituras) y se resuelve 200 ms después de soltar.
- **Sin el mouse**:
  - si se movió el origen, la ventana flota
  - si solo cambió el tamaño, se adopta
- Durante la reconfiguración de pantallas, el despertar y los cambios de escritorio hay 2 s de gracia: se ignoran los cambios y después se reconcilia.

### Estacionamiento

- Se deja visible un sliver de 1 pt (probado en macOS 26: se respeta). Los candidatos, en orden:
  1. el borde lateral del lado hacia donde quedó la ventana
  2. el borde del lado opuesto
- Se elige el primer candidato cuyo rectángulo no interseca otra pantalla. Si ninguno sirve, se usa el primero.
- Las esquinas inferiores no sirven: macOS sube la ventana hasta que la barra de título queda sobre el Dock.

### Firma, empaquetado e instalación

- `scripts/signing.sh` crea, una sola vez y sin interacción, la identidad autofirmada "Rambla Local Signing" en `.signing/rambla-signing.keychain-db` (OpenSSL con `-legacy` para el `.p12`). Al firmar, agrega el keychain a la lista de búsqueda del usuario y lo saca enseguida.
- `scripts/build.sh` compila con `swift build -c release` (arm64), arma `build/Rambla.app` (Info.plist, binario, ícono) y la firma.
- `scripts/dmg.sh` arma `build/Rambla.dmg` con la app y un alias a Aplicaciones.
- `scripts/install.sh` copia la app a /Applications y la reabre.
- El ícono de la app se genera con `scripts/make-icon.swift` (CoreGraphics), pasa por `iconutil` y queda en `Packaging/AppIcon.icns`.
- Requisitos: macOS 14+ y arm64.

### Pruebas

- **RamblaCore**: Swift Testing (`swift test`), TDD para el layout y las operaciones.
- **App**: verificación en vivo con el modo prueba `--only-bundle com.apple.TextEdit`, usando ventanas de TextEdit creadas con AppleScript, acciones por CLI y posiciones leídas con `CGWindowListCopyWindowInfo`. Hace falta que el usuario dé el permiso de Accesibilidad a Rambla.app una vez.

## Decisiones mías (a confirmar al leer)

- Nombre **Rambla** (como la carpeta), bundle id `io.github.coru29.Rambla` y esquema `rambla://`.
- Modificador **⌃⌘**. Ancho completo va en ⌃⌘M porque ⌃⌘F es pantalla completa. "Cerrar ventana" no tiene atajo porque ⌃⌘Q bloquea la pantalla.
- Swipe de **4 dedos** por defecto, como recomienda ChainYourMac. Para eso hay que apagar "Deslizar entre apps a pantalla completa" de macOS, y la app lo avisa.
- Gaps de 8 pt, presets 25/33/50/66/75, paso del 5 %, centrado "Nunca" y ancho de ventanas nuevas = el propio.
- macOS 14+ y arm64.
- Sin git ni commits salvo que el usuario lo pida.
