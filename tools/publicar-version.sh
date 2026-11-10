#!/bin/zsh
# Arma una versión publicada de Dixity: la app universal (Apple Silicon e Intel) con la búsqueda de actualizaciones
# prendida, el .zip firmado con la clave de Sparkle y la lista de versiones (appcast.xml). NO sube nada: al final dice
# cómo crear la versión en GitHub, que guarda el .zip y la lista.
# Uso: tools/publicar-version.sh 0.2.0
# Paso a paso y qué hacer la primera vez: docs/PUBLICAR.md.
set -euo pipefail
cd "$(dirname "$0")/.."

# Dónde viven las versiones publicadas: en las versiones (Releases) de GitHub. Cada una lleva su .zip y la lista
# (appcast.xml); "latest/download" siempre apunta a la de la última, así la app la encuentra sin otro servidor.
# Si publicás tu propia copia de Dixity, cambiá estas líneas (y generá tu clave: ver docs/PUBLICAR.md).
REPO="Halyon85/dixity"
LISTA="https://github.com/$REPO/releases/latest/download/appcast.xml"   # la lista de versiones que mira la app
# La clave pública de Sparkle (puede estar a la vista). Se pega acá la que imprime `generate_keys` la primera vez
# (docs/PUBLICAR.md, "La primera vez"). Sin ella el script no arranca: una app sin clave no podría actualizarse.
CLAVE_PUBLICA="wAig5+OOHW4qhLH0yZy8Ja6K1IOgc4QsZtnJA5gDZY8="
CUENTA="team.halyon.dixity"                            # el nombre de la clave privada en el Llavero

VERSION=${1:?"Uso: tools/publicar-version.sh <versión, por ejemplo 0.2.0>"}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "La versión tiene que ser como 0.2.0"; exit 1; }
[[ -n "$CLAVE_PUBLICA" ]] || { echo "Falta la clave pública de Sparkle en CLAVE_PUBLICA (ver docs/PUBLICAR.md)."; exit 1; }
# Lo que se publica tiene que ser exactamente lo que está guardado en git (así se puede saber qué código lleva).
[[ -z "$(git status --porcelain)" ]] || { echo "Hay cambios sin commit: guardalos antes de publicar."; exit 1; }

# Sparkle compara el número de compilación (CFBundleVersion), que tiene que crecer siempre: sale de la versión
# (0.2.0 → 200, 1.4.12 → 10412), así no depende del historial de git (la copia pública arranca sin historial).
IFS=. read -r MAYOR MENOR ARREGLO <<< "$VERSION"
NUMERO=$(( MAYOR * 10000 + MENOR * 100 + ARREGLO ))

# Cada versión en su carpeta, sola: la lista lleva solo la última (alcanza para actualizar desde cualquiera anterior).
SALIDA=build/publicar/$VERSION
[[ -e "$SALIDA" ]] && { echo "Ya existe $SALIDA: esa versión ya se armó. Usá otro número."; exit 1; }
mkdir -p "$SALIDA"
ZIP="$SALIDA/Dixity-$VERSION.zip"
DESCARGAS="https://github.com/$REPO/releases/download/v$VERSION/"

# El Info.plist de la versión publicada: el de siempre más la versión, la lista y la clave. Busca sola una vez por
# día y pregunta antes de instalar. A propósito nunca se instala sola: SUAllowsAutomaticUpdates en false saca la
# casilla de Sparkle «instalar automáticamente en el futuro», así siempre pregunta (01/11/2026).
# Vale igual con Developer ID.
INFO=build/Info-publicada.plist
cp Recursos/Info.plist "$INFO"
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $NUMERO" "$INFO"
$PB -c "Add :SUFeedURL string $LISTA" -c "Add :SUPublicEDKey string $CLAVE_PUBLICA" \
    -c "Add :SUEnableAutomaticChecks bool true" -c "Add :SUAllowsAutomaticUpdates bool false" \
    -c "Add :SUScheduledCheckInterval integer 86400" "$INFO"

