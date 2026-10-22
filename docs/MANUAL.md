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
12. [Ayudas visuales](#12-ayudas-visuales)
13. [Configuración](#13-configuración)
14. [Automatización](#14-automatización)
15. [Problemas comunes](#15-problemas-comunes)
16. [Desinstalar](#16-desinstalar)

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
3. macOS te pide el permiso de **Accesibilidad**, que es lo que permite mover ventanas de otras apps. Andá a **Ajustes del Sistema → Privacidad y seguridad → Accesibilidad** y activá **Rambla**. Si no aparece el aviso, el menú de Rambla tiene "Abrir Ajustes de Accesibilidad…".
4. Listo: Rambla detecta el permiso sola y ordena tus ventanas.

> Rambla no está notarizada por Apple. Si macOS dice que no puede verificar al desarrollador, hacé click derecho en la app → **Abrir**.

Rambla no necesita Grabación de pantalla, ni Monitoreo de entrada, ni desactivar SIP.

### Actualizaciones

Rambla revisa una vez por día si hay una versión nueva en GitHub. Cuando la hay, el menú muestra **"Actualizar a Rambla X…"**: te cuenta las novedades y, si aceptás, Rambla se descarga, verifica que la versión nueva tenga la misma firma, se reemplaza y se vuelve a abrir. El permiso de Accesibilidad se mantiene. También podés revisar a mano con **"Buscar actualizaciones…"** en el menú, o desactivar la revisión diaria en Configuración → General.

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
| **Tira** | La fila de columnas. Hay una por cada pantalla y por cada escritorio (Space). |
| **Columna** | Un lugar en la tira. Normalmente tiene una ventana, pero puede tener varias (pila o pestañas). |
| **Ventana enfocada** | La que recibe el teclado. Su columna siempre se ve entera. |
| **Ventanas estacionadas** | Las que quedan fuera de la pantalla. macOS no deja sacar una ventana del todo, así que Rambla las deja asomando **1 punto** en el borde. Si ves una línea finita en el borde de la pantalla, es eso. |
| **Ventanas flotantes** | Las que no están en la tira: diálogos, paneles, ventanas que no se pueden redimensionar y las que vos (o Rectangle) sacaste. Rambla no las toca. |
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

También podés enfocar como siempre: con un click, ⌘Tab, el Dock o Mission Control. La tira se desliza igual.

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

- Los atajos de Rambla usan **⌃⌘** y los de Rectangle **⌃⌥**, así que no chocan.
- Si usás Rectangle sobre una ventana de la tira (mitad izquierda, maximizar, centrar…), **esa ventana sale de la tira y queda flotando donde la puso Rectangle**. Rambla no se pelea con Rectangle.
- Para devolverla a la tira: ⌃⌘T con esa ventana enfocada, o **Reacomodar ventanas** en el menú (devuelve todas las que salieron así). También vuelven solas cuando Rambla se reinicia o se actualiza; las que sacaste vos con ⌃⌘T siguen flotando.
- Lo mismo pasa con las snap areas de Rectangle (arrastrar una ventana al borde de la pantalla).
- Configuración → Mac te avisa si algún atajo de Rambla coincide con uno de tu Rectangle.
- Si no querés este comportamiento, desactivá "Si otra app mueve una ventana, sacarla de la tira" en Configuración → General.

## 10. Mouse y trackpad

**Reordenar con el mouse.** Agarrá una ventana de la barra de título y soltala encima de otra columna. Se mueve a ese lugar, antes o después según de qué lado de la columna la sueltes. Si la soltás en otra pantalla, pasa a la tira de esa pantalla.

**Deslizar con el trackpad.** Deslizá con **cuatro dedos** a izquierda o derecha (podés cambiarlo a tres): la tira sigue tus dedos y al soltar se asienta en una columna. Un deslizamiento corto y rápido alcanza para pasar a la siguiente.

> macOS también usa ese gesto para cambiar de escritorio y Rambla no lo puede bloquear. Ojo con una trampa de Ajustes: en **«Cambiar entre apps en pantalla completa»**, la opción **«3 dedos»** deja activo también el gesto de 4 dedos, aunque no lo muestre. Elegí una de estas opciones:
>
> - **Cuatro dedos para Rambla (recomendado):** en Configuración → Trackpad y mouse, tocá **«Apagarlo en macOS»**. Rambla apaga solo el gesto de 4 dedos de macOS, y el de 3 dedos sigue cambiando de escritorio. A mano, lo más parecido es elegir **«Desactivado»** en Ajustes del Sistema → Trackpad → Más gestos → «Cambiar entre apps en pantalla completa», y cambiar de escritorio con ⌃← / ⌃→.
> - **Tres dedos para Rambla:** en Ajustes del Sistema → Trackpad → Más gestos, poné «Cambiar entre apps en pantalla completa» en **«4 dedos»** y «Cambiar de página» en **2 dedos**. Después elegí tres dedos en Configuración → Trackpad y mouse. Esta opción no sirve si usás «arrastrar con tres dedos».
>
> Configuración → Trackpad y mouse (y la página Mac) te avisa si el gesto de Rambla choca con el de macOS.

**Mover la tira con la ruedita del mouse.** Mantené **⌃⌘** y girá la ruedita: cada paso enfoca la columna de al lado. Con un Magic Mouse, o con dos dedos en el trackpad, manteniendo ⌃⌘ la tira se desliza como con el gesto y se asienta al soltar. Sin las teclas, la ruedita funciona como siempre. Las teclas se cambian en Configuración → Trackpad y mouse.

**El mouse sigue al foco / el foco sigue al mouse.** Son dos opciones de Configuración → Apariencia y vienen apagadas. La primera lleva el puntero al centro de la ventana que enfocás con un atajo. La segunda enfoca la ventana que tenga el puntero encima, sin mover la tira.

## 11. Varias pantallas y escritorios

- **Cada pantalla y cada escritorio tiene su propia tira**, con su foco y su scroll. Al cambiar de escritorio, Rambla retoma la tira de ese escritorio tal como la dejaste.
- Si pasás una ventana a otro escritorio desde Mission Control, Rambla la mueve a la tira de ese escritorio.
- **⌃⌘N** manda la ventana enfocada a la siguiente pantalla.
- Podés desactivar Rambla en una pantalla en Configuración → Pantallas. Ahí no ordena nada.
- **Recomendado**: dejá activado "Las pantallas tienen Spaces separados" (viene así en macOS). Con dos monitores, lo ideal es poner el segundo **arriba o abajo** del principal en Ajustes del Sistema → Pantallas → Organizar. Lado a lado también funciona, pero las ventanas solo pueden asomarse hasta la mitad hacia el otro monitor antes de estacionarse.
- Las ventanas en **pantalla completa** (botón verde) salen de la tira mientras están así y vuelven a su lugar cuando salís.
- Las ventanas **minimizadas** o de apps **ocultas** (⌘H) dejan su lugar sin ocupar espacio y reaparecen en el mismo sitio.

## 12. Ayudas visuales

- **Barra indicadora**: al navegar con atajos o deslizar, aparece abajo una barra esmerilada con un ícono por columna. Resalta la enfocada y marca las que se ven. Mientras mantengas apretadas ⌃⌘ sigue visible. Hacé click en un ícono para ir a esa columna o arrastralo para reordenar. Se desactiva en Configuración → Apariencia.
- **Borde de foco**: un borde de color alrededor de la ventana enfocada. Viene apagado. El color y el grosor se ajustan en Apariencia.
- **Atenuar inactivas**: oscurece un poco todo lo que no es la ventana enfocada. Viene apagado. La intensidad se ajusta en Apariencia.

## 13. Configuración

Abrila desde el ícono de la barra de menú → **Configuración…**. Mientras está abierta, Rambla aparece en el Dock.

| Sección | Para qué |
|---|---|
| **General** | Activar o pausar, arrancar con la Mac, animaciones y su velocidad, centrado, ancho de ventanas nuevas, mantener altura original, separación entre ventanas y margen, anchos prefijados, paso de ajuste, qué hacer cuando otra app mueve una ventana |
| **Atajos** | Cambiar cualquier atajo (cada acción admite dos). Hacé click en el atajo y apretá la combinación nueva: ⎋ cancela y ⌫ lo borra. Avisa si choca con Rectangle o si macOS no lo deja usar. "Restaurar predeterminados" vuelve todo a como venía. |
| **Trackpad y mouse** | El gesto del trackpad (dedos, sensibilidad, dirección natural), los conflictos con macOS y la ruedita del mouse |
| **Apariencia** | Barra indicadora, borde de foco, atenuar inactivas, mouse ↔ foco |
| **Apps** | Reglas por app: que flote siempre (ideal para calculadoras, reproductores o chats chiquitos), ancho inicial y dónde se abren sus ventanas (al lado de la enfocada, al principio o al final) |
| **Pantallas** | Activar o desactivar Rambla en cada monitor |
| **Mac** | Revisa los ajustes de macOS que afectan a Rambla (permiso, Spaces, Stage Manager, gestos, Rectangle) y te lleva al panel de Ajustes que corresponda |
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

## 14. Automatización

Todas las acciones tienen un nombre corto, por ejemplo `focus-left`, `cycle-width`, `focus-3`, `pin-left` o `toggle-pause`. La lista completa sale con `rambla list`.

**Enlaces:**

```sh
open -g "rambla://focus-left"
open -g "rambla://cycle-width"
```

**Terminal:** instalá el comando en Configuración → Automatización → "Instalar comando rambla".

```sh
rambla focus-right
rambla toggle-pause
rambla list
```

**Raycast:** en Configuración → Automatización → "Exportar scripts de Raycast…" elegí una carpeta y agregala en Raycast (Settings → Extensions → Script Commands → Add Directories). Vas a tener un comando por acción, por ejemplo "Rambla: Rotar ancho".

Los enlaces también sirven en Atajos de Apple, Alfred, Keyboard Maestro, BetterTouchTool o cualquier herramienta que pueda abrir una URL.

## 15. Problemas comunes

**Veo una línea finita en el borde de la pantalla.** Son las ventanas estacionadas: macOS no deja esconder una ventana del todo y Rambla deja 1 punto visible. Si hacés click ahí, la tira se desliza hasta esa ventana.

**Se me perdió una ventana.** Menú de Rambla → **Traer todas las ventanas a la pantalla**. Al salir o pausar, Rambla también las trae.

**Una ventana no entra en la tira.** Rambla deja flotando los diálogos, los paneles y las ventanas que no se pueden redimensionar. Si es una ventana normal, fijate si no la sacaste con ⌃⌘T o con Rectangle (en ese caso, ⌃⌘T la devuelve) y si no tiene una regla "Flotante" en Configuración → Apps.

**Una ventana salió sola de la tira.** Otra app la movió (Rectangle, un doble click en la barra de título, el botón verde con ⌥). Es a propósito: Rambla no pelea con otras apps. Devolvela con ⌃⌘T.

**Deslizar con el trackpad cambia de escritorio.** macOS usa el mismo gesto, aunque Ajustes diga «3 dedos»: mirá la [sección 10](#10-mouse-y-trackpad).

**Un atajo no hace nada.** Puede que otra app ya lo use. Revisá Configuración → Atajos, que marca los que macOS no dejó registrar, y cambialo por otro.

**Rambla pide el permiso de Accesibilidad otra vez.** En Ajustes del Sistema → Privacidad y seguridad → Accesibilidad, quitá Rambla con "−" y agregala de nuevo desde Aplicaciones.

**Algo se ve raro.** Probá **Reacomodar ventanas**. Si sigue, **Mostrar registro** te muestra qué pasó; esa información sirve para reportar el problema en [GitHub](https://github.com/Coru29/rambla/issues).

## 16. Desinstalar

1. Menú de Rambla → **Salir de Rambla**. Todas las ventanas vuelven a la pantalla.
2. Borrá **Rambla** de Aplicaciones.
3. En Ajustes del Sistema → Privacidad y seguridad → Accesibilidad, quitá Rambla con "−".
4. Para no dejar rastros, borrá también:

   ```sh
   rm -rf ~/Library/Application\ Support/Rambla ~/Library/Logs/Rambla
   defaults delete io.github.coru29.Rambla
   sudo rm -f /usr/local/bin/rambla   # solo si instalaste el comando
   ```
