" leollama.vim — autoload engine. Functions here are globally addressable
" (leollama#...), lazy-loaded, and stable across plugin re-sourcing.
"
" Talks to a local Ollama server's native generate endpoint:
"   POST http://localhost:11434/api/generate
"   { model, prompt, suffix, stream: false, options: {...} }
" FIM works for models whose template supports the suffix parameter
" (qwen3:8b, codellama:*-code, starcoder2, ...). Response JSON carries
" the completion in the top-level "response" field. No API key needed.

let s:default_endpoint = 'http://localhost:11434/api/generate'

function! s:get(key, default) abort
  return get(g:, 'leollama_' . a:key, a:default)
endfunction

function! s:log(msg) abort
  if get(g:, 'leollama_debug', 0)
    call writefile([strftime('%H:%M:%S') . ' ' . a:msg], '/tmp/leollama.log', 'a')
  endif
endfunction

let s:enabled = s:get('enabled', 1)
let s:ghost_lines = []
let s:ghost_active = 0
let s:timer_id = -1
let s:cur_job = v:null
let s:job_chunks = []
let s:gen = 0
let s:req_lnum = 0
let s:req_col = 0
let s:req_buf = 0
let s:warned_down = 0

function! s:clear_ghost() abort
  if s:ghost_active
    silent! call prop_remove({'type': 'leollama_ghost', 'all': v:true}, 1, line('$'))
    let s:ghost_lines = []
    let s:ghost_active = 0
  endif
endfunction

