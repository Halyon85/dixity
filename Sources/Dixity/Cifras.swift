import AppKit

// El modo Cifras (01/11/2026): para planillas y facturas. Lo dicho con números en palabras pasa a cifras con reglas
// fijas, en la Mac, sin IA: un monto no puede depender de que la IA no se equivoque. Lo llama el Motor al dictar en
// ese modo (o en Automático, en una planilla o un programa de facturación).
//
// - «un millón doscientos mil» → 1.200.000 · «mil ciento cincuenta con treinta y cinco» → 1.150,35
// - «dólares mil doscientos» o «mil doscientos dólares» → US$ 1.200,00 (en una Mac de EE. UU., $1,200.00)
// - «veinte por ciento» → 20 % · «CUIT 20 12345678 9» → 20-12345678-9 (y avisa si el dígito verificador no da)
// - En una planilla va el número pelado (1200,35 o 20%), para que la planilla lo tome como número y se pueda sumar.
//   En lo demás (una factura en el navegador, un documento), con formato: miles, decimales y el signo de la moneda.
// - El formato sale del país de la Mac (coma o punto para los decimales); se puede fijar en Modos › Cifras.
// - Entiende español e inglés. Lo que no es un número queda como lo dijiste.
enum Cifras {
    /// Dónde se escribe: en una planilla, el número sin adornos; en lo demás, con formato.
    enum Destino { case planilla, documento }

    struct Resultado: Equatable {
        var texto: String
        var aviso: String?     // un CUIT con el dígito verificador que no da, para mostrarlo en la píldora
    }

    // MARK: Dónde estás

    /// Planillas: por el nombre de la app o por el título de la ventana (Google Sheets en el navegador, un .xlsx en
    /// LibreOffice u OpenOffice, que son una sola app para todo).
    static func destino(_ c: ContextoCursor?) -> Destino {
        guard let c else { return .documento }
        let app = c.app.lowercased(), titulo = c.ventana.lowercased()
        if ["excel", "numbers"].contains(where: app.contains) { return .planilla }
        let pistas = ["google sheets", "hojas de cálculo", "hojas de calculo", "planilhas", "libreoffice calc", "openoffice calc",
                      "- calc", "— calc", ".xlsx", ".xls", ".ods", ".csv", ".numbers", "airtable", "smartsheet", "zoho sheet"]
        return pistas.contains(where: titulo.contains) ? .planilla : .documento
    }

    // MARK: El formato

    /// Coma o punto para los decimales. Automático: el del país de la Mac.
    struct Formato: Equatable {
        var decimal: String
        var miles: String
        var locale: Locale
        static func de(_ elegido: FormatoCifras, locale: Locale = .current) -> Formato {
            switch elegido {
            case .automatico: Formato(decimal: locale.decimalSeparator ?? ",", miles: locale.groupingSeparator ?? ".", locale: locale)
            case .coma: Formato(decimal: ",", miles: ".", locale: locale)
            case .punto: Formato(decimal: ".", miles: ",", locale: locale)
            }
        }
    }

    // MARK: Escribir

    static func escribir(_ dicho: String, destino: Destino, formato: Formato) -> Resultado {
        let fichas = Ficha.partir(dicho)
        var aviso: String?
        var i = 0
        var salida: [(String, Bool)] = []      // (texto, es un número armado) para saber qué pegar con espacio
        while i < fichas.count {
            if let cuit = leerCUIT(fichas, desde: i) {
                // Dicho solo («CUIT 20 …»), va el número solo, para el campo; en una frase, la palabra queda.
                let solo = i == 0 && fichas[cuit.hasta...].allSatisfy { $0.texto.first.map { ".,;".contains($0) } ?? true }
                // «el CUIT es …»: la palabra queda, bien escrita (la voz a texto pone «Quit»).
                if !solo, palabrasCUIT.contains(fichas[i].clave) { salida.append((fichas[i].clave.hasSuffix("l") ? "CUIL" : "CUIT", false)) }
                salida.append((cuit.texto, true))
                if !cuit.valido { aviso = T("Revisá el CUIT: el último número no coincide.", "Check the tax ID: the last digit doesn't match.") }
                i = cuit.hasta
                continue
            }
            if let n = leerMonto(fichas, desde: i, locale: formato.locale) {
                // Cifras solas, sin palabras, moneda, porcentaje ni decimales ("1200", "11 4567 8901"): como vinieron.
                if n.enPalabras { salida.append((escribirMonto(n, destino: destino, formato: formato), true)) }
                else { salida += fichas[i..<n.hasta].map { ($0.texto, true) } }
                i = n.hasta
                continue
            }
            salida.append((fichas[i].texto, false))
            i += 1
        }
        // Un número solo, sin el punto que agrega la voz a texto ("1200."), para que la planilla lo tome como número.
        if salida.count == 2, salida[0].1, [".", "…"].contains(salida[1].0) { salida.removeLast() }
        return Resultado(texto: unir(salida), aviso: aviso)
    }

