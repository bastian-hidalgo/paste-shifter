# Paste Shifter — contexto para asistentes de IA

Actualizado: 2026-10-11. Este archivo resume el propósito, la arquitectura, los modos, privacidad, firma, distribución y validación conocidos del proyecto. Los hechos del repositorio se distinguen de los pasos pendientes; no asumir que la app ya está publicada en App Store.

## Propósito

Paste Shifter es una utilidad de macOS para ordenar texto copiado y recuperarlo rápido desde la barra de menú. Su idea central es ofrecer espacios separados con distintos niveles de persistencia y privacidad: uso normal, historial Fantasma aislado, copia Flash efímera e historial Privado cifrado. La app no tiene una ventana permanente ni icono de Dock; aparece como utilidad de barra de menú (`LSUIElement=true`).

La interfaz debe ser rápida y compacta. Ajustes debe explicar para qué sirve cada modo y mostrar el icono brillante de la app; la barra de menú usa una silueta monocromática adaptable al tema de macOS, con un distintivo para el modo activo.

## Modos

| Modo | Funcionamiento actual en el código |
| --- | --- |
| Normal | Captura texto del portapapeles después de ⌘C. Vive en memoria y se vacía al cerrar la app. |
| Fantasma | El texto copiado va a una lista separada en memoria; no se mezcla con Normal. También se pueden mover elementos seleccionados a Fantasma. Se vacía al cerrar. |
| Flash | ⌥⇧C envía ⌘C a la app activa, espera hasta 1,5 s a que aparezca texto nuevo, abre el selector y conserva la copia durante 60 s. Al vencer, limpia la lista Flash y el portapapeles solo si este todavía contiene exactamente la copia Flash y no cambió su `changeCount`; una copia posterior del usuario se conserva. Salir de Flash o cerrar la app también cancela el temporizador e intenta borrar esa copia si sigue intacta. |
| Privado | Solo se guarda al pulsar + o «Guardar portapapeles en Privado». El historial se cifra con AES-GCM. Al salir del modo, cerrar la app o bloquear la sesión, se borra de memoria la lista descifrada y se invalida la clave de sesión. Abrir de nuevo el widget mientras la misma sesión Privada siga desbloqueada reutiliza la clave y no debería volver a autenticar. |

El menú de la app contiene «Cambiar modo»; elegir el modo que ya está activo lo alterna a Normal. El menú de estado también tiene opciones «Modo …» y acciones para abrir historial, pegar, guardar en Privado, mover a Fantasma, borrar, pausar, ajustes y salir. El estado del modo se refleja en el icono de la barra: candado para Privado, fantasma para Fantasma y rayo/contador para Flash.

### Requisito de autenticación de Privado

El requerimiento expresado por el usuario es pedir huella al entrar, volver a pedirla después de salir del modo y no pedirla al cerrar/reabrir solamente el widget durante una sesión Privada activa. El código actual usa `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`: permite Touch ID **o la contraseña de macOS**. Si la intención sigue siendo exigir estrictamente biometría, evaluar cambiar a `.deviceOwnerAuthenticationWithBiometrics`, manejar Mac sin Touch ID y mantener un mensaje de recuperación claro. La clave de llavero exige `.userPresence`.

El README y un comentario de `PrivateVault.swift` mencionan bloqueo automático a los 5 minutos o una hora, pero al corte de este resumen no se encontró ningún temporizador de inactividad para Privado en `ClipboardStore` ni en `AppDelegate`. El comportamiento confirmado en código es bloquear al salir de Privado y al terminar la app. Tratar el bloqueo por inactividad como documentación desactualizada hasta implementarlo y probarlo.

## Atajos y comportamiento del selector

- ⌘C: copia normal; la lista activa depende del espacio Normal o Fantasma. En Flash y Privado no importa automáticamente el contenido.
- ⌥V: pega la copia más reciente del espacio activo.
- ⌥⇧V: abre/cierra el selector.
- ⌥⇧C: captura la selección de la app activa para Flash y debería abrir el selector.
- Flechas y scroll cambian la selección; Enter/clic confirma; Esc/clic derecho cancela.
- El selector mide 360 × 44 pt y se coloca cerca del puntero.
- Pegar usa eventos de sistema; algunas apps pueden rechazar eventos sintéticos. En ese caso el texto queda en el portapapeles.

## Sonidos e identidad visual

- Activar Flash usa `Resources/malarbrush-camera-flash-204151.mp3`.
- Activar Privado usa `Resources/eaglaxle-switching-button-3-461630.mp3`.
- Los recursos de audio se reproducen a volumen 0,35.
- Activar Fantasma usa el sonido de sistema `Submarine`.
- `Resources/AppIcon-Purple.png` es el icono brillante del bundle y se utiliza en Ajustes.
- `Sources/PasteShifter/BrandIcon.swift` dibuja la silueta de la barra de menú.
- `Resources/Branding.md` explica la procedencia y uso de los activos visuales.

## Arquitectura y persistencia

