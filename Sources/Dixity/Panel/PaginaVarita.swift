import AppKit
import SwiftUI

// Varita: cómo se prende, cómo se usa, qué ofrece según lo que señalás, sus opciones, la voz para leer y los permisos
// que necesita. Antes vivía como una tarjeta en Atajos (hasta el 31/10).
struct PaginaVarita: View {
    @ObservedObject var ajustes: Ajustes
    let motor: Motor
    let refresco: Int

    private var prendida: Bool { ajustes.datos.sacudirMouse }

    var body: some View {
        let _ = refresco
        TituloPagina(titulo: T("Varita", "Wonder"),
                     subtitulo: T("Sacudí el mouse y la flecha se vuelve una herramienta: señalás algo y al lado te ofrece qué hacer.",
                                  "Shake the mouse and the pointer becomes a tool: point at something and it offers what to do next to it."))
        Tarjeta {
            Fila(titulo: T("Prender la Varita al sacudir el mouse", "Turn on Wonder by shaking the mouse"),
                 detalle: T("De un lado al otro, rápido, unas cuatro veces. Sacudir de nuevo la apaga.",
                            "Side to side, quickly, about four times. Shake again to turn it off.")) {
                Toggle("", isOn: $ajustes.datos.sacudirMouse).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Sensibilidad", "Sensitivity"),
                 detalle: T("Si se te prende sola moviendo el mouse, bajala. Alta se prende con una sacudida corta.",
                            "If it turns on by itself while you move the mouse, lower it. High turns on with a short shake.")) {
                Segmentos(valor: $ajustes.datos.sensibilidadSacudida, opciones: DetectorSacudida.Sensibilidad.allCases, nombre: \.nombre)
                    .disabled(!prendida).opacity(prendida ? 1 : 0.5)
            }
            Fila(titulo: T("Se apaga sola", "Turns itself off"),
                 detalle: T("Cuando no la usás este rato. Esc también la apaga.", "When you don't use it for this long. Esc turns it off too."),
                 divisor: false) {
                Selector(valor: $ajustes.datos.varitaApagado, opciones: ApagadoVarita.allCases, nombre: \.nombre, ancho: 180)
                    .disabled(!prendida)
            }
        }

        Tarjeta(titulo: T("Cómo se usa", "How to use it")) {
            Fila(titulo: T("Elegir", "Pick"), detalle: T("Elige lo que está debajo. En una caja de texto, además, la deja activa para escribir ahí.",
                                                       "Picks what's under the pointer. In a text box it also makes it active, so typing goes there.")) {
                TeclaVisual(texto: T("Clic", "Click"))
            }
            Fila(titulo: T("Seleccionar texto", "Select text"), detalle: T("Como siempre: la cajita pasa a ofrecer qué hacer con lo seleccionado.",
                                                                          "As usual: the box then offers what to do with the selection.")) {
                TeclaVisual(texto: T("Arrastrar", "Drag"))
            }
            Fila(titulo: T("Juntar varias cosas", "Collect several things"),
                 detalle: T("Cada una va a la cajita como miniatura y quedan copiadas juntas. Después las podés mandar a Claude o a Codex.",
                            "Each one goes to the box as a thumbnail and they're copied together. Then you can send them to Claude or Codex.")) {
                TeclaVisual(texto: "⇧"); Text(verbatim: "+").foregroundStyle(Tema.apagado); TeclaVisual(texto: T("Clic", "Click"))
            }
            Fila(titulo: T("Elegir una opción", "Choose an option"), detalle: T("O tocala en la cajita.", "Or click it in the box.")) {
                TeclaVisual(texto: "1"); Text(verbatim: "…").foregroundStyle(Tema.apagado); TeclaVisual(texto: "6")
            }
            Fila(titulo: T("Soltar o apagar", "Let go or turn off"), detalle: T("La primera vez suelta lo elegido; la segunda, apaga la Varita.",
                                                                               "The first time it lets go of what you picked; the second, it turns Wonder off."),
                 divisor: false) {
                TeclaVisual(texto: "Esc")
            }
        }

        Tarjeta(titulo: T("Qué te ofrece", "What it offers")) {
            Ofrece(icono: "character.cursor.ibeam", color: 0x3B82F6, titulo: T("Una caja de texto", "A text box"),
                   detalle: T("Pasar a inglés o español, Reformular y Corregir, que lo cambian ahí mismo (⌘Z deshace). Vacía: Dictá acá.",
                              "Translate, Rephrase and Fix, changed right there (⌘Z undoes). Empty: Dictate here."))
            Ofrece(icono: "text.quote", color: 0x0EA5E9, titulo: T("Un texto seleccionado", "Selected text"),
                   detalle: T("Leer en voz alta, Pasar a inglés o español, Resumir y Preguntá sobre esto. Si parece un error: Arreglalo con Claude.",
                              "Read aloud, Translate, Summarize and Ask about this. If it looks like an error: Fix it with Claude."))
            Ofrece(icono: "photo", color: 0x14B8A6, titulo: T("Una imagen", "An image"),
                   detalle: T("Copiar imagen, Leer el QR (si tiene uno), Mandar a Claude o a Codex, Sacar el texto y Preguntale a Claude.",
                              "Copy image, Read the QR (if it has one), Send to Claude or Codex, Grab the text and Ask Claude."))
            Ofrece(icono: "square.on.square", color: 0xFF4F9A, titulo: T("Varias cosas juntas", "Several things"),
                   detalle: T("Copiar todas juntas, Mandar a Claude o a Codex, Armar un collage y Preguntale a Claude.",
                              "Copy all together, Send to Claude or Codex, Make a collage and Ask Claude."))
            Ofrece(icono: "link", color: 0x6366F1, titulo: T("Un link o una tabla", "A link or a table"),
                   detalle: T("¿A dónde lleva?, Copiar link y Copiar como planilla.", "Where does it go?, Copy link and Copy as spreadsheet."))
            Ofrece(icono: "camera.viewfinder", color: 0xF59E0B, titulo: T("Siempre", "Always"),
                   detalle: T("Modo captura, al final. Lo que usa IA aparece solo si tenés una configurada en Proveedores.",
                              "Capture mode, at the end. Anything that uses AI only shows up if you set one up in Providers."),
                   divisor: false)
        }

        Tarjeta(titulo: T("Opciones", "Options")) {
            Fila(titulo: T("Cambiar el texto ahí mismo", "Change the text in place"),
                 detalle: T("Donde se puede escribir, traducir, reformular o corregir reemplaza el texto como si lo hubieras escrito vos. Apagado, te lo muestra en una tarjeta para copiarlo o pegarlo.",
                            "Where you can type, translating, rephrasing or fixing replaces the text as if you'd typed it. Off, it shows it in a card to copy or paste.")) {
                Toggle("", isOn: $ajustes.datos.varitaReemplaza).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Claude y Codex", "Claude and Codex"),
                 detalle: T("Ofrece Mandar a Claude o a Codex (pega lo elegido en su ventana abierta, sin apretar Enter) y Preguntale a Claude (mira la imagen y responde en la tarjeta). Solo aparecen si están en tu Mac.",
                            "Offers Send to Claude or Codex (pastes what you picked into its open window, without pressing Enter) and Ask Claude (looks at the image and answers in the card). They only show up if they're on your Mac.")) {
                Toggle("", isOn: $ajustes.datos.varitaAgentes).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Buscar QR en las imágenes", "Look for QR codes in images"),
                 detalle: T("Cuando dejás el mouse quieto sobre una imagen, mira si tiene un QR para ofrecer leerlo. Apagado, usa un poco menos de memoria.",
                            "When you rest the pointer on an image, it checks for a QR code to offer reading it. Off, it uses a bit less memory.")) {
                Toggle("", isOn: $ajustes.datos.varitaQR).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("La flecha de la Varita", "Wonder's pointer"),
                 detalle: T("Mientras está prendida, la flecha se vuelve azul, con un brillo que gira. Si alguna vez te queda una flecha rara, tocá Devolver; cerrar sesión siempre trae la de macOS.",
                            "While it's on, the pointer turns blue with a spinning glow. If you're ever left with an odd pointer, click Restore; logging out always brings back macOS's."),
                 divisor: false) {
                BotonSecundario(texto: T("Devolver", "Restore"), icono: "cursorarrow") { motor.devolverFlecha() }
                Toggle("", isOn: $ajustes.datos.varitaFlecha).toggleStyle(.switch).labelsHidden()
            }
        }

        Tarjeta(titulo: T("Leer en voz alta", "Read aloud")) {
            Fila(titulo: T("Con la voz de OpenAI", "With OpenAI's voice"),
                 detalle: T("Suena como una persona, con acento rioplatense. Usa tu clave de OpenAI de Proveedores: cerca de 1,5 centavos de dólar por minuto leído. Apagado (o sin clave), lee con las voces de la Mac, gratis.",
                            "Sounds like a real person. Uses your OpenAI key from Providers: about 1.5 US cents per minute read. Off (or with no key), it reads with the Mac's voices, for free.")) {
                Toggle("", isOn: $ajustes.datos.leerConOpenAI).toggleStyle(.switch).labelsHidden()
            }
            Fila(titulo: T("Probar la voz", "Try the voice"),
                 detalle: T("Lee una frase corta con la voz elegida. Esc la para.", "Reads a short sentence with the chosen voice. Esc stops it."),
                 divisor: false) {
                BotonSecundario(texto: T("Escuchar", "Listen"), icono: "speaker.wave.2.fill") { motor.probarVoz() }
            }
        }

        Tarjeta(titulo: T("Permisos", "Permissions")) {
            Fila(titulo: T("Accesibilidad", "Accessibility"),
                 detalle: T("Para saber qué hay debajo del puntero y escribir en la caja que señalás.",
                            "To know what's under the pointer and type into the box you point at.")) {
                Etiqueta(ok: Cursor.accesibilidadPermitida)
            }
            Fila(titulo: T("Grabación de pantalla", "Screen Recording"),
                 detalle: T("Para copiar, mandar o leer imágenes y buscar QR. La foto es solo de lo que elegís; la que mandás a Claude o Codex se borra al día.",
                            "To copy, send or read images and look for QR codes. The picture is only of what you pick; what you send to Claude or Codex is deleted after a day.")) {
                if Pantalla.permitido { Etiqueta(ok: true) }
                else { BotonSecundario(texto: T("Permitir", "Allow"), icono: "rectangle.dashed") { Pantalla.pedirPermiso() } }
            }
            Fila(titulo: T("Si macOS agranda el cursor al sacudir", "If macOS enlarges the pointer when you shake"),
                 detalle: T("Apagá «Agitar el puntero para localizarlo» en Ajustes del Sistema › Accesibilidad › Pantalla › Puntero.",
                            "Turn off “Shake mouse pointer to locate” in System Settings › Accessibility › Display › Pointer."),
                 divisor: false) { EmptyView() }
        }
    }
}

// Una fila de "Qué te ofrece": ícono de color, qué señalás y qué opciones aparecen.
private struct Ofrece: View {
    let icono: String
    let color: UInt32
    let titulo: String
    let detalle: String
    var divisor = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icono).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: color)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(titulo).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                    Text(detalle).font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            if divisor { Rectangle().fill(Tema.bordeSuave).frame(height: 1).padding(.leading, 56) }
        }
    }
}
