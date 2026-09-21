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
- **A `;` anywhere in a label ends the statement.** Mermaid takes it as a statement separator, so the
  rest of the label is parsed as a new statement and the diagram fails to render. This bites in
  `Note over` text and message labels alike, where a semicolon reads as natural prose. Use a comma, a
  dash, or `<br/>` instead. Same family as the colon rule under Class diagram below.
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
that contribute nothing to the subject, and say in the reply which ones you collapsed. A value
type (`TExecutionResult`) is not a participant: fold it into the message label or a note. A member
that is only read on the way still earns a lifeline when it is what the reader must understand
(the cursor's `Script` is such a member when the subject is how a script is executed); the test is
whether the diagram is about it, not whether it is mutated.

### Participant labels

The codebase repeats class names across namespaces and hides everything behind interfaces, so a
bare type name identifies a participant only when it is unambiguous in context (`TStepAction`,
`TExecutionResult`). Otherwise the label says which object it is, one line each, joined with
`<br/>`:

```
participant collection as TScanHead.SourcesCollection<br/>: sptr<ISourcesCollection><br/>= TOrderedResultWithLimitCollection
```

- line one: the class that declares the member, `.`, the member name. `.` and not `::`, because
  it is a member of an object, and `::` here means a namespace or a nested type;
- line two, starting with `: `: the declared type;
- line three, starting with `= `: the actual runtime type.

The leading `:` and `=` are what make the extra lines readable at a glance; keep them even when
only one extra line is present. Drop a line that adds nothing: the `=` line when the runtime type
is the same, unknown or irrelevant; the `:` line when the name already says the type.

When the owner on line one is itself ambiguous, fix the owner, not the member:

- for the trivial / simple / plain mirrors the namespace is the difference:
  `NTrivial::TScanHead.SourcesCollection`;
- for an interface with several implementations use the actual type of the owner:
  `TPortionDataSource.ExecutionContext`, not `IDataSource.ExecutionContext`;
- when nothing names the object, reach it through a participant already on the diagram:
  `TStepAction.SourceLease.ExecutionContext`.

A local or a parameter is owned by its function, and there `::` is right because a function is a
scope: `TScanHead::Start().context<br/>: TScanContext`.

Angle brackets in these labels render correctly; `sptr<ISourcesConstructor>` is fine here even
though class diagrams need `~ ~`.

Use `loop` and `opt` for real control flow — a per-item loop and a resume path are part of the
mechanism, not decoration. Use `Note over` for facts that are not messages, and to mark phase
boundaries ("initialization ends here, nothing about order changes after this").

### Indentation

Indent the source like code, two spaces per level, so the diagram can be read and edited as text.
Mermaid ignores the indentation; the reader does not. A blank line separates the participant
list from the messages, and phases from each other.

- every block that has an `end` (`loop`, `opt`, `alt` / `else`, `break`, `par`, `critical`)
  indents its body one level;
- `activate X` indents everything up to the matching `deactivate X` one level, so the extent of
  the activation is visible in the source;
- the `else` of an `alt` sits at the level of its `alt`.

```
  worker ->> step_action: DoExecuteImpl()
  activate step_action
    step_action ->> cursor: Execute(IDataSource&)
    loop !Script.IsFinished(CurrentStepIdx)
      cursor ->> step: ExecuteInplace(IDataSource&, TFetchingScriptCursor&)
      step -->> cursor: result: TExecutionResult
      break result.IsPending()
        cursor -->> step_action: result
      end
    end
    alt result.IsPending()
      step_action ->> async_job: Start(uptr<TDataSourceLease>)
      step_action -->> worker: false
    else
      step_action -->> worker: true
    end
  deactivate step_action
```

End with the consequence. The last note should be what the reader is meant to leave with, usually
the failure that follows when two parts disagree.

## Honesty

Say where the diagram simplifies. If a call is really made two hops later by another actor, either
draw that actor or state the shortcut in the reply.

Mark a defect in the text, not only in styling: `BUG:` for something confirmed, `TODO:` for
something needing a decision. Only mark what has been traced to code; a suspicion does not get a
marker.
