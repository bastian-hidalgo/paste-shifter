# Paste Shifter — identidad

- `AppIcon-Purple.png`: icono aprobado, con transparencia, utilizado por `MakeIcon.swift` para generar todos los tamaños del `.icns`.
- `Sources/PasteShifter/BrandIcon.swift`: silueta vectorial para la barra de menú, con un distintivo del modo activo. `isTemplate` permite a macOS mostrarla blanca u oscura según el fondo.
- Ajustes usa el icono de aplicación brillante (`AppIcon-Purple.png`) mediante el icono instalado en el bundle; no usa la silueta 2D.
- El icono conserva la política de app de barra de menú: aparece en Finder / Aplicaciones, pero la app no agrega un elemento permanente al Dock.

El bitmap se preparó con la herramienta integrada **imagegen**, a partir de la propuesta morada aprobada. Prompt final:

> Prepare this EXACT approved purple sparkle macOS app icon as a production transparent PNG asset. Background extraction edit only: remove all off-white background outside the rounded-square icon and remove the external cast shadow. Preserve the purple glitter lacquer, reflective rim, white two-part S logo geometry and every interior detail unchanged. Show only the isolated icon, front facing, on genuinely transparent alpha background. Square image canvas, center the icon, leave approximately 8% transparent margin on each side as standard macOS app icon padding. No new elements, no lettering, no mockup. Do not redesign the icon.