- Lenguaje: Swift 5.9; mínimo declarado: macOS 13.
- UI y ciclo de app: AppKit + SwiftUI en `Sources/PasteShifter`.
- Lógica reutilizable: `Sources/ClipboardCore` (historial, colocación, selección por scroll/clic y liberación de modificadores).
- Atajos globales: Carbon `RegisterEventHotKey` en `HotKeys.swift`.
- Lectura de portapapeles: `NSPasteboard.general`, consulta cada 0,3 s (tolerancia 0,1 s); los datos se leen cuando cambia `changeCount`. Se ignoran los tipos de portapapeles `ConcealedType`, `TransientType` y `AutoGeneratedType`.
- Scroll y clic globales del selector: `CGEvent` tap; requiere permiso de Accesibilidad.
- Preferencias: `UserDefaults`.
- Normal/Fantasma/Flash: memoria de proceso; máximo 60 textos, hasta 256.000 bytes UTF-8 por texto (ver `ClipboardCore/History.swift`).
- Privado: archivo `~/Library/Application Support/Paste Shifter/PrivateHistory.enc`, cifrado AES-GCM y escrito atómicamente con protección de archivo. Clave aleatoria en el Data Protection Keychain.
- Servicio de llavero: `cl.pasteshifter.app.private-vault`; cuenta `NSUserName()`; grupo de acceso: `BJ345NMP76.cl.pasteshifter.app`.
- No se encontró StoreKit, analítica, SDK de terceros, servidor, red ni webview en el proyecto actual. Volver a revisar estas afirmaciones si se añaden dependencias.

## Firma y estado de instalación conocidos

- Bundle ID: `cl.pasteshifter.app`.
- Team ID configurado: `BJ345NMP76`.
- Identidad de desarrollo presente en el llavero: `Apple Development: Bastian Hidalgo (K5BZN7PQ9M)`, certificado con OU `BJ345NMP76`.
- Entitlements actuales solo declaran el grupo de llavero; `ENABLE_APP_SANDBOX=NO` en Debug y Release.
- Info.plist actual: versión `0.5.5`, build `13`, `LSMinimumSystemVersion=13.0`, `LSUIElement=true`.
- Instalación comprobada el 2026-10-11: `/Applications/Paste Shifter.app`, versión Release firmada por esa identidad, `TeamIdentifier=BJ345NMP76`, bundle ID y grupo de llavero iguales a los de la copia anterior. `codesign --verify --deep --strict` pasó.
- Copia anterior guardada para reversión en `/tmp/Paste Shifter.pre-install-20261011.app` (también quedó el respaldo previo `/tmp/Paste Shifter.previous-20261011.app`).
- `spctl -a -vv` rechazó el bundle local porque está firmado con Apple Development y no tiene Developer ID/notarización. Esto no contradice el resultado correcto de `codesign --verify`; es esperable para un build local de desarrollo, no es un paquete público listo para Gatekeeper.
- En una ejecución restringida, `security find-identity` inicialmente no pudo leer el llavero y dio una falsa impresión de que faltaba certificado. Al ejecutar la inspección de firma con acceso al llavero, apareció una identidad válida. Para builds firmados en entornos gestionados, verificar el acceso al login keychain antes de cambiar a firma ad hoc.
- No reemplazar la app de `/Applications` con `CODE_SIGNING_ALLOWED=NO`, firma ad hoc ni un Team ID distinto: TCC (Accesibilidad) y el grupo del Data Protection Keychain dependen de una identidad y requisitos de firma estables. La app anterior se conservó hasta verificar la nueva.

### Build e instalación

El script `scripts/build-app.sh` compila Release, copia a un staging dentro del repo, verifica el bundle firmado y lo intercambia de forma reversible en `dist/Paste Shifter.app`. No instala en `/Applications`. Usa `-allowProvisioningUpdates`; `PASTE_SHIFTER_REGISTER_DEVICE=1` permite pedir a Xcode registrar el Mac si un perfil lo requiere. No ejecutar una compilación ad hoc sobre la instalación de uso diario.

Comandos habituales:

```sh
swift test --disable-sandbox
./scripts/build-app.sh
codesign --verify --deep --strict "dist/Paste Shifter.app"
```

En un host con acceso al llavero limitado, ejecutar la compilación firmada fuera de ese sandbox autorizado; no cambiar `DEVELOPMENT_TEAM` para evitar el problema. Antes de instalar, comparar `Identifier`, `TeamIdentifier`, `com.apple.application-identifier` y `keychain-access-groups` contra la instalación vigente. Mantener backup y cerrar la app antes del reemplazo.

## App Store y distribución

**Estado actual: no preparada ni publicada en Mac App Store.** No hay constancia de registro de app, SKU, ficha, distribución, perfil Mac App Store Connect, certificado Apple Distribution, archivo subido ni revisión aprobada. Hay una identidad Apple Development válida para compilar en este Mac; no asumir que eso equivale a certificados de distribución.

