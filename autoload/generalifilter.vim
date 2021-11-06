if !exists('g:loaded_generalifilter')
    finish
endif
let g:loaded_generalifilter = 1

let s:save_cpo = &cpo
set cpo&vim

" separator between choices and their descriptions (to be concealed)
let s:delimiter = '\\'
let s:prompt = '>> '

augroup GeneralIFilter
    autocmd!
augroup END


function! generalifilter#filter(choices=v:none, prompt=v:none) abort "{{{
    call s:init(a:choices, a:prompt)
    call s:create_window()
    call s:hide_listchars()
    let res = s:interactive_filter()
    call win_execute(s:winid, 'close')
    return res
endfunction "}}}

function! s:init(choices, prompt) abort "{{{
    call s:init_choices()
    call s:init_cands()
    call s:set_choices(a:choices)
    call s:set_prompt(a:prompt)
endfunction "}}}

function! s:init_choices() abort "{{{
    let s:choices = #{
            \ contents      : [],
            \ descriptions  : [],
            \ nodescriptions: 1,
            \ count         : 0,
            \ candidxs      : [],
            \ selidx        : -1,
            \ }
    let g:choices = s:choices

    function! s:choices.str(idx) abort "{{{
        let content = self.contents[a:idx]
        let description = s:choices.nodescriptions ? '' : self.descriptions[a:idx]
        let contentspace = s:choices.nodescriptions ? &textwidth : &textwidth / 3
        let contentlength = min([contentspace - 2,
                \ max(mapnew(s:choices.contents, { _,cont -> strlen(cont) }))])
        let res = trim(call('printf', [
                \ '%-' . contentlength . '.' . contentlength . 's %s %s',
                \ content,
                \ s:delimiter,
                \ description
                \ ]))
        return  (a:idx == self.selidx ? '> ' : '  ') . res
    endfunction "}}}
endfunction "}}}

function! s:init_cands() abort "{{{
    let s:cands = #{
            \ _idxs : [],
            \ count : 0
            \ }

    function! s:cands.idxs(idxs=v:none) abort "{{{
        if type(a:idxs) == v:t_none
            return self._idxs
        endif
        let self._idxs = a:idxs
        let self.count = len(a:idxs)
    endfunction "}}}
endfunction "}}}

function! s:set_choices(choices) abort "{{{
    let t = type(a:choices)
    if t == v:t_list
        call s:set_choices_aslist(a:choices)
    elseif t == v:t_dict
        call s:set_choices_asdict(a:choices)
    endif
endfunction "}}}

function! s:set_choices_aslist(choices) abort "{{{
    let s:choices.contents = a:choices
    if index(s:choices.contents, '') == -1
        call add(s:choices.contents, '')
    endif
    let s:choices.nodescriptions = 1
    let s:choices.count = len(s:choices.contents)
    call s:cands.idxs(range(s:choices.count))
endfunction "}}}

function! s:set_choices_asdict(choices) abort "{{{
    let s:choices.contents = keys(a:choices)
    let s:choices.descriptions = values(a:choices)
    if index(s:choices.contents, '') == -1
        call add(s:choices.contents, '')
        call add(s:choices.descriptions, '')
    endif
    let s:choices.nodescriptions =
        \ reduce(s:choices.descriptions, { acc,val -> acc && empty(val) }, 1)
    let s:choices.count = len(s:choices.contents)
    call s:cands.idxs(range(s:choices.count))
endfunction "}}}

function! s:set_prompt(prompt) abort "{{{
    if type(a:prompt) != v:t_none
        let s:prompt = a:prompt
    endif
endfunction "}}}