# Firma: con Developer ID si lo tenés (la cuenta paga de Apple); si no, la firma local. Nunca con el certificado
# "Apple Development": ese es para probar en tus Macs, no para repartir.
FIRMA=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
# Con Developer ID, Apple tiene que revisar la app (notarizar) para que abra sin avisos. La contraseña para eso vive
# en el Llavero con este nombre (docs/PUBLICAR.md, "Notarizar"). Se mira antes de compilar, así no se arma de balde.
NOTARIO=${DIXITY_NOTARIO:-dixity}
if [[ -n "$FIRMA" ]] && ! xcrun notarytool history --keychain-profile "$NOTARIO" >/dev/null 2>&1; then
  echo "Falta guardar en el Llavero el acceso para notarizar (perfil \"$NOTARIO\"). Ver docs/PUBLICAR.md, \"Notarizar\"."
  exit 1
fi
# Universal: la misma app anda en Macs con Apple Silicon (arm64) y con Intel (x86_64).
DIXITY_INFO="$INFO" DIXITY_FIRMA="${FIRMA:--}" DIXITY_ARQUITECTURAS="arm64 x86_64" ./compilar.sh

# Antes de empaquetar: que la app sea de verdad universal (si salió de una sola arquitectura, no se publica).
ARQS=$(lipo -archs build/Dixity.app/Contents/MacOS/Dixity)
[[ "$ARQS" == *arm64* && "$ARQS" == *x86_64* ]] || { echo "La app no salió universal (tiene: $ARQS). No se publica."; exit 1; }

# Notarizar: se manda a Apple, se espera la respuesta y el visto bueno se pega en la app (así abre sin internet).
# El .zip de envío va fuera de $SALIDA a propósito: generate_appcast toma todo .zip que encuentre ahí.
if [[ -n "$FIRMA" ]]; then
  ENVIO=build/Dixity-para-notarizar.zip
  ditto -c -k --keepParent build/Dixity.app "$ENVIO"
  RESPUESTA=$(xcrun notarytool submit "$ENVIO" --keychain-profile "$NOTARIO" --wait --output-format json) || true
  rm -f "$ENVIO"
  if ! grep -Eq '"status" *: *"Accepted"' <<< "$RESPUESTA"; then
    echo "Apple no aceptó la app: $RESPUESTA"
    echo "El detalle: xcrun notarytool log <id de arriba> --keychain-profile $NOTARIO"
    exit 1
  fi
  xcrun stapler staple build/Dixity.app
  spctl --assess --type execute -vv build/Dixity.app
fi

# El .zip (ditto conserva los enlaces y permisos de adentro de la app, cosa que zip no siempre hace).
ditto -c -k --sequesterRsrc --keepParent build/Dixity.app "$ZIP"

# Las novedades, si las escribiste: docs/novedades/<versión>.html (un pedazo de HTML, sin <html> ni <body>).
NOTAS=docs/novedades/$VERSION.html
[[ -f "$NOTAS" ]] && cp "$NOTAS" "$SALIDA/Dixity-$VERSION.html"

# Firma el .zip con la clave privada del Llavero y arma la lista.
HERRAMIENTAS=.build/artifacts/sparkle/Sparkle/bin
"$HERRAMIENTAS/generate_appcast" --account "$CUENTA" --download-url-prefix "$DESCARGAS" \
  --link "https://github.com/$REPO" --maximum-deltas 0 -o "$SALIDA/appcast.xml" "$SALIDA"

FIRMADA="la firma local"
[[ -n "$FIRMA" ]] && FIRMADA="$FIRMA y notarizada"
echo
echo "Listo: Dixity $VERSION (compilación $NUMERO, $ARQS), firmada con $FIRMADA, en $SALIDA."
echo "Para publicarla, desde la copia pública (el .zip y la lista van juntos en la versión de GitHub):"
echo "  gh release create v$VERSION --repo $REPO --title \"Dixity $VERSION\" --notes-file <notas.md> \\"
echo "    \"$PWD/$ZIP\" \"$PWD/$SALIDA/appcast.xml\""
