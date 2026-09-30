<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# El 4 de nomviemvre sale wow forever, vamos a jugar unos cuantos amigos. Y me gustaría crear algún adddon entre nosotros. Que nos de un extra de diversión o competitivas. Me gustaría saber si es posible y qué ideas podríamos hacer

Sí, podéis crear un addon privado para vuestro grupo y añadir una “capa de juego” propia: retos, puntos, rivalidades, logros absurdos y minijuegos. Para vosotros, yo empezaría por una liga de amigos con desafíos y un bingo de aventuras, no por otro medidor de daño. Forever admite addons, aunque su API tiene restricciones que conviene tener en cuenta desde el diseño.[^1_1][^1_2]

Y sí: Blizzard confirma el lanzamiento para el 4 de noviembre de 2026.[^1_3]

## Qué es posible hacer

Un addon puede tener ventanas propias, comandos, ajustes y datos guardados. Se desarrolla principalmente en Lua, con un archivo `.toc` que declara qué cargar; XML es opcional. Con tu experiencia programando, el reto principal será aprender la API de WoW y sus limitaciones, más que el lenguaje.[^1_4][^1_5]

También existe comunicación entre addons mediante `C_ChatInfo.SendAddonMessage`: permite intercambiar mensajes por canales como grupo, banda, hermandad o susurros, sin llenar el chat normal. Es la base para compartir desafíos, resultados y clasificaciones entre quienes tengan vuestro addon instalado. Su funcionamiento concreto habrá que probarlo en Forever.[^1_6][^1_7]

La precaución importante: Forever utiliza restricciones del WoW moderno, incluidos “valores secretos” que los addons no pueden procesar libremente. Las pruebas de la beta señalan limitaciones fuertes para analizar el registro de combate, así que no daría por hecho que podéis calcular daño, curaciones o quién cometió determinado error.[^1_2][^1_1]

Por eso plantearía tres tipos de objetivos: automáticos cuando la API lo permita, declarados por el jugador y confirmados por el grupo.

## Ideas para vuestro grupo

Estas son propuestas de diseño, no funciones que ya haya comprobado en el cliente. La dificultad presupone que podéis usar confirmación manual cuando no haya una API accesible.


| Idea | Cómo se jugaría | Qué aporta | Dificultad |
| :-- | :-- | :-- | :-- |
| Liga de colegas | Temporadas con puntos por retos, carreras y actividades compartidas | Competición continuada sin depender solo del nivel | Media |
| Bingo de aventuras | Cartón compartido con casillas como completar una mazmorra, pescar un objeto concreto o visitar un lugar | Os anima a salir de la ruta habitual | Baja-media |
| Contratos secretos | Cada uno recibe un objetivo privado y lo revela al cumplirlo | Sorpresas y piques durante la sesión | Media |
| Rally por Azeroth | Carrera con puntos de control y reglas acordadas sobre transporte | Eventos concretos para jugar todos juntos | Media |
| Mazmorras con modificadores | Antes de entrar se sortea una regla: sin consumibles, equipo limitado o una pausa obligatoria en cierto punto | Rejugar contenido con un giro | Baja si la validación es manual |
| Premios de la sesión | Votaciones a “mejor rescate”, “GPS averiado” o “negociador del año” | Humor y anécdotas del grupo | Baja |
| Liga de duelos | Cuadro de participantes, emparejamientos, resultados y revancha | Competición PvP organizada entre vosotros | Baja-media |
| Quiz de Warcraft | Preguntas sincronizadas con tiempo para responder | Minijuego para viajes o esperas | Baja-media |

Los contratos secretos pueden ser especialmente divertidos, pero evitaría objetivos que impliquen fastidiar a otros jugadores o provocar un wipe. Mejor “consigue que alguien te fabrique un objeto” que “haz morir al healer”.

## Mi apuesta: liga y bingo

Para vuestro caso diseñaría un addon provisionalmente llamado *La Taberna*: una temporada privada donde competir y, a la vez, conseguir objetivos juntos.

La gracia sería que el que juega más horas no ganara automáticamente. Mi propuesta:

- Puntos principalmente por retos durante las sesiones compartidas, no por acumular horas.
- Una clasificación individual y otra por parejas rotatorias.
- Bingo cooperativo que se completa entre todos.
- Uno o dos contratos secretos por sesión.
- Premios humorísticos separados de la clasificación competitiva.
- Historial de momentos: quién ganó una carrera, qué contrato se reveló y qué premio se llevó cada uno.