function! s:create_window() abort "{{{
    execute 'silent! botright ' . min([&lines / 4, s:choices.count]) . 'new ' .
            \ escape('+setlocal buftype=nofile
                              \ bufhidden=wipe
                              \ noswapfile
                              \ nobuflisted
                              \ nomodified
                              \ nowrap
                              \ nonumber
                              \ conceallevel=2
                              \ concealcursor=n
                              \ laststatus=0
                              \', ' ') .
            \escape(' |syntax region GIFDescription start='''.s:delimiter.''' end=''$'' contains=GIFDelimiter', ' \') .
            \escape(' |syntax match GIFDelimiter '''.s:delimiter.''' contained conceal', ' \') .
            \escape(' |highlight link GIFDescription Comment', ' ')

    let s:winid = win_getid()
    let s:bufnr = bufnr()
    wincmd p
endfunction "}}}

function! s:hide_listchars() abort "{{{
    execute 'autocmd GeneralIFilter BufLeave <buffer=' . s:bufnr .
                \ '> ++once set listchars=' . &listchars
    set listchars=
endfunction "}}}

function! s:hide_cursor() abort "{{{
    execute 'autocmd GeneralIFilter BufLeave <buffer=' . s:bufnr .
                \ '> ++once set t_ve=' . &t_ve
    set t_ve=
endfunction "}}}

function! s:interactive_filter() abort "{{{
    let s:inputstr = ''
    let s:inputstrlength = 0
    let s:cursorcol = 0
    " 1 <= s:cursorrow <= s:winheight
    let s:cursorrow = s:cands.count
    let s:result = ''
    let s:status = 0
    let s:finished = 0

    call s:hide_cursor()

    while !s:finished
        call s:render()

        let nr = getchar()
        let chr = !type(nr) ? nr2char(nr) : nr
        call s:key_filter(chr)

        call s:filter(s:inputstr)
        call Debug('s:cands.idxs() : ' . string(s:cands.idxs()))
    endwhile
    redraw!
    return #{result: s:result, status: s:status}
endfunction "}}}

function! s:update_cursorrow() abort "{{{
    if !s:nochoice_selected()
        let s:cursorrow = match(s:cands.idxs(), s:choices.selidx) + 1
    endif
    " Set the cursor to the bottom if the selected choice is not included
    " in the current candidates.
    if !s:cursorrow
        let s:cursorrow = s:cands.count
        let s:choices.selidx = get(s:cands.idxs(), -1, -1)
    endif
    if s:choices.selidx == -1
        let s:choices.selidx = s:cursorrow - 1
    endif
endfunction "}}}

function! s:move_cursor_bottom() abort "{{{
    let s:cursorrow = s:cands.count
    let s:choices.selidx = get(s:cands.idxs(), -1, -1)
endfunction "}}}

function! s:init_window() abort "{{{
    call win_execute(s:winid, '%delete')
    call win_execute(s:winid, 'resize ' . min([&lines / 4, s:cands.count]))
    call setbufline(s:bufnr, 1,
            \ mapnew(s:cands.idxs(), { _,idx -> s:choices.str(idx) }))
    call win_execute(s:winid, 'call cursor(s:cursorrow, 1)')
    redraw
endfunction "}}}

function! s:render() abort "{{{
    call s:update_cursorrow()
    call s:init_window()
    echohl Directory | echon s:prompt | echohl None
    "echohl Directory | echon '(selidx,cursorrow)=('.s:choices.selidx.','.s:cursorrow.')' | echohl None
    call s:mock_cursor()
endfunction "}}}

function! s:nochoice_selected() abort "{{{
    return s:choices.selidx == -1
endfunction "}}}

function! s:mock_cursor() abort "{{{
    echon s:cursorcol > 0 ? s:inputstr[:s:cursorcol-1] : ''
    if s:cursorcol == s:inputstrlength
        echohl Cursor | echon ' ' | echohl None
    else
        echohl Cursor | echon s:inputstr[s:cursorcol] | echohl None
        echon s:inputstr[s:cursorcol+1:]
    endif
endfunction "}}}

function! s:key_filter(chr) abort "{{{
    if a:chr == "\<Esc>"
        let s:status = 1
        let s:finished = 1
    elseif a:chr == "\<CR>"
        let s:result = s:choices.contents[s:choices.selidx]
        let s:finished = 1
    elseif a:chr == "\<C-a>"
        let s:cursorcol = 0
    elseif a:chr == "\<C-e>"
        let s:cursorcol = s:inputstrlength
    elseif a:chr == "\<C-b>" || a:chr == "\<Left>"
        let s:cursorcol = s:cursorcol > 0 ? s:cursorcol - 1 : 0
    elseif a:chr == "\<C-f>" || a:chr == "\<Right>"
        let s:cursorcol = s:cursorcol < s:inputstrlength ? s:cursorcol + 1 : s:inputstrlength
    elseif a:chr == "\<C-h>" || a:chr == "\<BS>"
        if s:cursorcol > 0
            let s:inputstr = (s:cursorcol == 1 ? '' : s:inputstr[:s:cursorcol-2]) . s:inputstr[s:cursorcol:]
            let s:inputstrlength -= 1
            let s:cursorcol -= 1
        endif
    elseif a:chr == "\<C-k>" || a:chr == "\<Up>"
        if s:cursorrow > 1
            let s:choices.selidx = s:cands.idxs()[s:cursorrow - 2]
        endif
    elseif a:chr == "\<C-j>" || a:chr == "\<Down>"
        if s:cursorrow < s:cands.count
            let s:choices.selidx = s:cands.idxs()[s:cursorrow]
        endif
    elseif a:chr >= ' ' && a:chr <= '~'
        let s:inputstr = (s:cursorcol > 0 ? s:inputstr[:s:cursorcol-1] : '') . a:chr . s:inputstr[s:cursorcol:]
        let s:inputstrlength += 1
        let s:cursorcol += 1
    endif
endfunction "}}}

function! s:filter(expr) abort "{{{
    if empty(a:expr)
        call s:cands.idxs(range(s:choices.count))
        return
    endif
    let [cands, poses, scores] = matchfuzzypos(s:choices.contents, a:expr)
    call s:cands.idxs(filter(range(s:choices.count), { _,idx -> index(cands, s:choices.contents[idx]) != -1 }))
endfunction "}}}


let &cpo = s:save_cpo
unlet s:save_cpo

" vim:tw=78:sw=0:ts=4:et:fdm=marker:
