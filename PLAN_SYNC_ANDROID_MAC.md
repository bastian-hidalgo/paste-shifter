# Plan: sincronización local segura entre Paste Shifter y Android

**Estado:** Orbital integrado en Mac; app Android nativa y APK debug compilados; interoperabilidad real en hardware pendiente  
**Alcance:** Paste Shifter para macOS existente y una app complementaria para Android. No requiere app para iPhone ni servicio alojado.

## Estado de implementación actual

- La app Mac inicia el listener Bonjour `_orbital._tcp` solo sobre Wi‑Fi, usa TLS 1.3 y mantiene su identidad P‑256/certificado en Keychain. Android debe fijar la huella SHA‑256 recibida en el QR antes de abrir TLS.
- El pairing usa QR aleatorio de un solo uso y dos minutos, HMAC ligado a ambos nonces, código de comparación de seis dígitos y aprobación explícita en Mac. Las reconexiones de dispositivos emparejados firman un desafío fresco P‑256; revocar o pausar cierra la sesión.
- El transporte acepta solo mensajes acotados de un dispositivo autenticado. Mac puede enviar clips manualmente o compartir copias nuevas de Normal mediante opt-in; los clips entrantes se agregan a Normal y al portapapeles del sistema, actualizando el change count para impedir ecos. Fantasma, Flash y Privado se excluyen.
- La UI de Ajustes presenta el estado, QR, aprobación, pausa, envío automático y revocación. La app debe permanecer abierta en Mac.
- `OrbitalProtocol/` especifica los formatos, framing, transcripciones criptográficas y mensajes v1 compartidos. Es la fuente de verdad para la implementación Android.
- `swift build --disable-sandbox` compila el ejecutable Mac. Xcode también compila un app bundle universal Debug (arm64 + x86_64) y la configuración AppStore en arm64, sin firma. El permiso de red local y el listener en una instalación sandboxed aún deben validarse. No se ejecutaron tests.
- `Android/` contiene una app nativa de una pantalla, lector QR Camera2 con decodificador ZXing Core sin SDK de telemetría, UI de emparejamiento/reconexión, destino directo **Mi Mac** en Android Sharesheet, lista temporal de clips recibidos y acción de copia explícita. `Android/gradlew :app:assembleDebug` genera un APK debug; no hay firma de release configurada.
- **Pendiente:** validar con mDNS/TLS reales en teléfono, permiso de red local en una instalación sandboxed de macOS y verificación de extremo a extremo frente a un tercer dispositivo.

## Objetivo y límites

Permitir copiar texto en un Mac y tenerlo disponible en un Android emparejado, y viceversa, con conexión directa dentro de la red local. Ningún servidor, cuenta, relay, telemetría ni servicio de descubrimiento externo participa. El contenido permanece en los dos dispositivos.

La seguridad buscada es que otro participante de la Wi‑Fi no pueda leer, alterar ni inyectar clips, ni hacerse pasar por un dispositivo ya emparejado. Esto depende de que el Mac y el teléfono estén íntegros y de que sus claves privadas permanezcan protegidas. No protege un dispositivo desbloqueado/comprometido ni evita que el router bloquee o retrase tráfico (denegación de servicio).

## Decisiones recomendadas

