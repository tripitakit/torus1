# Torus1

Un simulatore di volo spaziale in Godot 4. Un pianeta, una stazione orbitale ad anello lunga migliaia di
chilometri, l'interno abitato di ogni sezione, una luna con una base, e i mezzi per muoversi fra tutti questi
luoghi: in volo, in rover, in treno. La fisica ha basi reali (orbite, riferimenti in rotazione, gravità lunare)
con parametri semplificati perché si possa giocare.

## Requisito: Godot 4.6.1 compilato in doppia precisione

Il progetto **non funziona con il Godot scaricabile dal sito**. Serve un Godot 4.6.1 compilato con
`precision=double` (in `project.godot` è attiva la funzione `Double Precision`).

**Perché.** Le distanze sono enormi. L'anello sta a quasi 7.000 km dal centro del pianeta, la luna a
20.000 km. Con i numeri a 32 bit dell'editor normale, a quelle distanze la posizione ha una precisione di circa
mezzo metro: la nave trema, le collisioni sbagliano, il terreno vicino "salta". Con un Godot normale la scena si
vede nera.

Il gioco sposta anche l'origine del mondo dietro al giocatore (`world_origin_rebase.gd`), ma questo da solo non
basta per orbite, gate e riferimento lunare: servono i calcoli a 64 bit.

### Compilare l'editor

