module Foo

using Hyperspecialize

import Bar

@concretize AlsoNotAType Set{Type}([Int64])
@concretize Float64 Set{Type}([UInt16])

# Make sure that other modules can also change concretizations
@widen (Bar, Float64) Set{Type}([UInt16, Float32])

end #module
