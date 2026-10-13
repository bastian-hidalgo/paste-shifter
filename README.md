# Paste Shifter

Un portapapeles de textos para macOS, escrito en Swift con AppKit y SwiftUI. Vive en la barra de menú; no abre una ventana permanente ni aparece en el Dock.

## Probar la app

Requiere macOS 13 o posterior y Xcode / las herramientas de Swift para compilar.

```sh
./scripts/build-app.sh
open "dist/Paste Shifter.app"
```

En el primer inicio se abren los ajustes. Habilita **Paste Shifter** en **Ajustes del Sistema → Privacidad y seguridad → Accesibilidad**. Es necesario para enviar el comando de pegado a otras apps y capturar el scroll y clic globales mientras el selector está abierto. La captura del historial funciona sin este permiso.

Para uso diario, mueve la app a `/Applications` antes de conceder el permiso. Xcode firma la app con Apple Development y mantiene su grupo privado del llavero mediante un perfil macOS del equipo. La primera compilación requiere una cuenta de Apple Developer en Xcode y conexión a internet; para que Xcode también registre automáticamente el Mac, ejecuta `PASTE_SHIFTER_REGISTER_DEVICE=1 ./scripts/build-app.sh`. La app no está notarizada para distribución pública. En Ajustes puedes activar **Abrir al iniciar sesión en el Mac**. Usa el servicio nativo de macOS; si requiere aprobación, aparece un botón para abrir Ítems de inicio. Puedes desactivarlo desde la app o desde macOS. Conviene dejar la app en su ubicación definitiva antes de activarlo; moverla puede requerir volver a autorizarla.

### Si el permiso aparece activado pero no funciona

La firma ad hoc de una compilación nueva puede no coincidir con la autorización guardada. El registro de macOS muestra `Failed to match existing code requirement` en ese caso. No basta con volver a activar el interruptor de una entrada antigua.

1. Cierra la versión anterior desde el icono de la barra de menú → Salir y abre la app actual.
2. En sus ajustes pulsa **Mostrar esta app en Finder** para identificar la copia exacta.
3. Abre **Accesibilidad**, selecciona la entrada anterior de Paste Shifter y elimínala con **−**.
4. Añade la copia actual con **+** y habilítala. Si macOS pide reiniciar la app, hazlo.
5. Al volver, los ajustes actualizan el estado automáticamente. También puedes pulsar **Volver a comprobar**.

Cerrar los ajustes no termina la app; permanece en la barra de menú. Volver a abrir la app desde Finder muestra sus ajustes si no tiene ventanas visibles. La ventana tiene tamaño estable y scroll para evitar que los cambios de estado la colapsen.

La compilación firma y verifica un bundle nuevo con Xcode antes de sustituir el anterior; no modifica un ejecutable en ejecución. Al usar el mismo perfil y la misma identidad, las actualizaciones conservan la firma estable que macOS necesita para reconocer los permisos de Accesibilidad y del llavero.

## Uso

| Tecla | Acción |
| --- | --- |
| ⌘C | Copiar como siempre; el texto se agrega al historial y pasa a ser el activo. |
| ⌥V | Pegar siempre la copia más reciente, aunque antes hayas pegado otra del historial. |
| ⌥⇧V | Abrir o cerrar el selector. |
| ⌥⇧C | Copiar la selección actual en Flash durante 60 segundos. |
| ↑ / ↓ | Elegir un texto dentro del selector. |
| Scroll en cualquier parte de la pantalla | Elegir el texto anterior o siguiente con Magic Mouse o trackpad mientras el selector está abierto. |
| Clic en cualquier parte / Enter | Copiar el texto elegido al portapapeles y pegarlo en la app de origen. |
| Esc | Cerrar sin modificar el portapapeles. |

