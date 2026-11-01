# Dixity — mini manual

Dixity vive en la barra de menú. Apretás un atajo, hablás y el texto aparece prolijo donde está el cursor, en
cualquier app. Todo se configura en el panel (clic en el ícono de la barra › Ajustes).

## 1. La primera vez

1. **Permisos** (General › Permisos): Micrófono y Accesibilidad. Sin Accesibilidad el atajo no se escucha ni se puede
   pegar. "Leer la pantalla" pide además Grabación de pantalla.
2. **Cómo querés usarla** (Proveedores):
   - **Todo en la Mac**: la voz con Parakeet o con el motor de la Mac, y la limpieza con Apple Intelligence. Sin
     claves ni internet; nada sale de la Mac.
   - **Con tus propias claves**: OpenAI, Anthropic, Grok, Groq, OpenRouter o cualquier servicio compatible con OpenAI.
     Les pagás directo a ellos. Las claves quedan en el llavero de la Mac, nunca en un archivo.
3. **General › Abrir al iniciar sesión**, así el atajo anda siempre. La bienvenida se puede ver de nuevo en General.

## 2. Los atajos (se cambian en Atajos)

| Atajo | Qué hace |
|---|---|
| **⌥ derecha** | **Dictar.** Un toque empieza y otro termina, o mantenés y soltás. **Esc** cancela. |
| **⇧⌥ izquierdas** | **Reescribir** lo que seleccionaste ("más corto", "para un mail"). Sin selección, escribe lo que pedís. |
| **⌃⌥P** | **Preguntar**: la respuesta aparece en una ventanita antes de pegar. También le habla a Claude y Codex. |
| **⌃⌥V** | **Portapapeles**: lo que copiaste en las últimas 24 h. ↩ pega, ⌘1–9 pega rápido, ⌘⌫ borra. |
| **⌃⌥R** | **Volver a procesar** el último dictado (si salió mal o falló la IA). |
| **⌃⌥D** | **Sumar al diccionario** la palabra que tenés seleccionada. |
| **⌃⌥O / ⌃⌥S** | Acciones rápidas sobre una selección: **Ordenar** y **Resumir** (sin hablar). |
| **⌃⌥1…6** | Dictar en un modo puntual. **⌃⌥0** vuelve a Automático. Mientras grabás, 1…6 cambian el modo. |
| **Sacudir el mouse** | Prende la **Varita** (ver 5 bis). Todo lo de la Varita se ajusta en su página del panel, **Varita**. |

## 3. La píldora

Es la barrita que aparece mientras dictás. El punto tiene el color del modo. Con el mouse encima: **⏸ pausa** y
✓ termina (cancelar es **Esc**). En pausa el micrófono se apaga y no graba nada: **▶** sigue en el mismo dictado,
✕ cancela y ✓ termina con todo lo grabado. Si dictabas manteniendo la tecla, al pausar podés soltarla. Se arrastra y recuerda el lugar. Si no te escucha, lo avisa; si algo falla, queda con **Reintentar** y
suena. Estilo (clara, oscura, vidrio, cristal), tamaño y transparencia: General › Píldora.

## 4. Modos: cómo pasa en limpio (página Modos)

- **Automático** (por defecto) elige según la app. La lista se edita en "Qué modo usa en cada app".
- **Común**: mails, chats y notas, tal como lo dirías pero prolijo.
- **Prompt**: ordena lo que decís como pedido para una IA (Claude, ChatGPT, Codex…). Si la ventana es de un proyecto
  de tus **Carpetas de proyectos**, usa su guía (AGENTS.md o CLAUDE.md) para escribir bien los nombres.
- **Correo**, **Mensaje** (con un emoji que acompaña lo que decís, si lo dejás prendido), **Formal** y **Traducir** (el idioma se elige en
  "Traducir a").
- **Después de pegar**: en Prompt o Mensaje puede mandar Enter solo, para enviar sin tocar nada.
- **Acciones rápidas**: Ordenar, Resumir y Corregir vienen listas. Se editan, se les pone atajo y se suman otras.

## 5. Preguntar (⌃⌥P)

Mantené ⌃⌥P y pedí algo: "respondele que el jueves puedo", "¿cómo se dice esto en inglés?". Con texto seleccionado,
trabaja sobre ese texto.