function! s:render_ghost(lines) abort
  call s:clear_ghost()
  if empty(a:lines) || (len(a:lines) == 1 && a:lines[0] ==# '')
    return
  endif
  let l:lnum = line('.')
  let l:curlen = strlen(getline(l:lnum))
  let l:c = col('.')
  if l:c > l:curlen
    call prop_add(l:lnum, 0, {'type': 'leollama_ghost', 'text': a:lines[0], 'text_align': 'after'})
  else
    call prop_add(l:lnum, l:c, {'type': 'leollama_ghost', 'text': a:lines[0]})
  endif
  for l:extra in a:lines[1:]
    call prop_add(l:lnum, 0, {'type': 'leollama_ghost', 'text': l:extra, 'text_align': 'below'})
  endfor
  let s:ghost_lines = a:lines
  let s:ghost_active = 1
endfunction

function! s:on_out(gen, ch, msg) abort
  if a:gen != s:gen
    return
  endif
  call add(s:job_chunks, a:msg)
endfunction

function! s:on_err(gen, ch, msg) abort
  call s:log('ERR ' . a:msg)
endfunction

function! s:finish(gen, ch) abort
  if a:gen != s:gen
    call s:log('bail: stale job gen=' . a:gen . ' cur=' . s:gen)
    return
  endif
  call s:log('finish chunks=' . len(s:job_chunks))
  if bufnr('%') != s:req_buf || line('.') != s:req_lnum || col('.') != s:req_col
    call s:log('bail: cursor moved (buf/lnum/col mismatch)')
    return
  endif
  if mode() !~# '^i'
    call s:log('bail: not insert mode (' . mode() . ')')
    return
  endif
  let l:raw = join(s:job_chunks, '')
  if l:raw ==# ''
    if !s:warned_down
      let s:warned_down = 1
      echohl WarningMsg | echom 'LeOllama: empty reply — is the Ollama server running?' | echohl None
    endif
    call s:log('bail: empty response')
    return
  endif
  try
    let l:data = json_decode(l:raw)
  catch
    call s:log('bail: json_decode failed: ' . v:exception . ' raw=' . l:raw[0:300])
    return
  endtry
  if type(l:data) != v:t_dict
    call s:log('bail: non-dict response. raw=' . l:raw[0:300])
    return
  endif
  if has_key(l:data, 'error')
    call s:log('bail: ollama error: ' . string(l:data.error))
    if !s:warned_down
      let s:warned_down = 1
      echohl WarningMsg | echom 'LeOllama: ' . string(l:data.error) | echohl None
    endif
    return
  endif
  let l:text = get(l:data, 'response', '')
  if l:text ==# ''
    return
  endif
  let s:warned_down = 0
  let l:lines = split(l:text, "\n", 1)
  let l:maxl = s:get('max_lines', 3)
  if l:maxl > 0 && len(l:lines) > l:maxl
    let l:lines = l:lines[0 : l:maxl - 1]
  endif
  call s:render_ghost(l:lines)
endfunction

function! s:trigger(...) abort
  let s:timer_id = -1
  if !s:enabled || mode() !~# '^i'
    return
  endif
  call s:log('trigger fired')
  if type(s:cur_job) == v:t_job && job_status(s:cur_job) ==# 'run'
    call job_stop(s:cur_job)
  endif

  let l:lnum = line('.')
  let l:c = col('.')
  let s:req_lnum = l:lnum
  let s:req_col = l:c
  let s:req_buf = bufnr('%')

  let l:all = getline(1, '$')
  let l:cur = l:all[l:lnum - 1]
  let l:before_cur = strpart(l:cur, 0, l:c - 1)
  let l:after_cur = strpart(l:cur, l:c - 1)

  let l:prefix = ''
  if l:lnum > 1
    let l:prefix = join(l:all[0 : l:lnum - 2], "\n") . "\n"
  endif
  let l:prefix .= l:before_cur

  let l:suffix = l:after_cur
  if l:lnum < len(l:all)
    let l:suffix .= "\n" . join(l:all[l:lnum :], "\n")
  endif

  " Defaults are deliberately small: prompt evaluation dominates local FIM
  " latency (~2.5ms/token on an M4 Pro with the 7b model), and Ollama's KV
  " prefix cache only pays off when the context fits comfortably in num_ctx.
  let l:maxp = s:get('max_prefix', 2000)
  let l:maxs = s:get('max_suffix', 1000)
  if strlen(l:prefix) > l:maxp
    let l:prefix = strpart(l:prefix, strlen(l:prefix) - l:maxp)
    let l:nl = stridx(l:prefix, "\n")
    if l:nl >= 0
      let l:prefix = strpart(l:prefix, l:nl + 1)
    endif
  endif
  if strlen(l:suffix) > l:maxs
    let l:suffix = strpart(l:suffix, 0, l:maxs)
    let l:nl = strridx(l:suffix, "\n")
    if l:nl >= 0
      let l:suffix = strpart(l:suffix, 0, l:nl)
    endif
  endif

  " 64 tokens ≈ 4-5 lines — more than max_lines ever shows. A higher cap
  " only buys slower worst-case latency on runaway generations.
  let l:options = {
        \ 'temperature': s:get('temperature', 0.2),
        \ 'num_predict': s:get('max_tokens', 64),
        \ }
  let l:stop = s:get('stop', ["\n\n\n"])
  if type(l:stop) == v:t_list && !empty(l:stop)
    let l:options.stop = l:stop
  endif
  let l:payload = {
        \ 'model': s:get('model', 'qwen3:8b'),
        \ 'prompt': l:prefix,
        \ 'suffix': l:suffix,
        \ 'stream': v:false,
        \ 'keep_alive': s:get('keep_alive', '60m'),
        \ 'options': l:options,
        \ }
  let l:body = json_encode(l:payload)

  let l:argv = ['curl', '-s', '-X', 'POST', s:get('endpoint', s:default_endpoint),
        \ '-H', 'Content-Type: application/json',
        \ '-d', l:body]

  call s:log('POST body=' . strlen(l:body) . 'B prefix=' . strlen(l:prefix) . ' suffix=' . strlen(l:suffix))
  let s:gen += 1
  let l:gen = s:gen
  let s:job_chunks = []
  let s:cur_job = job_start(l:argv, {
        \ 'out_mode': 'raw',
        \ 'out_cb': function('s:on_out', [l:gen]),
        \ 'err_cb': function('s:on_err', [l:gen]),
        \ 'close_cb': function('s:finish', [l:gen]),
        \ })
endfunction

function! leollama#on_change() abort
  if !s:enabled
    return
  endif
  call s:clear_ghost()
  if s:timer_id != -1
    call timer_stop(s:timer_id)
  endif
  let s:timer_id = timer_start(s:get('debounce_ms', 150), function('s:trigger'))
endfunction

function! leollama#on_leave() abort
  call s:clear_ghost()
endfunction

function! leollama#dismiss() abort
  call s:clear_ghost()
endfunction

function! leollama#toggle() abort
  let s:enabled = !s:enabled
  if !s:enabled
    call s:clear_ghost()
  endif
  echo 'LeOllama ' . (s:enabled ? 'enabled' : 'disabled')
endfunction

function! leollama#accept() abort
  if !s:ghost_active
    if pumvisible()
      call feedkeys("\<C-n>", 'n')
    else
      call feedkeys("\<Tab>", 'n')
    endif
    return
  endif
  let l:lines = copy(s:ghost_lines)
  call s:clear_ghost()
  let l:lnum = line('.')
  let l:c = col('.')
  let l:cur = getline(l:lnum)
  let l:before = strpart(l:cur, 0, l:c - 1)
  let l:after = strpart(l:cur, l:c - 1)
  if len(l:lines) == 1
    call setline(l:lnum, l:before . l:lines[0] . l:after)
    call cursor(l:lnum, strlen(l:before . l:lines[0]) + 1)
  else
    call setline(l:lnum, l:before . l:lines[0])
    let l:lines[-1] = l:lines[-1] . l:after
    call append(l:lnum, l:lines[1:])
    let l:endlnum = l:lnum + len(l:lines) - 1
    call cursor(l:endlnum, strlen(l:lines[-1]) - strlen(l:after) + 1)
  endif
endfunction
