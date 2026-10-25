# Formal models

Two TLA+ models of the parts of the parser where a protocol, not a function, decides what is right. `Scripts/tlc.sh` runs TLC on each and checks the verdicts:
a model must pass, and its `.buggy.cfg` (the behaviour of the first implementation) must fail, so that the model is known to be able to catch what it is for.

| Model | What it states | Found |
|---|---|---|
| `LineSplitter.tla` | The lines the parser finds are CommonMark's lines for every way of cutting the input into pieces, at every snapshot and after the end. Positions, pieces of up to 3 bytes, 8 bytes in all: 19,682 distinct states. | A carriage return that ends the input was part of the last line, in `finish()` and in `snapshot()` (`Fixed = FALSE`). Fixed in `MarkdownParser+Lines.swift` (`close()`), with a regression test. |
| `SnapshotProtocol.tla` | Only closed slots are committed; a committed slot never changes; removing a slot touches the tail; a snapshot writes nothing to the committed part it shares; every container of a snapshot is closed. 7,563 distinct states. | The first implementation committed on the snapshot's copy, which wrote to storage that the snapshot shared and so copied the whole committed tape (`ProbeCommits = TRUE`). Fixed (`commitClosedBlocks` is called only on the real path); `SnapshotSharingTests` checks the storage is shared. |

What the models do not cover: the block structure rules (containers, lazy continuation, list looseness), which the specification examples and the differential tests
against cmark and commonmark.js check on real input instead; and the inline algorithms.

`modeler` (g-cqd/modeler) generated the class diagram and a skeleton TLA+ module per type; its `check` found nothing, `states` found no state machine, and the
skeletons were not used: they model each method as an unconstrained write of its variables, which cannot state a protocol. Two things it did not see are reported in `~/Public/formal`.
Lean 4 is not used: it is not installed, and the properties above are finite, which TLC decides.
