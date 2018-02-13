module foo
  using Test
  using Hyperspecialize
  @concretize Real Int64
  @widen Real Int32
  @concretize AbstractArray (Array, UnitRange{Int64})
  @widen Real Int32
  @concretize Number [Float32, Float64]
  
  @widen Real Int32
end