    // Une las fichas con espacios, salvo antes de la puntuación.
    private static func unir(_ partes: [(String, Bool)]) -> String {
        var t = ""
        for (p, _) in partes {
            let pegado = p.first.map { ".,;:!?…)%".contains($0) } ?? false
            if !t.isEmpty && !pegado && !(t.last.map { "¿¡(".contains($0) } ?? false) { t += " " }
            t += p
        }
        return t
    }

    // MARK: Fichas

    struct Ficha: Equatable {
        var texto: String       // tal como vino
        var clave: String       // en minúscula y sin tildes, para comparar
        static func partir(_ s: String) -> [Ficha] {
            // Palabras (con guión: "twenty-one"), números con sus separadores ("1.200,35", "20-12345678-9"), signos.
            let patron = #"[\p{L}]+(?:-[\p{L}]+)*|\$|US\$|€|£|%|\d+(?:[.,\-]\d+)*|[^\s\p{L}\d]"#
            guard let re = try? NSRegularExpression(pattern: patron) else { return [] }
            return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
                Range(m.range, in: s).map { r in
                    let t = String(s[r])
                    return Ficha(texto: t, clave: t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
                }
            }
        }
    }

    // MARK: Números en palabras

    private static let unidades: [String: Int] = [
        "cero": 0, "uno": 1, "una": 1, "un": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7,
        "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
        "dieciseis": 16, "diecisiete": 17, "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiuno": 21, "veintiun": 21,
        "veintiuna": 21, "veintidos": 22, "veintitres": 23, "veinticuatro": 24, "veinticinco": 25, "veintiseis": 26,
        "veintisiete": 27, "veintiocho": 28, "veintinueve": 29, "treinta": 30, "cuarenta": 40, "cincuenta": 50,
        "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90,
        "cien": 100, "ciento": 100, "doscientos": 200, "doscientas": 200, "trescientos": 300, "trescientas": 300,
        "cuatrocientos": 400, "cuatrocientas": 400, "quinientos": 500, "quinientas": 500, "seiscientos": 600,
        "seiscientas": 600, "setecientos": 700, "setecientas": 700, "ochocientos": 800, "ochocientas": 800,
        "novecientos": 900, "novecientas": 900,
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let multiplicadores: [String: Decimal] = [
        "mil": 1000, "thousand": 1000, "millon": 1_000_000, "millones": 1_000_000, "million": 1_000_000,
        "millions": 1_000_000, "billion": 1_000_000_000, "billon": 1_000_000_000_000, "billones": 1_000_000_000_000,
    ]
    // "un", "una" y "a" solo son un número antes de "mil", "millón"…: "una factura" no es "1 factura".
    private static let soloAntesDeMultiplicador: Set<String> = ["un", "una", "a"]

    /// El valor de una ficha que es parte de un número: una palabra («veinte», «twenty-one») o cifras («1.200»).
    private static func valor(_ f: Ficha) -> Decimal? {
        if let n = unidades[f.clave] { return Decimal(n) }
        let partes = f.clave.split(separator: "-")
        if partes.count == 2, let d = unidades[String(partes[0])], let u = unidades[String(partes[1])], d >= 20, d % 10 == 0, u < 10 {
            return Decimal(d + u)
        }
        return cifra(f.texto)
    }

    /// Cifras como las escribe la voz a texto: "1200", "1.200" o "1,200" (miles), "1,5" o "1.5" (decimales).
    static func cifra(_ t: String) -> Decimal? {
        guard t.first?.isNumber == true, !t.contains("-") else { return nil }
        let grupos = t.split(whereSeparator: { $0 == "." || $0 == "," })
        // Con todos los grupos de 3 después del primero, son miles; si no, el último separador es la coma decimal.
        if grupos.count > 1, grupos.dropFirst().allSatisfy({ $0.count == 3 }) {
            return Decimal(string: grupos.joined())
        }
        if let ultimo = t.lastIndex(where: { $0 == "." || $0 == "," }) {
            let entera = t[..<ultimo].filter(\.isNumber), dec = t[t.index(after: ultimo)...]
            return Decimal(string: entera + "." + dec)
        }
        return Decimal(string: t)
    }

    // MARK: Montos

    struct Monto: Equatable {
        var valor: Decimal
        var decimales: String?   // "35" de «con treinta y cinco», tal cual se dijo
        var moneda: String?      // código ISO: "USD", "ARS", "EUR"…
        var porcentaje = false
        var hasta: Int           // la primera ficha después del monto
        var enPalabras: Bool     // se dijo con palabras (o con moneda, porcentaje o decimales): se reescribe
    }

    private static let monedas: [String: String] = [
        "dolar": "USD", "dolares": "USD", "dollar": "USD", "dollars": "USD", "usd": "USD", "us$": "USD", "u$s": "USD",
        "euro": "EUR", "euros": "EUR", "€": "EUR", "eur": "EUR", "real": "BRL", "reales": "BRL", "libra": "GBP",
        "libras": "GBP", "pound": "GBP", "pounds": "GBP", "£": "GBP", "yen": "JPY", "yenes": "JPY", "soles": "PEN",
    ]
    private static let pesos: Set<String> = ["peso", "pesos", "$"]

    /// La moneda de una ficha (las de pesos, la del país de la Mac: argentinos en Argentina, mexicanos en México…).
    private static func moneda(_ f: Ficha, locale: Locale) -> String? {
        if let m = monedas[f.clave] { return m }
        guard pesos.contains(f.clave) else { return nil }
        let local = locale.currency?.identifier ?? ""
        return ["ARS", "MXN", "CLP", "COP", "UYU", "DOP", "PHP", "CUP"].contains(local) ? local
            : f.clave == "$" && !local.isEmpty ? local : "ARS"
    }

    /// Un monto desde la ficha `i`: «dólares» (opcional), el número en palabras o cifras, «con …» (opcional) y
    /// «dólares», «por ciento»… (opcional). Nil si ahí no empieza un número.
    static func leerMonto(_ f: [Ficha], desde i: Int, locale: Locale = .current) -> Monto? {
        var j = i
        var mon = j < f.count ? moneda(f[j], locale: locale) : nil
        if mon != nil { j += 1 }
        guard let (valor, palabras, fin) = leerNumero(f, desde: j) else { return nil }
        j = fin
        var decimales: String?
        // «con treinta y cinco», «coma cinco», «punto cinco», «point five»
        if j + 1 < f.count, ["con", "coma", "punto", "point"].contains(f[j].clave),
           let (d, _, finD) = leerNumero(f, desde: j + 1), d >= 0, (d as NSDecimalNumber).doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            decimales = "\(d)"
            j = finD
            if j < f.count, ["centavos", "centavo", "cents", "cent"].contains(f[j].clave) { j += 1 }
        }
        var porcentaje = false
        if mon == nil, j < f.count, let m = moneda(f[j], locale: locale) { mon = m; j += 1 }
        if j < f.count, f[j].clave == "%" || f[j].clave == "percent" { porcentaje = true; j += 1 }
        else if j + 1 < f.count, f[j].clave == "por", f[j + 1].clave == "ciento" { porcentaje = true; j += 2 }
        let especial = mon != nil || porcentaje || decimales != nil
        return Monto(valor: valor, decimales: decimales, moneda: mon, porcentaje: porcentaje, hasta: j, enPalabras: palabras || especial)
    }

