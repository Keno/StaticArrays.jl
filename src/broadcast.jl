################
## broadcast! ##
################

@static if VERSION < v"0.7.0-DEV.2638"
    ## Old Broadcast API ##
    import Base.Broadcast:
    _containertype, promote_containertype, broadcast_indices,
    broadcast_c, broadcast_c!

    # Add StaticArray as a new output type in Base.Broadcast promotion machinery.
    # This isn't the precise output type, just a placeholder to return from
    # promote_containertype, which will control dispatch to our broadcast_c.
    _containertype(::Type{<:StaticArray}) = StaticArray
    _containertype(::Type{<:Adjoint{<:Any,<:StaticVector}}) = StaticArray

    # issue #382; prevent infinite recursion in generic broadcast code:
    Base.Broadcast.broadcast_indices(::Type{StaticArray}, A) = indices(A)

    # With the above, the default promote_containertype gives reasonable defaults:
    #   StaticArray, StaticArray -> StaticArray
    #   Array, StaticArray       -> Array
    #
    # We could be more precise about the latter, but this isn't really possible
    # without using Array{N} rather than Array in Base's promote_containertype.
    #
    # Base also has broadcast with tuple + Array, but while implementing this would
    # be consistent with Base, it's not exactly clear it's a good idea when you can
    # just use an SVector instead?
    promote_containertype(::Type{StaticArray}, ::Type{Any}) = StaticArray
    promote_containertype(::Type{Any}, ::Type{StaticArray}) = StaticArray

    # Override for when output type is deduced to be a StaticArray.
    @inline function broadcast_c(f, ::Type{StaticArray}, as...)
        argsizes = broadcast_sizes(as...)
        _broadcast(f, combine_sizes(argsizes), argsizes, as...)
    end

    # TODO: This signature could be relaxed to (::Any, ::Type{StaticArray}, ::Type, ...), though
    # we'd need to rework how _broadcast!() and broadcast_sizes() interact with normal AbstractArray.
    @inline function broadcast_c!(f, ::Type{StaticArray}, ::Type{StaticArray}, dest, as...)
        argsizes = broadcast_sizes(as...)
        _broadcast!(f, broadcast_dest_size(broadcast_size(dest), combine_sizes(argsizes)), dest, argsizes, as...)
    end
else
    ## New Broadcast API ##
    import Base.Broadcast:
    BroadcastStyle, AbstractArrayStyle, broadcast

    # Add a new BroadcastStyle for StaticArrays, derived from AbstractArrayStyle
    # A constructor that changes the style parameter N (array dimension) is also required
    struct StaticArrayStyle{N} <: AbstractArrayStyle{N} end
    StaticArrayStyle{M}(::Val{N}) where {M,N} = StaticArrayStyle{N}()

    BroadcastStyle(::Type{<:StaticArray{<:Any, <:Any, N}}) where {N} = StaticArrayStyle{N}()
    BroadcastStyle(::Type{<:Adjoint{<:Any, <:StaticVector}}) = StaticArrayStyle{2}()
    BroadcastStyle(::Type{<:Adjoint{<:Any, <:StaticMatrix}}) = StaticArrayStyle{2}()

    # Precedence rules
    BroadcastStyle(::StaticArrayStyle{M}, ::Broadcast.DefaultArrayStyle{N}) where {M,N} =
        Broadcast.DefaultArrayStyle(Broadcast._max(Val(M), Val(N)))
    BroadcastStyle(::StaticArrayStyle{M}, ::Broadcast.DefaultArrayStyle{0}) where {M} =
        StaticArrayStyle{M}()

    # Add a broadcast method that calls the @generated routine
    @inline function broadcast(f::Tf, ::StaticArrayStyle, ::Nothing, ::Nothing, as::Vararg{Any, N}...) where {Tf, N}
        argsizes = broadcast_sizes(as...)
        _broadcast(f, combine_sizes(argsizes), argsizes, as...)
    end

    # Add a specialized broadcast! method that overrides the Base fallback and calls the old routine
    @inline function broadcast!(f::Tf, dest, ::StaticArrayStyle, as::Vararg{Any,N}...) where {Tf, N}
        argsizes = broadcast_sizes(as...)
        _broadcast!(f, broadcast_dest_size(broadcast_size(dest), combine_sizes(argsizes)), dest, argsizes, as...)
    end
end


###################################################
## Internal broadcast machinery for StaticArrays ##
###################################################

broadcast_indices(A::StaticArray) = indices(A)
@inline broadcast_size(a::Adjoint{<:Any,<:StaticArray}) = Size(a)
@inline broadcast_size(a::StaticArray) = Size(a)
@inline broadcast_size(a) = Size()

@inline broadcast_sizes(a, as...) = (broadcast_size(a), broadcast_sizes(as...)...)
@inline broadcast_sizes() = ()

function broadcasted_index(oldsize, newindex)
    index = ones(Int, length(oldsize))
    for i = 1:length(oldsize)
        if oldsize[i] != 1
            index[i] = newindex[i]
        end
    end
    return LinearIndices(oldsize)[index...]
end

# similar to Base.Broadcast.combine_indices:
@generated function combine_sizes(s::Tuple{Vararg{Size}})
    sizes = [sz.parameters[1] for sz ∈ s.parameters]
    ndims = 0
    for i = 1:length(sizes)
        ndims = max(ndims, length(sizes[i]))
    end
    newsize = ones(Int, ndims)
    for i = 1:length(sizes)
        s = sizes[i]
        for j = 1:length(s)
            if newsize[j] == 1
                newsize[j] = s[j]
            elseif newsize[j] ≠ s[j] && s[j] ≠ 1
                throw(DimensionMismatch("Tried to broadcast on inputs sized $sizes"))
            end
        end
    end
    quote
        @_inline_meta
        Size($(tuple(newsize...)))
    end
end

@generated function _broadcast(f, ::Size{newsize}, s::Tuple{Vararg{Size}}, a...) where newsize
    first_staticarray = 0
    for i = 1:length(a)
        if a[i] <: StaticArray
            first_staticarray = a[i]
            break
        end
    end

    exprs = Array{Expr}(undef, newsize)
    more = prod(newsize) > 0
    current_ind = ones(Int, length(newsize))
    sizes = [sz.parameters[1] for sz ∈ s.parameters]

    while more
        exprs_vals = [(!(a[i] <: AbstractArray) ? :(a[$i][]) : :(a[$i][$(broadcasted_index(sizes[i], current_ind))])) for i = 1:length(sizes)]
        exprs[current_ind...] = :(f($(exprs_vals...)))

        # increment current_ind (maybe use CartesianIndices?)
        current_ind[1] += 1
        for i ∈ 1:length(newsize)
            if current_ind[i] > newsize[i]
                if i == length(newsize)
                    more = false
                    break
                else
                    current_ind[i] = 1
                    current_ind[i+1] += 1
                end
            else
                break
            end
        end
    end

    eltype_exprs = [t <: Union{AbstractArray, Ref} ? :(eltype($t)) : :($t) for t ∈ a]
    newtype_expr = :(return_type(f, Tuple{$(eltype_exprs...)}))

    return quote
        @_inline_meta
        @inbounds return similar_type($first_staticarray, $newtype_expr, Size(newsize))(tuple($(exprs...)))
    end
end

if VERSION < v"0.7.0-DEV"
# Workaround for #329
    @inline function Base.broadcast(f, ::Type{T}, a::StaticArray) where {T}
        map(x->f(T,x), a)
    end
end

####################################################
## Internal broadcast! machinery for StaticArrays ##
####################################################

@inline broadcast_dest_size(destsize::Size{()}, size_from_args::Size) = size_from_args
@inline broadcast_dest_size(destsize::Size, size_from_args::Size{()}) = destsize
@inline broadcast_dest_size(destsize::Size{S}, size_from_args::Size{S}) where S = size_from_args
function broadcast_dest_size(destsize::Size, size_from_args::Size)
    throw(DimensionMismatch("Tried to broadcast to destination sized $destsize, while $size_from_args was expected."))
end

@generated function _broadcast!(f, ::Size{newsize}, dest::AbstractArray, s::Tuple{Vararg{Size}}, as...) where {newsize}
    sizes = [sz.parameters[1] for sz ∈ s.parameters]
    sizes = tuple(sizes...)

    ndims = 0
    for i = 1:length(sizes)
        ndims = max(ndims, length(sizes[i]))
    end

    exprs = Array{Expr}(undef, newsize)
    j = 1
    more = prod(newsize) > 0
    current_ind = ones(Int, max(length(newsize), length.(sizes)...))
    while more
        exprs_vals = [(!(as[i] <: AbstractArray) ? :(as[$i][]) : :(as[$i][$(broadcasted_index(sizes[i], current_ind))])) for i = 1:length(sizes)]
        exprs[current_ind...] = :(dest[$j] = f($(exprs_vals...)))

        # increment current_ind (maybe use CartesianIndices?)
        current_ind[1] += 1
        for i ∈ 1:length(newsize)
            if current_ind[i] > newsize[i]
                if i == length(newsize)
                    more = false
                    break
                else
                    current_ind[i] = 1
                    current_ind[i+1] += 1
                end
            else
                break
            end
        end
        j += 1
    end

    return quote
        @_inline_meta
        @inbounds $(Expr(:block, exprs...))
        return dest
    end
end
