module HSL

using LinearAlgebra
using SparseArrays

if isfile(joinpath(@__DIR__, "..", "deps", "deps.jl"))
  include("../deps/deps.jl")
else
  error("HSL library not properly installed. Please run Pkg.build(\"HSL\")")
end

function __init__()
  if (@isdefined libhsl_ma57) || (@isdefined libhsl_ma97)
    check_deps()
  end
end

# definitions applicable to all packages
const data_map = Dict{Type, Type}(Float32 => Cfloat,
                                  Float64 => Cdouble,
                                  ComplexF32 => Cfloat,
                                  ComplexF64 => Cdouble)

hslrealtype(::Type{Float64}) = Float64
hslrealtype(::Type{Float32}) = Float32
hslrealtype(::Type{ComplexF32}) = Float32
hslrealtype(::Type{ComplexF64}) = Float64
hslrealtype(::Type{T}) where T = error("$T not supported by HSL.")

# package-specific definitions
if (@isdefined libhsl_ma57) || haskey(ENV, "DOCUMENTER_KEY")
  include("hsl_ma57.jl")
  if (@isdefined libhsl_ma57_patch) || haskey(ENV, "DOCUMENTER_KEY")
    include("hsl_ma57_patch.jl")
  end
end
if (@isdefined libhsl_ma97) || haskey(ENV, "DOCUMENTER_KEY")
  include("hsl_ma97.jl")
end

end