El selector es una cápsula compacta de **360 × 44 puntos**, con fondo claro en apariencia luminosa, borde fino, extremos totalmente redondeados y sombra suave. Respeta la apariencia oscura del sistema. Muestra la frase elegida y, atenuadas arriba y abajo, las frases vecinas; cada línea tiene hasta 50 caracteres. Incluye un contador como «3/8». Se pega siempre el texto completo, incluyendo espacios y saltos de línea originales. Tocar el icono del modo activo vuelve a Normal; desde Normal, el icono izquierdo abre Fantasma. El fantasma relleno junto a Enter alterna Fantasma, y en Privado aparece + para guardar el contenido actual del portapapeles.

El scroll cambia de texto desde cualquier parte de la pantalla, sin desplazar el documento de abajo; se filtra la inercia para evitar saltos accidentales. Un clic izquierdo en cualquier parte de la pantalla pega la selección en el campo original, sin activar el control que hay debajo del mouse. Se consume el clic completo y se confirma al soltar el botón. También funcionan ↑ / ↓, Enter y Esc.

En **Ajustes → Pegar al soltar ⌥ y ⇧** puedes activar otro modo: abre con ⌥⇧V, mantén ⌥⇧ mientras recorres las copias con el scroll y suelta ambos modificadores para pegar. Soltar solo V no confirma; puedes continuar eligiendo mientras mantengas los modificadores. Esc o un clic derecho cancela y desarma el pegado al soltar. Abrir el historial desde la barra de menú nunca activa ese modo. Por defecto está desactivado y se confirma con clic o Enter.

⌥V pega la última copia del espacio activo, aunque el globo resalte otra. En Normal usa la última copia normal. Pegar desde el selector no cambia el orden de las copias. ⌘V usa el contenido actual del portapapeles del sistema. ⌥⇧C envía ⌘C a la app activa y guarda la selección en el espacio Flash; las capturas normales quedan separadas.

Un LED de 8 puntos parpadea azul cuando se captura una copia de texto y verde al enviar el pegado desde Paste Shifter o detectar ⌘V (también ⌘⇧V). Dura unos 0,7 segundos, no recibe clics ni quita el foco. Aparece junto al cursor de escritura cuando está disponible; en caso contrario, junto al puntero. Puede desactivarse en Ajustes. Durante Flash, el icono de rayo y el contador aparecen en la barra de menú y siguen visibles aunque se cierre el selector. Salir de Flash cancela el contador y borra la copia de inmediato. El verde también acompaña el cierre con Esc o clic derecho: en esos casos no se pega nada. Indica el gesto de salida o envío del comando, sin confirmar que la aplicación insertó el contenido. Los pegados hechos desde menús de otras apps no pueden detectarse de forma general.

El selector aparece a 14 puntos del mouse al abrirlo, en la pantalla donde está el puntero. Si no cabe a la derecha o debajo, cambia de lado y se mantiene dentro del área visible. Permanece anclado ahí mientras eliges. Un clic izquierdo donde quieras confirma; Esc, clic derecho o cambiar de aplicación lo cierran. Incluye soporte para distintos monitores y ventanas a pantalla completa mediante un panel flotante de AppKit.

La captura global filtra **scroll y clic izquierdo** mientras el selector está abierto. Consume también la inercia y el ciclo completo de clic (presionar, arrastrar y soltar), sin filtrar teclas. Al cerrar se retira; si había un clic presionado, consume su liberación pendiente sin pegar. Requiere Accesibilidad. Si macOS no permite crear el filtro, todavía puedes recorrer y confirmar dentro del globo, y los ajustes indican que la interacción global no está disponible.

El globo aparece con un fade-in de 180 ms y un crecimiento suave del 96 % al 100 %. Al pegar o cancelar se expande al 105 % y se desvanece en unos 220 ms. El foco vuelve al campo original al iniciar la salida. Reabrirlo durante la animación cancela el cierre anterior. Con Reducir movimiento activado conserva el fundido sin cambiar de escala.

El icono de la barra de menú permite abrir el selector, cambiar de espacio, guardar en Privado, mandar una copia a Fantasma, eliminar la selección, borrar cada historial, pausar, abrir ajustes y salir. Si un atajo ya está reservado, los ajustes muestran el conflicto.

