---------------------------- MODULE EditResync ----------------------------
(***************************************************************************)
(* The edit of MarkdownEditor+Resync.swift (ADR-0003, phase B): instead of *)
(* parsing the new text whole, restart the parse at a line where nothing   *)
(* is open, a block or two before the edit, read forward until a block of  *)
(* the new text starts at the place a block of the old text started        *)
(* (shifted by the edit), and keep the old blocks from there on.           *)
(*                                                                         *)
(* The claim: the blocks that come out are the blocks of a fresh parse of  *)
(* the new text, for every document, every edit, and every way the edit   *)
(* can reach back (a table's delimiter row takes the line above it out of  *)
(* a paragraph).                                                           *)
(*                                                                         *)
(* The model is lines, not bytes. A line is one of                         *)
(*   x  text            B  blank          F  a code fence (opens or closes)*)
(*   L  a list item     D  a table delimiter row (text anywhere else)      *)
(* and a block is its first line, its last line that has text (a fence    *)
(* ends at its closing line, or at the end of the input, blank lines      *)
(* included), and its kind. The reader is a state machine over the lines,  *)
(* as the parser is; it opens a block at a line or, for a table, one line  *)
(* before it. Positions are 1-based.                                       *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS MaxLen, MaxInsert, Variant   \* Variant: "ok", or "noBack" (the restart forgets the block above)

Syms == {"x", "B", "F", "L", "D"}

Idle == [k |-> "idle", s |-> 0, e |-> 0, bl |-> FALSE]
OpenAt(kind, i) == [k |-> kind, s |-> i, e |-> i, bl |-> FALSE]
CloseOf(st) == IF st.k = "idle" THEN <<>> ELSE <<[s |-> st.s, e |-> st.e, k |-> st.k]>>

(* One line c at position i in state st: the new state, the blocks that closed, and the position of a block that opened at this line (0 if none). *)
Step(st, c, i) ==
    CASE st.k = "idle" ->
            CASE c = "B" -> [st |-> st, out |-> <<>>, ns |-> 0]
              [] c = "F" -> [st |-> OpenAt("fence", i), out |-> <<>>, ns |-> i]
              [] c = "L" -> [st |-> OpenAt("list", i), out |-> <<>>, ns |-> i]
              [] OTHER -> [st |-> OpenAt("para", i), out |-> <<>>, ns |-> i]
      [] st.k = "para" ->
            CASE c = "x" -> [st |-> [st EXCEPT !.e = i], out |-> <<>>, ns |-> 0]
              [] c = "B" -> [st |-> Idle, out |-> CloseOf(st), ns |-> 0]
              [] c = "F" -> [st |-> OpenAt("fence", i), out |-> CloseOf(st), ns |-> i]
              [] c = "L" -> [st |-> OpenAt("list", i), out |-> CloseOf(st), ns |-> i]
              [] OTHER ->   \* D: the last line of the paragraph is the table's header
                    IF st.s < st.e
                    THEN [st |-> [k |-> "table", s |-> st.e, e |-> i, bl |-> FALSE],
                          out |-> <<[s |-> st.s, e |-> st.e - 1, k |-> "para"]>>, ns |-> 0]
                    ELSE [st |-> [k |-> "table", s |-> st.s, e |-> i, bl |-> FALSE], out |-> <<>>, ns |-> 0]
      [] st.k = "fence" ->
            IF c = "F" THEN [st |-> Idle, out |-> <<[s |-> st.s, e |-> i, k |-> "fence"]>>, ns |-> 0]
            ELSE [st |-> [st EXCEPT !.e = i], out |-> <<>>, ns |-> 0]
      [] st.k = "list" ->
            CASE c = "B" -> [st |-> [st EXCEPT !.bl = TRUE], out |-> <<>>, ns |-> 0]
              [] c = "L" -> [st |-> [st EXCEPT !.e = i, !.bl = FALSE], out |-> <<>>, ns |-> 0]
              [] c = "F" -> [st |-> OpenAt("fence", i), out |-> CloseOf(st), ns |-> i]
              [] OTHER ->
                    IF st.bl THEN [st |-> OpenAt("para", i), out |-> CloseOf(st), ns |-> i]
                    ELSE [st |-> [st EXCEPT !.e = i], out |-> <<>>, ns |-> 0]
      [] OTHER ->   \* table
            CASE c = "B" -> [st |-> Idle, out |-> CloseOf(st), ns |-> 0]
              [] c = "F" -> [st |-> OpenAt("fence", i), out |-> CloseOf(st), ns |-> i]
              [] c = "L" -> [st |-> OpenAt("list", i), out |-> CloseOf(st), ns |-> i]
              [] OTHER -> [st |-> [st EXCEPT !.e = i], out |-> <<>>, ns |-> 0]

(* The lines from i to j of doc, from state st: the state after them and the blocks that closed on the way. *)
RECURSIVE Run(_, _, _, _)
Run(doc, i, j, st) ==
    IF i > j THEN [st |-> st, out |-> <<>>]
    ELSE LET r == Step(st, doc[i], i)
             rest == Run(doc, i + 1, j, r.st)
         IN [st |-> rest.st, out |-> r.out \o rest.out]

(* The blocks of the document read whole. *)
Parse(doc) == LET r == Run(doc, 1, Len(doc), Idle) IN r.out \o CloseOf(r.st)

(* ---- the edit ---- *)

Take(seq, n) == SubSeq(seq, 1, n)
Drop(seq, n) == IF n >= Len(seq) THEN <<>> ELSE SubSeq(seq, n + 1, Len(seq))

(* The index of the last block that starts at or before line `line`, 0 if none. *)
RECURSIVE LastStartingAtOrBefore(_, _, _)
LastStartingAtOrBefore(blocks, line, n) ==
    IF n = 0 THEN 0 ELSE IF blocks[n].s <= line THEN n ELSE LastStartingAtOrBefore(blocks, line, n - 1)

(* The first block index from `from` whose start is at or after `line`; Len + 1 if none. *)
RECURSIVE FirstStartingAtOrAfter(_, _, _)
FirstStartingAtOrAfter(blocks, line, from) ==
    IF from > Len(blocks) THEN from ELSE IF blocks[from].s >= line THEN from ELSE FirstStartingAtOrAfter(blocks, line, from + 1)

(* The edit of old lines a .. b-1 into ins, done by restart and resync. `old` is the document; the result is the list of blocks. *)
Resync(old, a, b, ins) ==
    LET new == Take(old, a - 1) \o ins \o Drop(old, b - 1)
        delta == Len(ins) - (b - a)
        ob == Parse(old)
        r0 == LastStartingAtOrBefore(ob, a, Len(ob))
        \* blocks 1 .. keep are not read again: the ones before the block that holds the edit's line, and before the one above it when
        \* the edit is on the block's first two lines ("noBack" forgets that)
        near == Variant = "ok" /\ r0 > 0 /\ a <= ob[r0].s + 1
        keep == IF r0 = 0 THEN 0 ELSE IF near /\ r0 >= 2 THEN r0 - 2 ELSE r0 - 1
        restart == IF keep = 0 THEN 1 ELSE ob[keep].e + 1
        RECURSIVE Try(_)
        Try(q) ==
            IF q > Len(ob)
            THEN LET rr == Run(new, restart, Len(new), Idle) IN rr.out \o CloseOf(rr.st)
            ELSE LET boundary == ob[q].s + delta
                     rr == Run(new, restart, boundary - 1, Idle)
                     probe == Step(rr.st, new[boundary], boundary)
                 IN IF probe.ns = boundary
                    THEN rr.out \o CloseOf(rr.st)
                         \o [i \in 1 .. (Len(ob) - q + 1) |-> [s |-> ob[q + i - 1].s + delta, e |-> ob[q + i - 1].e + delta, k |-> ob[q + i - 1].k]]
                    ELSE Try(q + 1)
    IN Take(ob, keep) \o Try(FirstStartingAtOrAfter(ob, b, 1))

AllDocs == UNION {[1 .. n -> Syms] : n \in 0 .. MaxLen}
Inserts == UNION {[1 .. n -> Syms] : n \in 0 .. MaxInsert}

(* The invariant: for every document and every edit, restart and resync give the blocks of a fresh parse. *)
ResyncIsFreshParse ==
    \A old \in AllDocs : \A a \in 1 .. (Len(old) + 1) : \A b \in a .. (Len(old) + 1) : \A ins \in Inserts :
        Resync(old, a, b, ins) = Parse(Take(old, a - 1) \o ins \o Drop(old, b - 1))

VARIABLE done
Init == done = FALSE
Next == done' = TRUE
Spec == Init /\ [][Next]_done
TypeOK == done \in BOOLEAN
=============================================================================
