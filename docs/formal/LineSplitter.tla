---------------------------- MODULE LineSplitter ----------------------------
(***************************************************************************)
(* The line splitter of MarkdownParser+Lines.swift: `append` finds the     *)
(* complete lines in what has arrived, a carriage return at the end of     *)
(* the data waits for a line feed that may follow, and `finish` and        *)
(* `snapshot` take what is left as the last line.                          *)
(*                                                                         *)
(* The reference is CommonMark 2.1: a line ends at a line feed, a          *)
(* carriage return, or a carriage return and a line feed, and the last     *)
(* line may have no ending. The implementation must produce the reference  *)
(* lines for every way of cutting the input into pieces.                   *)
(*                                                                         *)
(* Bytes: "x" is any other byte, "N" is the line feed, "R" the carriage    *)
(* return. Positions are 1-based here; the Swift is 0-based.               *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS MaxLen, MaxPiece, Fixed   \* Fixed: the end handles a carriage return that waits

Bytes == {"x", "N", "R"}

VARIABLES src, lineStart, scanPos, lines, finished

vars == <<src, lineStart, scanPos, lines, finished>>

(* ---- the reference ---- *)

RECURSIVE FirstEnd(_, _)
FirstEnd(s, i) == IF i > Len(s) \/ s[i] \in {"N", "R"} THEN i ELSE FirstEnd(s, i + 1)

RECURSIVE RefFrom(_, _)
RefFrom(s, i) ==
    IF i > Len(s) THEN <<>>
    ELSE LET j == FirstEnd(s, i)
         IN IF j > Len(s) THEN <<SubSeq(s, i, Len(s))>>
            ELSE LET next == IF s[j] = "R" /\ j < Len(s) /\ s[j + 1] = "N" THEN j + 2 ELSE j + 1
                 IN <<SubSeq(s, i, j - 1)>> \o RefFrom(s, next)

RefLines(s) == RefFrom(s, 1)

(* ---- processCompleteLines ---- *)

RECURSIVE Scan(_, _, _, _)
Scan(s, cursor, ls, lns) ==
    IF cursor > Len(s) THEN [ls |-> ls, sp |-> cursor, ln |-> lns]
    ELSE IF s[cursor] = "N"
         THEN Scan(s, cursor + 1, cursor + 1, Append(lns, SubSeq(s, ls, cursor - 1)))
         ELSE IF s[cursor] = "R"
              THEN IF cursor + 1 > Len(s)
                   THEN [ls |-> ls, sp |-> cursor, ln |-> lns]          \* waits for a possible line feed
                   ELSE LET nl == IF s[cursor + 1] = "N" THEN cursor + 2 ELSE cursor + 1
                        IN Scan(s, nl, nl, Append(lns, SubSeq(s, ls, cursor - 1)))
              ELSE Scan(s, cursor + 1, ls, lns)

(* The last line, as `close()` takes it: everything from `lineStart`. Fixed: a carriage return at the very end is a line ending, not part of the line. *)
LastLine(s, ls, sp, lns) ==
    IF Fixed /\ sp <= Len(s) /\ s[sp] = "R" /\ sp = Len(s)
    THEN Append(lns, SubSeq(s, ls, sp - 1))
    ELSE IF ls <= Len(s) THEN Append(lns, SubSeq(s, ls, Len(s))) ELSE lns

(* ---- the machine ---- *)

Init == /\ src = <<>> /\ lineStart = 1 /\ scanPos = 1 /\ lines = <<>> /\ finished = FALSE

Pieces == {p \in UNION {[1..n -> Bytes] : n \in 1..MaxPiece} : TRUE}

Arrive(piece) ==
    /\ ~finished
    /\ Len(src) + Len(piece) <= MaxLen
    /\ LET s == src \o piece
           r == Scan(s, scanPos, lineStart, lines)
       IN /\ src' = s /\ lineStart' = r.ls /\ scanPos' = r.sp /\ lines' = r.ln
    /\ UNCHANGED finished

Finish ==
    /\ ~finished
    /\ lines' = LastLine(src, lineStart, scanPos, lines)
    /\ finished' = TRUE
    /\ UNCHANGED <<src, lineStart, scanPos>>

\* After the end the machine stays as it is (so the search ends at the end, not in a deadlock).
Next == (\E piece \in Pieces : Arrive(piece)) \/ Finish \/ (finished /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars

(* ---- what must hold ---- *)

\* What `snapshot()` shows at any moment: the lines as the end of the input would leave them.
Snapshot == IF finished THEN lines ELSE LastLine(src, lineStart, scanPos, lines)

\* However the input was cut, the lines are the reference lines, at every snapshot and after the end.
SnapshotIsReference == Snapshot = RefLines(src)

\* A line that was emitted is never changed.
EmittedLinesAreFinal == [][lines' = lines \/ (Len(lines') >= Len(lines) /\ SubSeq(lines', 1, Len(lines)) = lines)]_vars

TypeOK == /\ lineStart \in 1..(MaxLen + 2) /\ scanPos \in 1..(MaxLen + 2) /\ lineStart <= scanPos + 1
=============================================================================