- Mientras hablás, la píldora dice **sobre qué va a trabajar** ("Sobre 34 palabras", "Sin selección · Safari").
- La respuesta aparece en una **tarjeta** que cambia según lo que muestra: texto con formato (listas, código con su
  Copiar), traducción ("Español → Inglés" y el original plegado), texto leído, links de un QR (con el dominio grande y
  Abrir solo con clic), el uso de Claude y Codex con barras, o un posteo con una pestaña por red. **↩** o **Pegar** la
  pega, **Copiar** la copia, **Esc** (o escribir en otro lado) la cierra.
- **Botones para seguir trabajando** debajo de la respuesta: Pasar a inglés/español (gratis con el traductor de Apple,
  punto verde), Reformular, Más corto, Más formal o casual, Resumir si es larga. **Deshacer** vuelve a la versión
  anterior.
- **Volvé a mantener ⌃⌥P** para ajustarla: "más corto", "más formal".
- Queda en el Historial como "Respuesta".

**Sin selección, mira la ventana:** "¿qué dice acá?", "resumime esta página" o "explicame este error" le pasan a la
IA el texto de la ventana de adelante (con "Mirar la ventana" y "Leer la pantalla" prendidos).

**Gratis, en la Mac y sin IA** (la ventanita dice "en la Mac"):
- **"Traducilo al inglés"** con texto seleccionado: usa el traductor de Apple. Necesita los idiomas bajados en
  Ajustes del Sistema › General › Idioma y región › Idiomas de traducción; si no están, lo traduce tu IA.
- **"Escaneame el QR"**: lee los códigos QR o de barras de la ventana (o de la imagen que copiaste). Muestra el link,
  nunca lo abre solo.
- **"Sacame el texto de acá"** o **"…de la imagen que copié"**: el texto de la ventana o de la imagen, listo para
  copiar o pegar.
- Mirar la ventana necesita el permiso de Grabación de pantalla.

## 5 bis. La Varita

Sacudí el mouse de un lado al otro y **la flecha se vuelve la Varita** (azul, con un brillo que gira por dentro). Lo
que tenés debajo se marca con un borde de los mismos colores, y abajo a la derecha del cursor aparece una cajita con
qué hacer:
- **Una caja de texto (o un texto seleccionado dentro de una):** Pasar a inglés/español, Reformular y Corregir lo
  **cambian ahí mismo**, como si lo hubieras escrito vos (**⌘Z** lo deshace). Una caja vacía ofrece **Dictá acá**.
- **Un texto que tenías seleccionado:** Leer en voz alta, Pasar a inglés/español, Resumir, Preguntá sobre esto. Si
  parece un error de un programa: **Arreglalo con Claude** y Explicame este error.
- **Una palabra o un nombre seleccionado** (hasta 4 palabras): **Sumar al diccionario**, como ⌃⌥D, en el lugar de
  Resumir o Reformular.
- **Una imagen:** **Describir** (tu IA la mira y te dice qué hay, en un par de segundos, con la imagen chiquita arriba),
  **Sacar prompt** (un prompt en inglés para recrearla con un generador de imágenes, siempre en alta resolución;
  en la tarjeta elegís el formato —Original, 1:1, Post 4:5, Historia 9:16 o 16:9—, **Cambiar algo** por voz («que
  sea de noche»), **Animarla** —pregunta si el video va vertical 9:16 u horizontal 16:9 y arma un prompt de 15
  segundos para usar con la imagen como referencia en Sora, Veo, Runway o Kling, con «Copiar imagen»—, pasarlo a
  español o hacerlo más detallado), Leer el QR (solo si tiene uno), Copiar imagen, Sacar el texto y Mandar a Claude o a
  Codex. Para preguntar algo más sobre la imagen, mantené el atajo de Preguntar con la tarjeta abierta.
  Describir y Sacar prompt usan una IA que vea imágenes (OpenAI, Claude, Grok u OpenRouter): la imagen viaja a ella
  solo cuando lo pedís. Sin una de esas, Describir dice lo que reconoce la Mac (gratis) y la pregunta va a Claude Code
  si está.
- **Un texto:** Pasar a inglés/español, Leer en voz alta, Resumir, Mandar a Claude, Copiar texto.
- **Un link:** ¿A dónde lleva?, Copiar link. **Una tabla:** Copiar como planilla.
- **Siempre, al final:** Modo captura: arrastrás un recuadro con la Varita y lo recortado queda elegido, con las
  mismas opciones que una imagen (también se hace directo con **⌥ + arrastrar**). Lo que usa IA solo aparece si tenés una configurada; Claude y Codex, solo si
  están en tu Mac.
