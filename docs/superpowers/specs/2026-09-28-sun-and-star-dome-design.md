# Sole e volta stellata

## Contesto

- **Sfondo:** lo spazio esterno è nero uniforme.
- **Luce:** arriva da `SunLight`, un DirectionalLight3D nella radice della
  scena, ma il sole non si vede.
- **Pianeta:** l'alone dell'atmosfera legge la direzione del sole da
  `sun_path`. Nessun test verifica che sia davvero il sole della scena a
  guidarlo.

## Decisioni prese con l'utente

- **Sole sulla volta:** all'infinito, irraggiungibile, fisso rispetto alle
  stelle, nel punto da cui arriva la luce.
  - Disco bianco-caldo di circa 1° con un alone morbido, senza raggi.
- **Stelle:** tante, con la Via Lattea visibile ma discreta.
- **Generazione:** mappa panoramica generata in Blender tramite MCP.

## Mappa delle stelle (`tools/blender/sky_textures.py`)

- **Formato:** `assets/textures/sky/stars.png`, 8192×4096, equirettangolare.
  Usa la stessa formula direzione ↔ pixel del pianeta: v = 0 verso +Y, e la
  direzione è (sin 2πu · sin πv, cos πv, cos 2πu · sin πv).
- **Stelle:** tre strati di celle Voronoi 3D sulla direzione, un punto per
  cella, circa 1–1,6 pixel di raggio:
  - uno rado e più brillante;
  - uno fitto e debole;
  - uno ancora più fitto, solo dentro la fascia della Via Lattea.

  La luminosità è un numero casuale elevato a potenza, così quasi tutte le
  stelle sono deboli. Il colore va dall'azzurro al bianco all'arancio.
- **Via Lattea:**
  - fascia attorno a un cerchio massimo, con il polo inclinato di 60° rispetto
    a +Y;
  - bagliore lattiginoso tenue, più forte e più caldo verso il nucleo;
  - polveri scure fatte con rumore.
- **Importazione:** compressa (S3TC) con mipmap. Circa 32 MB. Una stella
  isolata resta un punto.

## Cielo e sole (`scripts/space_sky.gd`, sul nodo `WorldEnvironment`)

- **Costruzione:** all'avvio `build_sky()` mette lo sfondo a cielo, con uno
  `Sky` il cui materiale è uno shader di tipo sky:
  - **stelle:** lette dalla mappa con u = atan(x, z) / 2π e v = acos(y) / π.
    Per scegliere il livello di mipmap calcola i gradienti senza il salto
    fra u = 1 e u = 0, così dove la mappa si richiude non compare una riga;
    `star_energy` le può schiarire;
  - **sole:** se la luce 0 è accesa, un disco (raggio 0,0087 rad, cioè circa
    1° di diametro) nella direzione `LIGHT0_DIRECTION`, colore caldo,
    luminosità `sun_energy`, più un alone esponenziale largo circa 0,05 rad.
    Il sole è quindi sempre dove la luce dice, all'infinito.
- **Illuminazione invariata:**
  - la luce ambiente resta un colore fisso (`ambient_light_source` = colore);
  - i riflessi dal cielo sono spenti, così le stelle non si riflettono sui
    metalli.
- **Interno:** il nodo dell'ambiente resta anche dentro, ma lì la luce del
  sole è staccata. Il disco non compare, e le stelle solo se ci fosse
  un'apertura.

## Verifica dell'alone del pianeta

- **Test sulla scena vera:** dopo qualche frame, `sun_direction` dello shader
  dell'atmosfera coincide con la +Z globale di `SunLight`. Se si ruota
  `SunLight` di 90° attorno a Y, al frame dopo coincide ancora.
- **Se non coincide:** si corregge `planet.gd`.

## Fuori scope

- Pianeti lontani o lune sulla volta.
- Stelle che brillano.
- Lens flare.
- Il ciclo giorno-notte: il sole non si muove.

## Testing

- **Mappa:**
  - 8192×4096;
  - almeno 1000 stelle luminose (pixel sopra 0,8);
  - mediamente più luminosa lungo la fascia che verso il suo polo;
  - importata compressa con mipmap.
- **Cielo (senza scena):**
  - sfondo a cielo;
  - shader con `LIGHT0_DIRECTION` e la mappa;
  - riflessi spenti;
  - luce ambiente ancora a colore fisso.
- **Scena:** `WorldEnvironment` ha lo script. L'atmosfera segue `SunLight`
  anche dopo averla ruotata.
- **Render (xvfb):**
  - guardando verso la +Z di `SunLight`, il sole è al centro dell'immagine;
  - una vista con la Via Lattea;
  - la stazione illuminata come prima.
