let s:save_cpo = &cpo
set cpo&vim

let s:null_pos   = [0, 0, 0, 0]
let s:null_order = [-1, -1, -1, -1, -1, -1, -1]

function! operator#jerk#forward(motion_wise, ...)
  return s:jerk('f', 'following', a:motion_wise, a:000)
endfunction

function! operator#jerk#backward(motion_wise, ...)
  return s:jerk('b', 'following', a:motion_wise, a:000)
endfunction

function! operator#jerk#forward_partial(motion_wise, ...)
  return s:jerk('f', 'partial', a:motion_wise, a:000)
endfunction

function! operator#jerk#backward_partial(motion_wise, ...)
  return s:jerk('b', 'partial', a:motion_wise, a:000)
endfunction

function! operator#jerk#precedent(name, mode)
  call s:set_info('state', 1)
  call s:set_info('count', v:prevcount == 0 ? 1 : v:prevcount)
  call s:set_info('cursor', getpos('.'))
  call s:set_info('mode', a:mode)
  execute 'setlocal operatorfunc=operator#jerk#' . a:name
  return
endfunction

function! s:jerk(direction, kind, motion_wise, args) "{{{
  let textblock  = [getpos("'["), getpos("']")]
  if s:is_valid_range(textblock)
    let opt = {}
    let opt.shiftwidth = s:user_conf('shiftwidth', shiftwidth())
    let opt.shiftround = s:user_conf('shiftround', &l:shiftround)
    let opt.rigid_body = s:user_conf('rigid_body', 0)
    let opt.expandtab_inside = s:user_conf('expandtab_inside', 0)

    call s:jerk_{a:motion_wise}wise(a:direction, a:kind, textblock, opt)
    call s:set_info('state', 0)
  endif
  return
endfunction
"}}}
function! s:jerk_charwise(direction, kind, textblock, opt)  "{{{
  let [head, tail] = a:textblock
  let line    = getline(head[1])
  let l:count = s:get_info('count')

  let [order1, order2] = s:decide_orders(a:direction, a:kind, head[2],
                                        \ tail[2], line, l:count, a:opt)

  if order1 != s:null_order
    call setline(head[1], s:build_line(line, order1, order2))

    let byte_length = strlen(s:white_space(order1[1], order1[2], order1[3]))
    let modify_head = [0, head[1], order1[5], 0]
    if order2[5] < 0
      let modify_tail = order1[1] < 1 ? modify_head
                    \ : [0, head[1], order1[0] + byte_length + 1, 0]
    else
      let modify_tail_col = a:direction == 'f'
              \ ? order2[5] + order1[0] - order1[4] + byte_length + 2
              \ : order2[5] + order1[0] - order1[4] + byte_length + 1
      let modify_tail = [0, head[1], modify_tail_col, 0]
    endif
    let cursor = [0, head[1], order1[0] + byte_length + 2, 0]
    call s:setpos(modify_head, modify_tail, cursor)
  endif

  return
endfunction
"}}}
function! s:jerk_linewise(direction, kind, textblock, opt)  "{{{
  let [head, tail] = a:textblock
  let lines   = getline(head[1], tail[1])
  let modify  = 0
  let state   = s:get_info('state')
  let cur_col = state ? s:get_info('cursor')[2] : col('.')
  let l:count = s:get_info('count')

  let newlines = []
  for line in reverse(lines)
    let head_col = matchend(line, '\s*\zs\S', cur_col - 1)
    let tail_col = matchend(line, '\S\+', head_col - 1)

    let [order1, order2] = s:decide_orders(a:direction, a:kind, head_col,
                                          \ tail_col, line, l:count, a:opt)

    let modify = order1 != s:null_order ? 1 : modify
    let newlines += [s:build_line(line, order1, order2)]
  endfor

  if modify
    silent execute printf('%s,%sdelete', head[1], tail[1])
    call append(head[1] - 1, reverse(newlines))

    let byte_length = strlen(s:white_space(order1[1], order1[2], order1[3]))
    let modify_head = [0, head[1], 0, 0]
    let modify_tail = [0, tail[1], col([tail[1], '$']), 0]
    let cursor = order1 == s:null_order ? head : [0, head[1], order1[0] + byte_length + 2, 0]
    call s:setpos(modify_head, modify_tail, cursor)
  endif
  return
