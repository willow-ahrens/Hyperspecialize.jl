# Hyperspecialize

[![Build Status](https://travis-ci.org/peterahrens/Hyperspecialize.jl.svg?branch=master)](https://travis-ci.org/peterahrens/Hyperspecialize.jl)

[![Coverage Status](https://coveralls.io/repos/peterahrens/Hyperspecialize.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/peterahrens/Hyperspecialize.jl?branch=master)

[![codecov.io](http://codecov.io/github/peterahrens/Hyperspecialize.jl/coverage.svg?branch=master)](http://codecov.io/github/peterahrens/Hyperspecialize.jl?branch=master)

Hyperspecialize is a Julia package designed to resolve method ambiguity errors by automating the task of redefining functions on more specific types.

## Problem

It is best to explain the problem (and solution) by example.

Now, suppose Peter and his friend Jarrett have both developed eponymous modules `Peter` and `Jarrett` as follows:

```
module Peter
  import Base.+

  struct PeterNumber <: Number
    x::Number
  end

  Base.:+(p::PeterNumber, y::Number) = PeterNumber(p.x + y)

  export PeterNumber
end

module Jarrett
  import Base.+

  struct JarrettNumber <: Number
    y::Number
  end

  Base.:+(x::Number, j::JarrettNumber) = JarrettNumber(x + j.y)

  export JarrettNumber
end
```

Peter and Jarrett have both defined fun numeric types! However, look what
happens when the user tries to use Peter's and Jarrett's numbers together...

```
julia> using .Peter

julia> using .Jarrett

julia> p = PeterNumber(1.0) + 3
PeterNumber(4.0)

julia> j = 2.0 + JarrettNumber(2.0)
JarrettNumber(4.0)

julia> friends = p + j
ERROR: MethodError: +(::PeterNumber, ::JarrettNumber) is ambiguous. Candidates:
  +(x::Number, j::JarrettNumber) in Main.Jarrett at REPL[2]:8
  +(p::PeterNumber, y::Number) in Main.Peter at REPL[1]:8
Possible fix, define
  +(::PeterNumber, ::JarrettNumber)
```

Oh no! Since a `PeterNumber` is a `Number` and a `JarrettNumber` is a `Number`,
when we try to add the two kinds of numbers it looks as if both `+` methods
will apply, and neither is more specific.

There is a question of what role developers should play in the resolution of
this ambiguity.

  * All developers can coordinate their efforts to agree on how their types
should interact, and then define methods for each interaction. This solution is
unrealistic since it poses an undue burden of communication on the developers
and since multiple behaviors may be desired for an interaction between types.
In the above example, the two definitions of `+` have different behavior and
either may be desired by the user.

  * The developer can write their library to run in a modifed execution
environment like [Cassette](). This solution creates different contexts for
multiple dispatch.

  * A single developer can define their ambiguous methods on concrete
subtypes in `Base`, and provide utilities to extend these definitions. For
example, Peter could define `+` on all concrete subtypes of `Number` in Base.
`+` would default to Jarrett's definition unless the user asks for Peter's
definition.

  Hyperspecialize is designed to standardize and provide utilities for the
latter approach.

## Default Behavior

  Peter decided to use Hyperspecialize, and now his module looks like this:

```
module Peter
  import Base.+

  using Hyperspecialize

  struct PeterNumber <: Number
    x::Number
  end

  @replicable Base.:+(p::PeterNumber, y::@hyperspecialize(Number)) = PeterNumber(p.x + y)

  export PeterNumber
end
```

  This solution will define Peter's `+` method multiple times on all concrete
subtypes of Number. This list of subtypes depends on the module load order. If
Peter's module is loaded first, we get the following behavior:

```
julia> friends = p + j
JarrettNumber(PeterNumber(8.0))
```

If Jarrett's module is loaded first, we get the following behavior:

```
julia> friends = p + j
PeterNumber(JarrettNumber(8.0))
```

## Explicit behavior

  Peter doesn't like this unpredictable behavior, so he decides to explicitly
define the load order for his types. He asks for his code to only be defined on
the concrete subtypes of `Number` in `Base`. He uses the `@concretize` macro to
define which subtypes of `Number` to use.  Now his module looks like this:

```
module Peter
  import Base.+

  using Hyperspecialize

  struct PeterNumber <: Number
    x::Number
  end

  @concretize myNumber [BigFloat, Float16, Float32, Float64, Bool, BigInt, Int128, Int16, Int32, Int64, Int8, UInt128, UInt16, UInt32, UInt64, UInt8]

  @replicable Base.:+(p::PeterNumber, y::@hyperspecialize(myNumber)) = PeterNumber(p.x + y)

  export PeterNumber
end
```

  Since Peter has only defined `+` for the concrete subtypes of Number, the user
will need to ask for a specific definition of `+` for a type they would like to
use. Consider what happens when Peter's package and Jarrett's package are
loaded together.

```
julia> friends = p + j
JarrettNumber(PeterNumber(8.0))

julia> using Hyperspecialize

julia> @widen (Peter, myNumber) JarrettNumber
Set(Type[BigInt, Bool, UInt32, Float64, Float32, Int64, Int128, Float16, JarrettNumber, UInt128, UInt8, UInt16, BigFloat, Int8, UInt64, Int16, Int32])

julia> friends = p + j
PeterNumber(JarrettNumber(8.0))
```

Before the `myNumber` type tag in the `Peter` module is widened, there is no
definition of `+` for `PeterNumber` and `JarrettNumber` in the `Peter` package,
but since the `Jarrett` module defines a more generic method, that one is
chosen. After the user widens Peter's definition to include a JarrettNumber
(triggering a specific definition of `+` to be evaluated in Peter's module),
the more specific method in Peter's package is chosen.

## Opt-In, But Everyone Can Join

Suppose Jarrett has also been thinking about method ambiguities with Peter's
package and decides he will also use `Hyperspecialize`.

Now Jarret has added

```
  @concretize myNumber [BigFloat, Float16, Float32, Float64, Bool, BigInt, Int128, Int16, Int32, Int64, Int8, UInt128, UInt16, UInt32, UInt64, UInt8]

  @replicable Base.:+(x::@hyperspecialize(myNumber), j::JarrettNumber) = JarrettNumber(x + j.y)
```

to his module, and the behavior is as follows:

```
julia> p + j
ERROR: no promotion exists for PeterNumber and JarrettNumber
Stacktrace:
 [1] error(::String, ::Type, ::String, ::Type) at ./error.jl:42
 [2] promote_to_supertype at ./promotion.jl:284 [inlined]
 [3] promote_result at ./promotion.jl:275 [inlined]
 [4] promote_type at ./promotion.jl:210 [inlined]
 [5] _promote at ./promotion.jl:249 [inlined]
 [6] promote at ./promotion.jl:292 [inlined]
 [7] +(::PeterNumber, ::JarrettNumber) at ./promotion.jl:321
 [8] top-level scope
```

There is now no method for adding a PeterNumber and a JarrettNumber! The user
must ask for one explicitly using `@widen` on either Peter or Jarrett's
`myNumber` type tag. If the user chooses to widen Jarrett's definitions, we get

```
julia> @widen (Jarrett, myNumber) PeterNumber
Set(Type[BigInt, Bool, UInt32, Float64, Float32, Int64, Int128, Float16, PeterNumber, UInt128, UInt8, UInt16, BigFloat, Int8, UInt64, Int16, Int32])

julia> p + j
JarrettNumber(PeterNumber(8.0))
```

If the user instead chooses to widen Peter's definitions, we get

```
julia> @widen (Peter, myNumber) JarrettNumber
Set(Type[BigInt, Bool, UInt32, Float64, Float32, Int64, Int128, Float16, UInt128, UInt8, UInt16, BigFloat, Int8, UInt64, JarrettNumber, Int16, Int32])

julia> p + j
PeterNumber(JarrettNumber(8.0))
```

# Getting Started

#

# The Details

## Data And Precompilation

## When Is Hyperspecialize Right For Me?

## Drawbacks

## Avoiding Method Explosions