Apple exige App Sandbox para distribuir una app macOS por Mac App Store. El target actual desactiva App Sandbox y usa observación global de teclado/ratón, `CGEventTap`, accesibilidad y eventos sintéticos. Antes de prometer App Store, hacer una prueba técnica de compatibilidad en un target sandboxed y revisar las API/permisos permitidos. Puede requerir rediseño del flujo global. También se requiere el flujo de App Store Connect con Bundle ID explícito, perfil de distribución Mac App Store y certificado de distribución; revisar el proceso actual de Xcode antes de preparar un archivo.

Para distribución directa fuera de Mac App Store, preparar una firma **Developer ID Application**, hardened runtime, notarización de Apple y empaquetado/instalador adecuado. El proyecto indica expresamente que no está notarizado.

Para App Store Connect se debe completar información veraz de privacidad y proporcionar URL de política de privacidad. La app cifra contenido local y no se identificó transmisión de texto; revisar todos los SDK/servicios agregados antes de declarar «no recopila datos». Como usa AES-GCM y guarda claves, revisar las preguntas vigentes de cumplimiento de exportación/criptografía de Apple al enviar.

Referencias oficiales (revisadas el 2026-10-11):

- [App Sandbox: requisito para Mac App Store](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Configurar App Sandbox en Xcode](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Preparar apps para distribución](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Crear un perfil App Store Connect para macOS](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)
- [Certificados Developer ID y distribución directa](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Notarizar software macOS](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Privacidad de apps en App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)

## Pruebas

### Pruebas automatizadas existentes

Hay seis archivos de pruebas en `Tests/ClipboardCoreTests`; la última ejecución conocida terminó con **19 tests, 0 fallos**. Cubren:

- historial, selección vigente, deduplicación, capacidad/límite de bytes y preservación exacta del texto;
- previews Unicode;
- colocación cerca del puntero y bordes/coordenadas negativas;
- desplazamiento, inercia y cambios de dirección;
- cancelación/confirmación de clic y liberación de modificadores.

No hay pruebas automatizadas directas de `PrivateVault`, LocalAuthentication, atajos Carbon, polling del portapapeles ni temporizador/limpieza Flash.

### QA manual de esta instalación

- Release firmada compiló e instaló correctamente; firma, Team ID, bundle ID y keychain group verificados.
- Normal: copié un texto ficticio y el selector mostró exactamente ese clip.
- Fantasma: copié un texto ficticio con Fantasma activo y el selector mostró ese clip separado, con el control identificando «Espacio Fantasma».
- Privado: el estado accesible mostró el icono `lock.fill`; una reapertura del selector no mostró un mensaje de bloqueo. No se confirmó de forma concluyente el diálogo físico de Touch ID ni el nuevo prompt después de salir/reingresar. No leer ni reproducir el contenido privado guardado para probarlo.
- Flash: el atajo real no quedó validado. `cua_repl` envió ⌥⇧C como el carácter `Ç` al campo de texto español, por lo que la prueba simulada no demuestra que falle el atajo físico. La apertura/selector Flash y la limpieza a los 60 s todavía requieren una prueba con entrada de teclado física o una vía de prueba interna que llame al mismo método sin alterar el portapapeles real.
- No se debe afirmar que Flash limpia al minuto basándose solo en leer el código; comprobarlo realmente en una sesión con un literal ficticio, esperar los 60 s y verificar el portapapeles vacío. Si el usuario copia algo después de la captura Flash, la expiración debe preservar esa nueva copia.
- El permiso de Accesibilidad se mostró activo en Ajustes después de instalar la versión firmada.
- El documento temporal usado para QA se movió fuera de iCloud a `/tmp/PasteShifter QA - temporary test document.rtf`. La sesión intentó vaciar el portapapeles al terminar, pero la revisión automática bloqueó esa acción porque no se había comprobado de forma fiable que solo contuviera datos de prueba. No intentar vaciarlo por otra vía; pedir autorización explícita o dejar que el usuario lo limpie.

Usar únicamente literales de prueba, nunca copiar textos existentes del usuario. No inspeccionar el contenido del portapapeles privado. Borrar cualquier documento temporal de prueba y cerrar el editor al terminar. Si un test exige tocar Touch ID, detenerse ante la solicitud y dejar que el usuario la confirme en el Mac; no pedir ni introducir la contraseña del usuario.

## Puntos de atención para futuras sesiones

1. Antes de instalar, construir y verificar firma con el mismo Team ID y el grupo de llavero anterior.
2. Probar Flash con una selección ficticia y entrada real de teclado; comprobar widget abierto, modo/contador visibles y clipboard borrado tras 60 s.
3. Probar Privado con el usuario completando Touch ID: pide al entrar, no al reabrir el widget en la misma sesión, y vuelve a pedir después de cambiar a Normal y regresar.
4. Resolver el conflicto de documentación/código sobre bloqueo por inactividad de Privado.
5. Si se apunta a Mac App Store, realizar primero el prototipo App Sandbox; la configuración actual no lo habilita.
6. Revisar versión/build y elevar `CFBundleVersion` para cada entrega a App Store Connect.
