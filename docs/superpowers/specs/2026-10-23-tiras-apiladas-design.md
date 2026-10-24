# Tiras apiladas — diseño

Fecha: 2026-10-23 · Estado: idea y gestos acordados en el chat. El usuario dijo "me gusta", y el gesto de maximizar (tirar mucho hacia arriba) es propuesta suya. El resto son decisiones mías, listadas al final.

## Intención

El usuario quiere separar su entorno de trabajo de su entorno de casa/ocio en la misma pantalla y el mismo escritorio de macOS: "como lo que tenemos hoy, tal cual, pero sumar la posibilidad de tener otro arriba".

Rambla ya da una tira por escritorio de macOS, pero esos escritorios no sirven para esto:

- van de costado;
- cambiar de uno a otro es lento;
- mover ventanas entre ellos es engorroso.

La tira de arriba es de Rambla: se cambia con el mismo gesto de 4 dedos y no depende de Mission Control.

## Objetivos

- Cada pantalla y escritorio puede tener varias tiras, una arriba de la otra, y se ve una sola. La de siempre es la de abajo.
- Se cambia de tira con:
  - el gesto vertical, en el trackpad y con los botones del mouse;
  - atajos;
  - la vista general.
- Se pueden mandar ventanas de una tira a otra.
- Dentro de cada tira todo funciona igual que hoy.
- Las tiras sobreviven igual que la tira de hoy a reiniciar Rambla o la Mac, a desconectar pantallas y a cerrar la tapa.

## No-objetivos

- Nombres para las tiras.
- Reglas por app que manden sus ventanas a una tira.
- Que las tiras de distintas pantallas cambien juntas.
- Usar por debajo los escritorios de macOS.

## Anti-objetivos (sería un fracaso aunque "funcione")

- Que una ventana de otra tira asome, cruce la pantalla o aparezca en otra pantalla.
- Que se pierdan ventanas. Al salir, pausar o fallar, todas vuelven a la vista, como hoy.
- Que el teclado escriba en una ventana que no se ve.
- Que cambiar de tira sea lento o tenga pasos intermedios.
- Que quien no usa tiras pierda algo. El maximizar y la vista general siguen en el gesto, y en Configuración queda el gesto de antes.
- Que haya CPU en reposo o polling.

## Comportamiento

### Modelo

- **Pila de tiras:** cada par (pantalla, escritorio) tiene una pila de tiras numeradas desde abajo. La 0 es la tira de siempre.
- **Tira activa:** por cada par se ve una sola tira, la activa. Cada tira conserva su foco, su scroll y sus columnas fijadas.
- **Tira vacía nueva:** arriba de la tira más alta con ventanas siempre se puede subir a una tira vacía nueva. Existe recién cuando subís ahí o mandás una ventana ahí.
- **Tiras vacías que desaparecen:** una tira vacía que está arriba de todas las que tienen ventanas desaparece en cuanto deja de ser la activa.
- **Tiras vacías que se conservan:** las vacías de abajo o del medio se conservan. Así "trabajo abajo, casa arriba" no se da vuelta cuando una de las dos queda vacía un rato. La 0 existe siempre.
- **Bordes de la pila:** no se sube desde una tira vacía que ya es la más alta, ni se baja desde la 0.

### Gestos

**Trackpad.** Es el mismo gesto de 4 dedos de hoy, con los mismos umbrales: el corto es el 10 % del alto del trackpad y bien vertical, y el largo es el 30 %.

| Gesto | Qué hace | Cuándo |
|---|---|---|
| Un poco hacia abajo y soltar | va a la tira de arriba | al soltar |
| Un poco hacia arriba y soltar | va a la tira de abajo | al soltar |
| Bien hacia abajo (30 %) | abre la vista general, como hoy | en el momento |
| Bien hacia arriba (30 %) | la columna enfocada toma el ancho completo; si ya lo tenía, vuelve a su ancho anterior, como ⌃⌘M | en el momento |
| Volver antes de soltar (menos del 10 %) | nada | — |

Reglas del gesto:

- Hace una sola acción por swipe.
- **Dirección:** con "dirección natural" (el default), el contenido sigue a los dedos, así que hacia abajo aparece la tira de arriba. Sin dirección natural es al revés. Los gestos largos no cambian con esta opción.
- **Respuesta háptica** (si está activada):
  - un toque al pasar el 10 %, solo si hay una tira en esa dirección;
  - otro toque al pasar el 30 %.