    /// Un número entero (o en cifras) desde `i`: su valor, si tenía palabras y dónde termina.
    private static func leerNumero(_ f: [Ficha], desde i: Int) -> (Decimal, Bool, Int)? {
        var grande: Decimal = 0, miles: Decimal = 0, actual: Decimal = 0
        var j = i, algo = false, palabras = false, cifras = 0
        var anterior: Decimal?   // el valor de la palabra anterior, para «treinta y cinco»
        var trasY = false
        while j < f.count {
            let k = f[j].clave
            if let m = multiplicadores[k] {
                // «mil» solo es mil; «un millón», «dos mil millones», «cien mil».
                if m >= 1_000_000 { grande += max(miles + actual, 1) * m; miles = 0 } else { miles += max(actual, 1) * m }
                actual = 0; algo = true; palabras = true; anterior = m; trasY = false; j += 1; continue
            }
            if soloAntesDeMultiplicador.contains(k) {
                guard j + 1 < f.count, multiplicadores[f[j + 1].clave] != nil, !algo else { break }
                actual = 1; j += 1; continue
            }
            if k == "hundred", algo { actual = max(actual, 1) * 100; palabras = true; anterior = 100; trasY = false; j += 1; continue }
            // «y» / «and» solo entre partes de un número: «treinta y cinco», «two hundred and five».
            if (k == "y" || k == "and"), algo, j + 1 < f.count, let sig = valor(f[j + 1]), f[j + 1].texto.first?.isLetter == true,
               let a = anterior, (k == "y" ? a >= 20 && a < 100 && sig < 10 : a >= 100 && sig < 100) {
                trasY = true; j += 1; continue
            }
            guard let v = valor(f[j]) else { break }
            let esCifra = f[j].texto.first?.isNumber == true
            // Dos cifras seguidas son dos números ("11 4567 8901" no se suma); una cifra sigue a palabras solo antes
            // de "mil" o "millones" ("5 mil").
            if esCifra && algo { break }
            if esCifra { cifras += 1 } else { palabras = true }
            // Dos números chicos seguidos ("dos tres", "veinte cinco") son dos números; «treinta y cinco», «ciento
            // cinco» o «mil dos», uno solo.
            if algo, !esCifra, !trasY, let a = anterior, a < 100, v < 100 { break }
            actual += v; algo = true; anterior = v; trasY = false; j += 1
        }
        guard algo else { return nil }
        return (grande + miles + actual, palabras, j)
    }

