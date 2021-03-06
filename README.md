# StaticArrays

*Statically sized arrays for Julia*

[![StaticArrays](http://pkg.julialang.org/badges/StaticArrays_0.5.svg)](http://pkg.julialang.org/?pkg=StaticArrays)
[![Build Status](https://travis-ci.org/JuliaArrays/StaticArrays.jl.svg?branch=master)](https://travis-ci.org/JuliaArrays/StaticArrays.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/xabgh1yhsjxlp30d?svg=true)](https://ci.appveyor.com/project/JuliaArrays/staticarrays-jl)
[![Coverage Status](https://coveralls.io/repos/github/JuliaArrays/StaticArrays.jl/badge.svg?branch=master)](https://coveralls.io/github/JuliaArrays/StaticArrays.jl?branch=master)

**StaticArrays** provides a framework for implementing statically sized arrays
in Julia (≥ 0.5), using the abstract type `StaticArray{T,N} <: AbstractArray{T,N}`.
Subtypes of `StaticArray` will provide fast implementations of common array and
linear algebra operations. Note that here "statically sized" means that the
size can be determined from the *type* (so concrete implementations of
`StaticArray` must define a method `size(::Type{T})`), and "static" does **not**
necessarily imply `immutable`.

The package also provides some concrete static array types: `SVector`, `SMatrix`
and `SArray`, which may be used as-is (or else embedded in your own type).
Mutable versions `MVector`, `MMatrix` and `MArray` are also exported, as well
as `SizedArray` for annotating standard `Array`s with static size information.
Further, the abstract `FieldVector` can be used to make fast `StaticVector`s
out of any uniform Julia "struct".

## Speed

The speed of *small* `SVector`s, `SMatrix`s and `SArray`s is often > 10 × faster
than `Base.Array`. See this simplified benchmark (or see the full results [here](https://github.com/andyferris/StaticArrays.jl/blob/master/perf/bench10.txt)):

```
============================================
    Benchmarks for 3×3 Float64 matrices
============================================

Matrix multiplication               -> 8.2x speedup
Matrix multiplication (mutating)    -> 3.1x speedup
Matrix addition                     -> 45x speedup
Matrix addition (mutating)          -> 5.1x speedup
Matrix determinant                  -> 170x speedup
Matrix inverse                      -> 125x speedup
Matrix symmetric eigendecomposition -> 82x speedup
Matrix Cholesky decomposition       -> 23.6x speedup
```

These results improve significantly when using `julia -O3` with immutable static
arrays, as the extra optimization results in surprisingly good SIMD code.

Note that in the current implementation, working with large `StaticArray`s puts a
lot of stress on the compiler, and becomes slower than `Base.Array` as the size
increases.  A very rough rule of thumb is that you should consider using a
normal `Array` for arrays larger than 100 elements. For example, the performance
crossover point for a matrix multiply microbenchmark seems to be about 11x11 in
julia 0.5 with default optimizations.


## Quick start

```julia
Pkg.add("StaticArrays")  # or Pkg.clone("https://github.com/andyferris/StaticArrays.jl")
using StaticArrays

# Create an SVector using various forms, using constructors, functions or macros
v1 = SVector(1, 2, 3)
v1.data === (1, 2, 3) # SVector uses a tuple for internal storage
v2 = SVector{3,Float64}(1, 2, 3) # length 3, eltype Float64
v3 = @SVector [1, 2, 3]
v4 = @SVector [i^2 for i = 1:10] # arbitrary comprehensions (range is evaluated at global scope)
v5 = zeros(SVector{3}) # defaults to Float64
v6 = @SVector zeros(3)
v7 = SVector{3}([1, 2, 3]) # Array conversions must specify size

# Can get size() from instance or type
size(v1) == (3,)
size(typeof(v1)) == (3,)

# Similar constructor syntax for matrices
m1 = SMatrix{2,2}(1, 2, 3, 4) # flat, column-major storage, equal to m2:
m2 = @SMatrix [ 1  3 ;
                2  4 ]
m3 = eye(SMatrix{3,3})
m4 = @SMatrix randn(4,4)
m5 = SMatrix{2,2}([1 3 ; 2 4]) # Array conversions must specify size

# Higher-dimensional support
a = @SArray randn(2, 2, 2, 2, 2, 2)

# Supports all the common operations of AbstractArray
v7 = v1 + v2
v8 = sin.(v3)
v3 == m3 * v3 # recall that m3 = eye(SMatrix{3,3})
# map, reduce, broadcast, map!, broadcast!, etc...

# Indexing also supports tuples
v1[1] === 1
v1[(3,2,1)] === @SVector [3, 2, 1]
v1[:] === v1
typeof(v1[[1,2,3]]) <: Vector # Can't determine size from the type of [1,2,3]

# Is (partially) hooked into BLAS, LAPACK, etc:
rand(MMatrix{20,20}) * rand(MMatrix{20,20}) # large matrices can use BLAS
eig(m3) # eig(), etc uses specialized algorithms up to 3×3, or else LAPACK

# Static arrays stay statically sized, even when used by Base functions, etc:
typeof(eig(m3)) == Tuple{MVector{3,Float64}, MMatrix{3,3,Float64,9}}

# similar() returns a mutable container, while similar_type() returns a constructor:
typeof(similar(m3)) == MMatrix{3,3,Float64,9} # (final parameter is length = 9)
similar_type(m3) == SMatrix{3,3,Float64,9}

# The Size trait is a compile-time constant representing the size
Size(m3) === Size(3,3)

# reshape() uses Size() or types to specify size:
reshape([1,2,3,4], Size(2,2)) === @SMatrix [ 1  3 ;
                                             2  4 ]
reshape([1,2,3,4], SMatrix{2,2}) === @SMatrix [ 1  3 ;
                                                2  4 ]

# A standard Array can be wrapped into a SizedArray
m4 = Size(3,3)(rand(3,3))
inv(m4) # Take advantage of specialized fast methods
```

## Approach

The package provides an range of different useful built-in `StaticArray` types,
which include mutable and immutable arrays based upon tuples, arrays based upon
structs, and wrappers of `Array`. There is a relatively simple interface for
creating your own, custom `StaticArray` types, too.

This package also provides methods for a wide range of `AbstractArray` functions,
specialized for (potentially immutable) `StaticArray`s. Many of Julia's
built-in method definitions inherently assume mutability, and further
performance optimizations may be made when the size of the array is know to the
compiler. One example of this is by loop unrolling, which has a substantial
effect on small arrays and tends to automatically triger LLVM's SIMD
optimizations. Another way performance is boosted is by providing specialized
methods for `det`, `inv`, `eig` and `chol` where the algorithm depends on the
precise dimensions of the input. In combination with intelligent fallbacks to
the methods in Base, we seek to provide a comprehensive support for statically
sized arrays, large or small, that hopefully "just works".

## API Details

### The `Size` trait

The size of a statically sized array is a static parameter associated with the
type of the array. The `Size` trait is provided as an abstract representation of
the dimensions of a static array. An array `sa::SA` of size `(dims...)` is
associated with `Size{(dims...)}()`. The following are equivalent (`@pure`)
constructors:
```julia
Size{(dims...)}()
Size(dims...)
Size(sa::StaticArray)
Size(SA) # SA <: StaticArray
```
This is extremely useful for (a) performing dispatch depending on the size of an
array, and (b) passing array dimensions that the compiler can reason about.

An example of size-based dispatch for the determinant of a matrix would be:
```julia
det(x::StaticMatrix) = _det(Size(x), x)
_det(::Size{(1,1)}, x::StaticMatrix) = x[1,1]
_det(::Size{(2,2)}, x::StaticMatrix) = x[1,1]*x[2,2] - x[1,2]*x[2,1]
# and other definitions as necessary
```

Examples of using `Size` as a compile-time constant include
```julia
reshape(svector, Size(2,2))  # Convert SVector{4} to SMatrix{2,2}
Size(3,3)(rand(3,3))         # Construct a random 3×3 SizedArray (see below)
```

Users that introduce a new subtype of `StaticArray` should define a (`@pure`)
method for `Size(::Type{NewArrayType})`.

### Indexing

Statically sized indexing can be realized by indexing each dimension by a
scalar, a `StaticVector` or `:`. Indexing in this way will result a statically
sized array (even if the input was dynamically sized, in the case of
`StaticVector` indices) of the closest type (as defined by `similar_type`).

Conversely, indexing a statically sized array with a dynamically sized index
(such as a `Vector{Integer}` or `UnitRange{Integer}`) will result in a standard
(dynamically sized) `Array`.

### `similar_type()`

Since immutable arrays need to be constructed "all-at-once", we need a way of
obtaining an appropriate constructor if the element type or dimensions of the
output array differs from the input. To this end, `similar_type` is introduced,
behaving just like `similar`, except that it returns a type. Relevant methods
are:

```julia
similar_type{A <: StaticArray}(::Type{A}) # defaults to A
similar_type{A <: StaticArray, ElType}(::Type{A}, ::Type{ElType}) # Change element type
similar_type{A <: AbstractArray}(::Type{A}, size::Size) # Change size
similar_type{A <: AbstractArray, ElType}(::Type{A}, ::Type{ElType}, size::Size) # Change both
```

These setting will affect everything, from indexing, to matrix multiplication
and `broadcast`. Users wanting introduce a new array type should *only* overload
the last method in the above.

Use of `similar` will fall back to a mutable container, such as a `MVector`
(see below), and it requires use of the `Size` trait if you wish to set a new
static size (or else a dynamically sized `Array` will be generated when
specifying the size as plain integers).

### `SVector`

The simplest static array is the `SVector`, defined as

```julia
immutable SVector{N,T} <: StaticVector{T}
    data::NTuple{N,T}
end
```

`SVector` defines a series of convenience constructors, so you can just type
e.g. `SVector(1,2,3)`. Alternatively there is an intelligent `@SVector` macro
where you can use native Julia array literals syntax, comprehensions, and the
`zeros()`, `ones()`, `fill()`, `rand()` and `randn()` functions, such as `@SVector [1,2,3]`,
`@SVector Float64[1,2,3]`, `@SVector [f(i) for i = 1:10]`, `@SVector zeros(3)`,
`@SVector randn(Float32, 4)`, etc (Note: the range of a comprehension is evaluated at global scope by the
macro, and must be made of combinations of literal values, functions, or global
variables, but is not limited to just simple ranges. Extending this to
(hopefully statically known by type-inference) local-scope variables is hoped
for the future. The `zeros()`, `ones()`, `fill()`, `rand()` and `randn()` functions do not have this
limitation.)

### `SMatrix`

Static matrices are also provided by `SMatrix`. It's definition is a little
more complicated:

```julia
immutable SMatrix{S1, S2, T, L} <: StaticMatrix{T}
    data::NTuple{L, T}
end
```

Here `L` is the `length` of the matrix, such that `S1 × S2 = L`. However,
convenience constructors are provided, so that `L`, `T` and even `S2` are
unnecessary. At minimum, you can type `SMatrix{2}(1,2,3,4)` to create a 2×2
matrix (the total number of elements must divide evenly into `S1`). A
convenience macro `@SMatrix [1 2; 3 4]` is provided (which also accepts
comprehensions and the `zeros()`, `ones()`, `fill()`, `rand()`, `randn()` and `eye()`
functions).

### `SArray`

A container with arbitrarily many dimensions is defined as
`immutable SArray{Size,T,N,L} <: StaticArray{T,N}`, where
`Size = (S1, S2, ...)` is a tuple of `Int`s. You can easily construct one with
the `@SArray` macro, supporting all the features of `@SVector` and `@SMatrix`
(but with arbitrary dimension).

Notably, the main reason `SVector` and `SMatrix` are defined is to make it
easier to define the types without the extra tuple characters (compare
`SVector{3}` to `SArray{(3,)}`). This extra convenience was made possible
because it is so easy to define new `StaticArray` subtypes, and they naturally
work together.

### `Scalar`

Sometimes you want to broadcast an operation, but not over one of your inputs.
A classic example is attempting to displace a collection of vectors by the
same vector. We can now do this with the `Scalar` type:

```julia
[[1,2,3], [4,5,6]] .+ Scalar([1,0,-1]) # [[2,2,2], [5,5,5]]
```

`Scalar` is simply an implementation of an immutable, 0-dimensional `StaticArray`.

### Mutable arrays: `MVector`, `MMatrix` and `MArray`

These statically sized arrays are identical to the above, but are defined as
mutable Julia `type`s, instead of `immutable`. Because they are mutable, they
allow `setindex!` to be defined (achieved through pointer manipulation, into a
tuple).

As a consequence of Julia's internal implementation, these mutable containers
live on the heap, not the stack. Their memory must be allocated and tracked by
the garbage collector. Nevertheless, there is opportunity for speed
improvements relative to `Base.Array` because (a) there may be one less
pointer indirection, (b) their (typically small) static size allows for
additional loop unrolling and inlining, and consequentially (c) their mutating
methods like `map!` are extremely fast. Benchmarking shows that operations such
as addition and matrix multiplication are faster for `MMatrix` than `Matrix`,
at least for sizes up to 14 × 14, though keep in mind that optimal speed will
be obtained by using mutating functions (like `map!` or `A_mul_B!`) where
possible, rather than reallocating new memory.

Mutable static arrays also happen to be very useful containers that can be
constructed on the heap (with the ability to use `setindex!`, etc), and later
copied as e.g. an immutable `SVector` to the stack for use, or into e.g. an
`Array{SVector}` for storage.

Convenience macros `@MVector`, `@MMatrix` and `@MArray` are provided.

### `SizedArray`: a decorate size wrapper for `Array`

Another convenient mutable type is the `SizedArray`, which is just a wrapper-type
about a standard Julia `Array` which declares its knwon size. For example, if
we knew that `a` was a 2×2 `Matrix`, then we can type `sa = SizedArray{(2,2)}(a)`
to construct a new object which knows the type (the size will be verified
automatically). A more convenient syntax for obtaining a `SizedArray` is by calling
a `Size` object, e.g. `sa = Size(2,2)(a)`.

Then, methods on `sa` will use the specialized code provided by the *StaticArrays*
pacakge, which in many cases will be much, much faster. For example, calling
`eig(sa)` will be signficantly faster than `eig(a)` since it will perform a
specialized 2×2 matrix diagonalization rather than a general algorithm provided
by Julia and *LAPACK*.

In some cases it will make more sense to use a `SizedArray`, and in other cases
an `MArray` might be preferable.

### `FieldVector`

Sometimes it might be useful to imbue your own types, having multiple fields,
with vector-like properties. *StaticArrays* can take care of this for you by
allowing you to inherit from `FieldVector{T}`. For example, consider:

```julia
immutable Point3D <: FieldVector{Float64}
    x::Float64
    y::Float64
    z::Float64
end
```

With this type, users can easily access fields to `p = Point3D(x,y,z)` using
`p.x`, `p.y` or `p.z`, or alternatively via `p[1]`, `p[2]`, or `p[3]`. You may
even permute the coordinates with `p[(3,2,1)]`). Furthermore, `Point3D` is a
complete `AbstractVector` implementation where you can add, subtract or scale
vectors, multiply them by matrices (and return the same type), etc.

It is also worth noting that `FieldVector`s may be mutable or immutable, and
that `setindex!` is defined for use on mutable types. For mutable containers,
you may want to define a default constructor (no inputs) that can be called by
`similar`.

### Implementing your own types

You can easily create your own `StaticArray` type, by defining both `Size` (on the 
*type*, e.g. `StaticArrays.Size(::Type{Point3D}) = Size(3)`), and linear 
`getindex` (and optionally `setindex!` for mutable types - see 
`setindex(::SVector, val, i)` in *MVector.jl* for an example of how to
achieve this through pointer manipulation). Your type should define a constructor
that takes a tuple of the data (and mutable containers may want to define a
default constructor).

Other useful functions to overload may be `similar_type` (and `similar` for
mutable containers).

### Conversions from `Array`

In order to convert from a dynamically sized `AbstractArray` to one of the
statically sized array types, you must specify the size explicitly.  For
example,

```julia
v = [1,2]

m = [1 2;
     3 4]

# ... a lot of intervening code

sv = SVector{2}(v)
sm = SMatrix{2,2}(m)
sa = SArray{(2,2)}(m)

sized_v = Size(2)(v)     # SizedArray{(2,)}(v)
sized_m = Size(2,2)(m)   # SizedArray{(2,2)}(m)
```

We have avoided adding `SVector(v::AbstractVector)` as a valid constructor to
help users avoid the type instability (and potential performance disaster, if
used without care) of this innocuous looking expression. However, the simplest
way to deal with an `Array` is to create a `SizedArray` by calling a `Size`
instance, e.g. `Size(2)(v)`.

### Arrays of static arrays

Storing a large number of static arrays is convenient as an array of static
arrays. For example, a collection of positions (3D coordinates - `SVector{3,Float64}`)
could be represented as a `Vector{SVector{3,Float64}}`.

Another common way of storing the same data is as a 3×`N` `Matrix{Float64}`.
Rather conveniently, such types have *exactly* the same binary layout in memory,
and therefore we can use `reinterpret` to convert between the two formats
```julia
function svectors(x::Matrix{Float64})
    @assert size(x,1) == 3
    reinterpret(SVector{3,Float64}, x, (size(x,2),))
end
```
Such a conversion does not copy the data, rather it refers to the *same* memory
referenced by two different Julia `Array`s. Arguably, a `Vector` of `SVector`s
is preferable to a `Matrix` because (a) it provides a better abstraction of the
objects contained in the array and (b) it allows the fast *StaticArrays* methods
to act on elements.

### Working with mutable and immutable arrays

Generally, it is performant to rebind an *immutable* array, such as
```julia
function average_position(positions::Vector{SVector{3,Float64}})
    x = zeros(SVector{3,Float64})
    for pos ∈ positions
        x = x + pos
    end
    return x / length(positions)
end
```
so long as the `Type` of the rebound variable (`x`, above) does not change.

On the other hand, the above code for mutable containers like `Array`, `MArray`
or `SizedArray` is *not* very efficient. Mutable containers in Julia 0.5 must
be *allocated* and later *garbage collected*, and for small, fixed-size arrays
this can be a leading contribution to the cost. In the above code, a new array
will be instantiated and allocated on each iteration of the loop. In order to
avoid unnecessary allocations, it is best to allocate an array only once and
apply mutating functions to it:
```julia
function average_position(positions::Vector{SVector{3,Float64}})
    x = zeros(MVector{3,Float64})
    for pos ∈ positions
        # Take advantage of Julia 0.5 broadcast fusion
        x .= (+).(x, pos) # same as broadcast!(+, x, x, positions[i])
    end
    x .= (/).(x, length(positions))
    return x
end
```
Keep in mind that Julia 0.5 does not fuse calls to `.+`, etc (or `.+=` etc),
however the `.=` and `(+).()` syntaxes are fused into a single, efficient call
to `broadcast!`. The simpler syntax `x .+= pos` is expected to be non-allocating
(and therefore faster) in Julia 0.6.

The functions `setindex`, `push`, `pop`, `shift`, `unshift`, `insert` and `deleteat`
are provided for performing certain specific operations on static arrays, in
analogy with the standard functions `setindex!`, `push!`, `pop!`, etc. (Note that
if the size of the static array changes, the type of the output will differ from
the input.)

### SIMD optimizations

It seems Julia and LLVM are smart enough to use processor vectorization
extensions like SSE and AVX - however they are currently partially disabled by
default. Run Julia with `julia -O` or `julia -O3` to enable these optimizations,
and many of your (immutable) `StaticArray` methods *should* become significantly
faster!

## Relationship to *FixedSizeArrays* and *ImmutableArrays*

Several existing packages for statically sized arrays have been developed for
Julia, noteably *FixedSizeArrays* and *ImmutableArrays* which provided signficant
inspiration for this package. Upon consultation, it has been decided to move
forward with *StaticArrays* which has found a new home in the *JuliaArrays*
github organization. It is recommended that new users use this package, and
that existing dependent packages consider switching to *StaticArrays* sometime
during the life-cycle of Julia v0.5.

You can try `using StaticArrays.FixedSizeArrays` to add some compatibility
wrappers for the most commonly used features of the *FixedSizeArrays* package,
such as `Vec`, `Mat`, `Point` and `@fsa`. These wrappers do not provide a
perfect interface, but may help in trying out *StaticArrays* with pre-existing
code.

Furthermore, `using StaticArrays.ImmutableArrays` will let you use the typenames
from the *ImmutableArrays* package, which does not include the array size as a
type parameter (e.g. `Vector3{T}` and `Matrix3x3{T}`).