1. **Conexión directa:** Paste Shifter abre un listener TCP local; Android lo descubre con Bonjour/mDNS y se conecta directamente. Descubrimiento no equivale a confianza: se acepta solo una identidad emparejada. Si mDNS está bloqueado por el router, ofrecer dirección local manual o volver a escanear; nunca recurrir a Internet.
2. **Emparejamiento con presencia física:** el Mac muestra un QR de un solo uso y corta duración. El esquema compartido `OrbitalProtocol/pairing-v1.schema.json` lleva el fingerprint SHA-256 del certificado TLS, un secreto aleatorio de 256 bits, ID del Mac, ID de pairing y vencimiento de 2 minutos. No lleva IP: Android descubre el Mac por Bonjour y selecciona el que anuncia ese ID. Android lo escanea, genera en Android Keystore una clave de firma P‑256 y acredita posesión del secreto dentro del TLS ya fijado. El Mac muestra un código de comparación derivado del transcript; el usuario confirma y aprueba explícitamente el nuevo dispositivo. El secreto caduca, se consume una vez y no se anuncia por Bonjour.
3. **Canal autenticado estándar:** TLS 1.3 con certificado local del Mac fijado en Android durante el pairing. Después del handshake TLS, Android prueba su identidad firmando un desafío aleatorio fresco y ligado a la sesión con su clave P‑256 del Keystore; el Mac verifica con la clave pública X9.63 fijada durante el pairing. Así ambos extremos se autentican antes de aceptar clips, mientras TLS cifra y protege la integridad del canal. En macOS usar Network.framework; en Android, el TLS del sistema con verificación estricta de la huella QR. No aceptar certificados desconocidos/cambiados ni bajar a texto plano. La gestión del certificado local debe usar APIs/librerías X.509 mantenidas, no construir DER ni primitivas criptográficas propias.
4. **Claves locales:** clave privada TLS del Mac en Keychain y clave de firma Android en Android Keystore, hardware-backed cuando esté disponible. El Mac guarda la clave pública de firma Android (no la privada); Android guarda la huella del certificado TLS Mac. La revocación elimina la confianza local y cierra cualquier sesión activa de ese dispositivo.
5. **Descubrimiento mínimo:** publicar un tipo Bonjour propio, nombre genérico configurable y versión/capacidad del protocolo. No anunciar texto, historial, nombre de cuenta ni secreto. En macOS declarar `NSLocalNetworkUsageDescription` y el servicio en `NSBonjourServices`; tratar permiso denegado como estado recuperable. El sandbox de App Store tiene que permitir el listener y la red local con los entitlements correctos.
6. **Protocolo de clips pequeño:** primera versión solo texto plano UTF‑8, tamaño máximo alineado al límite actual de Paste Shifter (256 KB), framing con versión y longitud validada, IDs aleatorios de clip/origen y acuse de recibo. Rechazar mensajes sobredimensionados, malformados, duplicados/replay y tipos no soportados. Sin ejecución de contenido, archivos ni HTML.

## Flujo de producto

### Emparejar

1. En Ajustes de Paste Shifter, el usuario pulsa **Añadir Android**. El Mac inicia un pairing efímero, muestra QR y vence en 2 minutos.
2. En Android, **Emparejar con Mac** escanea el QR, fija el certificado TLS del Mac y conecta por LAN. Android crea la clave P‑256 en Android Keystore y demuestra posesión del secreto efímero.
3. El Mac verifica la firma/prueba, muestra el nombre y el código de comparación del transcript; Android muestra el mismo código. El usuario compara y aprueba en Mac. Si no coinciden, cancelar.
4. El Mac guarda el ID, nombre y clave pública Android en Keychain/local metadata; Android guarda la huella TLS Mac. Se borra el secreto temporal. Reconexiones exigen una firma nueva de desafío dentro de TLS.

### Sincronizar

- Control global **Sincronización local** y control por dispositivo; botón **Pausar** siempre accesible.
- Compartición manual por clip disponible al emparejar. Compartición automática separada, opt-in y apagada por defecto. Limitar ambas a texto elegible de **Normal**; nunca enviar **Fantasma**, **Flash** ni **Privado**. No enviar contenido que lleve marcas de secreto/transitorio/autogenerado conocidas.
- Evitar eco guardando `originDeviceID` y `clipID`; un clip recibido no vuelve a publicarse como nuevo.
- Al recibir: opción elegible “aceptar automáticamente desde dispositivos emparejados” o “preguntar”. Mostrar confirmación breve y permitir apagar autoescritura del portapapeles.
- Configurar retención Android explícitamente; ofrecer borrar clips recibidos y revocar dispositivos. No guardar historial cifrado persistente en Android en la primera entrega: mantenerlo en memoria/portapapeles del sistema conforme al modo elegido.

## Límite importante de Android

