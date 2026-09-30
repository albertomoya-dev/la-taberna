# La Taberna

Addon privado de liga para un grupo de amigos en WoW Forever. Una temporada
compartida con retos, puntos y clasificación, sincronizada por el canal de
hermandad. La validación la hace el organizador: es un diseño para un grupo de
confianza, no un sistema antitrampas.

## Instalación

1. Copia la carpeta `LaTaberna` dentro de `Interface/AddOns/` del cliente.
2. En el juego, ejecuta `/run print(GetBuildInfo())` y anota el primer número.
3. Abre `LaTaberna.toc` y pon ese número en la línea `## Interface:`.
4. Recarga la interfaz con `/reload` (o reinicia el cliente).

Todos los participantes deben estar en la misma hermandad: la sincronización
usa el canal de addon `GUILD`.

## Comandos

| Comando | Qué hace |
| :-- | :-- |
| `/taberna` | Abre o cierra la ventana |
| `/taberna crear` | Crea una sesión (serás el organizador) |
| `/taberna salir` | Sale de la sesión; el organizador la cierra para todos |
| `/taberna export` | Muestra un respaldo copiable del estado |
| `/taberna import` | Restaura un respaldo |

## Reglas de la liga (propuesta inicial)

- Los puntos solo los concede el organizador, confirmando resultados desde la
  pestaña **Retos**.
- Hay 3 retos activos por sesión, editables por el organizador.
- Retos iniciales de ejemplo:
  - **Mazmorra elegida** — 10 pt por participante que la complete.
  - **Rally por Azeroth** — 5 pt al ganador del rally previo.
  - **Contrato cumplido** — 3 pt por contrato secreto revelado y aceptado.
- Si el organizador está desconectado, las confirmaciones quedan en pausa.
- Ajustad las reglas tras las primeras sesiones; lo importante es que el que
  más juega no gane automáticamente.

## Cómo funciona por dentro

- `Rules.lua` — lógica pura: retos, puntos y clasificación. Sin API de WoW.
- `Protocol.lua` — formato de mensajes `OP|pv|sid|eid|campos…` con escape.
- `Storage.lua` — `SavedVariables` con versión de esquema y export/import.
- `Session.lua` — participantes, rol de organizador y aplicación de eventos.
- `Communication.lua` — cola con prioridad y ritmo limitado, snapshots
  troceados por susurro.
- `Stats.lua` — contadores de enemigos, duelos y rares (registro de combate y
  mensajes de duelo, con protección ante valores secretos) y su difusión.
- `UI.lua` — ventana con pestañas (Clasificación, Liga, Retos, Sesión).
- `Core.lua` — inicialización, eventos y comandos.

El id de sesión es `CuentaOrganizador:timestamp`, así que cualquier mensaje
identifica a su autoridad. La identidad es **por cuenta** (BattleTag vía
`BNGetInfo`); si la API no está disponible se usa el personaje como fallback.
Cada resultado lleva un id de evento único y los duplicados se descartan. Al
entrar o reconectar, el cliente pide el estado (`SREQ`) y el organizador
responde con un snapshot troceado (`SNAP`).

## Checklist de pruebas en el cliente (Forever)

Pendiente de verificar en el juego real; la API puede cambiar antes del
lanzamiento.

- [ ] El addon carga sin errores con `/console scriptErrors 1`.
- [ ] `## Interface:` del `.toc` coincide con `GetBuildInfo()`.
- [ ] `/taberna` abre y cierra la ventana; se cierra también con Esc.
- [ ] Crear sesión: aparecen los 3 retos y el organizador en la pestaña Sesión.
- [ ] Un segundo jugador recibe la invitación y se une; ambos ven al otro en
      la clasificación.
- [ ] El organizador confirma un reto y **ambos** clientes muestran los mismos
      puntos.
- [ ] Editar un reto propaga el cambio al otro cliente.
- [ ] `/reload` mantiene la sesión; **logout → login también** (en la beta se
      reportaron fallos de `SavedVariables`; si falla, usar export/import).
- [ ] Reconexión: un participante que entra tarde recibe el snapshot completo.
- [ ] Con el organizador desconectado, la pestaña Sesión indica
      "confirmaciones en pausa".
- [ ] Mensajes con versión de protocolo distinta se ignoran con aviso en chat.

## Limitaciones conocidas

- Sin métricas automáticas de combate (valores secretos de Forever).
- Sin comunicación HTTP: no hay backend ni web en esta versión.
- La clasificación muestra 21 filas y el selector de participantes 20; si el
  grupo crece más, habrá que añadir scroll.
- Sin elección automática de organizador: si se va, la sesión queda en pausa.

## Próximas fases

Bingo cooperativo, contratos secretos, liga de duelos, premios por votación y
automatización de retos con eventos no restringidos (`PLAYER_LEVEL_UP`,
`ZONE_CHANGED_NEW_AREA`, `PLAYER_DEAD`).