endfunction
"}}}
function! s:jerk_blockwise(direction, kind, textblock, opt) "{{{
  let [head, tail] = a:textblock
  let lines    = getline(head[1], tail[1])
  let head_col = head[2]
  let tail_col = tail[2]
  let state    = s:get_info('state')
  let l:count  = s:get_info('count')
  let mode     = s:get_info('mode')

  if a:kind ==# 'partial' && mode ==# 'x'
    if state
      normal! gv
      let is_extended = winsaveview().curswant == 1/0
      execute "normal! \<Esc>"
    else
      let is_extended = s:get_info('extended')
    endif
  else
    let is_extended = 0
  endif
  call s:set_info('extended', is_extended)

  let newlines = []
  let order_list = []
  for line in lines
    let order_list += [s:decide_orders(a:direction,
                                     \ a:kind,
                                     \ head_col,
                                     \ is_extended ? strlen(line) : tail_col,
                                     \ line,
                                     \ l:count,
                                     \ a:opt
                                     \ )[0]]
  endfor

  if a:direction ==# 'f'
    let pattern = 'v:val[0] + v:val[1] - v:val[4] + 1'
  elseif a:direction ==# 'b'
    let pattern = 'v:val[4] - v:val[0] - v:val[1] - 1'
  endif
  let width = min(map(copy(order_list), pattern))

  if width > 0
    let newlines = []
    for line in lines
      if a:direction ==# 'f'
        if a:kind ==# 'following'
          let order1 = s:push('head', head_col, line, l:count, a:opt, width)
          let order2 = copy(s:null_order)
        elseif a:kind ==# 'partial'
          let order1 = s:push('head', head_col, line, l:count, a:opt, width)
          let order2 = s:pull('tail', is_extended ? col([line, '$']) - 1 : tail_col, line, l:count, a:opt, width)
        endif
      elseif a:direction ==# 'b'
        if a:kind ==# 'following'
          let order1 = s:pull('head', head_col, line, l:count, a:opt, width)
          let order2 = copy(s:null_order)
        elseif a:kind ==# 'partial'
          let order1 = s:pull('head', head_col, line, l:count, a:opt, width)
          let order2 = s:push('tail', is_extended ? col([line, '$']) - 1 : tail_col, line, l:count, a:opt, width)
        endif
      endif

      let newlines += [s:build_line(line, order1, order2)]
    endfor

    silent execute printf('%s,%sdelete', head[1], tail[1])
    call append(head[1] - 1, newlines)

    let byte_length = strlen(s:white_space(order1[1], order1[2], order1[3]))
    let modify_head = [0, head[1], order1[5], 0]
    if order2[5] < 0
      let modify_tail = order1[1] < 1 ? [0, tail[1], order1[5], 0]
                    \ : [0, tail[1], order1[0] + byte_length + 1, 0]
    else
      let modify_tail_col = a:direction == 'f'
              \ ? order2[5] + order1[0] - order1[4] + byte_length + 2
              \ : order2[5] + order1[0] - order1[4] + byte_length + 1
      let modify_tail = [0, tail[1], modify_tail_col, 0]
    endif
    let cursor = [0, head[1], order1[0] + byte_length + 2, 0]
    call s:setpos(modify_head, modify_tail, cursor)
  endif

  return
