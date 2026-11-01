import Foundation

// Los pedidos ya escritos que la Varita le pasa a Preguntar o que cambian el texto ahí mismo (antes los ofrecía el menú
// del mouse de la tanda 2, que la Varita reemplazó el 31/10/2026). Los que se pueden hacer en la Mac usan frases que
// EnLaMac reconoce ("traducilo al inglés"), así no gastan IA.
enum PedidoEscrito: Hashable {
    case traducir(String), resumir, reformular, corregir

    init?(_ p: Varita.Pedido) {
        switch p {
        case .traducir(let a): self = .traducir(a)
        case .resumir: self = .resumir
        case .reformular: self = .reformular
        case .corregir: self = .corregir
        default: return nil
        }
    }

    var instruccion: String {
        switch self {
        case .traducir(let a): "Traducilo al \(Respuestas.nombreIdioma(a))."
        case .resumir: "Resumí este texto en pocas líneas, con lo importante."
        case .reformular: "Reformulá este texto con otras palabras: mismo sentido, mismo idioma."
        case .corregir: "Corregí la ortografía, los acentos y la puntuación. No cambies las palabras, el tono ni el sentido."
        }
    }

    /// Lo que dice la píldora cuando lo cambió en su lugar ("Pasado a inglés · ⌘Z deshace").
    var hecho: String {
        switch self {
        case .traducir(let a): T("Pasado a \(Respuestas.nombreIdioma(a))", "Changed to \(Respuestas.nombreIdioma(a))")
        case .resumir: T("Resumido", "Summarized")
        case .reformular: T("Reformulado", "Rephrased")
        case .corregir: T("Corregido", "Fixed")
        }
    }
}

// Lo que la Varita le pide a tu IA sobre una imagen: va con la imagen (tu IA la mira) y responde en la tarjeta, en un
// par de segundos. Antes «Preguntar» sobre una imagen pasaba por Claude Code, que tardaba y avisaba al final
// (01/11/2026: «debería responder ahí mismo»). El texto queda como pedido en el historial y en la tarjeta.
enum PedidoImagen: Equatable {
    case describir, prompt
    case logo, banner, maqueta    // tanda 3 (01/11/2026): recrear un logo o un banner, y la maqueta de una sección

    /// `tam`: el tamaño de lo elegido, para que el prompt diga la proporción (un recorte no siempre es 16:9).
    func instruccion(tam: CGSize) -> String {
        switch self {
        case .describir:
            return T("Describí qué hay en esta imagen, en pocas líneas: qué es, lo importante que se ve y, si tiene texto, qué dice. Sin títulos.",
                     "Describe what's in this image in a few lines: what it is, the important things you see and, if it has text, what it says. No headings.")
        case .prompt:
            // En inglés: los generadores de imágenes lo entienden mejor. La tarjeta ofrece pasarlo a español.
            return "Write a prompt to recreate this image with an image generator (GPT Image, Midjourney, Flux). One paragraph "
                + "in English: subject, composition and framing, medium or camera and lens, lighting, color palette, textures, "
                + "mood and style. Describe the style instead of naming artists, and don't name real people or brands. End with "
                + "\"High resolution, sharp detail. Aspect ratio \(PedidoImagen.proporcion(tam)).\" Reply with the prompt only."
        case .logo:
            // Para hacer uno parecido con tu texto («me gusta, pero que diga…»): el texto va entre comillas, así
            // «Cambiar algo» lo reemplaza limpio. No nombra la marca: se describe como un logo original en ese estilo.
            return "Write a prompt to create an original logo in the same style as this one, with an image generator. One "
                + "paragraph in English: the symbol or icon (shapes, style), the exact text it shows in double quotes (or "
                + "\"no text\"), typography (style, weight, case, spacing), colors with hex codes, and layout (icon left of the "
                + "text, stacked…). Flat vector logo, centered on a plain white background, no mockup, no shadows. Don't name "
                + "the brand. End with \"High resolution, sharp detail. Aspect ratio 1:1.\" Reply with the prompt only."
        case .banner:
            return "Write a prompt to recreate this banner with an image generator. One paragraph in English: the exact "
                + "texts in double quotes and where each one goes, typography, the image or illustration, layout and "
                + "spacing, colors with hex codes, and style. Don't name real people or brands. End with \"High resolution, "
                + "sharp detail. Aspect ratio \(PedidoImagen.proporcion(tam)).\" Reply with the prompt only."
        case .maqueta:
            // Para rehacerla: lo que la persona le pasa a Claude (o convierte en un prompt de imagen). En español, para
            // que la lea; los textos de la sección llegan aparte, leídos de la página (Senalador.textos).
            return T("Armá un resumen de diseño de esta sección para rehacerla como maqueta. En viñetas cortas, con estos "
                     + "títulos: Qué es · Estructura (de arriba a abajo: bloques, columnas y qué hay en cada uno) · Textos "
                     + "(títulos, botones y frases importantes, tal cual) · Colores (con código hex) · Tipografía (estilo, "
                     + "pesos, tamaños aproximados) · Detalles (bordes, sombras, espacios, imágenes, íconos). Si te paso los "
                     + "textos de la página, usá esos tal cual. No nombres la marca.",
                     "Write a design brief of this section to rebuild it as a mockup. Short bullets under these headings: "
                     + "What it is · Structure (top to bottom: blocks, columns and what's in each) · Texts (headings, buttons and "
                     + "key lines, verbatim) · Colors (hex codes) · Typography (style, weights, approximate sizes) · Details "
                     + "(borders, shadows, spacing, images, icons). If I give you the page texts, use them verbatim. Don't name the brand.")
        }
    }

