---
name: mermaid-knowledge-diagrams
description: Conventions for Mermaid diagrams that explain how one mechanism works across several collaborating classes in an existing codebase — a class diagram of the parts and a sequence diagram of the flow. Use whenever asked to document, diagram, draw or explain how something works (a scan, a request path, a protocol, a lifecycle, where a value comes from and who reads it). Not for inheritance trees; for one base class and its implementations use mermaid-class-hierarchy instead.
---

# Knowledge diagrams

Scope: one mechanism, spanning as many classes as it touches. The reader's question is "how does
this actually work, and what decides what". Everything below serves that.

## Produce both views

Unless the user asks for one, deliver both:

- a **class diagram** — who holds the thing, who derives it, who reads it;
- a **sequence diagram** — when each part is decided, in what order, and what is fixed by then.

They answer different questions and neither alone is enough. The class diagram cannot show that a
value is assigned late; the sequence diagram cannot show that two fields must agree.

## Output

Write each diagram to its own file under `~/tmp/`, named after the subject
(`~/tmp/sorting-in-scan-sequence.md`), with a one or two line intro above the fence saying what the
diagram answers. Update the same file in place when asked for changes; do not create a new one.

Use a ` ```mermaid-next ` fence. Never add `autonumber`.

## Renderer limits, do not fight these

The renderer runs Mermaid at the default `securityLevel: strict`:

- HTML in labels is escaped and shows up literally. `<b style="color:...">` does not work, and
  `securityLevel` is one of the keys Mermaid refuses to let a diagram set through `%%{init}%%`.
- So **no per-word colour or bold inside a sequence diagram**. Do not substitute textual markers
  such as `[ASC]` or `{LastPkAsc}` either — they were tried and rejected as worse than plain text.
- `<br/>` does work, and is the way to break a long label.
- Colour is only available per node in node-based diagrams, via `classDef` or `style`. Set `color`
  and `stroke` only; never `fill`, which breaks under light/dark theme switching.

## Choosing what goes in

Include only the classes that carry the thing being explained, and only the members that decide
something. A getter that merely names a field is noise.

Drop steps that name a method without showing anything happen. Three self-calls resolving three
values are worth one message plus a note saying what the values are.

Read the implementation for the real values before writing them down. A diagram whose value slots
are guesses is worse than no diagram.

## Class diagram

One `namespace` block per real namespace, dotted and fully qualified. Class ids must be globally
unique, so prefix them and restore the real name with a label: `class Chunks_TAccessor["TAccessor"]`.

Never use `note for`; it renders far from its class. Put everything in the box: a `<<...>>`
annotation for what this class is *for in this story*, and members for what it decides.

Members carry both type and value or decision, since that is what makes the diagram informative:

```
+GetSourcesSorting() ESourcesSorting = ASC gives FirstPkAsc, NONE gives SourceIdAsc unless deduplicating
-SourceIdx ui32 = stamped later by the heap, a position and not an identity
```

Abbreviate `uptr`, `sptr`, `opt`; generics with `~ ~`, never `<>`. Mark pure virtuals `()*`.

Edge labels must not contain a colon — the first `:` is the label separator and a second one is a
parse error. Use a dash.

## Sequence diagram

Participants are the objects that carry the thing, not every class on the call path. Collapse hops
that contribute nothing to the subject, and say in the reply which ones you collapsed.

Use `loop` and `opt` for real control flow — a per-item loop and a resume path are part of the
mechanism, not decoration. Use `Note over` for facts that are not messages, and to mark phase
boundaries ("initialization ends here, nothing about order changes after this").

End with the consequence. The last note should be what the reader is meant to leave with, usually
the failure that follows when two parts disagree.

## Honesty

Say where the diagram simplifies. If a call is really made two hops later by another actor, either
draw that actor or state the shortcut in the reply.

Mark a defect in the text, not only in styling: `BUG:` for something confirmed, `TODO:` for
something needing a decision. Only mark what has been traced to code; a suspicion does not get a
marker.