- **Sobre qué actúa:**
  - el cambio de tira, sobre la pantalla donde está el puntero;
  - el ancho completo, sobre la columna enfocada, como hoy.

**Botones del mouse.** Funcionan igual, con sus umbrales de hoy:

- 40 pt el corto;
- 160 pt el largo.

La dirección sigue la opción natural de los botones.

**Configuración → Trackpad.** Nueva opción "Deslizar hacia arriba o abajo":

- **Cambia de tira** (el default): lo de arriba.
- **Cambia el ancho:** el gesto de antes.
  - arriba, ancho completo en el momento;
  - abajo, el ancho anterior al soltar;
  - bien abajo, la vista general.

La opción vale para el trackpad y para los botones del mouse. El interruptor actual de gestos verticales apaga solo los del trackpad: los botones del mouse se apagan con su propio interruptor.

### Atajos nuevos (editables)

| Atajo | Comando | Qué hace |
|---|---|---|
| ⌃⌥⌘↑ | `strip-up` | ir a la tira de arriba |
| ⌃⌥⌘↓ | `strip-down` | ir a la tira de abajo |
| ⌃⌥⌘⇧↑ | `send-strip-up` | mandar la ventana enfocada a la tira de arriba, y seguirla |
| ⌃⌥⌘⇧↓ | `send-strip-down` | lo mismo hacia abajo |

- **Tira sobre la que actúan:** la de la ventana enfocada, o la de la pantalla del puntero si no hay ventana enfocada.
- **Dónde aparecen:** en el grupo Navegar.
- **Otras formas de usarlos:** como comandos (`rambla strip-up`), como links (`rambla://strip-up`) y en los scripts de Raycast.
- **Conflictos:** Rectangle no usa esas combinaciones. Comprobarlo con la tabla de `RectangleShortcuts`.

### Las ventanas de las otras tiras

- **Dónde quedan:** estacionadas en un borde lateral, como las columnas fuera de la vista, con 1 pt visible. Se usa el borde que no toca otra pantalla, con las reglas de Estacionamiento del diseño principal. Arriba y abajo no sirven: macOS no deja una ventana bajo la barra de menú ni con la barra de título bajo el Dock.
- **Si alguien las mueve:** puede ser macOS al cambiar las pantallas, la app al reacomodarse sola, una ventana que vuelve del Dock o una app oculta que se muestra. En todos esos casos Rambla las vuelve a estacionar, y nunca flotan por eso.
- **Escritorios:** no cambian de escritorio aunque macOS las archive en otro, igual que las minimizadas.
- **Mission Control y App Exposé:** las siguen mostrando, porque están en el mismo escritorio. Elegir una ahí es ir a ella (ver "Foco desde afuera").
- **Ventanas flotantes** (confirmado por el usuario: "A, dale"):
  - **Las que flotan por una regla de app** (WhatsApp, por ejemplo) no son de ninguna tira y se ven en todas. Lo mismo vale para los diálogos y paneles que Rambla nunca acomoda.
  - **Las que el usuario hizo flotar** (⌃⌘T), y las que Rambla dejó flotando porque otra app las movió (Rectangle), son de la tira que estaba a la vista en su pantalla al cambiar de tira:
    - se estacionan con ella;
    - vuelven a su lugar al volver a esa tira.
  - **Si Rambla se reinicia, se pausa o trae todas las ventanas** mientras una de esas está escondida, vuelve a la vista en su lugar, como flotante de la tira activa.
  - **"Reacomodar ventanas"** devuelve las que Rambla dejó flotando a la tira de la que eran, no a la que estás viendo.
  - **Mandar a otra tira** (⌃⌥⌘⇧↑/↓) una flotante enfocada: la ventana se va con vos.
- **Pantalla con otra pantalla a los dos lados:** no hay borde libre, así que las ventanas de las otras tiras quedan sobre la pantalla vecina del lado más cercano. Es el mismo límite que ya tienen hoy las columnas estacionadas en esa configuración. Queda documentado en el manual y no es la configuración del usuario.

### El cambio de tira

- **Es inmediato:**
  - las ventanas de la tira que se va saltan a su estacionamiento;
  - las de la que llega saltan a su lugar, sin cruzar la pantalla.
  - No hay movimiento vertical posible, porque macOS no deja sacar ventanas por arriba ni por abajo.
