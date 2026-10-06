# Speed Limits and Debug Teleport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native).

**Goal:** Limiti di velocità più alti con curve di frenata; teletrasporto di debug sui tasti 1–9 con legenda.

**Spec:** `docs/superpowers/specs/2026-10-06-speed-and-teleport-design.md`

## Global Constraints

- Godot `~/Godot_v4.6.1-stable-double_linux.x86_64`; solo test nuovi o toccati; TDD.
- Commit con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Schianto o attraversamento della luna/anello arrivando veloci — `_test_braking_curves_stop_in_time`.
2. Teletrasporto da dentro (sezione, Selene, avamposto) che lascia il mondo esterno staccato — test per modo.
3. Nave che resta "posata" o nel riferimento sbagliato dopo il teletrasporto in volo — tasti 1 e 9.

### Task 1: Limiti (`speed_limit.gd`, `void_cruiser.gd`)

**Produces:** `SpeedLimit.limit(ring_distance, gate_distance, in_moon_frame, moon_altitude := INF)`;
`NEAR_LIMIT 1000`, `MOON_LOW 800`, `MOON_LOW_ALTITUDE 2000`, `MOON_TOP 15000`, `OPEN_LIMIT 50000`,
`SAFE_BRAKE 500`.

- [ ] `test_speed_limit.gd`, `test_speed_limit_physics.gd`.

### Task 2: Teletrasporto (`debug_teleport.gd`, `game_mode.gd`, `project.godot`)

**Produces:** `GameMode.teleport(number: int)`, `GameMode.back_aboard()`; `DebugTeleport.LEGEND`; nodo `DebugLegend`.

- [ ] `tests/test_debug_teleport.gd`.

### Task 3: README, note, prova