Ejemplo de una noche, con puntuaciones inventadas:


| Actividad | Puntuación propuesta | Validación inicial |
| :-- | --: | :-- |
| Completar la mazmorra elegida | 10 puntos para cada participante | Confirma el organizador |
| Ganar el rally previo | 5 puntos | Puntos de control o confirmación |
| Cumplir un contrato secreto | 3 puntos | Se revela y el grupo lo acepta |
| Completar una línea del bingo | 8 puntos para el equipo | Confirma el organizador |
| Recibir el premio “GPS averiado” | Insignia, sin puntos | Votación |

Así no mezcláis demasiado las bromas con el resultado competitivo, y podéis ajustar las reglas tras las primeras partidas.

## Cómo lo construiría

Empezaría sin backend: la comunicación entre addons y el almacenamiento local son suficientes para probar una versión pequeña. WoW dispone de `SavedVariables` para persistir datos, aunque en la beta de Forever se han reportado fallos al recuperarlos entre sesiones; tendréis que comprobarlo antes de confiarle una temporada completa.[^1_8][^1_4]

Mi arquitectura propuesta sería:

```text
Interfaz
  ├── Panel de temporada y clasificación
  ├── Retos y bingo
  └── Votaciones

Lógica
  ├── Reglas y puntuación
  ├── Registro de resultados
  └── Validación de participantes

Comunicación
  ├── Crear y unirse a una sesión
  ├── Sincronizar cambios
  └── Recuperar el estado al reconectar

Persistencia
  └── SavedVariables
```

Para el primer prototipo elegiría un organizador como autoridad: su addon acepta los resultados y distribuye el estado. Cada evento llevaría un identificador para no puntuar dos veces, y solo admitiría mensajes de los participantes registrados. Es un diseño para un grupo de confianza, no un sistema antitrampas.

Además, sincronizaría cambios pequeños, no toda la clasificación continuamente: los mensajes de addon están sujetos a límites de envío.[^1_7]

Aunque te encaje montar una API en Spring Boot o FastAPI, la dejaría para una segunda fase con estadísticas web. Un addon no puede hacer peticiones HTTP directamente; necesitaríais exportación manual o una aplicación externa como puente.[^1_9]

## Qué haría primero

Mi primera versión tendría solo estas cinco cosas:

1. Crear una sesión e incorporar a los amigos.
2. Mostrar tres retos comunes.
3. Asignar un contrato secreto a cada participante.
4. Confirmar resultados y repartir puntos.
5. Mostrar la clasificación y guardar el historial.

No intentaría automatizarlo todo de entrada. Primero comprobaría que el juego que habéis inventado os divierte; después añadiría detección automática donde Forever lo permita. La API de la beta todavía puede cambiar antes del lanzamiento.[^1_1]

¿Cuántos vais a ser y os apetece más competir subiendo de nivel, hacer mazmorras juntos o montar piques PvP? Eso cambia bastante qué idea os encajaría mejor.

<span style="display:none">[^1_10][^1_11][^1_12][^1_13][^1_14][^1_15][^1_16][^1_17][^1_18][^1_19][^1_20][^1_21][^1_22][^1_23][^1_24][^1_25][^1_26][^1_27][^1_28][^1_29][^1_30][^1_31][^1_32][^1_33][^1_34][^1_35][^1_36][^1_37][^1_38][^1_39][^1_40][^1_41][^1_42][^1_43][^1_44][^1_45][^1_46][^1_47][^1_48][^1_49][^1_50][^1_51][^1_52][^1_53][^1_54][^1_55][^1_56][^1_57][^1_58][^1_59][^1_60][^1_61][^1_62][^1_63][^1_64][^1_65][^1_66][^1_67][^1_68][^1_69][^1_70][^1_71]</span>

<div align="center">⁂</div>

[^1_1]: https://warcraftforever.games/addons

[^1_2]: https://wowforever.es/guias/addons/

[^1_3]: https://worldofwarcraft.blizzard.com/es-es/forever

[^1_4]: https://www.wowhead.com/guide/comprehensive-beginners-guide-for-wow-addon-coding-in-lua-5338

[^1_5]: https://warcraft.wiki.gg/wiki/Create_a_WoW_AddOn_in_15_Minutes

