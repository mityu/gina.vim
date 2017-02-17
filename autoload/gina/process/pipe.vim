let s:Guard = vital#gina#import('Vim.Guard')
let s:Queue = vital#gina#import('Data.Queue')


" Store pipe -----------------------------------------------------------------
function! gina#process#pipe#store() abort
  let pipe = copy(s:store_pipe)
  let pipe._stdout = []
  let pipe._stderr = []
  let pipe._content = []
  return pipe
endfunction

let s:store_pipe = {}

function! s:store_pipe.on_stdout(job, msg, event) abort
  call s:extend_content(self._stdout, a:msg)
  call s:extend_content(self._content, a:msg)
endfunction

function! s:store_pipe.on_stderr(job, msg, event) abort
  call s:extend_content(self._stderr, a:msg)
  call s:extend_content(self._content, a:msg)
endfunction

function! s:store_pipe.on_exit(job, msg, event) abort
  if empty(get(self._content, -1, 'a'))
    call remove(self._content, -1)
  endif
  if empty(get(self._stdout, -1, 'a'))
    call remove(self._stdout, -1)
  endif
  if empty(get(self._stderr, -1, 'a'))
    call remove(self._stderr, -1)
  endif
  call gina#process#unregister(self)
endfunction

function! s:extend_content(content, msg) abort
  let leading = get(a:content, -1, '')
  if len(a:content) > 0
    call remove(a:content, -1)
  endif
  call extend(a:content, [leading . get(a:msg, 0, '')] + a:msg[1:])
endfunction


" Echo pipe ------------------------------------------------------------------
function! gina#process#pipe#echo() abort
  let pipe = extend(gina#process#pipe#store(), s:echo_pipe)
  return pipe
endfunction

let s:echo_pipe = {}

if has('nvim')
  function! s:echo_pipe.on_exit(job, msg, event) abort
    call gina#core#console#echo(join(self._content, "\n"))
    call gina#process#unregister(self)
  endfunction
else
  " NOTE:
  " Vim 8.0.0329 will not echo entire message which was invoked in timer/job.
  " While echo pipe is used to inform the result of the process to a user, it
  " is kind critical so use autocmd to forcedly invoke message.
  let s:echo_pipe_queue = s:Queue.new()
  function! s:echo_pipe.on_exit(job, msg, event) abort
    call gina#process#unregister(self)
    call s:echo_pipe_queue.put(join(self._content, "\n"))
    augroup gina_process_pipe_echo_internal
      autocmd! *
      autocmd * * call s:echo_pipe_callback()
    augroup END
  endfunction

  function! s:echo_pipe_callback() abort
    let msg = s:echo_pipe_queue.get()
    while msg isnot# v:null
      call gina#core#console#echo(msg)
      let msg = s:echo_pipe_queue.get()
    endwhile
    augroup gina_process_pipe_echo_internal
      autocmd! *
    augroup END
  endfunction
endif


" Stream pipe ----------------------------------------------------------------
function! gina#process#pipe#stream() abort
  let pipe = copy(s:stream_pipe)
  let pipe.writer = gina#core#writer#new(s:stream_pipe_writer)
  return pipe
endfunction

function! gina#process#pipe#stream_writer() abort
  return copy(s:stream_pipe_writer)
endfunction

let s:stream_pipe = {}
let s:stream_pipe_writer = {}

function! s:stream_pipe.on_start(job, msg, event) abort
  " DO NOT call gina#proceiss#register() here
  let self.writer._job = self
  call self.writer.start()
endfunction

function! s:stream_pipe.on_stdout(job, msg, event) abort
  call self.writer.write(a:msg)
endfunction

function! s:stream_pipe.on_stderr(job, msg, event) abort
  call self.on_stdout(a:job, a:msg, a:event)
endfunction

function! s:stream_pipe.on_exit(job, msg, event) abort
  " DO NOT call gina#proceiss#unregister() here
endfunction

function! s:stream_pipe_writer.on_start() abort
  let self._winview = getbufvar(self.bufnr, 'gina_winview', [])
  call gina#process#register(self._job)
endfunction

function! s:stream_pipe_writer.on_stop() abort
  call self._job.stop()
  call gina#process#unregister(self._job)

  let focus = gina#core#buffer#focus(self.bufnr)
  if empty(focus) || bufnr('%') != self.bufnr
    return
  endif
  let guard = s:Guard.store(['&l:modifiable'])
  try
    setlocal modifiable
    if empty(getline('$'))
      silent lockmarks keepjumps $delete _
    endif
    setlocal nomodified
  finally
    if !empty(self._winview)
      silent! call winrestview(self._winview)
    endif
    call guard.restore()
    call focus.restore()
  endtry
endfunction

function! s:stream_pipe_writer.on_check() abort
  return self._job.status() ==# 'run'
endfunction


" Automatically update b:gina_winview with cursor move while no buffer content
" is available in BufReadCmd and winsaveview() always returns unwilling value
augroup gina_process_pipe_internal
  autocmd! *
  autocmd CursorMoved  gina://* let b:gina_winview = winsaveview()
  autocmd CursorMovedI gina://* let b:gina_winview = winsaveview()
augroup END
