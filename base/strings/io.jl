# This file is a part of Julia. License is MIT: https://julialang.org/license

## core text I/O ##

"""
    print([io::IO], xs...)

Write to `io` (or to the default output stream [`STDOUT`](@ref)
if `io` is not given) a canonical (un-decorated) text representation
of values `xs` if there is one, otherwise call [`show`](@ref).
The representation used by `print` includes minimal formatting and tries to
avoid Julia-specific details.

# Examples
```jldoctest
julia> print("Hello World!")
Hello World!
julia> io = IOBuffer();

julia> print(io, "Hello", ' ', :World!)

julia> String(take!(io))
"Hello World!"
```
"""
function print(io::IO, x)
    lock(io)
    try
        show(io, x)
    finally
        unlock(io)
    end
    return nothing
end

function print(io::IO, xs...)
    lock(io)
    try
        for x in xs
            print(io, x)
        end
    finally
        unlock(io)
    end
    return nothing
end

"""
    println([io::IO], xs...)

Print (using [`print`](@ref)) `xs` followed by a newline.
If `io` is not supplied, prints to [`STDOUT`](@ref).

# Examples
```jldoctest
julia> println("Hello, world")
Hello, world

julia> io = IOBuffer();

julia> println(io, "Hello, world")

julia> String(take!(io))
"Hello, world\\n"
```
"""
println(io::IO, xs...) = print(io, xs..., '\n')

## conversion of general objects to strings ##

"""
    sprint(f::Function, args...)

Call the given function with an I/O stream and the supplied extra arguments.
Everything written to this I/O stream is returned as a string.

# Examples
```jldoctest
julia> sprint(showcompact, 66.66666)
"66.6667"
```
"""
function sprint(f::Function, args...; context=nothing, sizehint::Integer=0)
    s = IOBuffer(StringVector(sizehint), true, true)
    # specialized version of truncate(s,0)
    s.size = 0
    s.ptr = 1
    if context !== nothing
        f(IOContext(s, context), args...)
    else
        f(s, args...)
    end
    String(resize!(s.data, s.size))
end

tostr_sizehint(x) = 0
tostr_sizehint(x::AbstractString) = endof(x)
tostr_sizehint(x::Float64) = 20
tostr_sizehint(x::Float32) = 12

function print_to_string(xs...; env=nothing)
    # specialized for performance reasons
    s = IOBuffer(StringVector(tostr_sizehint(xs[1])), true, true)
    # specialized version of truncate(s,0)
    s.size = 0
    s.ptr = 1
    if env !== nothing
        env_io = IOContext(s, env)
        for x in xs
            print(env_io, x)
        end
    else
        for x in xs
            print(s, x)
        end
    end
    String(resize!(s.data, s.size))
end

string_with_env(env, xs...) = print_to_string(xs...; env=env)

"""
    string(xs...)

Create a string from any values using the [`print`](@ref) function.

# Examples
```jldoctest
julia> string("a", 1, true)
"a1true"
```
"""
string(xs...) = print_to_string(xs...)

print(io::IO, s::AbstractString) = (write(io, s); nothing)
write(io::IO, s::AbstractString) = (len = 0; for c in s; len += write(io, c); end; len)
show(io::IO, s::AbstractString) = print_quoted(io, s)

write(to::GenericIOBuffer, s::SubString{String}) =
    s.ncodeunits ≤ 0 ? 0 : unsafe_write(to, pointer(s.string, s.offset+1), UInt(s.ncodeunits))

## printing literal quoted string data ##

# this is the inverse of print_unescaped_chars(io, s, "\\\")

function print_quoted_literal(io, s::AbstractString)
    print(io, '"')
    for c = s; c == '"' ? print(io, "\\\"") : print(io, c); end
    print(io, '"')
end

"""
    repr(x)

Create a string from any value using the [`show`](@ref) function.

# Examples
```jldoctest
julia> repr(1)
"1"

julia> repr(zeros(3))
"[0.0, 0.0, 0.0]"

```
"""
function repr(x)
    s = IOBuffer()
    show(s, x)
    String(take!(s))
end

# IOBuffer views of a (byte)string:

"""
    IOBuffer(string::String)

Create a read-only `IOBuffer` on the data underlying the given string.

# Examples
```jldoctest
julia> io = IOBuffer("Haho");

julia> String(take!(io))
"Haho"

julia> String(take!(io))
"Haho"
```
"""
IOBuffer(str::String) = IOBuffer(unsafe_wrap(Vector{UInt8}, str))
IOBuffer(s::SubString{String}) = IOBuffer(view(unsafe_wrap(Vector{UInt8}, s.string), s.offset + 1 : s.offset + sizeof(s)))

# join is implemented using IO