- **Mandar a Claude / Codex** pega lo elegido en su ventana abierta (la terminal con Claude Code, la app de Claude o
  la de ChatGPT/Codex), con la página de donde viene, y empieza a escucharte para que le digas qué querés («quiero
  este botón en mi landing»). No aprieta Enter: lo mandás vos. Si no hay ninguna ventana abierta, queda copiado.
- **Leer en voz alta** usa las voces de la Mac, gratis. Si en la página Varita prendés «Con la voz de OpenAI», usa tu
  clave de OpenAI y suena como una persona, con acento rioplatense (cerca de 1,5 centavos de dólar por minuto).

Cómo se usa:
- **Clic** elige lo que está debajo (el clic no llega a la app, salvo en una caja de texto, que así queda activa).
  **Arrastrar** selecciona texto como siempre, y la cajita pasa a ofrecer qué hacer con eso.
- **⇧ + clic** suma más cosas: van a la cajita como miniaturas y quedan **copiadas juntas**; con varias, ofrece
  Copiar todas, Mandar a Claude o a Codex, Armar un collage o Preguntá sobre todas (tu IA las mira; sin una que vea imágenes, Claude Code).
- **Reconoce más que imágenes:**
  - **Un video** (de una página): Describir, Sacar prompt y **Copiar este cuadro** (la foto de lo que se ve, aunque
    esté andando).
  - **Un logo** (su texto lo dice, o es chico y lleva al inicio de la página): **Recrear logo** (un prompt para hacer
    uno original en ese estilo, con el texto entre comillas: con «Cambiar algo» le decís «que diga Halyon»), **Sacar
    colores**, Describir.
  - **Un banner** (una imagen ancha): **Recrear banner** (con sus textos), Describir, Sacar colores.
  - **Una sección, la ventana o un recorte:** **Hacer maqueta**: tu IA arma un resumen de diseño (qué es, estructura,
    textos tal cual —los lee de la página—, colores, tipografía y detalles), con **Mandar a Claude** para que la arme
    y **Prompt de imagen** para una maqueta visual.
  - **Sacar colores** es en la Mac y gratis: muestra cada color con su código y cuánto ocupa; clic en uno lo copia.
- **⌥ + rueda** (o el trackpad, o **⌥↑ / ⌥↓**) agranda lo marcado a lo que lo contiene: de una foto a su tarjeta, a
  la sección de la página y a la ventana entera (el borde dice «Sección · 2/4»); para el otro lado, se achica. Una
  sección o la ventana se trabajan como una imagen: Describir, Sacar prompt, Copiar, Sacar el texto, Mandar a Claude.
- **1…6** eligen una sugerencia; **Esc** suelta lo elegido y, otra vez, apaga. Se apaga sola a los 30 segundos sin
  usarla, al sacudir de nuevo o al pedir algo. La respuesta aparece al lado de donde estabas.
- Necesita Accesibilidad (ya la tenés) y, para copiar, mandar o leer imágenes, Grabación de pantalla.
- **En la página Varita del panel** están la sensibilidad de la sacudida, cuándo se apaga sola, si cambia el texto ahí
  mismo, Claude y Codex, buscar QR, la flecha (con un botón para devolver la de macOS), la voz para leer (con
  «Escuchar» para probarla) y los permisos.
- Si macOS agranda el cursor con el mismo gesto, apagá «Agitar el puntero para localizarlo» en Ajustes del Sistema ›
  Accesibilidad › Pantalla › Puntero.

## 5 ter. Postear con tus carpetas

En **Modos › Proyectos y marketing › Carpetas de marca y marketing** elegí tu carpeta de marketing (si tiene
`marcas/`, cada subcarpeta es una marca). Después, con ⌃⌥P: **"Armame un post para LinkedIn sobre Dixity"** o
**"el plan de contenidos de la semana para mi cafetería"**.
- Claude Code lo arma en esa carpeta, **solo leyendo** y con tu suscripción: lee la ficha de la marca y, si nombrás un
  producto de tus Carpetas de proyectos, su README.
- La tarjeta trae una pestaña por red, el contador de caracteres contra el límite de cada una y su Copiar.
- **Guardar borrador** (solo con clic) lo deja en `marcas/<marca>/organico/`. **Dixity nunca publica nada.**
- Si hay varias marcas y no nombrás ninguna, te pregunta cuál.

## 6. Claude y Codex por voz

Con la ventana del proyecto adelante (Terminal, Cursor, VS Code…), mantené ⌃⌥P y empezá con el nombre:
**"Claude, ¿por qué falla el login?"** o **"Codex, revisá las pruebas"**.

- Usa los programas `claude` y `codex` instalados en tu Mac, con tu suscripción.
- La carpeta del proyecto tiene que estar en **Modos › Proyectos › Carpetas de proyectos**. Si no, avisa
  "No sé en qué proyecto".
- **Primero solo mira**: Claude en modo plan, sin poder editar, y Codex en solo lectura. Mientras tanto seguís
  dictando. Cuando termina, suena y aparece la ventanita con la respuesta.
- **Hacelo con Claude** (o Codex): un botón que solo anda con clic. Ahí sí edita archivos del proyecto: Claude
  retoma la misma conversación y Codex trabaja dentro de la carpeta. **Nunca tiene permisos totales.**
- **"¿Cuánto me queda de Claude?"** (o de Codex, o "¿cuánto uso me queda?" para los dos) responde al instante, sin
  IA ni internet, con barras: cuánto usaste de la sesión y de la semana, cuánto te queda, cuándo se renueva y, en
  Claude, cuántas conversaciones abriste hoy en cada proyecto. El dato es de la última vez que usaste cada programa.

## 7. Diccionario

Nombres y palabras que Dixity tiene que escribir siempre bien. Para una corrección, escribí "cómo sale mal, cómo va".

- Se suman a mano, con **⌃⌥D** sobre una selección, con **Sumar al diccionario** de la Varita o con **Importar lista**.
- **Sugeridas por Dixity**: palabras que corrigió la IA, nombres de código, las que aparecen en tus ventanas y las
  que **corregiste a mano** después de pegar un dictado. Nunca entran solas: vos tocás Agregar o Descartar.

## 8. Voz (cómo escucha y qué mira)

- **Reconocimiento**: idioma (automático, español o inglés) y micrófono.
- **Mirar la ventana**: lee el texto alrededor del cursor y el nombre de la app, para seguir la frase y escribir bien
  los nombres.
- **Leer la pantalla**: lee el texto de la ventana de adelante en la Mac; la imagen no se guarda ni se manda.
- **Pasar en limpio**: limpiar con IA, limpieza básica sin IA, preferencias ("escribí con vos", "firmá como Ana") e
  **instrucciones por app o sitio** ("LinkedIn: tono profesional").
- **Memoria propia**: un resumen chico de cómo hablás y tus nombres. Se actualiza cada 12 dictados y se puede corregir
  o borrar.
- **Mientras dictás**: pausar la música y sonidos de empezar y terminar.

## 9. Historial

Las últimas 24 horas, con el audio. En cada dictado ves lo que escuchó, lo que pegó y qué servicio usó.
**Reprocesar** pasa el mismo audio por los servicios que tengas elegidos ahora, para comparar. **Vaciar** borra todo.

## 10. Privacidad

- **Contraseñas**: nunca lee campos de contraseña ni ventanas de gestores de contraseñas, y no guarda contraseñas en
  el portapapeles.
- **Claves**: lo que parece una clave en pantalla se tapa antes de mandarlo a la IA.
- **Datos**: ajustes, diccionario e historial viven en tu Mac (General › Tus datos › Ver carpeta).
- **Sin claves**, con "Todo en la Mac", nada sale de tu computadora.

## 11. Si algo no anda

- **El atajo no responde**: General › Permisos (Accesibilidad). Si recién actualizaste la app, macOS puede pedir los
  permisos de nuevo.
- **"No te escucho"**: revisá el micrófono en Voz › Reconocimiento.
- **Claude "no tiene la sesión iniciada"**: abrí `claude` en la Terminal y entrá con `/login`.
- **"No sé en qué proyecto"**: sumá la carpeta en Modos › Proyectos.
- **Salió mal un dictado**: ⌃⌥R lo vuelve a procesar. Si seleccionás lo que pegó antes, lo reemplaza.

## 12. Para quien programa

- `./compilar.sh` arma `build/Dixity.app`, y `./compilar.sh instalar` además la instala y la abre. Solo necesita las
  herramientas de línea de comandos de la Mac.
- `./probar.sh` corre las pruebas. Usan una carpeta y un llavero aparte, así que nunca tocan tus datos.
- La prueba con Claude y Codex de verdad (solo lectura, usa tu suscripción) se corre con
  `DIXITY_PRUEBA_REAL=1 ./probar.sh --filter AgentesDeVerdad`.
- `Dixity --capturas <carpeta>` dibuja todas las pantallas en PNG.