- **Orden:** primero se ubican las que llegan, que quedan detrás, y después se van las otras.
- **Foco:** se enfoca la ventana enfocada de la tira que llega, y su columna queda a la vista.
- **Indicador de tiras:** si el indicador está activado, aparece un momento un panel con una fila por tira de esa pantalla, la de arriba arriba.
  - cada fila muestra los íconos de sus apps;
  - la activa va resaltada;
  - una tira vacía dice "Vacía".
- **Si la tira que llega está vacía:**
  - Aparece el aviso "Tira vacía", como el de una pantalla sin ventanas, que dice cómo traer una ventana (⌃⌥⌘⇧ + flecha, o abrir una app) y cómo volver.
  - El teclado deja de ir a la ventana de la tira anterior: Rambla toma el foco sin mostrar nada, y la próxima app que se abra o se elija lo recupera.

### Mandar ventanas a otra tira

- **Con ⌃⌥⌘⇧↑/↓:**
  - La ventana enfocada, sola como en "mandar a la siguiente pantalla", va al lado de la columna enfocada de la otra tira, con su ancho.
  - Vos te vas con ella.
- **Desde la vista general:**
  - Se arrastra una tarjeta, que es una columna con su pila o sus pestañas, a otra fila.
  - También se puede, con la tarjeta elegida, apretar ⇧↑ o ⇧↓.
  - Mientras se arrastra aparece arriba una fila "Tira nueva", y soltar ahí la crea.
- **La tira de origen:** si queda vacía, sigue las reglas del Modelo.

### Foco desde afuera

