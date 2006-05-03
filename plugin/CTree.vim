" -------------------------------------------------------------------
"  CTree.vim -- Display Class/Interface Hierarchy "{{{
"
"  Author:   Yanbiao Zhao (yanbiao_zhao at yahoo.com)
"  Requires: Vim 7
"  Version:  1.1.1
"
"  Command:
"      CTree -- Display a tree of Class/Interface hierarchy
"      CTag  -- Jump to the class/interface definition of the tag
"  }}}

if v:version < 700
	echomsg "Vim 7 or higher is required for CTree.vim"
	finish
endif

command! -nargs=1 -complete=tag CTree      call s:CTree_GetTypeTree(<f-args>)
command! -nargs=1 -complete=tag CTag       call s:CT_Jump_To_ClassName(<f-args>)

"Short cut to use the commands
"nmap <silent> <M-F9>  :exec "CTree ".expand("<cword>")<CR>
"nmap <silent> <M-]>   :exec "CTag  ".expand("<cword>")<CR>

function! s:CT_Jump_To_ClassName(className)
    let tagEntry = {}
    let tagEntry["name"] = a:className 
    call s:CT_Jump_To_Class(tagEntry, "tselect")
endfunction

let s:CTree_AllTypeEntries = []
let s:CTree_TagEnvCache = ''
let s:CTree_tagFilesCache = {}

function! s:CTree_GetTypeTree(typeName)
    call s:CTree_LoadAllTypeEntries()

    let rootEntry = s:CTree_GetRootType(a:typeName, '')

    if empty(rootEntry)
        let rootEntry["name"] = a:typeName
        let rootEntry["namespace"] = ""
        let rootEntry["kind"] = 'c' 
        let rootEntry["inherits"] = ""
    endif

    echohl Title | echo '   #  tag' | echohl None

    let allEntries = []
    call s:CTree_GetChildren(allEntries, rootEntry, 0)

    let i = input('Choice number (<Enter> cancels):')
    let i = str2nr(i)
    if i > 0 && i <= len(allEntries)
        call s:CT_Jump_To_Class(allEntries[i-1], "tselect")
    endif
endfunction

function! s:CTree_GetChildren(allEntries, rootEntry, depth)
    call add(a:allEntries, a:rootEntry)
    call s:CTree_DisplayTagEntry(len(a:allEntries), a:rootEntry, a:depth)

    let children = []
    let rootTypeName = a:rootEntry["name"]
    for tagEntry in s:CTree_AllTypeEntries
        if index(split(tagEntry["inherits"], ","), rootTypeName) >= 0 
            call add(children, tagEntry)
        endif
    endfor

    let rootKind = a:rootEntry["kind"]
    for child in children
        "We only want to display class that implement an interface directly
        if child["kind"] == 'c' && rootKind == 'i'
            call add(a:allEntries, child) 
            call s:CTree_DisplayTagEntry(len(a:allEntries), child, a:depth+1)
        else
            call s:CTree_GetChildren(a:allEntries, child, a:depth+1)
        endif
    endfor
    
endfunction

" Return if the tag env has changed
function! s:HasTagEnvChanged()
    if s:CTree_TagEnvCache == &tags
        return 0
    else
        let s:CTree_TagEnvCache = &tags
        return 1
    endif
endfunc

" Return if a tag file has changed in tagfiles()
function! s:HasTagFileChanged()
    if s:HasTagEnvChanged()
        let s:CTree_tagFilesCache = {}
        return 1
    endif

    let tagFiles = map(tagfiles(), 'escape(v:val, " ")')
    let result = 0
    for tagFile in tagFiles
        if has_key(s:CTree_tagFilesCache, tagFile)
            let currentFiletime = getftime(tagFile)
            if currentFiletime > s:CTree_tagFilesCache[tagFile]
                " The file has changed, updating the cache
                let s:CTree_tagFilesCache[tagFile] = currentFiletime
                let result = 1
            endif
        else
            " We store the time of the file
            let s:CTree_tagFilesCache[tagFile] = getftime(tagFile)
            let result = 1
        endif
    endfor
    return result
endfunc

function! s:CTree_LoadAllTypeEntries()
    if !empty(s:CTree_AllTypeEntries) 
        if s:HasTagFileChanged()
            let s:CTree_AllTypeEntries = []
        else
            return
        endif
    endif

    echo 'Loading tag information. It may take a while...'
    let ch = 'A'
    while ch <= 'Z'
        call s:CTree_GetTypeEntryWithCh(ch)
        let ch = nr2char(char2nr(ch)+1)
    endwhile 

    call s:CTree_GetTypeEntryWithCh('_')

    let ch = 'a'
    while ch <= 'z'
        call s:CTree_GetTypeEntryWithCh(ch)
        let ch = nr2char(char2nr(ch)+1)
    endwhile 

     echo "Count of type tag entries loaded: ".len(s:CTree_AllTypeEntries)
endfunction

function! s:CTree_GetTypeEntryWithCh(ch)
    for tagEntry in taglist('^'.a:ch)
        let kind = tagEntry["kind"]
        if (kind == 'i' || kind == 'c') && has_key(tagEntry, "inherits")
            call add(s:CTree_AllTypeEntries, tagEntry)
        endif
    endfor
endfunction

function! s:CTree_GetRootType(typeName, originalKind)
    for tagEntry in taglist("^".a:typeName."$")  

        let kind = tagEntry["kind"] 
        if kind != 'c' && kind != 'i'
            continue
        endif

        let originalKind = a:originalKind
        if originalKind == '' 
            let originalKind = kind
        elseif originalKind != tagEntry["kind"]
            "We will not accept interface as a parent of class
            return {}
        endif

        if !has_key(tagEntry, "inherits")
            return tagEntry
        endif

        "interface support multiple inheritance, so we will not try to get its
        "parent if it has more than one parent 
        let parents = split(tagEntry["inherits"], ",")
        if originalKind == 'i' && len(parents) > 1
            return tagEntry
        endif

        for parent in parents 
            let rootEntry = s:CTree_GetRootType(parent, originalKind)

            if !empty(rootEntry)
                return rootEntry
            endif
        endfor

        return tagEntry
    endfor

    return {}
endfunction 

function! s:CTree_DisplayTagEntry(index, typeEntry, depth)
    let s = string(a:index)
    while strlen(s) < 4
        let s = ' '.s
    endwhile

    let s = s." "
    let i = 0
    while i < a:depth
        let s = s."    "
        let i = i + 1
    endwhile

    let s = s.a:typeEntry["name"]

    if has_key(a:typeEntry, "namespace")
        let s = s.' ['.a:typeEntry["namespace"].']'
    elseif has_key(a:typeEntry, "class")
        let s = s.' <'.a:typeEntry["class"].'>'
    endif

    echo s
endfunction

function! s:CT_Jump_To_Class(tagEntry, cmd)
    let className = a:tagEntry["name"]

    redir @z
    try
        exec "silent ".a:cmd." ".className
    catch
        echohl WarningMsg | echo "cannot find class ".className |echohl None
    endtry
    redir END

    if has_key(a:tagEntry, "namespace")
        let keyName = "namespace"
    elseif has_key(a:tagEntry, "class")
        let keyName = "class"
    else
        let keyName = ""
    endif

    if keyName == "" 
        let namespace = ""
    else
        let namespace = a:tagEntry[keyName] 
    endif

    let i = 1
    let idxstart = stridx( @z, s:GetIndexString(i) ) 
    while idxstart > 0 
        if @z[idxstart+9] =='c' || @z[idxstart+9] =='i'
            let idxns = s:GetKeyValue(idxstart, keyName)
            let idxnse = match( @z, " ", idxns)
            if idxnse > match( @z, "\n", idxns)
                let idxnse = match( @z, "\n", idxns)
            endif

            if namespace == "" || namespace == strpart( @z, idxns, idxnse - idxns)
                exec "silent ".i."tag ".className
                return
            endif
        endif
        let i = i + 1
        let idxstart = stridx( @z, s:GetIndexString(i) ) 
    endwhile
endfunction

function! s:GetKeyValue(idxstart, keyName)
    if a:keyName == ""
        let res = s:GetKeyValue(a:idxstart, "namespace:")
        if res == -1 
            res = s:GetKeyValue(a:idxstart, "calss:")
        endif
    else
        let res = match( @z, a:keyName.":", a:idxstart) + strlen(a:keyName) + 1
    endif
    return res
endfunction

function! s:GetIndexString(index)
    if a:index < 10
        return "\n  ".a:index." "
    elseif a:index < 100
        return "\n ".a:index." "
    else 
        return "\n".a:index." "
    endif
endfunction