[^1_6]: https://us.forums.blizzard.com/en/wow/t/addon-communication/1218002

[^1_7]: https://warcraft.wiki.gg/wiki/Patch_10.2.7/API_changes

[^1_8]: https://eu.forums.blizzard.com/en/wow/t/workaround-for-addon-settings-savedvariables-resetting-on-forever-beta/630138

[^1_9]: https://www.reddit.com/r/wowaddons/comments/lnttzs/could_a_wow_addon_make_a_request_to_an_external/

[^1_10]: http://worldofwarcraft.blizzard.com/es-es/forever

[^1_11]: https://worldofwarcraft.blizzard.com/en-us/news/24302498

[^1_12]: https://news.blizzard.com/en-us/feed/world-of-warcraft

[^1_13]: https://www.ign.com/wikis/world-of-warcraft/WoW_Forever_Release_Date_and_Details

[^1_14]: https://addonstudio.org/wiki/WoW:API_SendAddonMessage

[^1_15]: https://allthings.how/world-of-warcraft-forever-how-to-install-addons-without-the-curseforge-app/

[^1_16]: https://woweternity.com/forever/addons

[^1_17]: https://gagadget.com/en/725728-blizzcon-2026-wow-forever-warcraft-iiis-forsaken-kingdom-and-more/

[^1_18]: https://ground.news/article/world-of-warcraft-forever-launches-november-4-with-a-new-race-over-1-000-new-quests-and-9-dungeons

[^1_19]: https://windowsforum.com/news/world-of-warcraft-forever-launches-november-4-not-wow-2.444644/

[^1_20]: https://www.gamespot.com/articles/the-wow-forever-beta-starts-this-week-heres-how-to-get-access/

[^1_21]: https://gamerant.com/world-of-warcraft-wow-forever-beta-release-now/

[^1_22]: https://www.inkl.com/news/wow-forever-announced-at-blizzcon-2026-blizzard-brings-classic-wow-back-with-new-zones-1-000-quests-raids-and-a-new-race

[^1_23]: https://warcraft.wiki.gg/wiki/API:C_ChatInfo.SendAddonMessage

[^1_24]: https://www.wowinterface.com/forums/showthread.php?t=57897

[^1_25]: https://warcraft.wiki.gg/wiki/TOC_format

[^1_26]: https://warcraft.wiki.gg/wiki/API_talk:C_ChatInfo.SendAddonMessage

[^1_27]: https://wowpedia.fandom.com/wiki/TOC_format

[^1_28]: https://www.reddit.com/r/WowUI/comments/197gr5e/wa_how_does_wa_or_addons_communicate_to_each/

[^1_29]: https://github.com/nobewayo/ForeverSVFix

[^1_30]: https://wowpedia.fandom.com/wiki/API_C_ChatInfo.SendAddonMessage

[^1_31]: https://wowwiki-archive.fandom.com/wiki/Saving_variables_between_game_sessions

[^1_32]: interests.games.magic_the_gathering

[^1_33]: interests.app_monetization

[^1_34]: interests.games.magic_the_gathering.treasures

[^1_35]: work.projects.acc_migration

[^1_36]: programming.libraries.graphviz.implementation

[^1_37]: interests.games.magic_the_gathering.commanders

[^1_38]: interests.games.magic_the_gathering.rules

[^1_39]: work.projects.acc_migration.users

[^1_40]: projects.fastapi_antigravity

[^1_41]: projects.book_writing

[^1_42]: projects.personal_project.naming_preference.moya_brain

[^1_43]: projects.personal_project.naming_preference

[^1_44]: tools.intellij.project_view

[^1_45]: pets.hamsters.health

[^1_46]: preferences.coding.conditions

[^1_47]: family.grandfather.health

[^1_48]: health.urinary_symptoms

[^1_49]: projects.personal_project.moya_brain_hub

[^1_50]: sports.boxing.training_goal

[^1_51]: tools.shell.environment_variables

[^1_52]: https://www.perplexity.ai/search/c27bcbb2-0dac-4a57-a867-0f367a16df84

[^1_53]: https://www.perplexity.ai/search/539a251c-c70a-4839-a06e-d21f9145f75b

[^1_54]: https://www.perplexity.ai/search/ab0de3a6-7420-4a77-8566-516c6fe827ee

[^1_55]: https://www.perplexity.ai/search/b38d75db-2a68-453a-acec-351005816fca