    private static func escribirMonto(_ m: Monto, destino: Destino, formato: Formato) -> String {
        // Sin palabras, moneda, porcentaje ni decimales ("1200", "11 4567"): como vino.
        var valor = m.valor
        if let d = m.decimales, let extra = Decimal(string: "0." + d) { valor += extra }
        let decimales = m.decimales?.count ?? (valor.esEntero ? 0 : 2)
        let nf = NumberFormatter()
        nf.locale = formato.locale
        nf.decimalSeparator = formato.decimal
        nf.groupingSeparator = formato.miles
        nf.currencyDecimalSeparator = formato.decimal
        nf.currencyGroupingSeparator = formato.miles
        if destino == .planilla {
            // La planilla lo toma como número (y lo suma): sin miles ni signo; el porcentaje con su %.
            nf.numberStyle = .decimal
            nf.usesGroupingSeparator = false
            nf.minimumFractionDigits = decimales; nf.maximumFractionDigits = max(decimales, 6)
            let t = nf.string(from: valor as NSDecimalNumber) ?? "\(valor)"
            return m.porcentaje ? t + "%" : t
        }
        if let codigo = m.moneda {
            nf.numberStyle = .currency
            nf.currencyCode = codigo
            // En Argentina el dólar es US$ y el peso $ (lo hace el formato de Apple). Donde Apple pone el código
            // ("EUR 12,50"), va el signo.
            let signos = ["EUR": "€", "GBP": "£", "JPY": "¥", "BRL": "R$"]
            if nf.currencySymbol == codigo, let signo = signos[codigo] { nf.currencySymbol = signo }
            return sinEspacioDuro(nf.string(from: valor as NSDecimalNumber) ?? "\(valor)")
        }
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = decimales; nf.maximumFractionDigits = max(decimales, 6)
        // Los de 4 cifras van sin separador (2026, 1200), como se escribe; desde 10.000, con.
        nf.usesGroupingSeparator = valor >= 10_000 || valor <= -10_000
        let t = sinEspacioDuro(nf.string(from: valor as NSDecimalNumber) ?? "\(valor)")
        guard m.porcentaje else { return t }
        return formato.locale.language.languageCode?.identifier == "en" ? t + "%" : t + " %"
    }