"""
    join(io::IO, strings, delim, [last])

Join an array of `strings` into a single string, inserting the given delimiter between
adjacent strings. If `last` is given, it will be used instead of `delim` between the last
two strings. For example,

# Examples
```jldoctest
julia> join(["apples", "bananas", "pineapples"], ", ", " and ")
"apples, bananas and pineapples"
```

`strings` can be any iterable over elements `x` which are convertible to strings
via `print(io::IOBuffer, x)`. `strings` will be printed to `io`.
"""
function join(io::IO, strings, delim, last)
    i = start(strings)
    if done(strings,i)
        return
    end
    str, i = next(strings,i)
    print(io, str)
    is_done = done(strings,i)
    while !is_done
        str, i = next(strings,i)
        is_done = done(strings,i)
        print(io, is_done ? last : delim)
        print(io, str)
    end
end

function join(io::IO, strings, delim)
    i = start(strings)
    is_done = done(strings,i)
    while !is_done
        str, i = next(strings,i)
        is_done = done(strings,i)
        print(io, str)
        if !is_done
            print(io, delim)
        end
    end
end
join(io::IO, strings) = join(io, strings, "")

join(strings) = sprint(join, strings)
join(strings, delim) = sprint(join, strings, delim)
join(strings, delim, last) = sprint(join, strings, delim, last)

function print_quoted(io, s::AbstractString)
    print(io, '"')
    print(io, Unicode.escape(s, "\"\$")) #"# work around syntax highlighting problem
    print(io, '"')
end

macro b_str(s)
    v = codeunits(Unicode.unescape(s))
    QuoteNode(v)
end

"""
    @raw_str -> String

Create a raw string without interpolation and unescaping.
The exception is that quotation marks still must be escaped. Backslashes
escape both quotation marks and other backslashes, but only when a sequence
of backslashes precedes a quote character. Thus, 2n backslashes followed by
a quote encodes n backslashes and the end of the literal while 2n+1 backslashes
followed by a quote encodes n backslashes followed by a quote character.

# Examples
```jldoctest
julia> println(raw"\\ \$x")
\\ \$x

julia> println(raw"\\"")
"

julia> println(raw"\\\\\\"")
\\"

julia> println(raw"\\\\x \\\\\\"")
\\\\x \\"
```
"""
macro raw_str(s); s; end

## multiline strings ##

"""
    indentation(str::AbstractString; tabwidth=8)

Calculate the width of leading blank space, and also return if string is blank

Returns:

* width of leading whitespace, flag if string is totally blank
"""
function indentation(str::AbstractString; tabwidth=8)
    count = 0
    for ch in str
        if ch == ' '
            count += 1
        elseif ch == '\t'
            count = div(count + tabwidth, tabwidth) * tabwidth
        else
            return count, false
        end
    end
    count, true
end

"""
    unindent(str::AbstractString, indent::Int; tabwidth=8)

Remove leading indentation from string

Returns:

* `String` of multiline string, with leading indentation of `indent` removed
"""
function unindent(str::AbstractString, indent::Int; tabwidth=8)
    indent == 0 && return str
    pos = start(str)
    endpos = endof(str)
    # Note: this loses the type of the original string
    buf = IOBuffer(StringVector(endpos), true, true)
    truncate(buf,0)
    cutting = true
    col = 0     # current column (0 based)
    while pos <= endpos
        ch, pos = next(str,pos)
        if cutting
            if ch == ' '
                col += 1
            elseif ch == '\t'
                col = div(col + tabwidth, tabwidth) * tabwidth
            elseif ch == '\n'
                # Now we need to output enough indentation
                for i = 1:col-indent
                    write(buf, ' ')
                end
                col = 0
                write(buf, '\n')
            else
                cutting = false
                # Now we need to output enough indentation to get to
                # correct place
                for i = 1:col-indent
                    write(buf, ' ')
                end
                col += 1
                write(buf, ch)
            end
        elseif ch == '\t'       # Handle internal tabs
            upd = div(col + tabwidth, tabwidth) * tabwidth
            # output the number of spaces that would have been seen
            # with original indentation
            for i = 1:(upd-col)
                write(buf, ' ')
            end
            col = upd
        elseif ch == '\n'
            cutting = true
            col = 0
            write(buf, '\n')
        else
            col += 1
            write(buf, ch)
        end
    end
    # If we were still "cutting" when we hit the end of the string,
    # we need to output the right number of spaces for the indentation
    if cutting
        for i = 1:col-indent
            write(buf, ' ')
        end
    end
    String(take!(buf))
end

function String(chars::AbstractVector{Char})
    sprint(sizehint=length(chars)) do io
        for c in chars
            write(io, c)
        end
    end
end
