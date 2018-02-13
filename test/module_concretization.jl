@testset "Module Concretization" begin
  # Let's concretize a couple things, then load a module and see what happens
  @concretize NotAType [Int32]
  @concretize Float32 [Float64]
  import Foo
end