### Orbital

Orbital es la conexión local entre Paste Shifter para Mac y la app Android; no es un modo ni un historial aparte. La app de Mac incluye pairing por QR de un solo uso, aprobación explícita, listener Bonjour y transporte directo TLS 1.3 sobre Wi‑Fi. El clip individual se envía de forma explícita; compartir automáticamente copias nuevas de Normal es opt-in y empieza desactivado. Los clips recibidos se incorporan a Normal sin reemplazar el portapapeles ni volver a emitirse. Fantasma, Flash y Privado quedan excluidos.

La app Android nativa tiene pairing por QR local, conexión directa con pinning TLS y envío manual desde Compartir o desde su cuadro para escribir y pegar. En el Mac, cada clip Normal seleccionado se puede enviar de forma explícita al dispositivo conectado; compartir automáticamente sigue siendo opcional y empieza desactivado. El Android pone las copias recibidas directamente en su portapapeles, marca su vista previa como sensible y muestra una notificación local con sonido si las notificaciones están permitidas. La seguridad depende de validar estrictamente la huella del certificado leída en el QR; el descubrimiento Bonjour por sí solo no establece confianza. El protocolo rechaza clientes no emparejados y prueba cada reconexión con una firma fresca. Esto protege confidencialidad e integridad frente a intermediarios sin las claves confiables, aunque la red todavía puede bloquear o retrasar conexiones. Consulta el [plan de sincronización Mac–Android](PLAN_SYNC_ANDROID_MAC.md), la [app Android](Android/README.md) y la [especificación compartida del protocolo Orbital](OrbitalProtocol/README.md).

## Recursos y privacidad

- Sin cuentas, servidores, relays, analítica ni conexión a Internet en tiempo de ejecución. Orbital usa conexión directa en la Wi‑Fi local; la dependencia X.509 de Apple se incorpora durante la compilación. Sin Electron ni webviews.
- Hasta 60 textos; máximo 256.000 bytes UTF-8 por texto. Solo texto, con sus saltos de línea y espacios originales.
- Normal y Fantasma viven en memoria y desaparecen al salir. Al activar Fantasma, las copias nuevas van a esa lista oculta en vez de Normal. También puedes mover allí una copia seleccionada desde el menú.
- Privado solo agrega elementos al pulsar + o «Guardar portapapeles en Privado». Se cifra con AES-GCM; la clave aleatoria se guarda en el llavero de macOS, protegida por autenticación. Se desbloquea con Touch ID o la contraseña de la cuenta de macOS. No es un PIN propio de la app.
- En Ajustes, Privado se bloquea automáticamente a los 5 minutos, a la hora o al cerrar la app. Al bloquearlo, limpia la copia descifrada de la sesión; el archivo cifrado sigue hasta que el usuario elija «Borrar Privado».
- Flash copia la selección actual con ⌥⇧C. Su lista se elimina tras 60 segundos; al vencer, también limpia el portapapeles si sigue siendo la misma copia. Al salir de la app, la copia Flash se limpia de la misma forma.
- Consulta del contador del portapapeles cada 0,3 segundos, con tolerancia de 0,1 segundos; solo lee el contenido cuando ese contador cambia. Las copias extremadamente rápidas entre consultas pueden no capturarse. Con los LED activos y Accesibilidad autorizada, ⌘C también solicita una lectura a los 80 ms para reducir la latencia visual.
- Ignora las marcas estándar `ConcealedType`, `TransientType` y `AutoGeneratedType`. No puede detectar secretos de aplicaciones que no usan estas marcas. Pausa la captura cuando necesites copiar datos privados.
- Vaciar los historiales Normal, Fantasma y Privado borra sus listas; Flash también limpia la copia activa si sigue en el portapapeles. Pausar detiene la incorporación de nuevas copias; todavía permite pegar las anteriores.
- Los atajos usan Carbon; las flechas del selector se procesan en su ventana y el scroll y el clic izquierdo se interceptan globalmente solo mientras el selector está abierto. Con Accesibilidad y los LED habilitados, un observador de eventos detecta ⌘C / ⌘V sin guardar pulsaciones ni interceptarlas. No se registra lo que escribes en otras apps.

