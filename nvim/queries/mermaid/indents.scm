; Replaces nvim-treesitter's mermaid indent query. It must live in nvim/queries
; (not after/queries): the first base query file on runtimepath wins, and the
; plugin installs its copy into ~/.local/share/nvim/site, after the config dir.
;
; The upstream query indents every line one level below the diagram header and
; dedents "end" to the header, so inside a markdown ```mermaid block each new
; line is reset to a flat 2-space indent instead of following the previous line.
; Mermaid nesting (loop/alt/par blocks, class bodies) is just whitespace to the
; parser, so defer to Vim's 'autoindent' and keep the previous line's indent.
(source_file) @indent.auto
