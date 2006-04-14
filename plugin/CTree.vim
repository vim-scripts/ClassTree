command! -nargs=1 -complete=tag CTree call s:CTree_GetTypeTree(<f-args>)
map <F9> <Esc>:exec "CTree ".expand("<cword>")<CR>

let s:CTree_AllTypeEntries = []

function! s:CTree_GetTypeTree(rootTypeName)
    if empty(s:CTree_AllTypeEntries)
        call s:CTree_LoadAllTypeEntries()
    endif

    let s:CTree_Depth = 0
    let rootEntry = s:CTree_GetRootType(a:rootTypeName)

    if empty(rootEntry)
        let rootEntry["name"] = a:rootTypeName
        let rootEntry["namespace"] = ""
        let rootEntry["kind"] = 'c' 
        let rootEntry["inherits"] = ""
    endif

    echohl Title | echo '  #  tag' | echohl None

    let allEntries = []
    call s:CTree_GetChildren(allEntries, rootEntry, 0)

    let i = input('Choice number (<Enter> cancels):')
    let i = str2nr(i)
    if i > 0 && i <= len(allEntries)
        call CT_Jump_To_Class(allEntries[i-1], "tselect")
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

function! s:CTree_LoadAllTypeEntries()
    let s:CTree_AllTypeEntries = []

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

    return s:CTree_AllTypeEntries
endfunction

function! s:CTree_GetTypeEntryWithCh(ch)
    for tagEntry in taglist('^'.a:ch)
        let kind = tagEntry["kind"]
        if (kind == 'i' || kind == 'c') && has_key(tagEntry, "inherits")
            call add(s:CTree_AllTypeEntries, tagEntry)
        endif
    endfor
endfunction

function! s:CTree_GetRootType(typeName)
    let s:CTree_Depth = s:CTree_Depth + 1
    for tagEntry in taglist("^".a:typeName."$")  

        let kind = tagEntry["kind"] 
        if (kind != 'c' && kind != 'i') || (kind == 'i' && s:CTree_Depth != 1)
            continue
        endif

        "interface support multiple inheritance, so we will not try to get its
        "parent 
        if kind == 'i' || !has_key(tagEntry, "inherits")
            return tagEntry
        endif

        for parent in split(tagEntry["inherits"], ",")
            let rootEntry = s:CTree_GetRootType(parent)
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

function! CT_Jump_To_Class(tagEntry, cmd)
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
    let idxstart = stridx( @z, GetIndexString(i) ) 
    while idxstart > 0 
        if @z[idxstart+9] =='c' || @z[idxstart+9] =='i'
            let idxns = GetKeyValue(idxstart, keyName)
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
        let idxstart = stridx( @z, GetIndexString(i) ) 
    endwhile
endfunction

function! GetKeyValue(idxstart, keyName)
    if a:keyName == ""
        let res = GetKeyValue(a:idxstart, "namespace:")
        if res == -1 
            res = GetKeyValue(a:idxstart, "calss:")
        endif
    else
        let res = match( @z, a:keyName.":", a:idxstart) + strlen(a:keyName) + 1
    endif
    return res
endfunction

function! GetIndexString(index)
    if a:index < 10
        return "\n  ".a:index." "
    elseif a:index < 100
        return "\n ".a:index." "
    else 
        return "\n".a:index." "
    endif
endfunction
