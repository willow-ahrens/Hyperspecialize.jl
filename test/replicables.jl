module SimpleReplicables

@testset "Simple Replicables" begin
  using Hyperspecialize

  push!(LOAD_PATH, ".")

  @replicable function wobble(::Real)
    return Real
  end

  @test wobble(Float32(1.0)) == Real

  @replicable function wobble(x::@hyperspecialize Real)
    return typeof(x)
  end

  @test wobble(Float32(1.0)) == Float32
end

end