    /// De la maqueta a un prompt de imagen (el botón «Prompt de imagen» de su tarjeta): una captura de pantalla de esa
    /// sección, rehecha, para un generador de imágenes.
    static func instruccionPromptMaqueta(resumen: String, tam: CGSize) -> String {
        "<design_brief>\n\(resumen)\n</design_brief>\n\n"
            + "Turn this design brief (and the reference image) into a prompt for an image generator to create a "
            + "high-fidelity UI mockup of this section, as a flat website screenshot, no device frame. One paragraph in "
            + "English: layout top to bottom, the exact texts in double quotes, colors with hex codes, typography and style. "
            + "End with \"High resolution, sharp detail. Aspect ratio \(proporcion(tam)).\" Reply with the prompt only."
    }

    var titulo: String {
        switch self {
        case .describir: T("Lo que veo", "What I see")
        case .prompt, .logo, .banner: T("Prompt para recrearla", "Prompt to recreate it")
        case .maqueta: T("Maqueta", "Mockup")
        }
    }
    static var tituloVideo: String { T("Prompt para animarla", "Prompt to animate it") }

    /// Animarla: un prompt para una app de video que parte de la imagen (Sora, Veo, Runway, Kling), de 15 segundos
    /// (01/11/2026: los videos suelen durar eso). `formato`: "9:16" o "16:9", lo elegís en la tarjeta. Va con la
    /// imagen y con el prompt que ya se sacó, así respeta lo mismo.
    static func instruccionVideo(formato: String, promptImagen: String) -> String {
        let vertical = formato == "9:16"
        let tam = vertical ? "1080×1920" : "1920×1080"
        return "<image_prompt>\n\(promptImagen)\n</image_prompt>\n\n"
            + "Using this image as the reference first frame, write a prompt for an image-to-video generator (Sora, Veo, "
            + "Runway, Kling) to animate it into a 15-second clip, \(vertical ? "vertical" : "horizontal") \(formato). Keep the "
            + "subject, style, colors and lighting exactly as in the image (the image prompt above describes it). If the image "
            + "has a different shape, say how to reframe it to \(formato) keeping the main subject in frame. Plain text in "
            + "English, no markdown, with these parts:\n"
            + "- One opening paragraph: the scene and what must stay consistent.\n"
            + "- Camera: one clear, slow camera movement.\n"
            + "- Motion in three beats: 0–5 s, 5–10 s, 10–15 s (subject, background, light, particles).\n"
            + "- Sound: ambient sounds and music mood; no dialogue unless people are clearly talking.\n"
            + "- A last line: \"15 seconds, \(formato) \(vertical ? "vertical" : "horizontal"), \(tam), 24 fps, smooth natural "
            + "motion, no cuts, no text overlays.\"\n"
            + "Don't name real people or brands. Reply with the prompt only."
    }

    var clase: Respuestas.Clase {
        switch self {
        case .describir: .imagen
        case .prompt, .logo, .banner: .prompt
        case .maqueta: .maqueta
        }
    }

    /// La proporción más cercana de las comunes (16:9, 4:3, 1:1…), o la exacta si ninguna se parece.
    static func proporcion(_ tam: CGSize) -> String {
        guard tam.width > 0, tam.height > 0 else { return "1:1" }
        let r = tam.width / tam.height
        let comunes: [(String, CGFloat)] = [("1:1", 1), ("4:3", 4.0 / 3), ("3:4", 3.0 / 4), ("3:2", 1.5), ("2:3", 2.0 / 3),
                                           ("16:9", 16.0 / 9), ("9:16", 9.0 / 16), ("21:9", 21.0 / 9), ("4:5", 0.8), ("5:4", 1.25)]
        let mejor = comunes.min { abs($0.1 - r) < abs($1.1 - r) }!
        return abs(mejor.1 - r) / r < 0.06 ? mejor.0 : String(format: "%.2f:1", r)
    }
}