Android limita el acceso al portapapeles desde una app que no está en primer plano. La sincronización automática fiable cuando la app está cerrada puede no estar disponible o exigir un servicio visible con notificación y consumir batería; no se debe prometer funcionamiento idéntico a Universal Clipboard. La primera entrega debe probar las versiones objetivo y ofrecer un modo honesto: app abierta/activa sincroniza automáticamente; modo conectado en segundo plano, si la matriz de dispositivos lo permite, será opt-in, visible y con controles del sistema. El usuario puede enviar/recibir manualmente dentro de la app como alternativa.

Por defecto no pedir Accessibility Service, VPN, root, permiso de notificaciones ocultas ni “autostart” del fabricante. Si se evalúa un servicio foreground, documentar la notificación persistente, acción de detener, consumo y compatibilidad, y mantenerlo opt-in.

## Trabajo por etapas y gates

### 0. Prototipo de riesgo

**Pendiente en hardware.** Aunque el listener ya está integrado en la app Mac, falta comprobar pairing y transporte con Android real, en router y hotspot, junto al comportamiento de portapapeles Android.

- Probar listener local de macOS 13+ y Android actual; mDNS en router doméstico y hotspot; permiso de red local macOS; ciclo dormir/despertar/cambio de IP.
- Probar TLS 1.3 con certificado local del Mac fijado por QR, firma de desafío P‑256 de Android dentro del canal y código de comparación.
- Comprobar el comportamiento real de portapapeles Android en primer plano, background y proceso detenido en varios fabricantes/versiones.
- **Gate:** no avanzar si el modelo exige aceptar identidades no verificadas, usa relay, o requiere prometer lectura en background no garantizada. Dejar documentados alcance y matriz comprobada.

### 1. Especificación y modelo de amenazas

**Contrato v1 escrito y cotejado entre las implementaciones; vectores de protocolo e interoperabilidad en hardware pendientes.**

- Mantener protocolo versionado, estados del emparejamiento, formato del QR, certificados, rotación/revocación, límites, timeouts y errores alineados con los esquemas compartidos.
- Amenazas: escucha, MITM, suplantación, replay, inundación/DoS, QR fotografiado, pérdida del teléfono, eco, clips secretos, red aislada.
- Revisar el diseño criptográfico y los límites de privacidad antes de código de sincronización.

### 2. Transporte y pairing del Mac

**Implementado en la app Mac; falta validar el flujo completo en distribución y con Android.**

- Añadir módulo aislado, por ejemplo `Sources/LocalSync/`, sin meter socket/parsing en `ClipboardStore`.
- Gestionar listener/Bonjour con Network.framework, estados de permiso/conexión y cierre inmediato al desactivar/Salir.
- Implementar TLS 1.3 con certificado local del Mac, validación de desafío P‑256 Android dentro de TLS, alta/revocación de dispositivos, límites de conexión y rate limit de pairing.
- Agregar controles de Ajustes: habilitar, estado local, QR efímero, lista/revocación, pausa.
- Actualizar `Info.plist`, entitlements por configuración y descripción de privacidad. Conservar la separación entre build directo y App Store; verificar explícitamente sandbox y permiso de red local para el listener.

### 3. App Android mínima

**Implementada y compilada como APK debug; pendiente validación de dispositivo/red.**

- App Java nativa con proyecto Gradle reproducible, UI de una pantalla, conexión, estado, emparejamiento, pausa al salir de primer plano, revocación y controles de portapapeles.
- QR se escanea en el teléfono con Camera2 + ZXing Core local o se pega como JSON. Las claves P‑256 viven en Android Keystore; descubrimiento mDNS, TLS 1.3 con pin estricto y desafío de reconexión firmado.
- El destino directo **Mi Mac** recibe texto solo después de que la persona elige compartirlo. Se mantiene el teclado Samsung y no se vigila el portapapeles en segundo plano. Los clips entrantes del Mac pasan al portapapeles del Android automáticamente.
- `Android/README.md` documenta build, permisos y límites. APK debug no equivale a distribución firmada ni a interoperabilidad comprobada.

### 4. Integración y sincronización

