let s:is_win = has("win32") || has("win64")
let s:client = v:null
let s:name = 'coc'
let s:is_vim = !has('nvim')

function! coc#rpc#start_server()
  if $NODE_ENV ==# 'test'
    " server already started
    let s:client = coc#client#create(s:name, [])
    let s:client['running'] = 1
    let s:client['chan_id'] = get(g:, 'coc_node_channel_id', 0)
    call dictwatcheradd(g:, 'coc_node_channel_id', function('s:ChannelSet'))
    return
  endif
  if empty(s:client)
    let cmd = coc#util#job_command()
    if empty(cmd) | return | endif
    let $VIMCONFIG = coc#util#get_config_home()
    let s:client = coc#client#create(s:name, cmd)
  endif
  if !coc#client#is_running('coc')
    call s:client['start']()
  endif
endfunction

function! coc#rpc#ready()
  if empty(s:client) || s:client['running'] == 0 | return 0 | endif
  return 1
endfunction

function! s:ChannelSet(dict, key, val)
  let chan_id = get(a:val, 'new', 0)
  if empty(s:client) | return | endif
  let s:client['running'] = 1
  let s:client['chan_id'] = chan_id
  call dictwatcherdel(g:, 'coc_node_channel_id', function('s:ChannelSet'))
endfunction

function! coc#rpc#kill()
  let pid = get(g:, 'coc_process_pid', 0)
  if !pid | return | endif
  if s:is_win
    call system('taskkill /PID '.pid)
  else
    call system('kill -9 '.pid)
  endif
endfunction

function! coc#rpc#get_errors()
  return split(execute('messages'), "\n")
endfunction

function! coc#rpc#stop()
  if empty(s:client)
    return
  endif
  try
    if s:is_vim
      call job_stop(ch_getjob(s:client['channel']), 'term')
    else
      call jobstop(s:client['chan_id'])
    endif
  catch /.*/
    " ignore
  endtry
endfunction

function! coc#rpc#restart()
  if empty(s:client)
    call coc#rpc#start_server()
  else
    for i in range(1, winnr('$'))
      if getwinvar(i, 'float')
        execute i.'wincmd c'
      endif
    endfor
    call coc#rpc#request('detach', [])
    sleep 100m
    let s:client['command'] = coc#util#job_command()
    call coc#client#restart(s:name)
    echohl MoreMsg | echom 'starting coc.nvim service' | echohl None
  endif
endfunction

function! coc#rpc#request(method, args) abort
  if !coc#rpc#ready() | return '' | endif
  return s:client['request'](a:method, a:args)
endfunction

function! coc#rpc#notify(method, args) abort
  if !coc#rpc#ready() | return '' | endif
  call s:client['notify'](a:method, a:args)
  return ''
endfunction

function! coc#rpc#request_async(method, args, cb) abort
  if !coc#rpc#ready() | return cb('coc.nvim service not started.') | endif
  call s:client['request_async'](a:method, a:args, a:cb)
endfunction

" receive async response
function! coc#rpc#async_response(id, resp, isErr) abort
  if empty(s:client) | return | endif
  call coc#client#on_response(s:name, a:id, a:resp, a:isErr)
endfunction

" send async response to server
function! coc#rpc#async_request(id, method, args)
  let l:Cb = {err, res -> coc#rpc#notify('nvim_async_response_event', [a:id, err, res])}
  let args = a:args + [l:Cb]
  try
    call call(a:method, args)
  catch /.*/
    call coc#rpc#notify('nvim_async_response_event', [a:id, v:exception])
  endtry
endfunction
