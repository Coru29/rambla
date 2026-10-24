# Manual de Rambla

<p><a href="MANUAL.en.md">Read in English</a></p>

Rambla ordena tus ventanas en una **tira horizontal**, como un paseo que sigue más allá de los bordes de la pantalla. Este manual explica cómo usarla, desde el primer día hasta los trucos.

> Rambla se muestra en español si tu Mac está en español, y en inglés si no.

**Contenido**

1. [La idea en 30 segundos](#1-la-idea-en-30-segundos)
2. [Instalación y permiso](#2-instalación-y-permiso)
3. [Primeros pasos](#3-primeros-pasos)
4. [Conceptos](#4-conceptos)
5. [Moverte por la tira](#5-moverte-por-la-tira)
6. [Anchos y alturas](#6-anchos-y-alturas)
7. [Pilas y pestañas](#7-pilas-y-pestañas)
8. [Columnas fijadas](#8-columnas-fijadas)
9. [Ventanas flotantes y Rectangle](#9-ventanas-flotantes-y-rectangle)
10. [Mouse y trackpad](#10-mouse-y-trackpad)
11. [Varias pantallas y escritorios](#11-varias-pantallas-y-escritorios)
12. [Tiras apiladas](#12-tiras-apiladas)
13. [Ayudas visuales](#13-ayudas-visuales)
14. [Configuración](#14-configuración)
15. [Automatización](#15-automatización)
16. [Problemas comunes](#16-problemas-comunes)
17. [Desinstalar](#17-desinstalar)

---

## 1. La idea en 30 segundos

En macOS, cada ventana nueva se encima con las demás o te obliga a achicarlas. Rambla hace otra cosa: **cada ventana es una columna**, y las columnas van una al lado de la otra en una tira que puede ser más ancha que tu pantalla. La pantalla es una ventanita que se desliza sobre esa tira.

```
            lo que ves en la pantalla
          ┌───────────────────────────┐
  ┊ Mail ┊│  Safari   │   Terminal    │┊ Notas ┊ Música ┊
          └───────────────────────────┘
   ← fuera de pantalla                  fuera de pantalla →
```

- Abrís una ventana nueva: aparece **al lado de la que estás usando**, sin achicar las otras.
- Enfocás otra ventana (con un atajo, un click, ⌘Tab o el Dock): **la tira se desliza** hasta mostrarla entera.

## 2. Instalación y permiso

1. Abrí el `.dmg` y arrastrá **Rambla** a la carpeta **Aplicaciones**.
2. Abrí Rambla desde Aplicaciones. Va a aparecer un ícono en la barra de menú: tres ventanas sobre la rambla. La primera vez se abre también una guía corta (**Bienvenida**) que te acompaña con el permiso, el trackpad y los atajos básicos; la volvés a abrir desde el menú cuando quieras.
3. macOS te pide el permiso de **Accesibilidad**, que es lo que permite mover ventanas de otras apps. Andá a **Configuración del Sistema → Privacidad y seguridad → Accesibilidad** y activá **Rambla**. Si no aparece el aviso, el menú de Rambla tiene "Abrir la configuración de Accesibilidad…".
4. Listo: Rambla detecta el permiso sola y ordena tus ventanas.

> Rambla no está notarizada por Apple, así que la primera vez macOS no la abre. Andá a **Configuración del Sistema → Privacidad y seguridad** y tocá **«Abrir de todos modos»**. En macOS 14 alcanza con click derecho en la app → **Abrir**.

Rambla no necesita Grabación de pantalla, ni Monitoreo de entrada, ni desactivar SIP.

### Actualizaciones

Rambla revisa si hay una versión nueva en GitHub al arrancar y una vez por día. Cuando la hay, el menú muestra **"Actualizar a Rambla X…"**: te cuenta las novedades y, si aceptás, Rambla se descarga, verifica que la versión nueva tenga la misma firma, se reemplaza y se vuelve a abrir. El permiso de Accesibilidad se mantiene. También podés revisar a mano con **"Buscar actualizaciones…"** en el menú, o desactivar la revisión automática en Configuración → General → **Buscar actualizaciones automáticamente**.

## 3. Primeros pasos

Al arrancar, Rambla toma las ventanas del escritorio actual y las pone en fila, de izquierda a derecha, en el orden en que estaban. Probá esto:

1. Apretá **⌃⌘→** y después **⌃⌘←** (Control + Comando + flecha). El foco pasa de una ventana a la otra y la tira se desliza.
2. Apretá **⌃⌘R** varias veces. La ventana enfocada va rotando de ancho: 25 %, 33 %, 50 %, 66 % y 75 % de la pantalla.
3. Abrí una ventana nueva de cualquier app (por ejemplo ⌘N en Safari). Aparece justo a la derecha de la que tenías enfocada.
4. Apretá **⌃⌘⇧→**. La columna enfocada se mueve un lugar a la derecha.

Si algo no te gusta, todo se puede cambiar en **Configuración** (menú de Rambla → Configuración…). Para que Rambla deje de ordenar por un rato, usá **Pausar Rambla** en el mismo menú.

## 4. Conceptos

| Concepto | Qué es |
|---|---|
| **Tira** | La fila de columnas. Cada pantalla y cada escritorio (Space) tiene la suya. |
| **Tiras apiladas** | Varias tiras una arriba de otra en la misma pantalla y el mismo escritorio. Se ve una sola a la vez (capítulo 12). |
| **Columna** | Un lugar en la tira. Normalmente tiene una ventana, pero puede tener varias (pila o pestañas). |
| **Ventana enfocada** | La que recibe el teclado. Su columna siempre se ve entera. |
| **Ventanas estacionadas** | Las que quedan fuera de la pantalla. macOS no deja sacar una ventana del todo, así que Rambla las deja asomando **1 punto** en el borde. Si ves una línea finita en el borde de la pantalla, es eso. También quedan así las ventanas de las tiras apiladas que no ves. |
| **Ventanas flotantes** | Las que no están en la tira: diálogos, paneles, ventanas que no se pueden redimensionar y las que vos (o Rectangle) sacaste. Rambla no las toca, salvo que cambies de tira (capítulo 9). |
| **Columna fijada** | Una columna pegada al borde izquierdo o derecho que no se mueve con la tira. |

## 5. Moverte por la tira

| Atajo | Qué hace |
|---|---|
| ⌃⌘← / ⌃⌘→ (o ⌃⌘H / ⌃⌘L) | Enfoca la columna de la izquierda / derecha |
| ⌃⌘↑ / ⌃⌘↓ (o ⌃⌘K / ⌃⌘J) | Enfoca la ventana de arriba / abajo dentro de una pila o pestañas |
| ⌃⌘A / ⌃⌘E | Va a la primera / última columna |
| ⌃⌘1 … ⌃⌘9 | Va directo a la columna 1 … 9 |
| ⌃⌘⇧← / ⌃⌘⇧→ (o ⌃⌘⇧H / ⌃⌘⇧L) | Mueve la columna enfocada a la izquierda / derecha |
| ⌃⌘⇧↑ / ⌃⌘⇧↓ (o ⌃⌘⇧K / ⌃⌘⇧J) | Mueve la ventana hacia arriba / abajo dentro de su pila |
| ⌃⌘N | Manda la ventana a la tira de la siguiente pantalla |
| ⌃⌥⌘↑ / ⌃⌥⌘↓ | Va a la tira de arriba / abajo (ver [Tiras apiladas](#12-tiras-apiladas)) |
| ⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓ | Manda la ventana enfocada a la tira de arriba / abajo y te lleva con ella |
| ⌃⌘O | Abre la vista general de la tira |

También podés enfocar como siempre: con un click, ⌘Tab, el Dock o Mission Control. La tira se desliza igual. Si usás tiras apiladas, una ventana de otra tira te puede llevar a esa tira: mirá el [capítulo 12](#12-tiras-apiladas).

**Vista general.** Con **⌃⌘O** (o bajando bastante con el trackpad o con los botones del mouse, ver el capítulo 10) ves toda la tira de la pantalla en chico: cada ventana con su app y su título, las pilas, las pestañas y las columnas fijadas. Una barra arriba marca la parte que está en pantalla ahora. Si tenés varias tiras apiladas, ves una fila por tira ([capítulo 12](#12-tiras-apiladas)). Hacé click en una ventana para ir a ella, o elegila con las flechas y tocá ↩; con 1 … 9 vas directo a esa columna. Para cambiar el orden, arrastrá una ventana a otro lugar, o elegila y tocá ⇧← o ⇧→ (también ⌃⌘⇧← →): su columna se mueve en la tira (las fijadas quedan en su borde). Esc, ⌘W, un click afuera o ⌃⌘O de nuevo la cierran. Mientras está abierta, los atajos de Rambla para moverte (⌃⌘ + flechas, ⌃⌘1 … 9) mueven la selección en vez de la tira, y los de cambiar de tira (⌃⌥⌘↑ / ⌃⌥⌘↓) la pasan a la fila de arriba o de abajo.

**Centrado.** Por defecto, la tira se mueve lo justo para que la columna enfocada se vea entera. En Configuración → General podés elegir que la centre **siempre** o **solo si la tira no entra en la pantalla**. Con **⌃⌘C** centrás la columna enfocada en cualquier momento.

## 6. Anchos y alturas

| Atajo | Qué hace |
|---|---|
| ⌃⌘R | Rota entre los anchos prefijados (25, 33, 50, 66 y 75 %, editables) |
| ⌃⌘M | Ancho completo. Repetilo para volver al ancho que tenía. |
| ⌃⌘= / ⌃⌘- | Más ancha / más angosta, de a 5 % (configurable) |
| ⌃⌘⇧= / ⌃⌘⇧- | Más alta / más baja: en una pila cambia la proporción de la ventana |
| ⌃⌘0 | Iguala las alturas de la pila |

- **Con el mouse**: si cambiás el tamaño de una ventana arrastrando su borde, Rambla adopta ese ancho para la columna.
- **Ventanas nuevas**: por defecto conservan su ancho propio. En Configuración → General podés fijar uno (33, 50 o 66 %).
- **Mantener altura original**: activalo en General si preferís que las ventanas conserven la altura con la que se abren, alineadas arriba, en vez de ocupar toda la altura.
- Algunas apps tienen un ancho mínimo (Safari, por ejemplo). Rambla lo detecta solo y acomoda el resto.

## 7. Pilas y pestañas

Una columna puede tener varias ventanas.

| Atajo | Qué hace |
|---|---|
| ⌃⌘[ / ⌃⌘] | Mete la ventana enfocada en la columna de la izquierda / derecha (apilar) |
| ⌃⌘⇧[ / ⌃⌘⇧] | La saca de la pila a una columna nueva, a la izquierda / derecha |
| ⌃⌘⇧T | Alterna la columna entre **pila** (una arriba de la otra) y **pestañas** |

- **Pila**: las ventanas se reparten la altura. Con ⌃⌘⇧= / ⌃⌘⇧- le das más o menos lugar a la enfocada, y ⌃⌘0 las iguala.
- **Pestañas**: las ventanas ocupan el mismo lugar y arriba aparece una barra con el ícono y el título de cada una. Hacé click en una pestaña o usá ⌃⌘↑ / ⌃⌘↓ para cambiar.
- Las **pestañas propias de macOS** (las del Finder o la Terminal) ocupan una sola columna.

## 8. Columnas fijadas

**⌃⌘P** fija la columna enfocada al borde **izquierdo** y **⌃⌘⇧P** al **derecho**. La columna queda a la vista, a toda la altura, y el resto de la tira se desliza en el espacio que sobra. Sirve, por ejemplo, para tener la música, el chat o una lista de tareas siempre visible.

- Repetí el atajo para soltarla; vuelve a su lugar en la tira.
- Hay una sola columna fijada por lado.

## 9. Ventanas flotantes y Rectangle

**⌃⌘T** saca la ventana enfocada de la tira: queda centrada, flotando y Rambla no la toca más. Apretalo de nuevo con esa ventana enfocada para devolverla a la tira, al lado de la columna enfocada.

**Rambla convive con Rectangle.** Podés seguir usando Rectangle como siempre:

- Los atajos de Rambla usan **⌃⌘** y los de Rectangle **⌃⌥**, así que no chocan. (Los de cambiar de tira usan ⌃⌥⌘ con ↑ y ↓, y Rectangle usa ⌃⌥⌘ solo con ← y →.) Si usás el set Spectacle de Rectangle, un par sí: la página Mac te dice cuáles.
- Si usás Rectangle sobre una ventana de la tira (mitad izquierda, maximizar, centrar…), **esa ventana sale de la tira y queda flotando donde la puso Rectangle**. Rambla no se pelea con Rectangle.
- Para devolverla a la tira: ⌃⌘T con esa ventana enfocada, o **Reacomodar ventanas** en el menú (devuelve todas las que salieron así, cada una a la tira de la que era). También vuelven solas cuando Rambla se reinicia o se actualiza; las que sacaste vos con ⌃⌘T siguen flotando.
- Lo mismo pasa con las snap areas de Rectangle (arrastrar una ventana al borde de la pantalla).
- Configuración → Mac te avisa si algún atajo de Rambla coincide con uno de tu Rectangle.
- Si no querés este comportamiento, desactivá "Si otra app mueve una ventana, sacarla de la tira" en Configuración → General.

**Flotantes y tiras apiladas.** Si usás varias tiras apiladas ([capítulo 12](#12-tiras-apiladas)), no todas las flotantes se comportan igual al cambiar de tira:

- Las que flotan por una regla de app, los diálogos, los paneles, las ventanas que no se pueden redimensionar, Imagen en imagen y Vista rápida **se ven en todas las tiras**.
- Las que flotan por ⌃⌘T, y las que Rambla dejó flotando porque otra app las movió (Rectangle), **se van con su tira**: se estacionan con ella y vuelven a su lugar cuando volvés.

## 10. Mouse y trackpad

**Reordenar con el mouse.** Agarrá una ventana de la barra de título y soltala encima de otra columna. Se mueve a ese lugar, antes o después según de qué lado de la columna la sueltes. Si la soltás en otra pantalla, pasa a la tira de esa pantalla.

**Deslizar con el trackpad.** Deslizá con **cuatro dedos** a izquierda o derecha (podés cambiarlo a tres): la tira sigue tus dedos y al soltar se asienta en una columna. Un deslizamiento corto y rápido alcanza para pasar a la siguiente. Mientras esos dedos están en el trackpad, la app que está bajo el puntero no se desplaza. Con un trackpad Force Touch sentís un toque suave cada vez que la tira va a pasar a otra columna (en un deslizamiento rápido, apenas arranca), y otro con los gestos hacia arriba o abajo (para cambiar de tira, solo si hay una tira en esa dirección); si no lo querés, apagá **«Respuesta háptica»** en Configuración → Trackpad y mouse.

> macOS también usa ese gesto para cambiar de escritorio y Rambla no lo puede bloquear. Ojo con una trampa de Configuración del Sistema: en **«Cambiar entre apps en pantalla completa»**, la opción **«3 dedos»** deja activo también el gesto de 4 dedos, aunque no lo muestre. Elegí una de estas opciones:
>
> - **Cuatro dedos para Rambla (recomendado):** en Configuración → Trackpad y mouse, tocá **«Apagarlo en macOS»**. Rambla apaga solo el gesto de 4 dedos de macOS, y el de 3 dedos sigue cambiando de escritorio. A mano, lo más parecido es elegir **«Desactivado»** en Configuración del Sistema → Trackpad → Más gestos → «Cambiar entre apps en pantalla completa», y cambiar de escritorio con ⌃← / ⌃→.
> - **Tres dedos para Rambla:** en Configuración del Sistema → Trackpad → Más gestos, poné «Cambiar entre apps en pantalla completa» en **«4 dedos»** y «Cambiar de página» en **2 dedos**. Después elegí tres dedos en Configuración → Trackpad y mouse. Esta opción no sirve si usás «arrastrar con tres dedos».
>
> Configuración → Trackpad y mouse (y la página Mac) te avisa si el gesto de Rambla choca con el de macOS.

**Arriba y abajo con el trackpad.** Con los mismos dedos también podés deslizar hacia arriba o abajo. Lo que hace se elige en Configuración → Trackpad y mouse → **Deslizar hacia arriba o abajo**:

- **Cambia de tira** (viene así). Un deslizamiento corto hacia abajo, y soltar, muestra la tira de arriba; uno corto hacia arriba, la de abajo (ver [Tiras apiladas](#12-tiras-apiladas)). Un deslizamiento largo hacia arriba da a la columna enfocada todo el ancho de la pantalla, sin la pantalla completa de macOS (como ⌃⌘M), o la vuelve al ancho que tenía si ya lo tenía. Uno largo hacia abajo abre la **vista general**. Los largos actúan en el momento, sin esperar a que sueltes. Si volvés atrás antes de soltar, no pasa nada.
- **Cambia el ancho** (el gesto de antes). **Hacia arriba**, la columna enfocada ocupa todo el ancho de la pantalla, sin la pantalla completa de macOS (como ⌃⌘M). **Hacia abajo** y soltando, vuelve al ancho que tenía; si seguís bajando un buen trecho, se abre la **vista general**.

Con la **dirección natural** (viene activada), el contenido sigue a los dedos: al bajarlos aparece la tira de arriba, como cuando arrastrás una página hacia abajo para ver lo que hay arriba. Sin ella, es al revés. Los deslizamientos largos no cambian con esta opción.

macOS abre Mission Control con el deslizamiento hacia arriba, y su opción «3 dedos» también deja activo el de 4: Configuración → Trackpad y mouse te avisa y lo apaga con **«Apagarlo en macOS»** (Mission Control sigue con 3 dedos y con ⌃↑). Si no querés estos gestos, apagá **«Gestos hacia arriba y abajo»** en la misma página. Ese interruptor es solo del trackpad: los gestos con los botones del mouse se apagan con el suyo, más abajo.

**Mover la tira con la ruedita del mouse.** Mantené **⌃⌘** y girá la ruedita: cada paso enfoca la columna de al lado. Con un Magic Mouse, o con dos dedos en el trackpad, manteniendo ⌃⌘ la tira se desliza como con el gesto y se asienta al soltar. Sin las teclas, la ruedita funciona como siempre. Las teclas se cambian en Configuración → Trackpad y mouse.

**Gestos con los botones del mouse.** En Configuración → Trackpad y mouse → Botones del mouse, activá **«Gestos con botones del mouse»** y elegí los botones: hacé clic en el campo **Botones**, apretá juntos los que quieras (por ejemplo, los dos laterales, 4 y 5) y soltalos. Después, con esos botones apretados, mové el mouse:

- **Hacia los costados**, la tira sigue al puntero y al soltar se asienta en una columna. Un movimiento corto y rápido pasa a la siguiente.
- **Un poco hacia abajo** y soltando, muestra la tira de arriba; **un poco hacia arriba**, la de abajo. Eso es con la **«Dirección natural»** de los botones, que viene activada; sin ella, es al revés.
- **Hacia arriba un buen trecho**, la columna enfocada toma el ancho completo o, si ya lo tenía, vuelve al que tenía.
- **Hacia abajo un buen trecho**, se abre la **vista general**.

Eso es con **«Cambia de tira»** (viene así). Con **«Cambia el ancho»**, **hacia arriba** la columna enfocada toma el ancho completo y **hacia abajo**, soltando, vuelve al ancho que tenía; si seguís bajando un buen trecho, se abre la **vista general**. Esa opción está en la sección Trackpad de la misma página y vale también para los botones del mouse.

Con un solo botón (el del medio, por ejemplo), un clic sin mover sigue funcionando como siempre. Con varios, cada botón por separado también sigue haciendo lo suyo: Rambla espera un instante a ver si llega el otro y, si no llega, le pasa el clic a la app. La sensibilidad y la dirección se cambian en la misma sección.

> **Con Mac Mouse Fix u otra app que use los botones del mouse:** elegí una combinación que esa app no use, como 4 + 5 juntos. Rambla recibe los botones y la ruedita antes que esas apps, así que ⌃⌘ + ruedita también funciona aunque Mac Mouse Fix use ⌘ + ruedita para el zoom. Si una de esas apps se reinicia, Rambla vuelve a ponerse adelante a los pocos segundos.

**El mouse sigue al foco / el foco sigue al mouse.** Son dos opciones de Configuración → Apariencia y vienen apagadas. La primera lleva el puntero al centro de la ventana que enfocás con un atajo. La segunda enfoca la ventana que tenga el puntero encima, sin mover la tira.

## 11. Varias pantallas y escritorios

- **Cada pantalla y cada escritorio tiene su propia tira** (o varias apiladas, [capítulo 12](#12-tiras-apiladas)), con su foco y su scroll. Al cambiar de escritorio, Rambla retoma la tira de ese escritorio tal como la dejaste.
- Si pasás una ventana a otro escritorio desde Mission Control, Rambla la mueve a la tira de ese escritorio.
- **⌃⌘N** manda la ventana enfocada a la siguiente pantalla. Si abrís la vista general en una pantalla sin ventanas (en ninguna de sus tiras), te recuerda cómo traer una.
- Podés desactivar Rambla en una pantalla en Configuración → Pantallas. Ahí no ordena nada.
- **Recomendado**: dejá activado "Las pantallas tienen Spaces separados" (viene así en macOS). Con dos monitores, lo ideal es poner el segundo **arriba o abajo** del principal en Configuración del Sistema → Pantallas → Organizar. Lado a lado también funciona: las ventanas se asoman como mucho hasta la mitad hacia el otro monitor, y las que quedan fuera de ese lado se estacionan en el borde opuesto (igual entran y salen por su lado).
- Las ventanas en **pantalla completa** (botón verde) salen de la tira mientras están así y vuelven a su lugar cuando salís.
- Las ventanas **minimizadas** o de apps **ocultas** (⌘H) dejan su lugar sin ocupar espacio y reaparecen en el mismo sitio, aunque mientras tanto conectes otra pantalla o abras la tapa.
- Si **desconectás una pantalla** (por ejemplo, al sacar la notebook del dock) y pasan más de 15 segundos, sus ventanas se suman a la tira de la pantalla donde las deja macOS. Si cerrás la tapa de la Mac, las de su pantalla se suman enseguida. Con tiras apiladas, cada tira se suma a la que ocupa su mismo lugar, como cuenta el [capítulo 12](#12-tiras-apiladas). **Cuando la volvés a conectar, vuelven a su lugar**, en el mismo orden y con sus anchos. Vuelven las que están a la vista en ese momento: una minimizada o en otro escritorio se queda donde está. Las ventanas que abriste mientras tanto quedan donde estaban. Mientras no vuelve, Rambla recuerda su orden hasta un mes, aunque reinicies; si reiniciás la Mac, reconoce cada ventana por su título.

## 12. Tiras apiladas

¿Querés separar el trabajo de la casa en la misma pantalla? Con las tiras apiladas podés tener **más de una tira por pantalla y por escritorio, una arriba de otra**. Ves una sola a la vez. La de siempre es la de abajo: ahí dejás el trabajo, y arriba ponés la casa.

```
            ┊ Música ┊ Chat ┊ Compras ┊     ← la casa (no se ve)
          ┌───────────────────────────┐
  ┊ Mail ┊│  Safari   │   Terminal    │┊ Notas ┊   ← el trabajo (lo que ves)
          └───────────────────────────┘
```

Cambiás de una a otra con un deslizamiento, con un atajo o desde la vista general. El cambio es inmediato, no pasa por Mission Control y no usa los escritorios de macOS. Dentro de cada tira todo funciona como siempre, y cada una guarda su foco, su scroll y sus columnas fijadas. Las ventanas de las tiras que no ves quedan estacionadas en el borde de la pantalla, como las columnas que están fuera de la vista. Si macOS o una app mueve una, Rambla la vuelve a estacionar: nunca queda flotando por eso.

> No las confundas con las pilas del [capítulo 7](#7-pilas-y-pestañas), que apilan ventanas dentro de una columna. Acá se apilan tiras enteras.

Probá esto:

1. Apretá **⌃⌥⌘↑**. Aparece una tira vacía arriba, y las ventanas que tenías se van de la vista: siguen en la tira de abajo.
2. Abrí una app que no esté abierta. Aparece en la tira nueva, y sus ventanas nuevas (⌘N) también. Una app que ya tiene ventanas abajo, en cambio, te lleva abajo, a ellas.
3. Apretá **⌃⌥⌘↓** para volver a la de abajo, y **⌃⌥⌘↑** para volver a la de arriba, que se quedó con su ventana.

### Cómo aparecen y desaparecen

- Arriba de la tira más alta que tiene ventanas siempre podés subir a una **tira nueva y vacía**. Existe recién cuando subís ahí o le mandás una ventana.
- Una tira vacía que está arriba de todas las que tienen ventanas **desaparece sola** en cuanto dejás de verla.
- Las vacías de abajo o del medio **se quedan**. Así, "trabajo abajo, casa arriba" no se da vuelta cuando una de las dos queda vacía un rato. La de abajo, la de siempre, existe siempre.
- Desde una tira vacía que ya es la más alta no se puede subir más, ni se baja desde la de abajo: no pasa nada.

### Cambiar de tira

**Con el trackpad o con los botones del mouse.** Un deslizamiento corto hacia abajo, y soltar, muestra la tira de arriba; uno corto hacia arriba, la de abajo. Eso es con la dirección natural, que viene activada; sin ella, es al revés. Los deslizamientos largos hacen lo de siempre: hacia arriba, el ancho completo, y hacia abajo, la vista general. Si preferís el gesto de antes, elegí **Cambia el ancho** en Configuración → Trackpad y mouse → **Deslizar hacia arriba o abajo**. El detalle está en el [capítulo 10](#10-mouse-y-trackpad).

**Con el teclado.**

| Atajo | Qué hace |
|---|---|
| ⌃⌥⌘↑ / ⌃⌥⌘↓ | Va a la tira de arriba / abajo |
| ⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓ | Manda la ventana enfocada a la tira de arriba / abajo y te lleva con ella |

Actúan sobre la tira de la ventana enfocada o, si no hay ninguna enfocada, sobre la de la pantalla donde está el puntero. Están en Configuración → Atajos, en el grupo **Navegar**, y se cambian como cualquier otro. Rectangle usa ⌃⌥⌘ solo con ← y →, así que no chocan. También son acciones de automatización (`strip-up`, `strip-down`, `send-strip-up` y `send-strip-down`), así que sirven con el comando `rambla`, con enlaces y con Raycast ([capítulo 15](#15-automatización)).

**Desde la vista general**, como se cuenta más abajo.

Al cambiar de tira, aparece un momento un panel con todas las tiras de la pantalla ([capítulo 13](#13-ayudas-visuales)).

### Mandar ventanas a otra tira

- Con **⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓**, la ventana enfocada (sola, no toda su columna) va a la tira de arriba o de abajo. Queda al lado de la columna enfocada de esa tira y con su ancho, y vos te vas con ella. Si estás en la tira más alta y la mandás hacia arriba, se crea una tira nueva.
- Desde la vista general podés mandar columnas enteras, con su pila o sus pestañas (más abajo).
- Si la tira de la que salió queda vacía, valen las reglas de arriba.

### Foco desde afuera

Rambla no te deja escribiendo en una ventana que no ves, y no te cambia de tira por algo que hizo macOS solo. Así se comporta cuando el foco llega de afuera:

- **Elegís una ventana de otra tira** (desde el menú Ventana, con ⌘`, en Mission Control, o sacándola minimizada del Dock): Rambla va a esa tira y la muestra. Mission Control tiene una excepción (ver [Límites](#límites)).
- **Llegás a una app con ⌘Tab, el Dock o una notificación:** pasa lo mismo que con los escritorios de macOS. Si la app tiene ventanas en la tira que ves, te quedás en esa tira y Rambla enfoca la última de esas ventanas que usaste. Si todas están en otra tira, va a esa tira.
- **macOS mueve el foco solo,** porque cerraste o minimizaste una ventana, o ocultaste o cerraste una app: Rambla no cambia de tira. Enfoca la última ventana que usaste, en la tira que ves, de la app a la que macOS le pasó el foco; si no hay, la última de cualquier app. Si la tira quedó vacía, Rambla toma el teclado, como en una tira vacía.
- **Se abre una ventana nueva:** se suma a la tira que ves en la pantalla donde aparece, aunque su app tenga ventanas en otra tira.

### La vista general con varias tiras

Con más de una tira, **⌃⌘O** (o un deslizamiento largo hacia abajo) muestra **una fila por tira** de la pantalla, la de arriba arriba. Cada fila es como la vista general de siempre. La barra de lo que está en pantalla aparece solo en la tira que ves, y las filas se achican para entrar. Una tira sin ventanas es una tarjeta **Vacía** que no se puede elegir. Con una sola tira, se ve igual que antes.

- **Elegir** una ventana de otra fila (con un click, o con las flechas y ↩) te lleva a esa tira y la enfoca.
- **↑ y ↓** recorren las ventanas de una pila y, al llegar a su borde, pasan a la fila de arriba o de abajo. Los atajos de cambiar de tira (⌃⌥⌘↑ / ⌃⌥⌘↓) y un deslizamiento corto hacia arriba o abajo llevan la selección directo a la fila de arriba o de abajo, sin recorrer la pila. No cambian la tira que está detrás.
- **Para mandar una columna a otra tira**, con su pila o sus pestañas: arrastrala a otra fila, o elegila y tocá **⇧↑ / ⇧↓** (también ⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓). Queda después de la columna enfocada de esa tira, o donde la sueltes si la arrastraste. Desde la tira más alta, ⇧↑ la manda a una tira nueva arriba.
- **Tira nueva.** Mientras arrastrás una columna, aparece arriba una fila **Tira nueva**: si la soltás ahí, se crea una tira con esa columna. No se ofrece para la única columna de la tira de arriba, ni al arrastrar ni con ⇧↑. Si la tira de arriba está vacía, soltala directamente ahí.

### Una tira vacía

Cuando llegás a una tira vacía:

- Aparece un momento el aviso **Tira vacía**. Dice que abras lo que quieras ahí, cómo traer una ventana desde la tira más cercana que tiene ventanas y cómo volver a ella. Para volver nombra el atajo, y el deslizamiento solo si el del trackpad cambia de tira: con el trackpad y sus **«Gestos hacia arriba y abajo»** activados, y **Cambia de tira** elegido. Nombra los atajos que tenés configurados, y si uno está sin asignar, esa parte no aparece; sin atajo ni deslizamiento, no dice cómo volver. Se ve aunque la barra indicadora esté apagada.
- Rambla **se queda con el teclado**, sin mostrar nada. Así, lo que escribas no llega a una ventana que no ves. En cuanto abrís una app o elegís una ventana, el teclado vuelve a ella.
- Si esa tira es la de más arriba y te vas, desaparece.

### Ventanas flotantes

- Las que flotan por una **regla de app** (una calculadora o un chat chiquito, por ejemplo), los **diálogos**, los **paneles**, las ventanas que **no se pueden redimensionar**, **Imagen en imagen** y **Vista rápida** no son de ninguna tira: se ven en todas.
- Las que flotan por **⌃⌘T**, y las que Rambla dejó flotando porque otra app las movió (Rectangle), **se van con la tira de su pantalla**. Al cambiar de tira se estacionan con la que dejás, y vuelven a su lugar cuando volvés a esa.
- Con una de esas flotantes enfocada, **⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓** la lleva con vos: la tira cambia y ella se queda a la vista.
- **Reacomodar ventanas** devuelve las que Rambla dejó flotando a la tira de la que eran, no a la que estás viendo.
- Si Rambla se reinicia o se pausa, o si usás **Traer todas las ventanas a la pantalla**, las que estaban estacionadas con una tira vuelven a su lugar, a la vista. Desde ahí son de la tira que ves.

### Pantallas y reinicios

- **Cada pantalla y cada escritorio (Space) tiene sus propias tiras** y su propia tira a la vista. Cuando volvés a un escritorio, ves la tira que dejaste.
- **Las pantallas no cambian juntas.** El deslizamiento corto actúa sobre la pantalla donde está el puntero, y los atajos sobre la tira de la ventana enfocada (o la de la pantalla del puntero, si no hay ninguna enfocada). El ancho completo sigue actuando sobre la columna enfocada, esté donde esté el puntero.
- **Una ventana que cambia de pantalla o de escritorio** va a la tira que se ve ahí. Pasa si la mandás con ⌃⌘N, si la arrastrás a otra pantalla o si la pasás a otro escritorio desde Mission Control.
- **Si desconectás una pantalla** (o cerrás la tapa de la Mac), cada una de sus tiras se suma a la que ocupa el mismo lugar, contando desde abajo, en la pantalla donde macOS deja las ventanas. Si esa tira no existe, se crea. Las que no están a la vista quedan estacionadas. **Cuando la volvés a conectar,** cada tira recupera sus ventanas y la pantalla vuelve a mostrar la tira que tenía. Si la ventana donde estabas escribiendo queda en una tira que no se ve, el teclado pasa a una ventana a la vista.
- **Al reiniciar Rambla o la Mac,** las tiras se arman de nuevo, cada ventana en la suya, y cada pantalla muestra la que tenía a la vista. Las demás quedan estacionadas. Las tiras de una pantalla desconectada o de un escritorio que no visitaste se guardan hasta un mes, como siempre.
- **Al salir de Rambla o pausarla,** las ventanas de todas las tiras vuelven a la vista, para que no se pierda ninguna. Al volver a abrirla o reanudarla, cada una vuelve a su tira.

### Límites

- **Mission Control y App Exposé muestran las ventanas de todas las tiras**, porque siguen en el mismo escritorio. Elegir una ahí te lleva a su tira.
- **Una excepción en Mission Control:** si elegís la ventana de una app que no estaba al frente y esa app también tiene ventanas en la tira que ves, Rambla lo toma como un ⌘Tab. Te quedás en esta tira, con la última ventana de esa app que usaste acá. Para ir a la otra tira, usá un deslizamiento, un atajo o la vista general.
- **Con pantallas a los dos lados de una pantalla** (tres en fila, la del medio) no queda un borde libre donde estacionar. Las ventanas de las otras tiras quedan sobre la pantalla vecina del lado más cercano. Las columnas estacionadas ya tenían este límite. Con dos pantallas no pasa.
- **Los diálogos y los paneles se ven en todas las tiras**: no son de ninguna.
- **Al desconectar una pantalla,** las ventanas de sus tiras que no se ven pueden aparecer en la pantalla que queda hasta 15 segundos (2 con la tapa de la Mac cerrada). Después se suman a su tira y, si no es la que se ve, quedan estacionadas.

## 13. Ayudas visuales

- **Barra indicadora**: al navegar con atajos o deslizar, aparece abajo una barra esmerilada con un ícono por columna. Resalta la enfocada y marca las que se ven. Mientras mantengas apretadas ⌃⌘ sigue visible. Hacé click en un ícono para ir a esa columna o arrastralo para reordenar. Se desactiva en Configuración → Apariencia.
- **Panel de tiras**: al cambiar de tira aparece un momento, abajo, un panel esmerilado con una fila por tira de la pantalla, la de arriba arriba. Cada fila muestra los íconos de las apps de sus columnas; la tira que ves va resaltada, y una tira sin ventanas dice «Vacía». No aparece si hay una sola tira, y se apaga con la barra indicadora.
- **Aviso «Tira vacía»**: al llegar a una tira sin ventanas, dice cómo traer una y cómo volver (ver el [capítulo 12](#12-tiras-apiladas)). Se ve aunque la barra indicadora esté apagada.
- **Borde de foco**: un borde de color alrededor de la ventana enfocada. Viene apagado. El color y el grosor se ajustan en Apariencia.
- **Atenuar inactivas**: oscurece un poco todo lo que no es la ventana enfocada. Viene apagado. La intensidad se ajusta en Apariencia.

## 14. Configuración

Abrila desde el ícono de la barra de menú → **Configuración…**. Mientras está abierta, Rambla aparece en el Dock.

| Sección | Para qué |
|---|---|
| **General** | Activar o pausar, arrancar con la Mac, animaciones y su velocidad, centrado, ancho de ventanas nuevas, mantener altura original, separación entre ventanas y margen, anchos prefijados, paso de ajuste, qué hacer cuando otra app mueve una ventana |
| **Atajos** | Cambiar cualquier atajo (cada acción admite dos). Hacé click en el atajo y apretá la combinación nueva: ⎋ cancela y ⌫ lo borra. Avisa si choca con Rectangle o si macOS no lo deja usar. "Restaurar predeterminados" vuelve todo a como venía. |
| **Trackpad y mouse** | El gesto del trackpad (dedos, sensibilidad, dirección natural, los gestos hacia arriba y abajo y si cambian de tira o el ancho, respuesta háptica), los conflictos con macOS, la ruedita y los botones del mouse |
| **Apariencia** | Barra indicadora (y el panel de tiras), borde de foco, atenuar inactivas, mouse ↔ foco |
| **Apps** | Reglas por app: que flote siempre (ideal para calculadoras, reproductores o chats chiquitos), ancho inicial y dónde se abren sus ventanas (al lado de la enfocada, al principio o al final) |
| **Pantallas** | Activar o desactivar Rambla en cada monitor |
| **Mac** | Revisa los ajustes de macOS que afectan a Rambla (permiso, Spaces, Organizador visual, gestos, Rectangle) y te lleva al panel de Configuración del Sistema que corresponda |
| **Automatización** | Instalar el comando `rambla` y exportar scripts de Raycast |
| **Acerca de** | Versión, enlace al proyecto y registro |

### El menú de la barra

| Opción | Qué hace |
|---|---|
| Pausar / Reanudar Rambla | Deja de ordenar y trae todas las ventanas a la pantalla. Al reanudar, vuelve a armar la tira. |
| Reacomodar ventanas | Vuelve a revisar todas las ventanas, devuelve a la tira las que sacó otra app (como Rectangle) y aplica el orden |
| Traer todas las ventanas a la pantalla | Rescata cualquier ventana estacionada en un borde |
| Flotar / volver la ventana actual | Lo mismo que ⌃⌘T |
| Configuración… | Abre la configuración |
| Bienvenida… | Vuelve a abrir la guía del primer arranque: permiso, trackpad y atajos básicos |
| Manual de uso | Abre este manual |
| Mostrar registro | Abre el registro de actividad, útil si algo falla |

## 15. Automatización

Todas las acciones tienen un nombre corto, por ejemplo `focus-left`, `cycle-width`, `focus-3`, `pin-left` o `toggle-pause`. La lista completa sale con `rambla list`.

**Enlaces:**

```sh
open -g "rambla://focus-left"
open -g "rambla://cycle-width"
```

Los enlaces ejecutan todas las acciones menos `close-window`: cualquier página web puede abrir un enlace, y así ninguna puede cerrarte una ventana. Esa acción funciona solo con el comando `rambla` y con su script de Raycast.

**Terminal:** instalá el comando en Configuración → Automatización → "Instalar comando rambla".

```sh
rambla focus-right
rambla toggle-pause
rambla list
```

**Raycast:** en Configuración → Automatización → "Exportar scripts de Raycast…" elegí una carpeta y agregala en Raycast (Settings → Extensions → Script Commands → Add Directories). Vas a tener un comando por acción, por ejemplo "Rambla: Rotar ancho".

Los enlaces también sirven en Atajos de Apple, Alfred, Keyboard Maestro, BetterTouchTool o cualquier herramienta que pueda abrir una URL.

## 16. Problemas comunes

**Veo una línea finita en el borde de la pantalla.** Son las ventanas estacionadas: macOS no deja esconder una ventana del todo y Rambla deja 1 punto visible. Si hacés click ahí, la tira se desliza hasta esa ventana. Si es de una tira apilada que no ves, vale lo de «Foco desde afuera» del [capítulo 12](#12-tiras-apiladas).

**Se me perdió una ventana.** Si usás tiras apiladas, puede estar en otra tira: la vista general (**⌃⌘O**) las muestra todas. Si no, menú de Rambla → **Traer todas las ventanas a la pantalla**. Al salir o pausar, Rambla también las trae.

**Mission Control muestra ventanas que no veo en la pantalla.** Son las de las otras tiras apiladas, que siguen en el mismo escritorio. Mirá los límites del [capítulo 12](#12-tiras-apiladas).

**Una ventana no entra en la tira.** Rambla deja flotando los diálogos, los paneles y las ventanas que no se pueden redimensionar. Si es una ventana normal, fijate si no la sacaste con ⌃⌘T o con Rectangle (en ese caso, ⌃⌘T la devuelve) y si no tiene una regla "Flotante" en Configuración → Apps.

**Una ventana salió sola de la tira.** Otra app la movió (Rectangle, un doble click en la barra de título, el botón verde con ⌥). Es a propósito: Rambla no pelea con otras apps. Devolvela con ⌃⌘T.

**Deslizar con el trackpad cambia de escritorio.** macOS usa el mismo gesto, aunque Configuración del Sistema diga «3 dedos»: mirá la [sección 10](#10-mouse-y-trackpad).

**Un atajo no hace nada.** Puede que otra app ya lo use. Revisá Configuración → Atajos, que marca los que macOS no dejó registrar, y cambialo por otro.

**Rambla pide el permiso de Accesibilidad otra vez.** En Configuración del Sistema → Privacidad y seguridad → Accesibilidad, quitá Rambla con "−" y agregala de nuevo desde Aplicaciones.

**Algo se ve raro.** Probá **Reacomodar ventanas**. Si sigue, **Mostrar registro** te muestra qué pasó; esa información sirve para reportar el problema en [GitHub](https://github.com/Coru29/rambla/issues).

## 17. Desinstalar

1. Menú de Rambla → **Salir de Rambla**. Todas las ventanas vuelven a la pantalla.
2. Borrá **Rambla** de Aplicaciones.
3. En Configuración del Sistema → Privacidad y seguridad → Accesibilidad, quitá Rambla con "−".
4. Para no dejar rastros, borrá también:

   ```sh
   rm -rf ~/Library/Application\ Support/Rambla ~/Library/Logs/Rambla
   defaults delete io.github.coru29.Rambla
   sudo rm -f /usr/local/bin/rambla   # solo si instalaste el comando
   ```