**Implementada en ambos lados a nivel de código; falta la comprobación bidireccional en hardware.**

- Crear una frontera pequeña en `ClipboardStore`: observar copias elegibles y recibir clips autenticados. El transporte nunca lee directamente `NSPasteboard` ni muta el historial por su cuenta.
- Sincronizar solo Normal por defecto; clips recibidos se incorporan sin reemitirse ni reemplazar el portapapeles del sistema.
- No cambiar selección/espacios existentes ni registrar texto en logs. Logs limitados a estado y códigos de error.

### 5. Verificación de seguridad y lanzamiento gradual

- Pruebas de protocolo compartidas: QR expirado/reusado, huella falsa/cambiada, cliente no emparejado, replay, truncamiento, payload demasiado grande, reconexión, duplicados y revocación.
- Ensayo en Wi‑Fi compartida con un tercer equipo: comprobar que no descifra ni logra sesión autenticada, aun anunciando Bonjour falso o interceptando/redirigiendo tráfico.
- Pruebas manuales de instalación/actualización con identidad de firma estable, permisos local-network, App Sandbox de distribución y Android en versiones/fabricantes objetivo.
- Política de privacidad y fichas de tienda actualizadas antes de distribuir. No declarar que “es imposible” MITM: declarar que el protocolo autenticado detecta/rechaza intermediarios sin las claves confiables y que la disponibilidad puede ser atacada.

## Componentes actuales y trabajo pendiente

- `Sources/PasteShifter/Orbital*.swift`: identidad local, handshake y listener directo TLS/Bonjour.
- `Sources/PasteShifter/ClipboardStore.swift`: frontera para capturar copias elegibles y recibir clips en Normal y en el portapapeles del sistema sin volver a emitirlos.
- `Sources/PasteShifter/PickerView.swift`: ajustes Orbital y acción explícita para compartir cada clip elegible.
- `Resources/Info.plist` y `Resources/PasteShifter-AppStore.entitlements`: declaración de Bonjour/red local y entitlement de servidor para la configuración sandbox.
- `OrbitalProtocol/`: esquemas JSON, framing y transcripciones normativas comunes.
- `Android/app`, `Android/orbital-protocol/.../OrbitalProtocol.java` y `Android/orbital-transport/...`: app nativa, lector QR local, cliente TLS fijado, descubrimiento mDNS, pairing y controles de portapapeles; el APK debug compila offline.
- `Android/README.md`: arquitectura, permisos de red local, build y límites conocidos.
- Pendiente: correr pairing/transmisión en hardware y capturar tráfico para descartar conexiones externas durante la sesión; validar diferencias de mDNS/ruta por router y versiones Android; verificar el listener sandboxed y el permiso local de macOS al instalar; revisar privacidad y fichas antes de publicar.

## Criterios de aceptación de v1

- Dos dispositivos emparejados transmiten texto directamente por LAN sin tráfico hacia Internet; se puede verificar con captura de red.
- Una identidad no emparejada, certificado modificado, pairing expirado o mensaje alterado falla cerrado y no cambia el portapapeles/historial.
- Revocar un Android detiene inmediatamente su acceso; volver a conectar exige nuevo pairing.
- No se transmiten Fantasma, Flash ni Privado; el eco de clips recibidos no produce bucles.
- Límites/tipos/versionado se validan antes de reservar memoria o insertar contenido.
- La UI diferencia “emparejado”, “conectado”, “pausado”, “permiso denegado” y “sin conexión”; no confunde descubrimiento con autenticación.
- Las capacidades de sincronización Android en segundo plano se describen según evidencia del prototipo, sin promesa universal.

## Referencias primarias

- Apple, [TN3151: elegir API de red](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api): Network.framework, Bonjour y TLS.
- Apple, [TN3179: privacidad de red local](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): permiso de red local, claves `Info.plist` y Bonjour.
- Android, [Copiar y pegar](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste): marco de portapapeles y comportamiento/UX del sistema.
- Android, [Cambios de Android 13](https://developer.android.com/about/versions/13/features): confirmación del sistema al copiar y protección de contenido sensible.

