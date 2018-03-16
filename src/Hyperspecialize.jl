module Hyperspecialize

import Compat
using MacroTools
using Compat.InteractiveUtils

macro isdefined(var)
 quote
   try
     local _ = $(esc(var))
     true
   catch err
     isa(err, UndefVarError) ? false : rethrow(err)
   end
 end
end

"""
    concretesubtypes(t)

Return an `Array` containing all concrete subtypes of `t` at load time.

# Examples
```julia-repl
julia> Hyperspecialize.concretesubtypes(Real)
16-element Array{Any,1}:
 BigFloat
 Float16
 Float32
 Float64
 Bool
 BigInt
 Int128
 Int16
 Int32
 Int64
 Int8
 UInt128
 UInt16
 UInt32
 UInt64
 UInt8
```
"""
function concretesubtypes(t)
  if Compat.isconcretetype(t)
    return [t]
  else
    return vcat([concretesubtypes(s) for s in subtypes(t)]...)
  end
end

"""
    allsubtypes(t)

Return an `Array` containing all subtypes of `t` at load time.

# Examples
```julia-repl
julia> Hyperspecialize.allsubtypes(Real)
24-element Array{Type,1}:
 Real
 AbstractFloat
 BigFloat
 Float16
 Float32
 Float64
 AbstractIrrational
 Irrational
 Integer
 Bool
 Signed
 BigInt
 Int128
 Int16
 Int32
 Int64
 Int8
 Unsigned
 UInt128
 UInt16
 UInt32
 UInt64
 UInt8
 Rational
```
"""
function allsubtypes(t)
  return vcat([t], [allsubtypes(s) for s in subtypes(t)]...)
end

function parse_element(base_mod, K)
  if @capture(K, (L_, R_))
    M = esc(L)
    K = R
  else
    M = base_mod
  end
  return (M, K)
end

struct Replicable
  def_mod::Module
  E::Any
  defined::Set{Any}
  elements::Vector{Tuple{Module, Symbol}}
end

struct Tag
  concretization::Set{Type}
  replicables::Vector{Replicable}
end

function _concretize(base_mod::Module, target_mod::Module, key::Symbol, types::Type)
  return _concretize(base_mod, target_mod, key, [types])
end

function _concretize(base_mod::Module, target_mod::Module, key::Symbol, types)
  return _concretize(base_mod, target_mod, key, Set{Type}(types))
end

function _concretize(base_mod::Module, target_mod::Module, key::Symbol, types::Set{Type})
  if base_mod == target_mod
    if !isdefined(base_mod, :__hyperspecialize__)
      eval(base_mod, quote
        const global __hyperspecialize__ = Dict{Symbol, Any}()
      end)
    end
    if haskey(target_mod.__hyperspecialize__, key)
      error("cannot reconcretize \"$key\" in module \"$target_mod\"")
    else
      target_mod.__hyperspecialize__[key] = Tag(types, [])
    end
  else
    error("cannot concretize \"$key\" in module \"$target_mod\" from module \"$base_mod\"")
  end
  return Set{Type}(target_mod.__hyperspecialize__[key].concretization)
end

"""
    @concretize(tag, ts)

Define the set of types corresponding to a type tag as `ts`, where `ts`
is either a single type or any collection that may be passed to a set
constructor. A type tag is a pair `(mod, Tag)` where the mod specifies a module
and the `Tag` is interpreted literally as a symbol. If just the `Tag` is given,
then the module is assumed to be the module in which the macro was expanded.

Note that you may not concretize a type in another module.

# Examples
```julia-repl
julia> @concretize (Main, BestInts) [Int32, Int64]
Set(Type[Int32, Int64])

julia> @concretize BestFloats Float64
Set(Type[Float64])

julia> @concretize BestStrings (String,)
Set(Type[String])

julia> @concretization BestInts
Set(Type[Int32, Int64])
```
"""
macro concretize(K, T)
  (M, K) = parse_element(:(Compat.@__MODULE__), K)
  return :(_concretize(Compat.@__MODULE__, $(M), $(QuoteNode(K)), $(esc(T))))
end

function _widen(base_mod::Module, target_mod::Module, key::Symbol, types::Type)
  return _widen(base_mod, target_mod, key, [types])
end

function _widen(base_mod::Module, target_mod::Module, key::Symbol, types)
  return _widen(base_mod, target_mod, key, Set{Type}(types))
end

function _widen(base_mod::Module, target_mod::Module, key::Symbol, types::Set{Type})
  _concretization(base_mod, target_mod, key)
  union!(target_mod.__hyperspecialize__[key].concretization, types)
  map(_define, target_mod.__hyperspecialize__[key].replicables)
  return Set{Type}(target_mod.__hyperspecialize__[key].concretization)
end

"""
    @widen(tag, ts)

Expand the set of types corresponding to a type tag to include `ts`, where `ts`
is either a single type or any collection that may be passed to a set
constructor. A type tag is a pair `(mod, Tag)` where the mod specifies a module
and the `Tag` is interpreted literally as a symbol. If just the `Tag` is given,
then the module is assumed to be the module in which the macro was expanded.
If no concretization exists, create a default concretization consisting of the
conrete subtypes of whatever type shares the name of `Tag` at load time.

If `@widen` is called for a type tag which has been referenced by a
`@replicable` code block, then that code block will be replicated even more to
reflect the new concretization.

# Examples
```julia-repl
julia> @concretize BestInts [Int32, Int64]
Set(Type[Int32, Int64])

julia> @replicable println(@hyperspecialize(BestInts))
Int32
Int64

julia> @widen BestInts (Bool, Int32, UInt128)
Bool
UInt128
Set(Type[Bool, UInt128, Int32, Int64])

julia> @concretization BestInts
Set(Type[Bool, Int8, Int32, Int64, UInt128])
```
"""
macro widen(K, T)
  (M, K) = parse_element(:(Compat.@__MODULE__), K)
  return :(_widen(Compat.@__MODULE__, $(M), $(QuoteNode(K)), $(esc(T))))
