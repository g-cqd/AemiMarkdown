------------------------- MODULE SnapshotProtocol -------------------------
(***************************************************************************)
(* The commit and snapshot protocol of MarkdownParser and SlotTape.        *)
(*                                                                         *)
(* Slots go on a tail. A top-level block that has closed is committed:     *)
(* its slots move to a committed part that is final and shared with every  *)
(* snapshot. `snapshot()` closes the open blocks on a copy of the parser   *)
(* and returns the committed part and the copy's tail.                     *)
(*                                                                         *)
(* What must hold:                                                         *)
(*  - only closed slots are ever committed, and a committed slot never     *)
(*    changes;                                                             *)
(*  - removing a slot (a paragraph that only held definitions) touches     *)
(*    the tail, never the committed part;                                  *)
(*  - a snapshot writes nothing to the shared committed part (a write to   *)
(*    storage that a snapshot shares would copy the whole of it);          *)
(*  - the snapshot's tape is well formed: every container is closed, so    *)
(*    its end is known.                                                    *)
(*                                                                         *)
(* ProbeCommits = TRUE is the first implementation, where the copy ran the *)
(* same line loop as the parser and so committed on the copy.              *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS MaxSlots, MaxDepth, ProbeCommits

\* A slot is a container ("c") or a leaf ("p"); a container is open or closed.
Slot(kind, closed) == [kind |-> kind, closed |-> closed]

VARIABLES committed, tail, stack, sharedWrites

vars == <<committed, tail, stack, sharedWrites>>

Init == committed = <<>> /\ tail = <<>> /\ stack = <<>> /\ sharedWrites = 0

Total == Len(committed) + Len(tail)

\* Index in the tail of the slot that the open stack's entry stands for: entries are indices into the whole tape.
OpenContainer ==
    /\ Total < MaxSlots /\ Len(stack) < MaxDepth
    /\ tail' = Append(tail, Slot("c", FALSE))
    /\ stack' = Append(stack, Total + 1)
    /\ UNCHANGED <<committed, sharedWrites>>

OpenLeaf ==
    /\ Total < MaxSlots /\ Len(stack) < MaxDepth
    /\ tail' = Append(tail, Slot("p", TRUE))
    /\ stack' = Append(stack, Total + 1)
    /\ UNCHANGED <<committed, sharedWrites>>

\* The innermost open block closes. A container learns its end (is closed); a leaf may vanish if it held only definitions and is the last slot.
Close(vanish) ==
    /\ stack /= <<>>
    /\ LET top == stack[Len(stack)]
           local == top - Len(committed)
       IN /\ local >= 1 /\ local <= Len(tail)
          /\ IF vanish /\ tail[local].kind = "p" /\ local = Len(tail)
                THEN tail' = SubSeq(tail, 1, Len(tail) - 1)
                ELSE tail' = [tail EXCEPT ![local].closed = TRUE]
    /\ stack' = SubSeq(stack, 1, Len(stack) - 1)
    /\ UNCHANGED <<committed, sharedWrites>>

\* After a line, when nothing is open the tail becomes final.
Commit ==
    /\ stack = <<>> /\ tail /= <<>>
    /\ committed' = committed \o tail /\ tail' = <<>>
    /\ UNCHANGED <<stack, sharedWrites>>

\* What `snapshot()` returns: every open block closed, on a copy. With ProbeCommits the copy also commits, which writes the shared part.
ProbeTail == [i \in 1..Len(tail) |-> Slot(tail[i].kind, TRUE)]
Snapshot == committed \o ProbeTail

\* The snapshot as an action: it reads, and (in the first implementation) counts a write to the shared storage when the copy commits.
TakeSnapshot ==
    /\ sharedWrites' = IF ProbeCommits /\ tail /= <<>> THEN sharedWrites + 1 ELSE sharedWrites
    /\ UNCHANGED <<committed, tail, stack>>

Next == OpenContainer \/ OpenLeaf \/ Close(TRUE) \/ Close(FALSE) \/ Commit \/ TakeSnapshot

Spec == Init /\ [][Next]_vars

(* ---- what must hold ---- *)

CommittedIsClosed == \A i \in 1..Len(committed) : committed[i].closed
SnapshotIsWellFormed == \A i \in 1..Len(Snapshot) : Snapshot[i].closed
SnapshotWritesNothingShared == sharedWrites = 0
CommittedIsFinal == [][Len(committed') >= Len(committed) /\ SubSeq(committed', 1, Len(committed)) = committed]_vars
StackPointsIntoTail == \A i \in 1..Len(stack) : stack[i] > Len(committed) /\ stack[i] <= Total
=============================================================================
