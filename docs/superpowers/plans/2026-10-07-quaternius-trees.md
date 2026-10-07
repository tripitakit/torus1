# Quaternius Trees Implementation Plan

> Native execution. Spec: `docs/superpowers/specs/2026-10-07-quaternius-trees-design.md`.

## Review Focus

1. Alberi doppi o buchi al confine dei 500 m — stesso taglio nei due shader.
2. Scatti ricostruendo volando veloci — thread a parte, una ricostruzione per volta.
3. FPS in un bosco fitto — prova GPU; ripiego a ~350 m o varianti leggere se serve.

### Task 1: `tree_models.gd` + asset — `tests/test_tree_models.gd`
### Task 2: `near_trees.gd` + taglio nelle forme semplici + collegamento in `interior_world.gd` — `tests/test_near_trees.gd`, `test_interior_world.gd`
### Task 3: Prova GPU, README (crediti), note
