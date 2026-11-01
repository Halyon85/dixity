import AppKit
import CoreImage
import Foundation
import Testing
@testable import Dixity

// Preguntar sin IA (31/10/2026): traducir con el traductor de Apple, sacar texto y leer QR con Vision.
@Suite(.serialized) struct PreguntarEnLaMac {
    init() { Ayudas.preparar() }

    @Test func reconoceLosPedidosQueSeHacenEnLaMac() {
        #expect(EnLaMac.entender("Traducí esto al inglés.") == .traducir(destino: "en"))
        #expect(EnLaMac.entender("traducilo") == .traducir(destino: nil))
        #expect(EnLaMac.entender("Translate this to Portuguese") == .traducir(destino: "pt"))
        #expect(EnLaMac.entender("Escaneame el QR") == .escanear(deCopiada: false))
        #expect(EnLaMac.entender("leé el código de barras de la imagen que copié") == .escanear(deCopiada: true))
        #expect(EnLaMac.entender("Sacame el texto de esta imagen") == .leerTexto(deCopiada: false))
        #expect(EnLaMac.entender("copiame el texto de la imagen copiada") == .leerTexto(deCopiada: true))
        // Lo que tiene que pensar va a la IA.
        #expect(EnLaMac.entender("Traducilo al inglés y hacelo más formal") == nil)
        #expect(EnLaMac.entender("resumime esto") == nil)
        #expect(EnLaMac.entender("¿Qué dice acá?") == nil)
        #expect(EnLaMac.entender("Escribile a Juan que el texto del contrato lo mando mañana a la tarde sin falta, así lo revisa") == nil)
    }

    @Test func sabeCuandoHablaDeLoQueSeVe() {
        #expect(EnLaMac.hablaDeLoVisible("¿Qué dice acá?"))
        #expect(EnLaMac.hablaDeLoVisible("resumime esta página"))
        #expect(EnLaMac.hablaDeLoVisible("explicame este error"))
        #expect(!EnLaMac.hablaDeLoVisible("un mail para pedir presupuesto"))
        #expect(!EnLaMac.hablaDeLoVisible("¿cómo se dice plazo de entrega en inglés?"))
    }

    @Test func leeUnQR() throws {
        let filtro = try #require(CIFilter(name: "CIQRCodeGenerator"))
        filtro.setValue(Data("https://halyon.team".utf8), forKey: "inputMessage")
        let qr = try #require(filtro.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let imagen = try #require(CIContext().createCGImage(qr, from: qr.extent.insetBy(dx: -40, dy: -40)))
        #expect(EnLaMac.codigos(en: imagen) == ["https://halyon.team"])
    }

    @Test func laVentanaVaComoContenidoSoloSinSeleccion() {
        let u = Prompts.usuarioRespuesta(pedido: "¿qué dice acá?", seleccion: "", anterior: nil, contexto: nil, terminos: [],
                                         extra: "", ventana: "Factura 0001 · Total $ 5.000")
        #expect(u.contains("<texto_de_la_ventana>\nFactura 0001 · Total $ 5.000\n</texto_de_la_ventana>"))
        #expect(u.hasSuffix("(El pedido es sobre el texto de la ventana de arriba.)"))
        let conSeleccion = Prompts.usuarioRespuesta(pedido: "resumilo", seleccion: "Hola", anterior: nil, contexto: nil,
                                                    terminos: [], extra: "", ventana: "otra cosa")
        #expect(!conSeleccion.contains("texto_de_la_ventana"))
    }
}

// A mano: `DIXITY_PRUEBA_REAL=1 ./probar.sh --filter TraductorDeVerdad`. Usa los idiomas de traducción bajados en
// esta Mac; si no están, la traducción va a la IA y la prueba lo dice.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DIXITY_PRUEBA_REAL"] != nil))
struct TraductorDeVerdad {
    @Test func traduceEnLaMac() async {
        let r = await EnLaMac.traducir("Mañana a primera hora te mando el informe.\n\nGracias por esperar.", a: "en", idiomaPersona: "es")
        print("TRADUCCIÓN:", r ?? "(no se pudo en la Mac: falta bajar español o inglés en Idiomas de traducción)")
        if let r { #expect(r.lowercased().contains("report") && r.contains("\n\n")) }
    }
}
