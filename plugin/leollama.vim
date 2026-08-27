" leollama.vim — Copilot-style inline autocomplete for classic Vim 9 via a
" local Ollama server (FIM through /api/generate's suffix parameter).
" Grey ghost text after the cursor; <Tab> accepts. Free, offline, no API key.
" Logic lives in autoload/leollama.vim (stable across re-sourcing).

if exists('g:loaded_leollama')
  finish
endif
let g:loaded_leollama = 1

if !has('patch-9.0.0067') || !has('textprop') || !has('job')
  echohl WarningMsg
  echom 'LeOllama: needs Vim 9.0.0067+ with +textprop and +job'
  echohl None
  finish
endif

highlight default LeOllamaGhost guifg=#808080 ctermfg=245 gui=NONE cterm=NONE
if empty(prop_type_get('leollama_ghost'))
  call prop_type_add('leollama_ghost', {'highlight': 'LeOllamaGhost'})
endif

augroup LeOllama
  autocmd!
  autocmd ColorScheme * highlight default LeOllamaGhost guifg=#808080 ctermfg=245 gui=NONE cterm=NONE
  autocmd TextChangedI * call leollama#on_change()
  autocmd CursorHoldI  * call leollama#on_idle()
  autocmd InsertLeave,BufLeave * call leollama#on_leave()
augroup END

let s:accept_key = get(g:, 'leollama_accept_key', '<Tab>')
execute 'inoremap <silent> ' . s:accept_key . ' <Cmd>call leollama#accept()<CR>'
inoremap <silent> <C-]> <Cmd>call leollama#dismiss()<CR>

command! LeOllamaToggle call leollama#toggle()
command! LeOllamaDismiss call leollama#dismiss()
