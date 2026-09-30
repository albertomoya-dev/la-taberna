# La Taberna

Addon privado de **World of Warcraft: Forever** para un grupo de amigos.
Añade una capa de juego propia por encima del WoW: una **liga por temporadas**
con retos, puntos y clasificación, sincronizada entre todos los miembros de la
hermandad que tengan el addon instalado.

La idea: que no gane quien más horas juega, sino quien cumple los retos de las
sesiones compartidas.

## Cómo funciona

1. **Alguien crea la sesión** (`/taberna crear`) y se convierte en el
   **organizador**: la autoridad de la liga.
2. El addon anuncia la sesión por el **canal de hermandad** (mensajes de addon,
   invisibles en el chat). El resto recibe una invitación y se une con un clic.
3. La liga es **por cuenta, no por personaje**: cada participante se identifica
   por su BattleTag, así que da igual con qué personaje entre — sus puntos son
   siempre los mismos.
4. La sesión tiene **3 retos activos** (título, descripción y puntos), que el
   organizador puede editar en cualquier momento.
5. Cuando alguien cumple un reto, **el organizador lo confirma** desde la
   ventana del addon y los puntos se reparten al instante a todos los clientes.
6. La **clasificación** se actualiza en todos los addons a la vez. Cada
   resultado lleva un identificador único, así que no se puede puntuar dos
   veces lo mismo.
7. El estado se **guarda entre sesiones** y se sincroniza al reconectar: si
   entras tarde, tu addon pide el estado completo al organizador.

Si el organizador se desconecta, las confirmaciones quedan **en pausa** hasta
que vuelva (no hay elección automática de líder: es un grupo de confianza).

### Retos iniciales de ejemplo

| Reto | Puntos |
| :-- | --: |
| Completar la mazmorra elegida por el grupo | 10 |
| Ganar el rally previo a la sesión | 5 |
| Completar y revelar un contrato secreto | 3 |

Son solo la propuesta inicial: el organizador puede reescribirlos desde la
propia ventana del addon.

## Instalación

1. Copia la carpeta [`LaTaberna`](LaTaberna/) dentro de `Interface/AddOns/`
   del cliente de WoW Forever.
2. En el juego, ejecuta `/run print(GetBuildInfo())` y anota el primer número.
3. Abre `LaTaberna/LaTaberna.toc` y pon ese número en la línea `## Interface:`.
4. `/reload` (o reinicia el cliente).

**Requisito:** todos los participantes deben estar en la misma hermandad — la
sincronización usa el canal de addon `GUILD`.

## Uso

| Comando | Qué hace |
| :-- | :-- |
| `/taberna` | Abre o cierra la ventana |
| `/taberna crear` | Crea una sesión (serás el organizador) |
| `/taberna salir` | Sale de la sesión; el organizador la cierra para todos |
| `/taberna export` | Muestra un respaldo copiable del estado |
| `/taberna import` | Restaura un respaldo |

La ventana tiene tres pestañas:

- **Clasificación** — puntos de cada participante, en orden.
- **Retos** — los 3 retos activos; el organizador ve además los botones
  *Confirmar…* (elegir quién lo completó) y *Editar*.
- **Sesión** — organizador, tu rol, participantes, estado de las
  confirmaciones y botones de crear/salir/exportar/importar.

## Qué hay debajo (resumen técnico)

- **Lua + API de WoW**, sin frameworks y sin XML: toda la interfaz se
  construye por código.
- **Comunicación entre addons** con `C_ChatInfo.SendAddonMessage` por el canal
  `GUILD`, con un protocolo propio (`OP|versión|sesión|evento|campos…`), cola
  de envío con prioridad y límite de ritmo, y snapshots troceados por susurro
  para las reconexiones.
- **Persistencia** con `SavedVariables` versionadas + export/import manual
  como red de seguridad.
- **Sin backend**: un addon no puede hacer peticiones HTTP; una futura web de
  estadísticas se haría por exportación.

La documentación técnica completa (modelo de datos, protocolo, checklist de
pruebas en el cliente) está en [`LaTaberna/README.md`](LaTaberna/README.md).

## Limitaciones conocidas

- **Nada de métricas de combate automáticas** (daño, curación, quién la lió):
  Forever usa "valores secretos" que los addons no pueden procesar. La
  validación la hace el organizador.
- La clasificación muestra 21 filas y el selector de participantes 20; para
  grupos mayores habrá que añadir scroll.
- Es un diseño para un **grupo de confianza**, no un sistema antitrampas.

## Roadmap

- **Fase 2 — Robustez**: historial navegable, más tolerancia a mensajes
  desordenados.
- **Fase 3 — Minijuegos**: bingo cooperativo, contratos secretos, liga de
  duelos, premios de la sesión por votación, quiz de Warcraft.
- **Fase 4 — Automatización** con eventos no restringidos: subida de nivel,
  llegada a zonas, muertes (para premios de humor).
