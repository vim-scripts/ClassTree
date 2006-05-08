" -------------------------------------------------------------------
"  CTree.vim -- Display Class/Interface Hierarchy "{{{
"
"  Author:   Yanbiao Zhao (yanbiao_zhao at yahoo.com)
"  Requires: Vim 7
"  Version:  1.1.2
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
    if s:CT_Jump_To_Class(tagEntry)== 0
        echohl WarningMsg | echo 'tag not found: '.a:className | echohl None
    endif
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
        call s:CT_Jump_To_Class(allEntries[i-1])
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

" Return if a tag file has changed in tagfiles()
function! s:HasTagFileChanged()
    let result = 0
    let tagFiles = map(tagfiles(), 'escape(v:val, " ")')
    let newTagFilesCache = {}

    if len(tagFiles) != len(s:CTree_tagFilesCache)
        let result = 1
    endif

    for tagFile in tagFiles
        let currentFiletime = getftime(tagFile)
        let newTagFilesCache[tagFile] = currentFiletime

        if !has_key(s:CTree_tagFilesCache, tagFile)
            let result = 1
        elseif currentFiletime != s:CTree_tagFilesCache[tagFile]
            let result = 1
        endif
    endfor

    let s:CTree_tagFilesCache = newTagFilesCache
    return result
endfunc

function! s:CTree_LoadAllTypeEntries()
    if s:HasTagFileChanged()
        let s:CTree_AllTypeEntries = []
    else
        return
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

function! s:CT_Jump_To_Class(tagEntry)
    let className = a:tagEntry["name"]

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
    let entries = taglist('^'.className.'$')
    for entry in entries 
        let kind = entry["kind"]
        if kind == 'c' || kind == 'i' || kind == 'g'
            if namespace == "" || namespace == entry[keyName]
                exec "silent ".i."tag ".className
                return 1
            endif
        endif
        let i += 1
    endfor
    return 0
endfunction
