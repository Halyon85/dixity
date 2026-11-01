#!/bin/zsh
# Compila Dixity (antes Dicta y Dixis), arma Dixity.app y la firma con el certificado de desarrollo (así los permisos no se pierden).
# Uso: ./compilar.sh            → deja la app en build/Dixity.app
#      ./compilar.sh instalar   → además la copia a /Applications/Dixity.app y la abre
# Para publicar una versión, `tools/publicar-version.sh` la llama con DIXITY_INFO (un Info.plist con la versión, la
# lista de versiones y la clave de Sparkle), DIXITY_FIRMA (con qué firmar; "-" es la firma local) y
# DIXITY_ARQUITECTURAS="arm64 x86_64" (app universal, para Macs con Apple Silicon y con Intel).
set -euo pipefail
cd "$(dirname "$0")"

# Por defecto solo arm64 (más rápido para probar en esta Mac); la versión publicada pide las dos.
BANDERAS=()
for arq in ${=DIXITY_ARQUITECTURAS:-arm64}; do BANDERAS+=(--arch "$arq"); done
swift build -c release "${BANDERAS[@]}"
CARPETA_BIN="$(swift build -c release "${BANDERAS[@]}" --show-bin-path)"
BIN="$CARPETA_BIN/Dixity"
APP="build/Dixity.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Dixity"
cp "${DIXITY_INFO:-Recursos/Info.plist}" "$APP/Contents/Info.plist"
[[ -f Recursos/AppIcon.icns ]] && cp Recursos/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Recursos/BarraMenu.png Recursos/BarraMenu@2x.png "$APP/Contents/Resources/"
# Las licencias viajan con la app: la nuestra, el NOTICE (lo pide la Apache 2.0) y la de Sparkle (MIT).
cp LICENSE NOTICE "$APP/Contents/Resources/"
[[ -f .build/artifacts/sparkle/Sparkle/LICENSE ]] && cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
# Sparkle (actualizaciones): va en Frameworks y el ejecutable la busca ahí. Dixity no usa la caja de arena de macOS,
# así que los servicios XPC de Sparkle no hacen falta (son para apps en caja de arena) y se sacan.
ditto "$CARPETA_BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
# El ejecutable ya puede traer esta ruta (según cómo compile swift build): se agrega solo si falta.
otool -l "$APP/Contents/MacOS/Dixity" | grep -q "@executable_path/../Frameworks" \
  || install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Dixity"
strip -x "$APP/Contents/MacOS/Dixity" 2>/dev/null || true

IDENTIDAD=${DIXITY_FIRMA-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}
IDENTIDAD=${IDENTIDAD:--}
# Primero lo de adentro de Sparkle (de adentro hacia afuera) y al final la app, todo con la misma firma.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for pieza in "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --options runtime --timestamp=none --sign "$IDENTIDAD" "$pieza"
done
# Con la firma local macOS solo deja cargar bibliotecas del mismo equipo de Apple, y la firma local no tiene equipo:
# sin este permiso, Dixity no arranca porque no puede abrir Sparkle. Con un certificado de Apple no hace falta.
PERMISOS=Recursos/Dixity.entitlements
if [[ "$IDENTIDAD" == "-" ]]; then
  PERMISOS=build/Dixity-firma-local.entitlements
  cp Recursos/Dixity.entitlements "$PERMISOS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$PERMISOS"
fi
codesign --force --options runtime --timestamp=none \
  --entitlements "$PERMISOS" \
  --sign "$IDENTIDAD" "$APP"
[[ "$IDENTIDAD" == "-" ]] && echo "Firmada con: firma local (ad-hoc)" || echo "Firmada con: $IDENTIDAD"
du -sh "$APP"

if [[ "${1:-}" == "instalar" ]]; then
  pkill -x Dixity 2>/dev/null || true
  pkill -x Dicta 2>/dev/null || true      # versiones anteriores (Dicta / Dixis)
  sleep 1
  rm -rf /Applications/Dicta.app /Applications/Dixis.app /Applications/Dixity.app
  cp -R "$APP" /Applications/Dixity.app
  open /Applications/Dixity.app
  echo "Instalada en /Applications/Dixity.app"
fi
