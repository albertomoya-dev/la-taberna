# Análisis de Forever IRS (0.5.2) y propuesta para La Taberna

Fuente: `referencia/ForeverIRS/` (copia íntegra del release 0.5.2 de CurseForge,
licencia MIT, autor "Forever IRS contributors", verificado contra el build
1.60.1.70124 del cliente Forever — el mismo que usamos).

## 1. Lo que hace Forever IRS

Es un "libro contable" de estadísticas de personaje. Su idea central es
**no contar eventos propios, sino leer los contadores que el propio juego
lleva por personaje** (la pestaña Estadísticas del panel de Logros):

- Para uno mismo: `GetStatistic(id)` directamente.
- Para otro jugador cercano: `SetAchievementComparisonUnit(unit)` +
  esperar el evento `INSPECT_ACHIEVEMENT_READY` + `GetComparisonStatistic(id)`.
- Guarda snapshots locales (máx. 20 por personaje) en SavedVariables y permite
  comparar capturas en el tiempo.

## 2. Técnica clave: IDs de estadísticas verificados

IDs extraídos de `Achievement.db2` del build 1.60.1.70124
(wago.tools/db2/Achievement/csv). Los relevantes para La Taberna, **todos
confirmados en los datos del cliente**:

| ID | Estadística | Uso en La Taberna |
|----|-------------|-------------------|
| 107 | Creatures killed | Contador de enemigos (sustituye al parseo de mensajes de XP) |
| 319 | Duels won | Duelos ganados (sustituye al parseo de CHAT_MSG_SYSTEM) |
| 320 | Duels lost | Duelos perdidos (nuevo, desempates) |
| 328 | Total gold acquired | Oro total ganado (válido entre personajes de la misma cuenta… con matices, ver §6) |
| 334 | Most gold ever owned | Pico histórico de oro |
| 333 | Gold looted | Oro looteado |
| 326 | Gold from quest rewards | Oro de misiones |
| 921 | Gold from vendors | Oro de vendedores |
| 919 | Gold earned from auctions | Oro de subastas |
| 98 | Quests completed | Misiones completadas |
| 588 | Total Honorable Kills | HKs totales |
| 60 | Total deaths | Muertes totales (¡leaderboard de "más muertes"!) |
| 932 | Dungeons entered | Mazmorras |
| 1518 | Fish caught | Pesca |

No existe estadística de "rares matados" en el db2: los **rares siguen
necesitando nuestra detección por eventos** (UnitClassification).

Defensas que usa al leer (debemos copiarlas):

- `issecretvalue(value)` — Forever tiene "secret values" (como Midnight); un
  valor secreto no se puede usar, hay que tratarlo como no disponible.
- `pcall(getter, id)` por cada estadística; si falla, se marca la razón
  (`readError`, `skipped`, `unsupported`, `notReported`).
- Valores monetarios pueden venir como texto con iconos (`|TInterface\MoneyFrame\...|t`);
  incluye un parser estricto a cobre (`parseMoney`) que rechaza formatos
  ambiguos en vez de adivinar.
- Filosofía: **"missing no es cero"** — un contador no reportado se muestra
  como `--` gris, nunca como 0. Importante para la liga: no acusar a nadie
  de hacer trampas por un contador ausente.

## 3. Cómo está programado (arquitectura)

- `local ADDON, I = ...` — una única tabla `I` compartida entre archivos vía
  varargs del toc; todo cuelga de `I` (igual que nuestra tabla `LaTaberna`).
- Un solo frame de eventos con todos los `RegisterEvent` listados en un
  bucle; handler como función anónima con `if/elseif` por evento.
- Estado de petición con **timeout y anti-spam**: `pending` único, 5 s de
  espacio entre peticiones, deadline de 15 s, sin reintento automático.
- `hooksecurefunc` sobre `SetAchievementComparisonUnit` /
  `ClearAchievementComparisonUnit` para detectar que otro addon "roba" la
  comparación y ceder limpiamente.
- Guardia de compatibilidad con el panel de logros de Blizzard
  (`installAchievementGuard`): el frame de comparación solo se suscribe al
  evento mientras está visible. Evita errores de la UI nativa.
- Storage con **esquema versionado** (SCHEMA=3) y validación exhaustiva de
  todo lo que viene de SavedVariables (tipos, rangos, longitudes, GUID con
  patrón `^Player%-%w[%w%-]*$`). Si el guardado es de una versión más nueva,
  entra en modo "session only" y no lo pisa.
- Comandos slash con subcomandos (`/irs target|me|history|status|scale|reset`).
- Ventana registrada en `UISpecialFrames` (se cierra con Escape), posición y
  escala persistidas y validadas.

## 4. La interfaz (lo que la hace verse profesional)

La nuestra usa texturas planas dibujadas a mano; la suya **reutiliza las
plantillas nativas del cliente**, y por eso parece parte del juego:

1. **`ButtonFrameTemplate`** como ventana principal: marco metálico, barra de
   título, botón de cierre, retrato circular (`SetPortraitToAsset`) e inset —
   idéntica a la ventana de Inspeccionar. Esto existe y funciona en Forever.
