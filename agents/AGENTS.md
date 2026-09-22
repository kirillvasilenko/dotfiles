# Rules for every coding agent

These rules apply in every repository and every session, on top of the repository's own
`AGENTS.md`. When the two disagree, these win.

## Git

1. Never commit. Not even when asked. I commit everything myself after reviewing it.
2. Never stage or unstage anything (`git add`, `git rm`, `git mv`, `git restore --staged`,
   `git reset`, `git update-index`) unless I ask for that exact action in that message.
   When you resolve merge conflicts, edit the files in the working tree and leave them
   unstaged; I review the resolution as an ordinary diff.
3. Never push, rebase, merge, cherry-pick, stash, or switch branches on your own.

## Builds and tests

1. Do not edit sources while a build or a test run is in progress. Queue the edits and
   apply them after the run has ended.
2. In a review session (I read someone else's change), do not build or run tests unless I
   ask; deliver findings from reading.
3. Write logs and temporary files under `~/tmp`, never under `/tmp`.

## Working with me

1. A question about code ("why is this here?", "do we need this?") asks for an explanation.
   Answer it; do not change the code unless I ask for a change.
2. When you point at code, write a path that a fuzzy file finder resolves from the repository
   root, followed by `:line`, and make sure the line is the statement you mean.
3. Do not spend effort on formatting; clang-format runs on commit.
