import AppKit
import Testing
@testable import Dixity

// El modo Cifras (01/11/2026): números en palabras a cifras, con el formato del país y según dónde se escribe.
@Suite(.serialized) struct CifrasPruebas {
    init() { Ayudas.preparar() }

    private let ar = Cifras.Formato.de(.automatico, locale: Locale(identifier: "es_AR"))
    private let us = Cifras.Formato.de(.automatico, locale: Locale(identifier: "en_US"))

    private func doc(_ t: String, _ f: Cifras.Formato? = nil) -> String { Cifras.escribir(t, destino: .documento, formato: f ?? ar).texto }
    private func hoja(_ t: String, _ f: Cifras.Formato? = nil) -> String { Cifras.escribir(t, destino: .planilla, formato: f ?? ar).texto }

    @Test func losNumerosEnPalabrasPasanACifras() {
        #expect(doc("un millón") == "1.000.000")
        #expect(doc("un millón doscientos") == "1.000.200")
        #expect(doc("un millón doscientos mil") == "1.200.000")
        #expect(doc("quinientos cincuenta y cinco") == "555")
        #expect(doc("mil novecientos noventa y nueve") == "1999")   // 4 cifras, sin punto, como se escribe
        #expect(doc("dos mil millones") == "2.000.000.000")
        #expect(doc("veintiún mil") == "21.000")
        #expect(doc("cien mil") == "100.000")
        #expect(doc("ciento cinco") == "105")
        #expect(doc("5 mil") == "5000")
        #expect(doc("two hundred and five", us) == "205")
        #expect(doc("one million two hundred thousand", us) == "1,200,000")
        #expect(doc("twenty-one", us) == "21")
    }

    @Test func monedasDecimalesYPorcentajes() {
        #expect(doc("dólares mil doscientos") == "US$ 1.200,00")
        #expect(doc("mil doscientos dólares") == "US$ 1.200,00")
        #expect(doc("pesos mil doscientos") == "$ 1.200,00")
        #expect(doc("mil ciento cincuenta con treinta y cinco") == "1150,35")
        #expect(doc("1150 con 35") == "1150,35")
        #expect(doc("1150 con 35 pesos") == "$ 1.150,35")
        #expect(doc("doce con cincuenta euros") == "€ 12,50")
        #expect(doc("doce con cincuenta euros", Cifras.Formato.de(.automatico, locale: Locale(identifier: "es_ES"))) == "12,50 €")
        #expect(doc("veinte por ciento") == "20 %")
        #expect(doc("one thousand two hundred dollars", us) == "$1,200.00")
        #expect(doc("twenty percent", us) == "20%")
    }

    @Test func enUnaPlanillaVaElNumeroPelado() {
        #expect(hoja("dólares mil doscientos") == "1200")
        #expect(hoja("mil ciento cincuenta con treinta y cinco") == "1150,35")
        #expect(hoja("un millón") == "1000000")
        #expect(hoja("veinte por ciento") == "20%")
        #expect(hoja("Mil doscientos.") == "1200")    // sin el punto que agrega la voz a texto
        #expect(hoja("one thousand two hundred point five", us) == "1200.5")
    }

    @Test func loQueNoEsUnNumeroQuedaComoLoDijiste() {
        #expect(doc("una factura para Juan") == "una factura para Juan")
        #expect(doc("dos cajas de tornillos") == "2 cajas de tornillos")
        #expect(doc("llamame al 11 4567 8901") == "llamame al 11 4567 8901")   // cifras solas: no se suman
        #expect(doc("en 2026") == "en 2026")
        #expect(doc("a thousand thanks", us) == "1000 thanks")
        #expect(doc("a car", us) == "a car")
    }

    @Test func elCUITVaConGuionesYSeRevisa() {
        // 20-12345678-6 es válido (dígito verificador 6); con un 9 al final, no.
        #expect(Cifras.escribir("CUIT 20 12345678 6", destino: .documento, formato: ar) == .init(texto: "20-12345678-6", aviso: nil))
        let mal = Cifras.escribir("CUIT 20 12345678 9", destino: .documento, formato: ar)
        #expect(mal.texto == "20-12345678-9" && mal.aviso != nil)
        #expect(doc("el CUIT es 20-12345678-6") == "el CUIT 20-12345678-6")
        #expect(Cifras.hayCUITMal("20-12345678-9") && !Cifras.hayCUITMal("20-12345678-6"))
        // Como lo escribe de verdad la voz a texto (historial del 01/11): «Quit», con comas, de a pares, sin la «y».
        #expect(doc("Quit, veinte, doce, treinta y cuatro, cinco, seis, siete, ocho, seis.") == "20-12345678-6")
        #expect(doc("Quit veinte doce treinta cuatro cincuenta y seis setenta ocho seis") == "20-12345678-6")
        #expect(hoja("cuil 27 onze 22 33 44 5") == Cifras.escribir("cuil 27 11 22 33 44 5", destino: .planilla, formato: ar).texto)
        // Sin la palabra: solo si es todo lo dictado y el dígito verificador da.
        #expect(doc("Veinte, doce, treinta y cuatro, cincuenta y seis, setenta y ocho, seis.") == "20-12345678-6")
        #expect(doc("Veinte, treinta y uno, ochenta y cinco, once, ochenta y cinco.") == "20, 31, 85, 11, 85.")
        #expect(doc("quit smoking") == "quit smoking")
    }

    @Test func sabeSiEstasEnUnaPlanilla() {
        #expect(Cifras.destino(ContextoCursor(app: "Microsoft Excel")) == .planilla)
        #expect(Cifras.destino(ContextoCursor(app: "Numbers")) == .planilla)
        #expect(Cifras.destino(ContextoCursor(app: "LibreOffice", ventana: "Facturas.ods - LibreOffice Calc")) == .planilla)
        #expect(Cifras.destino(ContextoCursor(app: "Google Chrome", ventana: "Ventas 2026 - Hojas de cálculo de Google")) == .planilla)
        #expect(Cifras.destino(ContextoCursor(app: "Google Chrome", ventana: "Comprobantes en línea")) == .documento)
        // En Automático, una planilla o un programa de facturación elige Cifras.
        let a = Ajustes.shared
        let antes = a.datos.estilo
        a.datos.estilo = .automatico
        #expect(a.estiloPara(ContextoCursor(app: "Microsoft Excel")) == .cifras)
        #expect(a.estiloPara(ContextoCursor(app: "Safari", bundle: "com.apple.Safari", ventana: "Xubio - Facturación")) == .cifras)
        a.datos.estilo = antes
    }
}