2. **Pestañas inferiores** con `PanelTabButtonTemplate`,
   `PanelTemplates_SetNumTabs` / `PanelTemplates_SetTab` /
   `PanelTemplates_TabResize`, y sonido `SOUNDKIT.IG_CHARACTER_INFO_TAB` al
   cambiar. (Nuestras pestañas actuales son botones caseros dentro del
   marco; las suyas cuelgan del borde inferior como las ventanas de Blizzard.)
3. **Botones `UIPanelButtonTemplate`** (los rojos estándar del juego).
4. **Moneda con iconos de moneda reales** (`|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t`),
   omitiendo denominaciones vacías (90 cobre se lee "90c", no "0g 0s 90c") y
   respetando `colorblindMode`.
5. **Filas rayadas** (fondo blanco al 5% en filas impares), etiqueta dorada a
   la izquierda y valor a la derecha; **tooltip en cada cifra** explicando su
   origen.
6. **Cabeceras de columna ordenables** (`ColumnDisplayButtonShortTemplate` +
   atlas `auctionhouse-ui-sortarrow`), con orden persistente.
7. **Buscador** con `SearchBoxTemplate` (texto de instrucciones y botón de
   limpiar incluidos).
8. Nombre del personaje **coloreado por clase** (`RAID_CLASS_COLORS`,
   resolviendo el token a través de `LOCALIZED_CLASS_NAMES_MALE/FEMALE`).
9. **Escala de ventana** 0.6–1.6 (`/irs scale`), con ajuste automático para
   que quepa en pantalla (`fit` contra `UIParent`).
10. Barra de progreso con `Interface\TargetingFrame\UI-StatusBar`.
11. Ventana de "copiar informe": `ButtonFrameTemplate` + `ScrollFrame` +
    `EditBox` multilínea con todo seleccionado — exactamente el patrón que
    ya usamos para el código de invitación.

## 5. Qué NO tiene (nuestro terreno)

- Nada de red: ni mensajes de addon, ni sesiones, ni liga. Es 100% local.
- Nada de rares, ni retos, ni pestañas múltiples de clasificación.

## 6. Propuesta de incorporación a La Taberna

### 6.1 Contadores por estadísticas (cambio mayor de fiabilidad)

Sustituir la detección por mensajes de chat por **deltas de GetStatistic**
muestreados periódicamente (p. ej. cada 30 s y al ganar XP / terminar duelo):

- Enemigos: delta de `GetStatistic(107)` respecto al valor al entrar en sesión.
- Duelos: delta de `GetStatistic(319)` (ganados) y 320 (perdidos).
- Oro: seguimos con PLAYER_MONEY para "oro actual", pero podemos añadir
  "oro ganado" con delta de 328.

Ventajas: inmune a formatos de chat localizados, no se pierde nada si el
mensaje no llega, y no depende de que la criatura dé XP (el chat de XP solo
cuenta muertes con XP; el contador 107 cuenta **todas** las criaturas).

Precauciones: leer con `pcall`, tratar `issecretvalue` como "no disponible",
y nunca convertir ausencia en cero (regla "missing ≠ 0" de IRS).

### 6.2 Interfaz al estilo IRS

- Migrar la ventana principal a `ButtonFrameTemplate` con retrato propio
  (podemos generar un TGA; IRS incluye script `make_portrait.py` como
  referencia del enfoque).
- Pestañas inferiores con `PanelTabButtonTemplate` + sonido de pestaña.
- Botones `UIPanelButtonTemplate` en barra inferior.
- Clasificación con filas rayadas, cabeceras ordenables con flecha y
  nombres coloreados por clase.
- Oro con iconos de moneda reales.
- Tooltips explicativos en cada cifra ("reportado por el juego", "no
  disponible ≠ 0").
- Escala configurable `/taberna escala 0.6-1.6` y posición persistente.
- Aviso de precisión en el pie, como su DISCLAIMER.

### 6.3 Robustez que conviene copiar

- Validación estricta al cargar SavedVariables (ya tenemos algo; endurecer
  tipos y rangos como su `cleanSnapshot`).
- `UISpecialFrames` para cerrar con Escape (si no lo tenemos ya).
- Comando `/taberna estado` al estilo de su `/irs status` (versiones, APIs
  disponibles) — ya tenemos `/taberna depura`; unificar.
- Tests: su repo tiene un harness que simula la API de WoW (`tests/`); a
  largo plazo nos vendría bien algo así para no depender solo del cliente.

### 6.4 Lo que NO debemos copiar

- La inspección de otros jugadores (`SetAchievementComparisonUnit`): en la
  liga cada miembro se reporta a sí mismo por el canal de hermandad; no
  necesitamos inspeccionar, y así funciona a cualquier distancia.
- Su ausencia total de red es justo lo contrario a nuestro diseño.

## 7. Nota sobre los rares

Confirmado: no hay contador de rares en las estadísticas del juego. Nuestra
vía sigue siendo la detección por `UnitClassification("target")` ==
`"rare"`/`"rareelite"` + muerte detectada por eventos de unidad. Pendiente de
validación en campo.
