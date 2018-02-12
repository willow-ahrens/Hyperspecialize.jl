using Hyperspecialize
@testset "simple concretization" begin
  using foo

  @concretize Real Float32
  @test @concretization(Real) == Set{Type}((Float32,))
  @test @concretization((foo, Real)) == Set{Type}((Int64, Int32))
  @widen (foo, Real) Int16
  @test @concretization((foo, Real)) == Set{Type}((Int64, Int32, Int16))
end
