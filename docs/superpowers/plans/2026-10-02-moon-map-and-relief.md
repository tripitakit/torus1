# Piano: mappa NASA e rilievo della luna

Spec: `docs/superpowers/specs/2026-10-02-moon-map-and-relief-design.md`. Esecuzione in sessione, test prima del
codice, un commit per compito.

1. **Dati** — `tools/moon_maps.py`: scarica (cache fuori dal repo), converte colore, quote, normal map. Test
   `test_moon_maps`: dimensioni, mari più scuri, Platone più basso del suo bordo.
2. **Shader e coordinate** — lo shader della luna legge le mappe nuove (lon = atan2(z, −x)). Via le mappe
   generate e `tools/moon_textures.gd`. Prova GPU da 5.000 km.
3. **Base in Platone** — `base_direction`, est locale; `START_ANGLE` se serve. Test esistenti verdi.
4. **`moon_terrain.gd`** — quote NASA bilineari, crateri piccoli, spianata. Test `test_moon_terrain`.
5. **Luna intera deformata** — vertici alla quota NASA; base costruita sulla quota della spianata.
6. **Toppa** — `moon_patch.gd`, tre anelli, thread, discard nella luna intera. Test `test_moon_patch`.
7. **Collisione e HUD** — `moon.altitude` col terreno, contatto sugli angoli dello scafo. Test fisici nuovi.
8. **Prova GPU**, suite completa, note nella spec.