endfunction
"}}}
function! s:decide_orders(direction, kind, head, tail, line, count, opt)  "{{{
  if a:direction ==# 'f'
    if a:kind ==# 'following'
      let order1 = s:push('head', a:head, a:line, a:count, a:opt)
      let order2 = copy(s:null_order)
    elseif a:kind ==# 'partial'
      let order1 = s:push('head', a:head, a:line, a:count, a:opt)
      let order2 = s:pull('tail', a:tail, a:line, a:count, a:opt)
      let width1 = order1[6]
      let width2 = a:tail >= strlen(a:line) ? 1/0 : order2[6]
      if min([width1, width2]) > 0
        if width1 > width2
          let order1 = s:push('head', a:head, a:line, a:count, a:opt, width2)
        else
          let order2 = s:pull('tail', a:tail, a:line, a:count, a:opt, width1)
        endif
      else
        let [order1, order2] = [copy(s:null_order), copy(s:null_order)]
      endif
    endif
  elseif a:direction ==# 'b'
    if a:kind ==# 'following'
      let order1 = s:pull('head', a:head, a:line, a:count, a:opt)
      let order2 = copy(s:null_order)
    elseif a:kind ==# 'partial'
      let order1 = s:pull('head', a:head, a:line, a:count, a:opt)
      let width1 = a:tail >= strlen(a:line) ? 1/0 : order1[6]
      if width1 > 0
        let order2 = s:push('tail', a:tail, a:line, a:count, a:opt, width1)
      else
        let order2 = copy(s:null_order)
      endif
    endif
  endif

  return [order1, order2]
endfunction
"}}}
function! s:build_line(line, order1, order2)  "{{{
  if a:order1 == s:null_order && a:order2 == s:null_order
    let line = a:line
  elseif a:order2 == s:null_order
    let line = printf('%s%s%s',
                    \   a:order1[0] < 0 ? '' : a:line[: a:order1[0]],
                    \   s:white_space(a:order1[1], a:order1[2], a:order1[3]),
                    \   a:line[a:order1[4] :]
                    \ )
  else
    let line = printf('%s%s%s%s%s',
                    \   a:order1[0] < 0 ? '' : a:line[: a:order1[0]],
                    \   s:white_space(a:order1[1], a:order1[2], a:order1[3]),
                    \   a:line[a:order1[4] : a:order2[0]],
                    \   s:white_space(a:order2[1], a:order2[2], a:order2[3]),
                    \   a:line[a:order2[4] :]
                    \ )
  endif

  return line
endfunction
"}}}
function! s:white_space(width, expandtab, gap) "{{{
  if a:expandtab
    let ws = repeat(' ', a:width)
  else
    let ws    = ''
    let width = a:width

    if a:gap > 0
      let ws .= repeat('	', 1)
      let width -= a:gap
    endif

    let ws .= repeat('	', width/&l:tabstop)
    let ws .= repeat(' ', width%&l:tabstop)
  endif

  return ws
endfunction
"}}}
function! s:setpos(head, tail, cursor) "{{{
  call setpos("'[", a:head)
  call setpos("']", a:tail)
  call setpos('.', a:cursor)
  return
