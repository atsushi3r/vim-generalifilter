if exists("g:loaded_generalifilter")
    finish
endif
let g:loaded_generalifilter = 1

let s:save_cpo = &cpo
set cpo&vim


let &cpo = s:save_cpo
unlet s:save_cpo

" vim:tw=78:sw=0:ts=4:et:fdm=marker:
