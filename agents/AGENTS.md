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

## Internal services

Internal pages are reachable only through MCP servers; web search or fetch cannot see them and will report the page as inaccessible. Match a link to a server by the service it belongs to, not by the exact hostname: the same service is served from several domains (different installations, mirrors, old and new names), and the servers do not publish a list. If a tool takes a URL, pass the link as is; otherwise turn it into what the tool expects (page slug, issue key, dashboard reference):

- Wiki pages, usually `wiki.yandex-team.ru`: the `wiki` server.
- Tracker issues, usually `st.yandex-team.ru`: the `tracker_mcp` server.
- Monitoring dashboards, alerts and metrics (Monium / Solomon UI), usually `monitoring.yandex-team.ru` but also other domains: the `monium_mcp` server; its dashboard tool accepts the full URL.
- Searching internal sources (wiki, tracker, Arcanum, internal Stack Overflow) or the monorepo by description: the `intrasearch` server. The `wiki` server only opens a page by slug; use `intrasearch` to find the page first.
- Sandbox resources (CI logs, Allure reports, attachments in tracker issues), usually `proxy.sandbox.yandex-team.ru/<id>/...` but also `sandbox.yandex-team.ru/resource/<id>/...` and other hosts: no MCP, download with `ya` from the shell. A link being there does not mean it has to be downloaded: fetch a resource only when the answer needs what is inside it. If the stack trace in the issue already explains the failure, the logs stay where they are. The long number in the URL is the Sandbox resource id; the rest of the URL is a path inside that resource. Put it under `~/tmp/<current branch>/<what it is>/`, so that everything belonging to a finished branch can be deleted together and the name says what the data is (issue key and kind, not the resource id). `--output` must name a directory that does not exist yet. Run it from an arcadia directory (the `ya` on `PATH` resolves tools through the checkout it is run in):

  ```bash
  # working on branch fix-cs-verify, logs of the nemesis run from YDBBUGS-523
  cd ~/dev/arcadia && ya download sbr:13441222991 --output ~/tmp/fix-cs-verify/YDBBUGS-523-nemesis-logs
  # https://proxy.sandbox.yandex-team.ru/13441222991/data/attachments/58480e6f3fe83946.gz
  # is now ~/tmp/fix-cs-verify/YDBBUGS-523-nemesis-logs/data/attachments/58480e6f3fe83946.gz
  ```

  Resources can be large (a whole Allure report is gigabytes), and a `.gz` attachment there is usually a tar archive with one directory per host.
