# La Taberna

Addon privado de **World of Warcraft: Forever** para un grupo de amigos.
Añade una capa de juego propia por encima del WoW: una **liga por temporadas**
con rankings automáticos (enemigos, duelos, oro, tiempo jugado…) y una
puntuación general, sincronizada entre todos los miembros de la hermandad que
tengan el addon instalado.

## Cómo funciona

1. **Alguien crea la sesión** (`/taberna crear`) y se convierte en el
   **organizador**: la autoridad de la liga.
2. El addon anuncia la sesión por el **canal de hermandad** (mensajes de addon,
   invisibles en el chat). El resto recibe una invitación y se une con un clic
   o con un código.
3. La liga es **por cuenta, no por personaje**: cada participante se identifica
   por su BattleTag, así que da igual con qué personaje entre — sus números son
   siempre los mismos.
4. Cada addon **cuenta automáticamente** lo que hace su jugador (enemigos
   derrotados, duelos, oro ganado, tiempo jugado, misiones, muertes, honor,
   rares y profesiones) y lo comparte con el grupo.
5. De todos esos rankings sale la **puntuación general de la liga** con un
   sistema de puntos por posición (Borda): en cada ranking, el 1.º suma N
   puntos, el 2.º N−1 y así hasta el último con valor mayor que cero (N =
   participantes con valor en ese ranking). Los empates comparten puntos. Como
   solo importa la posición, no se mezclan escalas (miles de oro contra unos
   pocos duelos).
6. La clasificación se actualiza en todos los addons a la vez, y el estado se
   **guarda entre sesiones** y se sincroniza al reconectar: si entras tarde,
   tu addon pide el estado completo al organizador.

Si el organizador se desconecta, la sesión queda **en pausa** hasta que vuelva
(no hay elección automática de líder: es un grupo de confianza).

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
| `/taberna unirse <código>` | Te unes a una liga con su código de invitación |
| `/taberna alias <nombre>` | Te pones un alias (vacío para volver al BattleTag) |
| `/taberna export` / `import` | Respaldo copiable del estado |
| `/taberna jugado` | Tu tiempo jugado por cuenta, con desglose por personaje |
| `/taberna anunciar` | Publica el top 5 de la clasificación en el chat de hermandad |
| `/taberna escala 0.6-1.6` | Tamaño de la ventana (`reset` para el defecto) |
| `/taberna estado` | Versiones, APIs disponibles y estado de la sesión |
| `/taberna depura` | Activa el diagnóstico de contadores |

La ventana tiene cuatro pestañas:

- **Clasificación** — la puntuación general de la liga (sistema Borda sobre
  todos los rankings), con medallas de oro/plata/bronce en el podio, punto
  verde/gris de conexión y un tooltip con el desglose: de dónde sale cada
  punto.
- **Liga** — rankings automáticos con menú lateral: **enemigos derrotados**,
  **duelos ganados y perdidos**, **rares**, **oro ganado**, **tiempo jugado**,
  **misiones**, **muertes**, **muertes con honor** y **profesiones**. Cada
  addon cuenta los suyos y los comparte con el grupo.
- **Historial** — las sesiones cerradas, más recientes primero.
- **Sesión** — estado en dos columnas, invitaciones, respaldo y zona
  peligrosa (borrado con doble confirmación).

Además: icono de minimapa arrastrable con estado de la sesión en el tooltip,
sonidos al recibir invitaciones o perder el liderato de un ranking, y anuncio
en el chat cuando alguien toma el liderato.

### Código de invitación

El organizador (o cualquier participante) puede compartir la sesión aunque
estés desconectado cuando se creó: pestaña **Sesión → Código de invitación**,
lo copias y se lo pasas a tus amigos. Ellos se unen con:

```
/taberna unirse <código>
```

### Borrado de datos

Nada se borra solo: los resultados, las estadísticas y el historial se
conservan siempre. Solo hay dos acciones destructivas, ambas con **doble
confirmación** (hay que pulsar el botón dos veces):

- **Reiniciar liga** — solo el líder; pone a cero las estadísticas para
  todos los participantes.
- **Borrar historial** — limpia tu archivo local de sesiones cerradas.

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

- Forever **bloquea** que los addons se suscriban al registro de combate (es
  acción protegida). Por eso los contadores no usan el combat log:
  - Enemigos, duelos (ganados y perdidos), misiones, muertes y honor se leen
    de las **estadísticas nativas del juego** (`GetStatistic`, IDs verificados
    contra `Achievement.db2` del build 1.60.1), contando solo los incrementos
    desde que entraste en la liga. Inmune a traducciones y no se pierde nada.
  - Oro: por el evento `PLAYER_MONEY` (solo suman los incrementos).
  - Tiempo jugado: por `RequestTimePlayed`, sumando los personajes de la
    cuenta (el servidor limita el ritmo: una petición por personaje y sesión).
  - Rares: se detectan por **eventos de unidad** (clasificación rare +
    muerte); no existe estadística nativa de rares.
- Los comandos `/taberna stat <id>` y `/taberna scanstats <a> <b>` son
  herramientas de diagnóstico sobre el panel de estadísticas del juego.
- La clasificación muestra 15 filas y cada ranking de la liga 14; para grupos
  mayores habrá que añadir scroll.
- Es un diseño para un **grupo de confianza**, no un sistema antitrampas.

## Roadmap

- **Minijuegos**: bingo cooperativo, contratos secretos, liga de duelos,
  premios de la sesión por votación, quiz de Warcraft.
- **Más automatización** con eventos no restringidos: subida de nivel,
  llegada a zonas.
