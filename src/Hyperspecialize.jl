module Hyperspecialize

using MacroTools
using InteractiveUtils

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

function concretesubtypes(t)
  if isconcretetype(t)
    return [t]
  else
    return vcat([concretesubtypes(s) for s in subtypes(t)]...)
  end
end

function allsubtypes(t)
  return vcat([t], [allsubtypes(s) for s in subtypes(t)]...)
end

function parse_element(base_mod, K)
  if @capture(K, (L_, R_))
    M = L
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

struct Concrete
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
      error("cannot reconcretize \"$key\" in module \"$target_mod\" (TODO)")
    else
      target_mod.__hyperspecialize__[key] = Concrete(types, [])
    end
  else
    error("cannot concretize \"$key\" in module \"$target_mod\" from module \"$base_mod\"")
  end
  return Set{Type}(target_mod.__hyperspecialize__[key].concretization)
end

macro concretize(K, T)
  (M, K) = parse_element(__module__, K)
  return :(_concretize($(esc(__module__)), $(esc(M)), $(QuoteNode(K)), $(esc(T))))
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

macro widen(K, T)
  (M, K) = parse_element(__module__, K)
  return :(_widen($(esc(__module__)), $(esc(M)), $(QuoteNode(K)), $(esc(T))))
end

function _concretization(base_mod::Module, target_mod::Module, key::Symbol)
  if !isdefined(target_mod, :__hyperspecialize__) || !haskey(target_mod.__hyperspecialize__, key)
    if isdefined(target_mod, key)
      types = concretesubtypes(eval(target_mod, key))
    else
      types = []
    end
    _concretize(base_mod, target_mod, key, types)
  end
  return Set{Type}(target_mod.__hyperspecialize__[key].concretization)
end

macro concretization(K)
  (M, K) = parse_element(__module__, K)
  return :(_concretization($(esc(__module__)), $(esc(M)), $(QuoteNode(K))))
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

macro replicable(E)
  elements = []
  count = 0
  E = MacroTools.postwalk(X -> begin
    if @capture(X, @hyperspecialize(K_))
      (M, K) = parse_element(__module__, K)
      push!(elements, :(($(esc(M)), $(QuoteNode(K)))))
      count += 1
      :(@hyperspecialize($count))
    else
      X
    end
  end, E)
  return :(_replicable($(esc(__module__)), $(QuoteNode(E)), $(elements...)))
end

export @concretize, @widen, @concretization, @replicable

end # module
