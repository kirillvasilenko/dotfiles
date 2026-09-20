---
name: review-plan
description: Write a review plan (REVIEW_PLAN*.md) that walks a reviewer through a code change in execution order, stop by stop, with telescope-resolvable file:line links. Use whenever asked for a review plan, a reading order for a diff, a guide for reviewing a branch or a colleague's pull request, or "how should I review this". Not for the review itself, and not for a summary of the change.
---

# Review plan

Scope: one change (a branch, a pull request, a set of commits) and one reader who will review it
in an editor with the code open. The reader's question is "in what order do I read this so that
each piece makes sense when I reach it, and what exactly changed at each place". Everything below
serves that.

Ask for a review plan file, not a summary. A summary tells what changed; a plan tells where to
stand and what to look at, one place at a time.

## Before writing

Read the whole diff first, then the code around it, then trace the execution path the change
sits on. The plan follows the path, not the diff order and not the file order. If the change has
several independent paths, the plan has several chains of stops; say so at the top.

Find the entry point the reader already knows. If the reader stopped their own reading of the
code at some place earlier (they may say so), the plan starts there and continues from it.

## File

One file at the repository root, named `REVIEW_PLAN.md`, or `REVIEW_PLAN_<TOPIC>.md` when
several plans coexist on the branch. It is not committed. Update it in place when the code
moves; never leave a plan whose line numbers point at the wrong statements.

## Header

In this order, in prose, short:

1. Title: what the change does in one line, with the branch name and the issue if any.
2. The idea of the change in a few sentences: the invariant it introduces or the rule it
   enforces, stated so that every later stop can refer to it.
3. What is deliberately left out or left for later (old workarounds kept on purpose, a cleanup
   that follows in a separate step). The reviewer must not spend time on those.
4. Naming or convention decisions the diff relies on, if any.
5. The link convention (see Links) in one sentence, and the instruction to read the code first
   and then `git diff -- <file>`.
6. Verification state: which suites ran on this exact state and what they showed, including
   known failures and why they are unrelated. Numbers and test names, not adjectives.

## Stops

A stop is one place in the execution path where the reader learns one thing. Number them and
give each a title that names the mechanism, not the file (`Stop 6. Accessor fetch`, not
`Stop 6. accessor_callback.cpp`).

Each stop has two parts, as bullets:

- **Understand**: what happens here, what the reader needs to hold in their head to follow the
  next stops, with links inline at the place where each piece of code is discussed.
- **Changed**: what the diff does at this place and why, in terms of the idea from the header.
  Say when a stop changes nothing (`Changed: nothing`); the reader still needs it for context.
  Say when the change is mechanical (a signature rewrite repeated in every step) so the reader
  can skim it.

Extra bullets are fine for a sub-mechanism or a contract the stop introduces.

Order rules:

- execution order along the path: creation, dispatch, first work, callbacks, completion;
- a contract (an interface, a result type) is introduced at the stop where it is first used,
  not in a separate "types" stop;
- a mirror copy of code (a second reader that is a namespace copy of the first) gets one stop
  that says it is a mirror and names the only pieces of its own;
- callers outside the changed area get the last stop.

Keep a stop to what fits on one screen. If it grows, it is two mechanisms; split it.

## Links

Every reference to code is a link the reader can paste into a fuzzy file finder from the
repository root:

- a full link is enough of the path to identify the file uniquely, then `:line`:
  `common_reader/common/script.h:19`. Not necessarily the full path, but never just a
  file name, and never a directory;
- a short link `file.cpp:48` is allowed only when the last full link before it, in reading
  order, points at the same file. After a full link to a different file, give the full link
  again;
- links go inline, at the sentence that discusses that code. Do not open a stop with a list of
  links;
- the line must be the statement being discussed, verified against the current file, not the
  function header nearby. Re-verify every link after any edit to the code.

Quote identifiers (`TStepAction`) and never a code snippet longer than one line.

## Close

End with a short list of properties the reviewer can check while reading: invariants that
should hold across the whole diff ("every `std::move(SourceLease)` is the last use in that
function", "no `IDataSource*` member exists anywhere"). Only properties that were checked
mechanically before writing them down.

## Honesty

Say what was not verified. A plan that claims a test run that did not happen, or a line that
was not checked, costs the reviewer more than no plan.

Do not editorialize about the change; the reviewer judges it. The plan says what is where and
why it is there, in the change's own terms.