- **Regla general:** si una ventana de otra tira toma el foco, Rambla va a esa tira y la muestra. Vale para Mission Control, el menú Ventana, ⌘`, una notificación, ⌘Tab, el Dock o una ventana que vuelve del Dock.
- **Excepción, como los escritorios de macOS:** cuando el foco llega porque se activó la app (⌘Tab, el Dock, una notificación) y esa app tiene ventanas en la tira que estás viendo, Rambla enfoca la última que usaste de esas y no cambia de tira.
- **Cuando macOS mueve el foco solo,** después de cerrar o minimizar una ventana, u ocultar o salir de una app, Rambla no cambia de tira:
  - enfoca la última ventana que usaste de esa app en la tira que estás viendo;
  - si no hay, la última que usaste de cualquier app en esa tira;
  - si la tira quedó vacía, toma el teclado como en una tira vacía.
- **Ventanas nuevas:** se suman a la tira activa de la pantalla donde aparecen, aunque su app tenga otras ventanas en otra tira.

### Vista general

- **Filas:** muestra todas las tiras de la pantalla, una fila por tira, con la de arriba arriba.
  - Cada fila es como la vista general de hoy: tarjetas a escala, y la barra de lo que está en pantalla solo en la activa.
  - Las filas se achican para entrar.
- **Elegir una tarjeta de otra fila:** va a esa tira y enfoca esa ventana.
- **Teclado:**
  - ↑ y ↓ en el borde de una pila pasan a la fila de arriba o de abajo, a la tarjeta más cercana;
  - ⇧↑ y ⇧↓ mandan la columna elegida a la tira de arriba o de abajo.
- **Con una sola tira:** se ve igual que hoy.

### Pantallas y escritorios

- **Tira activa por escritorio:** cada par (pantalla, escritorio) tiene su pila y su tira activa, que se recuerda al ir y volver de escritorio.
- **Pantalla desconectada:**
  - Las ventanas de su tira N se suman a la tira N de la pantalla donde las deja macOS, que se crea si no existe.
  - Si esa tira no es la activa, las ventanas quedan estacionadas.
  - Cuando la pantalla vuelve, recupera cada tira con sus ventanas, como hoy, y vuelve a tener activa la tira que tenía.
- **Ventana mandada a otra pantalla** (con el atajo o arrastrándola): va a la tira activa de esa pantalla.
- **Ventana pasada a otro escritorio desde Mission Control:** va a la tira activa de ese escritorio.

### Persistencia

- **`state.json`:** guarda cada tira con su número, y cuál está activa en cada pantalla y escritorio. Las tiras de versiones anteriores son la 0.
- **Al arrancar:** se reconstruyen todas las tiras, y las que no están activas se estacionan.
- **Archivo:** las tiras de pantallas desconectadas y de escritorios no visitados se guardan con su número.
- **Al salir, pausar, fallar o usar "Traer todas las ventanas":**
  - las ventanas de todas las tiras vuelven a la vista, como hoy las estacionadas;
  - al volver Rambla, cada una vuelve a su tira.

### Comandos y diagnóstico

- `rambla dump` incluye el número de cada tira y si está activa.
- Hay cuatro comandos nuevos, `strip-up`, `strip-down`, `send-strip-up` y `send-strip-down`, para:
  - la línea de comandos;
  - los links;
  - los scripts de Raycast exportados.

### Textos y documentación

- **Configuración:** las páginas Trackpad, Mouse y Atajos.
- **Bienvenida:** si describe el gesto vertical.
- **Manuales y README:**
  - el MANUAL en español e inglés;
  - el README en español e inglés.
- **Diseño principal:** las secciones Trackpad, Mouse, Vista general, Pantallas y Persistencia.
- **Traducción:** `Localizable.strings` en inglés.
- **Notas de la versión.**
- **Web:** se ve con el usuario al publicar.

## Pruebas

**Unitarias (RamblaCore):**

- el gesto vertical del trackpad y del mouse, en los dos modos y en las dos direcciones;
- las reglas de la pila:
  - subir y bajar;
  - crear la tira vacía;
  - limpiar las vacías;
  - no pasar de los bordes;
- mandar ventanas a otra tira;
- el estacionamiento de una tira inactiva: a qué lado va y qué pasa con otra pantalla al lado;
- la vista general con varias filas:
  - posiciones;
  - selección entre filas;
  - mover una columna a otra fila;
- guardar y leer tiras con número, y que los archivos viejos queden como la 0;
- el archivo y la recuperación por número;
- los atajos por defecto y sus conflictos;
- `CommandPolicy`.

**En vivo (`scripts/e2e.sh`, con TestHost):**

- subir a una tira vacía, y que las ventanas de abajo queden estacionadas y no se vean;
- mandar ventanas arriba y abajo, y volver;
- dar el foco a una ventana de otra tira;
- una app que mueve una ventana estacionada;
- el vecino de prueba (`debug-neighbor`), para comprobar que ninguna ventana asome en otra pantalla;
- la CPU en reposo en 0 %.

**Con la tapa** (`scripts/e2e-lid.sh`, a mano con el usuario): una tira 1 con ventanas en la pantalla de la Mac al cerrar y abrir la tapa.

## Fuera de alcance (ideas para después)

- Nombres para las tiras, como "Trabajo" o "Casa", en el indicador y en la vista general.
- Reglas por app que manden sus ventanas a una tira.
- Un barrido animado que acompañe el cambio de tira, si el cambio inmediato se ve brusco.

## Decisiones mías (a confirmar al leer)

1. **Gestos:** lo corto cambia de tira y lo largo hace lo de siempre. Bien abajo abre la vista general, y bien arriba maximiza, que ahora alterna con el ancho anterior.
2. **Dirección:** el cambio de tira sigue la opción "dirección natural".
3. **Gesto de antes:** queda como opción en Configuración, y por defecto el gesto cambia de tira.
4. **Tiras dinámicas:**
   - la vacía de arriba aparece al subir;
   - desaparece si queda vacía arriba de todas y no estás en ella;
   - las vacías de abajo se conservan.
5. **Estacionamiento y cambio:** las ventanas de las otras tiras se estacionan en los bordes laterales, porque arriba y abajo no se puede, y el cambio es inmediato.
6. **Indicador:** muestra las tiras con íconos, sin nombres.
7. **Foco:** manda lo que enfocás. Con ⌘Tab, el Dock o una notificación, si la app tiene una ventana en la tira actual, te quedás.
8. **Ventanas flotantes:** las de reglas de app, los diálogos y los paneles se ven en todas las tiras. Las que flotan por el usuario o por Rectangle son de su tira. El usuario lo confirmó.
9. **Atajos y arrastre:**
   - los atajos son ⌃⌥⌘↑/↓ y ⌃⌥⌘⇧↑/↓;
   - mandar con atajo mueve la ventana sola;
   - arrastrar en la vista general mueve la columna entera.
10. **Tira vacía:** al llegar a una, Rambla toma el teclado para que no se escriba en una ventana que no se ve.
11. **Pantallas:** las pilas son por pantalla y escritorio. Al desconectar una pantalla, su tira N va a la tira N de la otra.
12. **Foco movido por macOS:** cuando macOS mueve el foco después de cerrar, minimizar, ocultar o salir, Rambla nunca cambia de tira.
13. **Pantallas vecinas a los dos lados:** las ventanas de las otras tiras quedan sobre la pantalla vecina, igual que hoy las columnas estacionadas. Queda como límite documentado.
