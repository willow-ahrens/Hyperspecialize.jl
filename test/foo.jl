module foo
  using Test
  using Hyperspecialize
  @concretize Real Int64
  @test (@concretization Real) == Set{Type}((Int64,))
  @widen Real Int32
  @test @concretization(Real) == Set{Type}((Int64, Int32))
end