end

function _concretization(base_mod::Module, target_mod::Module, key::Symbol)
  if !isdefined(target_mod, :__hyperspecialize__) || !haskey(target_mod.__hyperspecialize__, key)
    if isdefined(target_mod, key)
      if eval(target_mod, key) isa Type
        types = concretesubtypes(eval(target_mod, key))
      else
        error("Cannot create default concretization from type tag ($target_mod, $key): Not a type.")
      end
    else
      error("Cannot create default concretization from type tag ($target_mod, $key): Not defined.")
    end
    _concretize(base_mod, target_mod, key, types)
  end
  return Set{Type}(target_mod.__hyperspecialize__[key].concretization)
end

"""
    @concretization(tag)

Return the set of types corresponding to a type tag. A type tag is a
pair `(mod, Tag)` where the mod specifies a module and the `Tag` is interpreted
literally as a symbol. If just the `Tag` is given, then the module is assumed to
be the module in which the macro was expanded. If no concretization
exists, create a default concretization consisting of the conrete subtypes of
whatever type shares the name of `Tag` at load time.

A concretization can be set and modified with `@concretize` and `@widen`

# Examples
```julia-repl
julia> @concretization((Main, Real))
Set(Type[BigInt, Bool, UInt32, Float64, Float32, Int64, Int128, Float16, UInt128, UInt8, UInt16, BigFloat, Int8, UInt64, Int16, Int32])

julia> @concretize BestInts [Int32, Int64]
Set(Type[Int32, Int64])

julia> @concretization BestInts
Set(Type[Int32, Int64])

julia> @concretization NotDefinedHere
ERROR: Cannot create default concretization from type tag (Main, NotDefinedHere): Not defined.
```
"""
macro concretization(K)
  (M, K) = parse_element(:(Compat.@__MODULE__), K)
  return :(_concretization(Compat.@__MODULE__, $(M), $(QuoteNode(K))))
end

_define(r::Replicable) = _define(r.E, r)

function _define(E, r::Replicable)
  found = false
  target_mod = nothing
  key = nothing
  MacroTools.postwalk(X -> begin
    if @capture(X, @hyperspecialize(I_)) && !found
      (target_mod, key) = r.elements[I]
      found = true
    end
    X
  end, E)
  if found
    for typ in _concretization(r.def_mod, target_mod, key)
      found = false
      _define(MacroTools.postwalk(X -> begin
        if @capture(X, @hyperspecialize(_)) && !found
          found = true
          typ
        else
          X
        end
      end, E), r)
    end
  else
    if !(E in r.defined)
      eval(r.def_mod, E)
      push!(r.defined, E)
    end
  end
end

function _replicable(base_mod::Module, E, elements::Vararg{Tuple{Module, Symbol}})
  r = Replicable(base_mod, E, Set{Any}(), [elements...])
  for (target_mod, key) in Set{Tuple{Module, Symbol}}([elements...])
    _concretization(base_mod, target_mod, key)
    push!(target_mod.__hyperspecialize__[key].replicables, r)
  end
  _define(r)
end

"""
    @replicable block

Replicate the code in `block` where each tag referred to by
`@hyperspecialize(tag)` is replaced by an element in the concretization of
`tag`. `block` is replicated at global scope in the module where `@replicable`
was expanded once for each combination of types in the concretization of each
`tag`.  A type tag is a pair `(mod, Tag)` where the mod specifies a module and
the `Tag` is interpreted literally as a symbol.  If just the `Tag` is given,
then the module is assumed to be the module in which the macro was expanded.
If no concretization exists for a tag, create a default concretization
consisting of the conrete subtypes of whatever type shares the name of `Tag` at
load time.

If `@widen` is called for a type tag which has been referenced by a
`@replicable` code block, then that code block will be replicated even more to
reflect the new concretization.

# Examples
```julia-repl
julia> @concretize BestInts [Int32, Int64]
Set(Type[Int32, Int64])

julia> @replicable println(@hyperspecialize(BestInts), @hyperspecialize(BestInts))
Int32Int32
Int32Int64
Int64Int32
Int64Int64

julia> @widen BestInts (Bool,)
BoolBool
BoolInt32
BoolInt64
Int32Bool
Int64Bool
Set(Type[Bool, Int32, Int64])
```
"""
macro replicable(E)
  elements = []
  count = 0
  E = MacroTools.postwalk(X -> begin
    if @capture(X, @hyperspecialize(K_))
      (M, K) = parse_element(:(Compat.@__MODULE__), K)
      push!(elements, :(($(M), $(QuoteNode(K)))))
      count += 1
      :(@hyperspecialize($count))
    else
      X
    end
  end, E)
  return :(_replicable(Compat.@__MODULE__, $(QuoteNode(E)), $(elements...)))
end

export @concretize, @widen, @concretization, @replicable

end # module
