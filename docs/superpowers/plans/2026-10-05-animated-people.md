# Animated People Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native, by the plan's author in the
> same session). Interfaces and tests are fixed here; implementation is written during execution.

**Goal:** Pedoni, gente dei moli e passeggeri degli ascensori come umano low poly CC0 (Quaternius) che cammina,
al posto delle sagome a birillo.

**Architecture:** `people_model.gd` legge il `.glb` con `GLTFDocument`, fa lo skinning sulla CPU e cuoce la
camminata in due texture (posizioni, normali); lo shader di `LoopTraffic` in variante "animata" legge il
fotogramma dalla strada percorsa. Entro 80 m il modello animato, oltre la sagoma di oggi (due MultiMesh sullo
stesso buffer). I passeggeri usano una mesh statica nella posa Idle.

**Tech Stack:** Godot 4.6.1 doppia precisione, `gl_compatibility`, GDScript, test `extends SceneTree`.

**Spec:** `docs/superpowers/specs/2026-10-05-animated-people-design.md`

## Global Constraints

- Godot `~/Godot_v4.6.1-stable-double_linux.x86_64`; un test `--headless --path . -s tests/<file>.gd`.
- Solo test nuovi o toccati; TDD.
- Valori della spec: 1,8 m, muso +Z, piedi a y = 0; Walk 16 fotogrammi su 1 s; passo 1,4 m per ciclo; righe di
  1.024 texel; dettaglio entro 80 m, `visibility_range_end` 150 m per il MultiMesh animato.
- Commit con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Piedi che scivolano (fase del ciclo non legata alla strada percorsa) — controllo a vista nella prova GPU e
   `_test_stride_matches_speed` (funzione pura della fase).
2. Modello girato o capovolto (assi del glTF, scala 69× dell'armatura) — `_test_faces_plus_z`, `_test_height`.
3. Persone che "saltano" fra i due livelli a 80 m o doppie (i due MultiMesh visibili insieme) — un solo criterio
   di distanza condiviso nei due shader (`detail_from`/`detail_to` dello stesso valore).
4. Costo: 4.733 vertici per persona — FPS in città nella prova GPU, prima e dopo.
5. Pedoni nascosti di notte (`night_hide`) anche nella variante animata — stesso codice dello shader di oggi.

---

### Task 1: Modello e cottura (`people_model.gd`)

**Produces:** `PeopleModel.PATH`, `FRAMES := 16`, `STRIDE := 1.4`, `ROW := 1024`, `HEIGHT := 1.8`;
`PeopleModel.bake() -> Dictionary` `{mesh: ArrayMesh, positions: ImageTexture, normals: ImageTexture,
idle: ArrayMesh, frames: int, vertices: int}` (in cache statica); `PeopleModel.frame_points(frame: int) ->
PackedVector3Array` (posizioni skinnate di un fotogramma, per i test); `PeopleModel.cycle_phase(distance:
float) -> float` (0..1).

- [ ] `tests/test_people_model.gd`: `_test_loads`, `_test_height` (1,8 m, piedi a 0), `_test_faces_plus_z`,
  `_test_feet_swap_at_half_cycle`, `_test_hips_stay_in_place`, `_test_parts` (gambe UV.x 1, visiera 2),
  `_test_texture_frame_zero_matches`, `_test_idle_mesh`, `_test_stride_matches_speed`.
- [ ] Asset `assets/people/animated_human.glb` (+ nota CC0).

### Task 2: Shader animato e due livelli

**Produces:** `LoopTraffic.material(..., animated: Dictionary = {})` (con `bake()` imposta texture e dettaglio);
`LoopTraffic.DETAIL_TO := 80.0`; il materiale della sagoma con `detail_from = 80`. `interior_world.gd`:
`Walkers_xx_yy` (sagoma) e `WalkersNear_xx_yy` (animato, `visibility_range_end` 150), `PierPeople` e
`PierPeopleNear`; passeggeri con `bake().idle`.

- [ ] `tests/test_interior_world.gd` (toccato): `_test_walkers_in_the_town_chunks` vuole anche
  `WalkersNear_xx_yy` sullo stesso buffer e con la mesh animata; `_test_piers_with_their_life` vuole
  `PierPeopleNear`; `_test_lift_riders_idle` (nuovo): i passeggeri usano la mesh Idle.
- [ ] `tests/test_loop_traffic.gd` se esiste: il materiale animato compila (shader senza errori) — altrimenti
  dentro `test_people_model.gd` `_test_animated_material`.

### Task 3: Prova GPU, README e note

- [ ] Scatti: paese, molo, ascensore, da vicino; FPS in città prima e dopo.
- [ ] README: persone animate e credito Quaternius CC0.
- [ ] "Cambiato durante l'esecuzione" nella spec; commit.