[^1_56]: https://www.perplexity.ai/search/2726370f-47f5-443e-b384-ab5b310a415d

[^1_57]: https://www.perplexity.ai/search/00c186f8-6d5a-4545-9542-ee22824d00a5

[^1_58]: https://www.perplexity.ai/search/4562182b-21f1-46a9-8874-f6fbcd506377

[^1_59]: https://www.perplexity.ai/search/4cbb295d-c172-4c64-a034-bb49cbed8b03

[^1_60]: https://www.perplexity.ai/search/846cb9c7-e551-4dfa-b0ef-5d8d998b9209

[^1_61]: https://www.perplexity.ai/search/8794e4f4-b17c-46e4-8521-a5a9f212c6ec

[^1_62]: https://www.perplexity.ai/search/6e16154a-511c-433a-af25-17a7148a6273

[^1_63]: https://www.perplexity.ai/search/a60aa112-02d1-4cc6-adc1-a4ceca6c9e15

[^1_64]: https://www.perplexity.ai/search/3c26af53-37e6-4742-b806-e824fd6bb749

[^1_65]: https://www.perplexity.ai/search/bf271e0e-5965-4416-99ee-77f69b5e6276

[^1_66]: https://www.perplexity.ai/search/e5d374af-a8a9-470c-bf63-1df3ff0afd2f

[^1_67]: https://www.perplexity.ai/search/e214b302-75b9-4abc-83e6-e34d04938738

[^1_68]: https://www.perplexity.ai/search/58816663-e0f6-4f7e-89ce-8fbea7ecc54e

[^1_69]: https://www.perplexity.ai/search/da3e6a3b-c70a-4975-bd80-5609cfea33fe

[^1_70]: https://www.perplexity.ai/search/a618a582-e467-4f8d-ae6d-20500da78357

[^1_71]: https://www.perplexity.ai/search/291b94c7-8a4f-4d02-89a3-fcc2fb682b2e


---

# Que necesitamos para desarrollar esto?

Para empezar necesitamos el cliente de WoW donde probarlo, un editor con soporte Lua y un proyecto pequeño. El juego ejecuta el addon directamente: no hace falta montar un servidor, una base de datos ni un proceso de compilación para el primer prototipo.[^2_1]

Para vuestra liga de amigos, empezaría por una ventana de retos y puntos con confirmación manual; después añadiría sincronización y automatizaciones.

## 1. Herramientas necesarias

| Elemento | Para qué lo necesitamos | Mi propuesta |
| :-- | :-- | :-- |
| Cliente de WoW Forever | Ejecutar el addon y comprobar las funciones disponibles | Probar en la beta si tenéis acceso; validar de nuevo en lanzamiento |
| Editor con soporte Lua | Autocompletado, navegación y diagnóstico de errores | IntelliJ, que ya utilizas, o VS Code |
| Git | Versionar el código y distribuir versiones | Repositorio privado |
| Segundo jugador de pruebas | Verificar que ambos reciben los mismos retos y resultados | Un amigo con el mismo cliente y versión del addon |
| Documento de reglas | Definir cómo se ganan puntos y quién confirma resultados | Un `README.md` corto |

Forever tiene una API moderna: no podemos asumir que cualquier ejemplo de Classic vaya a funcionar sin cambios. Hay que comprobar las funciones en el cliente concreto.[^2_2]

Puedes mantener IntelliJ: la documentación de *WoW Lua Language Server* ofrece un plugin para IDEs JetBrains 2025.2 o superiores. También tiene extensión para VS Code. Sus referencias integradas cubren Retail y Classic, así que el autocompletado no garantiza por sí solo compatibilidad con Forever.[^2_3]

**No necesitas instalar Lua aparte para ejecutar el addon dentro del juego**. Un intérprete independiente sería opcional para probar lógica pura, como puntuaciones; las funciones de WoW requieren el entorno del cliente.[^2_4]

## 2. Qué debemos aprender

Con tu experiencia en backend, lo enfocaría como una aplicación orientada a eventos, no como una API REST.


| Concepto | Equivalente práctico |
| :-- | :-- |
| Lua y sus tablas | Funciones, colecciones y estructuras de datos |
| Eventos de WoW | Manejadores que reaccionan a login, cambios del juego o mensajes |
| Frames | Ventanas, botones y elementos de interfaz |
| Archivo `.toc` | Metadatos y orden de carga de los archivos |
| `SavedVariables` | Persistencia local gestionada por el cliente |
| Mensajes entre addons | Comunicación para compartir el estado de la sesión |