Servono i normali strumenti di compilazione di Godot (Python 3, SCons, un compilatore C++; su Linux anche le
librerie di sviluppo X11/Wayland, OpenGL, ALSA/PulseAudio). Istruzioni complete:
[Compiling Godot](https://docs.godotengine.org/en/stable/contributing/development/compiling/index.html).

```bash
git clone https://github.com/godotengine/godot.git -b 4.6.1-stable --depth 1
cd godot
# Linux
scons platform=linuxbsd target=editor precision=double
# Windows: platform=windows   macOS: platform=macos
```

Il file prodotto è in `bin/`, per esempio `bin/godot.linuxbsd.editor.double.x86_64`. Per esportare il gioco
servono anche i template compilati con la stessa opzione
(`target=template_release precision=double`).

Negli esempi sotto il binario si chiama `godot-double`.

### Avviare

```bash
godot-double --path .            # il gioco (scena scenes/torus1_system.tscn)
godot-double --editor --path .   # l'editor
```

Il renderer è **Compatibility** (OpenGL 3.3).

## Cosa c'è oggi

### Il sistema

- **Il pianeta**, con le mappe NASA della Terra: Blue Marble, luci delle città sul lato notte, nuvole, rilievo
  e mare da GEBCO.
- **Torus1**, un anello di **2000 sezioni** cilindriche (raggio 2 km, lunghe 20 km) unite da 2000 ponti, in
  orbita sull'equatore. Le sezioni ruotano per dare gravità; ogni ponte ha un attracco.
- **La luna** (raggio 250 km, a 20.000 km) con le mappe NASA (colori LRO, rilievo LOLA), crateri piccoli
  generati, e una toppa di terreno fine che segue il giocatore.
- **Base Selene**, nel cratere Platone, in stile Base Alpha (Spazio 1999): settori, cupole, tubi, una torre
  con faro e sei pad di atterraggio.
- **Due portali**, vicino alla Terra e sopra la luna, per attraversare in un attimo la distanza fra i due.
- Sole, cupola di stelle, luce del giorno e della notte.

### Il void-cruiser (volo esterno)

- Volo a sei gradi di libertà, con una spinta che sale da 1x a 10x a 100x tenendo premuto.
- Volo in orbita: l'anello e la luna si muovono, e la nave entra ed esce dal riferimento lunare senza scatti.
- **Attracco** ai ponti, con guida a quadrati, luci, pannello di avvicinamento e assistenza.
- **Atterraggio** sulla luna e sui pad di Selene, con pannello di quota e velocità; schianto se si arriva
  troppo forte o inclinati.
- **Computer di bordo**: sceglie il bersaglio (attracco, gate Terra, gate Luna, Selene), calcola la rotta a
  tappe e può arrivare da solo al punto d'ingresso.
- **Limiti di velocità** per zona, frenata automatica.
- **HUD** a zone: croce della velocità, croce delle accelerazioni, navball, marcatori sui bersagli.
- Visto da fuori è un'**Eagle** di Spazio 1999 (modello low poly).

### Il Moon Buggy (sulla luna)

- Con la nave posata sulla luna, **V** fa scendere il pilota sul rover; **V** vicino alla nave lo fa risalire.
- Guida arcade sul terreno lunare vero (pendenze, piccoli salti, gravità lunare), urti con gli edifici di
  Selene, fari.
- Vista dal posto di guida, HUD con velocità, rotta, pendenza e quota, marcatori sulla nave e su Selene.

### L'interno delle sezioni

Attraccando a un ponte si entra nell'interno della stazione e si vola con l'**internal cruiser**.

- Ogni sezione è un mondo a sé, generato: **città, paesi, campi, colline, montagne, boschi, laghi**.
- **Giorno e notte** che scorrono lungo l'anello.
- **Traffico stradale**, **traffico aereo** (incrociatori sci-fi), **treno** sulla spina centrale con
  stazioni, piloni e **ascensori di vetro** con persone dentro.
- **Barche** sui laghi con la loro scia, **moli** con persone, carrelli e droni, **pedoni** in città.
- Le sezioni vicine si caricano e si scaricano mentre si vola lungo l'anello.
- In ogni paese e in ogni città c'è una **piazzola d'atterraggio**; l'HUD del cruiser indica la più vicina
  (`PAD`) e, sopra di essa e quasi fermi, propone `K LAND`: il cruiser si posa da solo.

### A piedi

- Si scende a piedi con **K** dall'Eagle posata sulla luna, dal Moon Buggy fermo e dall'internal cruiser posato
  su una piazzola. Vista in prima persona: i mezzi si vedono da fuori.
- Camminata (1,5 m/s) e corsa (4 m/s), salti: sulla luna balzi lenti con la gravità lunare, dentro le sezioni un
  salto normale con la gravità verso la parete del cilindro.
- Si urtano edifici, pad e mezzi; dentro le sezioni il terreno, gli alberi e gli edifici hanno collisioni.
- HUD a piedi: velocità, marcatori sui mezzi (`SHIP`, `ROVER`, `CRUISER`) con la distanza, `K BOARD` quando si è
  abbastanza vicini (8 m) per risalire. Il rover resta parcheggiato dove lo si lascia; se si risale sull'Eagle
  torna nella stiva.

## Comandi

| Tasto | Nave / cruiser interno | Rover | A piedi |
|---|---|---|---|
| W / S | avanti / indietro (tenere: 1x → 10x → 100x) | gas / freno e retromarcia | avanti / indietro |
| A / D | di lato | sterzo | di lato |
| Z / X | su / giù | — | — |
| Q / E | rollio | — | — |
| Mouse | orientamento | guardarsi attorno | girarsi, guardare su / giù |
| C | cruise (mantiene la velocità) | — | — |
| B | freno | freno a mano | — |
| F | attracco / sgancio (anche all'interno) | — | — |
| T | scegli il bersaglio del computer di bordo | — | — |
| G | arrivo automatico al bersaglio | — | — |
| V | scendi sul rover (nave posata sulla luna) | risali sulla nave | — |
| K | scendi a piedi (nave posata; cruiser: posa sulla piazzola) | scendi a piedi | risali sul mezzo vicino |
| J | — | — | corsa (tenere premuto) |
| Spazio | — | — | salto |
| L | — | fari | — |
| R | ripartenza dopo uno schianto | — | — |

## Struttura del progetto

- `scenes/torus1_system.tscn` — la scena principale.
- `scripts/` — tutto il codice. Quasi tutti i modelli (navi, edifici, mezzi, persone) sono costruiti a codice,
  low poly.
- `shaders/` — parti di shader condivise.
- `assets/` — mappe e texture già pronte (non serve scaricare nulla per giocare).
- `tools/` — gli script che hanno generato le mappe NASA (`earth_maps.py`, `moon_maps.py`) e le texture
  (Blender, Python).
- `tests/` — i test automatici, uno script per file.
- `docs/superpowers/specs/` e `docs/superpowers/plans/` — il progetto di ogni funzione e il piano con cui è
  stata costruita, in ordine di data.

## Test

Ogni test è uno script indipendente che si lancia senza finestra:

```bash
godot-double --headless --path . -s tests/test_moon_rover.gd
```

Un test passato stampa `ALL TESTS PASSED`; un test fallito stampa righe `FAIL ...`. Alcuni test caricano la
scena intera e richiedono un minuto o più.

## Crediti

- Mappe della Terra e della Luna: NASA (Visible Earth, Blue Marble, Black Marble, SVS CGI Moon Kit — LRO e
  LOLA), GEBCO. Pubblico dominio.
- Eagle, Moon Buggy e Base Alpha sono omaggi alla serie *Spazio 1999*.