    // El formato de Apple separa el signo con un espacio duro (U+00A0): en un formulario o una planilla puede no
    // entenderse como número. Va un espacio común.
    private static func sinEspacioDuro(_ t: String) -> String {
        t.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    // MARK: CUIT / CUIL

    /// Hay un CUIT ya escrito (20-12345678-9) con el dígito verificador que no da. Lo usa el Motor para avisar.
    static func hayCUITMal(_ texto: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: #"\b\d{2}-\d{8}-\d\b"#) else { return false }
        return re.matches(in: texto, range: NSRange(texto.startIndex..., in: texto)).contains { m in
            guard let r = Range(m.range, in: texto) else { return false }
            return leerCUIT(Ficha.partir("cuit " + texto[r]), desde: 0)?.valido == false
        }
    }

    // Cómo escribe la voz a texto «CUIT» y «CUIL»: «Quit» es lo más común, y a veces «Quick» (01/11/2026). Sin los 11
    // números detrás no es un CUIT, así que «quick question» queda como está.
    private static let palabrasCUIT: Set<String> = ["cuit", "cuil", "cuitl", "quit", "quick", "kuit", "quil", "kuil", "cuid", "quid"]
    // Lo que puede ir entre los grupos del número: la voz a texto pone comas y puntos al dictarlo de a pares.
    private static let entreGrupos: Set<String> = [",", ".", "-", ":", ";", "y"]

    /// «CUIT 20 12345678 9» (o con los números en palabras, de a pares, con comas en el medio): 11 números seguidos
    /// de la palabra CUIT o CUIL. Sin la palabra, solo si es todo lo que dictaste, da 11 números con el dígito
    /// verificador bien y empieza como un CUIT (20, 23, 24, 27, 30, 33 o 34): «veinte, doce, treinta y cuatro…».
    static func leerCUIT(_ f: [Ficha], desde i: Int) -> (texto: String, valido: Bool, hasta: Int)? {
        guard i < f.count else { return nil }
        let conPalabra = palabrasCUIT.contains(f[i].clave)
        guard conPalabra || i == 0 else { return nil }
        var j = conPalabra ? i + 1 : i
        while j < f.count, ["es", "numero", "nro", ":", ","].contains(f[j].clave) { j += 1 }
        var numeros = ""
        while j < f.count, numeros.count < 11 {
            let t = f[j].texto
            if t.first?.isNumber == true { numeros += t.filter(\.isNumber); j += 1; continue }
            if var v = unidades[f[j].clave] ?? (f[j].clave == "onze" ? 11 : nil), v < 100 {
                j += 1
                // «treinta y uno» o «treinta uno»: un solo par.
                if v >= 20, v % 10 == 0 {
                    var k = j
                    if k < f.count, f[k].clave == "y" { k += 1 }
                    if k < f.count, let u = unidades[f[k].clave], u > 0, u < 10 { v += u; j = k + 1 }
                }
                numeros += "\(v)"
                continue
            }
            if entreGrupos.contains(f[j].clave) { j += 1; continue }
            break
        }
        guard numeros.count == 11 else { return nil }
        let d = numeros.compactMap(\.wholeNumberValue)
        let pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
        let resto = 11 - zip(d, pesos).map(*).reduce(0, +) % 11
        let verificador = resto == 11 ? 0 : resto == 10 ? 9 : resto
        let valido = verificador == d[10]
        if !conPalabra {
            let soloSignos = f[j...].allSatisfy { $0.texto.first.map { ".,;".contains($0) } ?? true }
            guard soloSignos, valido, ["20", "23", "24", "27", "30", "33", "34"].contains(String(numeros.prefix(2))) else { return nil }
        }
        let texto = "\(numeros.prefix(2))-\(numeros.dropFirst(2).prefix(8))-\(numeros.suffix(1))"
        return (texto, valido, j)
    }
}

private extension Decimal {
    var esEntero: Bool { var a = self, r = Decimal(); NSDecimalRound(&r, &a, 0, .down); return r == self }
}

/// Coma o punto para los decimales de Cifras (Modos › Cifras). Automático: el del país de la Mac.
enum FormatoCifras: String, Codable, CaseIterable, Identifiable {
    case automatico, coma, punto
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .automatico: T("Según tu Mac", "Like your Mac")
        case .coma: "1.234,56"
        case .punto: "1,234.56"
        }
    }
}