Estos son los componentes básicos del desarrollo de addons; la interfaz puede construirse en Lua sin utilizar XML.[^2_1]

La parte nueva para ti será principalmente la interfaz de WoW, el ciclo de vida y las restricciones de la API. No necesitamos trasladar al proyecto toda la complejidad de un backend.

## 3. Estructura del proyecto

Propondría esta organización, sin frameworks al principio:

```text
LaTaberna/
├── LaTaberna.toc
├── Core.lua
├── Storage.lua
├── Rules.lua
├── Session.lua
├── Communication.lua
├── UI.lua
└── README.md
```

- `Core.lua`: inicialización y registro de eventos.
- `Storage.lua`: ajustes, historial y versión del formato de datos.
- `Rules.lua`: retos y cálculo de puntos, separado de la API del juego.
- `Session.lua`: participantes, organizador y estado de la partida.
- `Communication.lua`: intercambio y validación de mensajes.
- `UI.lua`: ventana principal, botones y clasificación.

La carpeta se instala dentro de `Interface/AddOns/` del cliente correspondiente. El archivo `.toc` debe llamarse igual que la carpeta y declarar los archivos en el orden de carga. No usaríamos a ciegas la ruta de Retail ni su número de interfaz.[^2_1]

Dentro del cliente podemos consultar la versión y el número de interfaz con:

```lua
/run print(GetBuildInfo())
```

Ese número permite configurar el campo `Interface` del `.toc` para el cliente que realmente estáis usando.[^2_1]

Para el modelo de datos, propongo guardar:

- Identificador de sesión y versión del protocolo.
- Organizador y participantes.
- Retos con sus puntos y método de validación.
- Resultados con identificador único para evitar duplicados.
- Historial de cambios.

El organizador tendría la autoridad para confirmar resultados. Si se desconecta, en la primera versión pausaría las confirmaciones en lugar de implementar una elección automática de otro organizador.

## 4. Desarrollo y pruebas

El ciclo normal será editar, guardar y ejecutar `/reload` dentro del juego. Para ver errores y explorar la interfaz existen estos comandos:[^2_1]

```text
/console scriptErrors 1
/reload
/etrace
/fstack
```

- `/console scriptErrors 1` muestra errores Lua.
- `/reload` recarga la interfaz y el código.
- `/etrace` ayuda a observar eventos.
- `/fstack` permite identificar elementos de interfaz bajo el cursor.[^2_1]

Haría el desarrollo en este orden:

1. Cargar el addon y abrir una ventana con `/taberna`.
2. Crear tres retos locales y permitir que el organizador confirme uno.
3. Calcular la clasificación y guardar el estado.
4. Enviar una prueba de comunicación entre dos jugadores.
5. Sincronizar retos, resultados y clasificación.
6. Probar reconexiones, mensajes duplicados y versiones incompatibles.
7. Añadir bingo o contratos secretos.

La comunicación entre addons utiliza `C_ChatInfo.SendAddonMessage` y tiene límites de envío; conviene mandar cambios pequeños y solicitar un estado completo al reconectar, no enviar todo constantemente.[^2_5][^2_6]

También hay que probar la persistencia cerrando sesión y entrando de nuevo. En la beta de Forever se han reportado problemas con `SavedVariables`, así que no daría ese punto por resuelto solo porque funciona un `/reload`.[^2_7][^2_2]

## 5. Primera versión y límites

Mi propuesta para la primera versión sería:

- Una sesión privada para vuestro grupo.
- Tres retos comunes.
- Confirmación manual por el organizador.
- Clasificación compartida.
- Historial local.
- Comprobación de compatibilidad entre versiones.

Dejaría fuera inicialmente la detección de daño, errores de combate y otros objetivos que dependan de datos restringidos. La compatibilidad debe comprobarse función por función en Forever.[^2_2]

Tampoco montaría Spring Boot, PostgreSQL o una web todavía. Si más adelante queréis estadísticas fuera del juego, diseñaremos una exportación o un puente externo: un addon no puede hacer peticiones HTTP directamente a vuestro backend.[^2_8]

El primer objetivo técnico sería muy concreto: **dos jugadores ven la misma sesión, el organizador confirma un reto y ambos reciben la misma puntuación**. Una vez funcione eso y el estado sobreviva al cierre de sesión, tendremos la base para añadir cualquiera de los minijuegos.

