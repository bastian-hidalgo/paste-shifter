# Orbital para Android

Este directorio contiene una app Android nativa de una pantalla y el cliente Orbital. La app se comunica directamente con Paste Shifter para Mac por Wi‑Fi local: no necesita cuenta, backend, relay ni servicios externos en ejecución. La lectura del QR usa Camera2 y ZXing Core para decodificar localmente; no usa ML Kit, Google Play Services, telemetría ni descarga de modelos en tiempo de ejecución.

## Estado

- `:app:assembleDebug` genera `app/build/outputs/apk/debug/app-debug.apk`.
- El proyecto incluye Gradle Wrapper 8.14.3. Ejecuta `./gradlew :app:assembleDebug` desde este directorio.
- La interfaz permite emparejar escaneando el QR del Mac (o pegando su JSON), activar o pausar Orbital y revocar la confianza local.
- Para enviar texto desde cualquier app, selecciona el texto y elige **Compartir → Mi Mac** en la fila de destinos directos, o **Paste Shifter** en la lista de apps. No hay que cambiar el teclado. Android entrega el texto compartido por acción explícita del usuario.
- También puedes escribir o pegar texto en el cuadro de la app y tocar **Enviar al Mac**.
- El destino **Mi Mac** se publica al emparejar. Android controla su posición en la fila directa y puede tardar en mostrarlo; usar Paste Shifter en la lista de apps funciona como alternativa.
- Mientras Orbital está activado, un servicio visible mantiene la conexión en segundo plano y vuelve a buscar el Mac cuando Android se conecta a una Wi‑Fi. El servicio se detiene al pausar Orbital. Se puede añadir un control Orbital a Ajustes rápidos desde la app.
- Los clips entrantes del Mac pasan al portapapeles de Android automáticamente, con la vista previa del sistema marcada como sensible. Una notificación local avisa que ya está listo para pegar; el sonido usa el canal **Copias recibidas**, configurable desde los ajustes de notificaciones de Android. El texto no se persiste en la app.
- Las claves privadas P‑256 viven en Android Keystore. La clave pública/certificado del Mac se fija en el QR durante el pairing. El Android confirma el código de comparación y el Mac exige aprobar el dispositivo.
- El historial Android es temporal y solo vive en memoria; no se persiste el texto recibido.
- Build debug generado localmente; falta probar pairing, transporte y envío desde el Sharesheet en teléfonos reales y redes Wi‑Fi/hotspot. No declarar interoperabilidad completa hasta superar esas comprobaciones.

## Build

Requisitos: Android SDK con API 36 y JDK 17. La primera compilación descarga Gradle y ZXing Core desde repositorios oficiales; estas dependencias quedan empaquetadas en el APK. La app no contacta esos repositorios al ejecutarse.

```sh
./gradlew :app:assembleDebug
```

## Seguridad y red

El QR de un solo uso tiene un secreto aleatorio de 256 bits, huella SHA‑256 del certificado TLS del Mac, UUID y vencimiento de dos minutos. No publica IP ni hostname. Android descubre por mDNS el servicio `_orbital._tcp` que coincide con el UUID, rechaza destinos sin ruta conectada directamente por Wi‑Fi y enlaza el socket a esa red antes de conectarse. El TLS 1.3 valida exactamente el certificado fijado en el QR antes de transmitir el secreto. Las reconexiones autentican Android con una firma P‑256 fresca de Android Keystore. El canal no baja a HTTP ni admite certificados nuevos por aviso.

Esto impide que un participante de la Wi‑Fi lea, modifique o suplante una sesión sin las claves confiables, pero el router aún puede bloquear o retrasar tráfico. Una denegación de servicio sigue siendo posible.

El manifiesto usa `INTERNET` únicamente para el socket directo, `ACCESS_NETWORK_STATE` para validar la ruta local, `CHANGE_WIFI_MULTICAST_STATE` para mDNS, y un servicio visible `connectedDevice` para sostener la conexión solicitada por el usuario. No se pide VPN, Accessibility Service ni ubicación. El permiso de notificaciones habilita avisos de reconexión y recepción. Con `targetSdk` 37 o superior, Android 17 requiere `ACCESS_LOCAL_NETWORK`; el flujo UI ya incluye la solicitud en contexto y debe comprobarse al subir el target. Otra alternativa es integrar el picker de `NsdManager` para limitar el acceso al servicio que el usuario elige. Consultar la [guía oficial de permisos de red local](https://developer.android.com/privacy-and-security/local-network-permission) y la [API `NsdManager`](https://developer.android.com/reference/android/net/nsd/NsdManager).

## Código

- `orbital-protocol`: transcripciones Pair/Auth, HMAC-SHA256, código SAS, firma/verificación ECDSA P‑256, pin de huella y framing acotado.
- `orbital-transport`: lectura estricta del QR, descubrimiento mDNS, TLS 1.3 fijado y gestión de sesión.
- `app`: UI nativa, lector QR local basado en ZXing Core, permisos contextuales y política del portapapeles.
- `../OrbitalProtocol/`: esquemas y contrato interoperable v1.
- `app/src/main/assets/licenses/ZXing-LICENSE.txt`: licencia de la única dependencia runtime de terceros.

Solo se admite texto UTF‑8 no vacío hasta 256.000 bytes. Los clips remotos se agregan a Normal en Mac y reemplazan el portapapeles de Android para que queden listos para pegar. Fantasma, Flash y Privado quedan excluidos.
