# Implementation of the bug-hunt decisions — notes to discuss

## To discuss
- facts 8.2: TicTacToeMatch getters became suspend functions (honest API, also fixed a check-then-act race across separate replays). Alternative: live StateFlow projection, or revert to runBlocking. Owner to confirm.

## Worth mentioning
- quality-scorer: usage errors are a dedicated InvalidInputException (b5452b6); Main exits 2 only for those.
- facts and quality-scorer catalogs bumped by `just build` (facts swissknife 1.0.26 → 1.0.46), confirmed by owner.