<span style="display:none">[^2_10][^2_11][^2_12][^2_13][^2_14][^2_15][^2_16][^2_17][^2_18][^2_19][^2_20][^2_21][^2_22][^2_23][^2_24][^2_25][^2_26][^2_27][^2_28][^2_29][^2_30][^2_31][^2_32][^2_33][^2_34][^2_35][^2_36][^2_37][^2_38][^2_39][^2_40][^2_9]</span>

<div align="center">⁂</div>

[^2_1]: https://warcraft.wiki.gg/wiki/Create_a_WoW_AddOn_in_15_Minutes

[^2_2]: https://classicwowforever.com/guides/wow-forever-addons-api-compatibility/

[^2_3]: https://tradeskillmaster.github.io/wowlua-ls/guide/getting-started

[^2_4]: https://warcraft.wiki.gg/wiki/Introduction_to_Lua

[^2_5]: https://us.forums.blizzard.com/en/wow/t/addon-communication/1218002

[^2_6]: https://warcraft.wiki.gg/wiki/Patch_10.2.7/API_changes

[^2_7]: https://eu.forums.blizzard.com/en/wow/t/workaround-for-addon-settings-savedvariables-resetting-on-forever-beta/630138

[^2_8]: https://www.reddit.com/r/wowaddons/comments/lnttzs/could_a_wow_addon_make_a_request_to_an_external/

[^2_9]: https://marketplace.visualstudio.com/items?itemName=TradeSkillMaster.wowlua-ls

[^2_10]: https://warcraft.wiki.gg/wiki/HOWTOs

[^2_11]: https://marketplace.visualstudio.com/items?itemName=Septh.wow-bundle

[^2_12]: https://github.com/Thunderz96/forever-addon-kit

[^2_13]: https://addonstudio.org/wiki/WoW:Lua_editors

[^2_14]: https://github.com/imperial64/forever-addon-dev/tree/main/reference/api

[^2_15]: https://atraeau.github.io/WoW-Addons/

[^2_16]: https://www.better-addons.com/

[^2_17]: https://wowforeverwiki.org/es/addons

[^2_18]: https://wowwiki-archive.fandom.com/wiki/AddOn_programming_tutorial/Introduction

[^2_19]: work.projects.inditex_kafka_pipes

[^2_20]: work.projects.inditex.wsc_fmpfraud

[^2_21]: projects.kass_app

[^2_22]: projects.personal_project.kass_app

[^2_23]: work.projects.acc_migration.store_group_user

[^2_24]: programming.tuid_parsing

[^2_25]: work.projects.inditex_api.stores

[^2_26]: tools.flutter

[^2_27]: https://www.perplexity.ai/search/2361f9f7-7097-4c47-bf8f-6e8910a69e1b

[^2_28]: https://www.perplexity.ai/search/69cc3a4c-df98-4f9d-8b7b-697e9df759f1

[^2_29]: https://www.perplexity.ai/search/df6a0935-e805-49a4-a338-84e1dc132cbc

[^2_30]: https://www.perplexity.ai/search/b8bec663-89b6-4ce9-88ed-7b25091d4200

[^2_31]: https://www.perplexity.ai/search/81298207-a1fc-4f7c-92f9-9b02a6c5e4ee

[^2_32]: https://www.perplexity.ai/search/04d39232-38be-48c0-ab42-e8a0b98e9471

[^2_33]: https://www.perplexity.ai/search/9c61269e-7911-4bdf-9e9e-dc1c56c62547

[^2_34]: https://www.perplexity.ai/search/d6847137-80de-4530-92d3-9a429f49c60d

[^2_35]: https://www.perplexity.ai/search/09e7ab6f-3865-4dba-a08f-c2d68918646a

[^2_36]: https://www.perplexity.ai/search/4e7a1be2-0681-42bc-ab22-fadc42b6a943

[^2_37]: https://www.perplexity.ai/search/54d5919a-2995-41aa-9586-c0642b51aceb

[^2_38]: https://www.perplexity.ai/search/51990dea-32a0-427e-acec-8cc3a3008a36

[^2_39]: https://www.perplexity.ai/search/26e074d5-fab5-4337-aec5-d8c82ddab147

[^2_40]: https://warcraftforever.games/addons