La entrega de ⌘V está implementada con eventos del sistema. Apps que bloquean eventos sintéticos, campos protegidos y apps que no aceptan texto pueden impedir el pegado. No es posible confirmar programáticamente que cualquier aplicación haya insertado el texto: si falla, el texto elegido queda disponible en el portapapeles para pegarlo manualmente.

## Desarrollo y validación

```sh
swift test --disable-sandbox
./scripts/build-app.sh
```

`--disable-sandbox` desactiva únicamente el sandbox de compilación de SwiftPM, necesario al compilar desde algunos entornos que ya están restringidos. La app necesita permisos de Accesibilidad y no se distribuye con App Sandbox.

Las diecinueve pruebas verifican deduplicación, selección del texto activo, límites por bytes y cantidad, limpieza, preservación exacta del texto y filtrado del scroll continuo, la inercia y los cambios de dirección. También verifican que la última copia sea independiente de la selección anterior, el límite Unicode de la vista previa y la confirmación al soltar ambos modificadores una sola vez, con cancelación. Verifican además que el scroll se consuma únicamente con el selector abierto, que la inercia no se propague y la colocación junto al mouse en bordes y monitores con coordenadas negativas. Las pruebas de clic verifican la confirmación única al soltar, la cancelación durante una pulsación y la reapertura sin confirmar un clic anterior. Para validar la integración real:

1. Autorizar Accesibilidad y abrir TextEdit con un documento vacío.
2. Copiar dos textos distintos con ⌘C, esperando un segundo entre copias.
3. Abrir con ⌥⇧V, elegir el anterior con ↓ y pegar con Enter.
4. Pulsar ⌥V; comprobar que pega el último texto copiado, aunque se eligió el anterior en el selector.
5. Recorrer copias, cancelar con Esc y comprobar que el documento y el portapapeles no cambian.
6. Probar clic izquierdo afuera para pegar, clic derecho para cancelar, cambio de app, pantalla completa, segundo monitor y apariencia oscura.
7. Pausar, copiar otro texto y verificar que no se incorpora al historial.
8. Abrir el selector junto al mouse y recorrer el historial con el scroll del Magic Mouse sobre la aplicación de fondo, fuera del globo: cambia la selección y el documento permanece inmóvil. Cerrar con Esc y comprobar que el scroll vuelve a desplazar el documento. Comprobar también los bordes del monitor y la inercia.
9. Activar el pegado al soltar en ajustes. Mantener ⌥⇧ al abrir con ⌥⇧V, recorrer con el scroll y soltar ambos modificadores: debe pegar solo una vez. Repetir y cancelar con Esc: no debe pegar al soltar.
10. Confirmar con clic sobre un botón de otra app: pega en el campo original sin activar ese botón. Cancelar con Esc mientras se mantiene presionado el mouse y soltar: no debe pegar.
11. Revisar la entrada y salida animadas, reabrir durante el fade-out y probar Reducir movimiento. Esc debe mostrar el verde sin pegar.
12. Activar el inicio automático, comprobar Paste Shifter en Ajustes del Sistema → General → Ítems de inicio y cerrar/reabrir sesión para verificarlo. Desactivarlo y comprobar que deja de abrirse.
13. Comprobar el pulso azul al copiar y el verde al pegar con ⌥V, Enter o ⌘V. Verificar que no cambian el foco y que el ajuste permite desactivarlos.

La compilación genera un bundle local en `dist/Paste Shifter.app`, firmado con Apple Development. Para distribuir a otras personas se necesita firma Developer ID y notarización de Apple.

Para revisar el diseño sin capturar ni modificar el portapapeles, cierra la app y ábrela con `open "dist/Paste Shifter.app" --args --demo`. Este modo usa cinco textos ficticios y no realiza pegados.