endfunction
"}}}
function! s:push(edge, col, line, count, opt, ...) "{{{
  let [l:count, shiftwidth, shiftround] = a:0 > 0
      \ ? [1, a:1, 0]
      \ : [a:count, a:opt.shiftwidth, a:edge ==# 'tail' ? 0 : a:opt.shiftround]
  let expandtab_inside = a:opt.expandtab_inside
  let rigid_body       = a:opt.rigid_body

  let output = copy(s:null_order)
  if shiftwidth > 0
    let col = a:col - 1

    if a:edge ==# 'head'
      let space_len  = 0
      let width      = shiftwidth
      let head_width = 0

      if rigid_body && col > 0 && a:line[col - 1 : col] =~# '\S\S'
        let col = match(a:line[: col], '\%(^\|\s\)\zs\S\+$')
      endif

      if col > 0
        let spaces     = matchstr(a:line[: col - 1], ' *$')
        let space_len  = strlen(spaces)
        let width      = space_len + shiftwidth
        let head_width = strdisplaywidth(a:line[: col - 1])
      endif

      let ledge   = col - space_len - 1
      let redge   = col
    elseif a:edge ==# 'tail'
      let spaces     = ''
      let space_len  = 0
      let width      = shiftwidth
      let head_width = strdisplaywidth(a:line[: col])

      if col >= 0 && col < strlen(a:line)
        if col != strlen(a:line) - 1
          if rigid_body && a:line[col : col + 1] =~# '\S\S'
            let col += match(a:line[col :], '\S\%(\s\|$\)')
          endif

          let spaces     = matchstr(a:line[col + 1 :], '^\s*')
          let space_len  = strdisplaywidth(spaces, strdisplaywidth(a:line[: col]))
          let width      = shiftwidth + space_len
          let head_width = strdisplaywidth(a:line[: col])
        endif
      endif

      let ledge = col
      let redge = col + strlen(spaces) + 1
    endif

    if col >= 0 && col < strlen(a:line) && !(a:edge ==# 'tail' && redge == strlen(a:line))
      let expandtab = space_len >= &l:tabstop
                  \ || (expandtab_inside && col > match(a:line, '^\s*\zs\S'))
                  \ ? 1 : &l:expandtab
      let shiftround = space_len >= &l:tabstop && !&l:expandtab
                   \ ? 1 : shiftround

      if !(a:edge == 'tail')
        if !expandtab || shiftround
          if (head_width + shiftwidth)/shiftwidth() > head_width/shiftwidth()
            let width -= (head_width + shiftwidth)%shiftwidth()
          endif
        endif

        " for {count}
        if l:count > 1
          let width += shiftwidth*(l:count - 1)
        endif
      endif

      let gap  = 0
      let slip = a:edge == 'tail' && a:0 > 0 ? a:1 : 0
      if (!expandtab || shiftround) && ledge > 0 && width > 0
        let gap = (&l:tabstop - (strdisplaywidth(a:line[: ledge]) - slip)%&l:tabstop)%&l:tabstop
        let gap = gap <= width + slip ? gap : 0
      endif

      if a:edge ==# 'head'
        let medge = !expandtab && (gap > 0 || (gap == 0 && width >= &l:tabstop))
                \ ? ledge + 2 : ledge + space_len + 2
      elseif a:edge ==# 'tail'
        let medge = ledge + strlen(s:white_space(width, expandtab, gap)) + 1
      endif

      let output = [ledge, width, expandtab, gap, redge, medge, width - space_len]
    endif
  endif

  return output
endfunction
"}}}
function! s:pull(edge, col, line, count, opt, ...) "{{{
  let [l:count, shiftwidth, shiftround] = a:0 > 0
      \ ? [1, a:1, 0]
      \ : [a:count, a:opt.shiftwidth, a:edge ==# 'tail' ? 0 : a:opt.shiftround]
  let expandtab_inside = a:opt.expandtab_inside
  let rigid_body       = a:opt.rigid_body

  let output = copy(s:null_order)
  if shiftwidth > 0
    let col     = a:col - 1
    let max_len = 0
    if (a:edge ==# 'head' && col > 0 && col < strlen(a:line))
          \ || (a:edge ==# 'tail' && col >= 0 && col < strlen(a:line) - 1)
      if a:edge ==# 'head'
        if rigid_body && a:line[col - 1 : col] =~# '\S\S'
          let col = match(a:line[: col], '\%(^\|\s\)\zs\S\+$')
        endif

        let ws = matchstr(a:line[: col - 1], '\s*$')
      elseif a:edge ==# 'tail'
        if rigid_body && a:line[col : col + 1] =~# '\S\S'
          let col += match(a:line[col :], '\S\%(\s\|$\)')
        endif

        let ws = matchstr(a:line[col + 1 :], '^\s*')
      endif
      let max_len = strlen(ws)
    endif

    if max_len > 0
      if a:edge ==# 'head'
        let start_col = col - 1
        let stop_col  = start_col - max_len
        let idx       = start_col
        let expandtab = 0
      elseif a:edge ==# 'tail'
        let stop_col  = col
        let start_col = stop_col + max_len
        let idx       = start_col
        let expandtab = (expandtab_inside && col > match(a:line, '^\s*\zs\S'))
                    \ ? 1 : &l:expandtab
        let header_width = strdisplaywidth(a:line[: stop_col])
      endif

      if shiftround
        let width = strdisplaywidth(a:line[: start_col]) - shiftwidth
        let rounded_col = width < 0 || width%shiftwidth() == 0
                      \ ? width
                      \ : width + (shiftwidth() - width%shiftwidth())
      endi

      let overrun = 0
      while idx > stop_col
        let idx -= 1

        let width = strdisplaywidth(a:line[idx + 1 : start_col], strdisplaywidth(a:line[: idx]))
        if width >= shiftwidth
          let overrun = width - shiftwidth
          break
        endif

        if shiftround
          let idx_width = strdisplaywidth(a:line[: idx])
          if idx_width <= rounded_col
            let overrun = rounded_col - idx_width
            break
          endif
        endif
      endwhile

      " for {count}
      if l:count > 1
        let idx = overrun > 0 ? idx + 1 : idx
        let thr_width = width + shiftwidth*(l:count - 1)

        let overrun = 0
        while idx > stop_col
          let idx -= 1

          let width = strdisplaywidth(a:line[idx + 1 : start_col], strdisplaywidth(a:line[: idx]))
          if width >= thr_width
            let overrun = width - thr_width
            break
          endif
        endwhile
      endif

      if a:edge ==# 'head'
        let medge        = idx + 2
        let displacement = strdisplaywidth(a:line[: start_col]) - strdisplaywidth(a:line[: idx]) - overrun
        let gap          = 0
      elseif a:edge ==# 'tail'
        let overrun     += strdisplaywidth(a:line[stop_col + 1 : idx], header_width)
        let displacement = strdisplaywidth(a:line[stop_col + 1 : start_col], strdisplaywidth(a:line[: stop_col])) - overrun
        let idx          = stop_col
        let medge        = a:col - 1

        let gap = 0
        if (!expandtab || shiftround) && start_col + 1 > 0 && overrun > 0
          let slip = a:edge == 'tail' && a:0 > 0 ? a:1 : 0
          if (strdisplaywidth(a:line[: start_col + 1]))%&l:tabstop == 1
            let gap = (&l:tabstop - (strdisplaywidth(a:line[: idx]) + slip)%&l:tabstop)%&l:tabstop
          else
            let gap = 0
          endif
          let gap = gap <= width ? gap : 0
        endif
      endif

      let output = [idx, overrun, expandtab, gap, start_col + 1, medge, displacement]
    endif
  endif

  return output
endfunction
"}}}

function! s:is_valid_range(range)  "{{{
  let [head, tail] = a:range
  if head != s:null_pos && tail != s:null_pos
    \ && (head[1] == tail[1] && head[2] <= tail[2]) || (head[1] < tail[1])
    return 1
  else
    return 0
  endif
endfunction
"}}}
function! s:user_conf(name, default)    "{{{
  let user_conf = a:default

  if exists('g:operator_jerk_' . a:name)
    let user_conf = g:operator_jerk_{a:name}
  endif

  if exists('t:operator_jerk_' . a:name)
    let user_conf = t:operator_jerk_{a:name}
  endif

  if exists('w:operator_jerk_' . a:name)
    let user_conf = w:operator_jerk_{a:name}
  endif

  if exists('b:operator_jerk_' . a:name)
    let user_conf = b:operator_jerk_{a:name}
  endif

  return user_conf
endfunction
"}}}
function! s:get_info(name)  "{{{
  if !exists('b:operator_jerk')
    " initialization
    let b:operator_jerk = {}
    let b:operator_jerk.state = 0
    let b:operator_jerk.count = 1
    let b:operator_jerk.cursor = [0, 0, 0, 0]
    let b:operator_jerk.mode = ''
    let b:operator_jerk.extended = 0
  endif
  return b:operator_jerk[a:name]
endfunction
"}}}
function! s:set_info(name, value) "{{{
  if !exists('b:operator_jerk')
    " initialization
    call s:get_info('state')
  endif
  let b:operator_jerk[a:name] = a:value
endfunction
"}}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:
