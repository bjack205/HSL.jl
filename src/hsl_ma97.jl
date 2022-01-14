export Ma97_Control, Ma97_Info, Ma97
export ma97_csc, ma97_coord,
       ma97_factorize!, ma97_factorise!,
       ma97_factorize, ma97_factorise,
       ma97_solve, ma97_solve!,
       ma97_inquire, ma97_enquire,
       ma97_alter!,
       ma97_min_norm, ma97_least_squares
export Ma97Exception

const Ma97Data = Union{Float32, Float64, ComplexF32, ComplexF64}
const Ma97Real = Union{Cfloat, Cdouble}

const VecOrNull{T} = Union{Vector{T},Ptr{Cvoid}}

using SparseArrays: getcolptr, getrowval 

struct AKeep
  ptr::Vector{Ptr{Cvoid}}
end
@inline Base.cconvert(::Type{Ref{Ptr{Cvoid}}}, akeep::AKeep) = akeep.ptr
@inline Base.unsafe_convert(::Type{Ptr{Ptr{Cvoid}}}, akeep::AKeep) = Base.unsafe_convert(Ptr{Ptr{Cvoid}}, akeep.ptr)
AKeep() = AKeep([C_NULL])
isnull(akeep::AKeep) = akeep.ptr[1] == C_NULL

struct FKeep
  ptr::Vector{Ptr{Cvoid}}
end
@inline Base.cconvert(::Type{Ref{Ptr{Cvoid}}}, fkeep::FKeep) = fkeep.ptr
@inline Base.unsafe_convert(::Type{Ptr{Ptr{Cvoid}}}, fkeep::FKeep) = Base.unsafe_convert(Ptr{Ptr{Cvoid}}, fkeep.ptr)
FKeep() = FKeep([C_NULL])
isnull(fkeep::FKeep) = fkeep.ptr[1] == C_NULL

const ma97alg = getalg(:hsl_ma97)
const ma97types = getdatatypes(ma97alg)
const libma97 = getlib(ma97alg)

ma97_checktype(::Type{T}) where T = T ∈ ma97types 

"""# Main control type for MA97.

    Ma97_Control{T}(; kwargs...)
    Ma97_Control(T)

If the type `T` is passed in as an argument, any type supported by HSL will be converted 
to it's corresponding real type.

## Keyword arguments:

* `print_level::Int`: integer controling the verbosit level. Accepted values are:
    * <0: no printing
    * 0: errors and warnings only (default)
    * 1: errors, warnings and basic diagnostics
    * 2: errors, warning and full diagnostics
* `unit_diagnostics::Int`: Fortran file unit for diagnostics (default: 6)
* `unit_error::Int`: Fortran file unit for errors (default: 6)
* `unit_warning::Int`: Fortran file unit for warnings (default: 6)
"""
mutable struct Ma97_Control{T <: Ma97Real}

  "`f_arrays`=1 indicates that arrays are 1-based"
  f_arrays :: Cint

  "`action`=0 aborts factorization if matrix is singular"
  action :: Cint

  "two neighbors in the etree are merged if both involve < `nemin` eliminations"
  nemin :: Cint

  "factor by which memory is increased"
  multiplier :: T

  ordering :: Cint
  print_level :: Cint
  scaling :: Cint

  "tolerance under which a pivot is treated as zero"
  small :: T

  "relative pivot tolerance"
  u :: T

  unit_diagnostics :: Cint
  unit_error :: Cint
  unit_warning :: Cint

  "parallelism is used if `info.num_flops` ≥ `factor_min`"
  factor_min :: Clong

  "use level 3 BLAS for single right-hand side"
  solve_blas3 :: Cint

  "parallelism is used if `info.num_factor` ≥ `solve_min`"
  solve_min :: Clong

  "`solve_mf`=1 use a multifrontal forward solve instead of a supernodal solve"
  solve_mf :: Cint

  "tolerance for consistent equations"
  consist_tol :: T

  "spare integer storage currently unused"
  ispare :: Vector{Cint}

  "spare real storage currently unused"
  rspare :: Vector{T}

  function Ma97_Control{T}(; print_level :: Int=-1, unit_diagnostics :: Int=6, unit_error :: Int=6, unit_warning :: Int=6) where {T}
    control = new(0, 0, 0, 0.0, 0, 0, 0, 0.0,
                  0.0, 0, 0, 0, 0, 0, 0, 0, 0.0,
                  zeros(Cint, 5), zeros(T, 10))

    if T == Float32
      ccall((:ma97_default_control_s, libhsl_ma97), Nothing, (Ref{Ma97_Control{Float32}},), control)
    elseif T == Float64
      ccall((:ma97_default_control_d, libhsl_ma97), Nothing, (Ref{Ma97_Control{Float64}},), control)
    elseif T == ComplexF32
      ccall((:ma97_default_control_c, libhsl_ma97), Nothing, (Ref{Ma97_Control{Float32}},), control)
    elseif T == ComplexF64
      ccall((:ma97_default_control_z, libhsl_ma97), Nothing, (Ref{Ma97_Control{Float64}},), control)
    end
    control.f_arrays = 1  # Use 1-based indexing for arrays, avoiding copies.
    control.print_level = print_level
    control.unit_diagnostics = unit_diagnostics
    control.unit_error = unit_error
    control.unit_warning = unit_warning
    return control
  end
end
Ma97_Control(::Type{T}) where T = Ma97_Control{hslrealtype(T)}()

const orderings97 = Dict{Symbol,Int}(
                      :user  => 0,
                      :amd   => 1,
                      :md    => 2,
                      :metis => 3,
                      :ma47  => 4,
                      :metis_or_amd_par => 5,
                      :metis_or_amd_ser => 6,
                      :mc80  => 7,
                      :matching_metis => 8,
                    )


const ordering_names97 = Dict{Int,AbstractString}(
                           0 => "user supplied or none",
                           1 => "AMD",
                           2 => "minimum degree",
                           3 => "METIS",
                           4 => "MA47",
                           5 => "METIS or AMD parallel",
                           6 => "METIS or AMD serial",
                           7 => "matching with HSL_MC80",
                           8 => "matching + METIS",
                         )


const matrix_types97 = Dict{Symbol,Int}(
                         :real_spd   =>  3,  # real symmetric positive definite
                         :real_indef =>  4,  # real symmetric indefinite
                         :herm_pd    => -3,  # hermitian positive definite
                         :herm_indef => -4,  # hermitian indefinite
                         :cmpl_indef => -5,  # complex symmetric indefinite
                       )

const jobs97 = Dict{Symbol,Int}(
                 :A    => 0,  # solve Ax = b
                 :PL   => 1,  # solve PLx = Sb
                 :D    => 2,  # solve Dx = b
                 :LPS  => 3,  # solve L'P'S⁻¹x = b
                 :DLPS => 4,  # solve DL'P'S⁻¹x = b
               )


"Exception type raised in case of error."
mutable struct Ma97Exception <: Exception
  msg  :: AbstractString
  flag :: Int
end


"""# Main info type for MA97

    info = Ma97_Info{T <: Ma97Real}()
    info = Ma97_Info(T)

An `info` variable is used to collect statistics on the analysis, factorization and solve.

If the type `T` is passed in as an argument, any type supported by HSL will be converted 
to it's corresponding real type.

"""
mutable struct Ma97_Info{T <: Ma97Real}
  "exit status"
  flag :: Cint

  "exit status from MC68"
  flag68 :: Cint

  "exit status from MC77 (for scaling)"
  flag77 :: Cint

  "number of duplicate entries found and summed"
  matrix_dup :: Cint

  matrix_rank :: Cint

  "number of out-of-range entries found and discarded"
  matrix_outrange :: Cint

  "number of diagonal entries without a value"
  matrix_missing_diag :: Cint

  "maximum depth of assembly tree"
  maxdepth :: Cint

  "maximum front size"
  maxfront :: Cint

  "number of delayed eliminations"
  num_delay :: Cint

  "number of entries in the factor L"
  num_factor :: Clong

  "number of flops to perform the factorization"
  num_flops :: Clong

  "number of negative eigenvalues"
  num_neg :: Cint

  "number of supernodes"
  num_sup :: Cint

  "number of 2x2 pivots"
  num_two :: Cint

  ordering :: Cint

  "Fortran stat parameter in case of a memory error"
  stat :: Cint

  "spare integer storage currently unused"
  ispare :: Vector{Cint}

  "spare real storage currently unused"
  rspare :: Vector{T}

  function Ma97_Info{T}() where {T}
    return new(0, 0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0, 0, 0,
               zeros(Cint, 5), zeros(T, 10))
  end
end
Ma97_Info(::Type{T}) where T = Ma97_Info{hslrealtype(T)}()


# in the Ma97 type, we need to maintain a constraint on the types
# the following is inspired by
# https://groups.google.com/d/msg/julia-users/JNQ3eBUL3QU/gqAfij6bAgAJ

mutable struct Ma97{T <: Ma97Data, S <: Ma97Real}
  __akeep::AKeep
  __fkeep::FKeep 
  n::Int
  col::Vector{Cint}
  row::Vector{Cint}
  nzval::Vector{T}
  control::Ma97_Control{S}
  info::Ma97_Info{S}
  iscoord::Bool  # are col and row in coordinate format
  # TODO: add order and scale

  function Ma97{T, S}(n::Int, col::Vector{Cint}, row::Vector{Cint}, nzval::Vector{T},
                      control::Ma97_Control{S}, info::Ma97_Info{S}) where {T, S}
    nzeros = length(nzval)
    if (length(col) == length(row) == length(nzval)) && (col[end] != length(nzval)+1)
      iscoord = true
    else
      @assert length(col) == n+1
      @assert length(nzval) == nzeros
      @assert col[end] == nzeros+1
      iscoord = false
    end
    __akeep = AKeep()
    __fkeep = FKeep()

    t = eltype(nzval)
    S == data_map[t] || throw(TypeError(:Ma97, "Ma97{$T, $S}\n", data_map[t], t))
    new(__akeep, __fkeep, n, col, row, nzval, control, info, iscoord)
  end
end

# Convert integer to Int32 and infer types
function Ma97(n::Int, col::Vector{<:Integer}, row::Vector{<:Integer}, nzval::Vector{T};
              analyse::Bool=true,
              control::Ma97_Control{S}=Ma97_Control(T), 
              info::Ma97_Info{S}=Ma97_Info(T)) where {T, S}
  # Note that the input must be upper or lower triangular
  row = convert(Vector{Cint}, row)
  col = convert(Vector{Cint}, col)
  M = Ma97{T, S}(n, col, row, nzval, control, info)
  if analyse
    ma97_analyse(M)
  end
  return M
end

"""# Instantiate and perform symbolic analysis on a sparse Julia matrix

    M = Ma97(A; kwargs...)

Instantiate an object of type `Ma97` and perform the symbolic analysis on a sparse Julia matrix.

## Input arguments

* `A::SparseMatrixCSC{T<:Ma97Data,Int}`: input matrix. The lower triangle will be extracted.

## Keyword arguments

All keyword arguments are passed directly to `ma97_csc()`.
"""
function Ma97(L::SparseMatrixCSC{T,Ti}; 
  analyse::Bool=true,
  control::Ma97_Control{S}=Ma97_Control{data_map[T]}(), 
  info::Ma97_Info{S}=Ma97_Info{data_map[T]}()
) where {T,S,Ti}
  # Convert to lower triangular
  if !istril(L)
    L = tril(L)
  end
  # Convert to Int32
  if Ti != Cint
    L = SparseMatrixCSC{T,Cint}(L)
  end
  ma97 = Ma97{T,S}(size(L,1), L.colptr, L.rowval, L.nzval, control, info)
  if analyse
    ma97_analyse(ma97)
  end
  return ma97
end

# Convert dense to sparse
Ma97(A::Array{T,2}; kwargs...) where {T <: Ma97Data} = Ma97(sparse(A); kwargs...)

# Basic info
isanalysisdone(ma97::Ma97) = !isnull(ma97.__akeep)
isfactorisedone(ma97::Ma97) = !isnull(ma97.__fkeep)
SparseArrays.getcolptr(M::Ma97) = isempty(M.col) ? C_NULL : M.col
SparseArrays.getrowval(M::Ma97) = isempty(M.row) ? C_NULL : M.row

# Memory management methods
ma97_free_akeep(M::Ma97{T}) where T = ma97_free_akeep(T, M.__akeep)
ma97_free_fkeep(M::Ma97{T}) where T = ma97_free_fkeep(T, M.__fkeep)
function ma97_finalise(M::Ma97{T}) where T 
  if !isnull(M.__akeep) && !isnull(M.__fkeep)
    ma97_finalise(T, M.__akeep, M.__fkeep)
  elseif !isnull(M.__akeep)
    ma97_free_akeep(M)
  elseif !isnull(M.__fkeep)
    ma97_free_fkeep(M)
  end
  return
end
@inline ma97_finalize(M::Ma97) = ma97_finalise(M)

##############################
# Core Methods
##############################
function ma97_analyse(M::Ma97{T}; check=true, order::VecOrNull{Cint}=C_NULL) where T
  if order !=C_NULL 
    @assert length(order) == M.n
  end
  if M.iscoord
    ma97_analyse_coord(M, order=order)
  else
    ma97_analyse(T, check, M.n, M.col, M.row, M.nzval, M.__akeep, M.control, M.info, order)
  end
end

# Old method
function ma97_csc(n :: Int, colptr :: Vector{Cint}, rowval :: Vector{Cint}, nzval :: Vector{T}; kwargs...) where {T}
  D = data_map[T]
  control = Ma97_Control{D}(; kwargs...)
  info = Ma97_Info{D}()
  M = Ma97{T, D}(n, colptr, rowval, nzval, control, info)

  # Perform symbolic analysis.
  ma97_analyse(T, true, M.n, M.col, M.row, C_NULL, M.__akeep, M.control, M.info, C_NULL)

  finalizer(ma97_finalize, M)
  return M
end

function ma97_analyse_coord(M::Ma97{T}; order::VecOrNull{Cint}=C_NULL) where {T<:Ma97Data}
  @assert M.iscoord "Data must be stored in coordinate format."
  ma97_analyse_coord(T, M.n, M.row, M.col, M.nzval, M.__akeep, M.control, M.info, order)
end

### Factorization ###
function ma97_factorize!(M::Ma97; matrix_type::Symbol=:real_indef, 
                         scale::VecOrNull{Float64}=C_NULL)
  mt = matrix_types97[matrix_type]
  ma97_factor(mt, getcolptr(M), getrowval(M), M.nzval, M.__akeep, M.__fkeep, M.control, 
              M.info, scale)
end

function ma97_factorize(A::SparseMatrixCSC{T,Int}; matrix_type::Symbol=:real_indef) where {T <: Ma97Data}
  ma97 = Ma97(A)
  ma97_factorize!(ma97, matrix_type=matrix_type)
  return ma97
end

# Z's not dead.
@inline ma97_factorise(A::SparseMatrixCSC; kwargs...) = ma97_factorize(M; kwargs...)
@inline ma97_factorise!(M::Ma97; kwargs...) = ma97_factorize!(M; kwargs...)

### Solve Methods ###
# In-place solves
function ma97_solve!(M::Ma97{T}, b::Array{T}; job::Symbol=:A) where {T<:Ma97Data}
  jobint = jobs97[job]
  ma97_solve(jobint, b, M.__akeep, M.__fkeep, M.control, M.info)
end

function ma97_factor_solve!(M::Ma97{T}, b::Array{T}; 
                            matrix_type::Symbol=:real_indef, 
                            scale::VecOrNull{Cint}=C_NULL) where {T<:Ma97Data}
  mattype = Cint(matrix_types97[matrix_type])
  ma97_factor_solve(mattype, getcolptr(M), getrowval(M), M.nzval, b, 
      M.__akeep, M.__fkeep, M.control, M.info, scale)
end

# Out-of-place solve
function ma97_solve(ma97::Ma97{T}, b::Array{T}; kwargs...) where {T<:Ma97Data}
  x = copy(b)
  ma97_solve!(ma97, x; kwargs...)
  return x
end

import Base.\
\(ma97::Ma97{T}, b::Array{T}) where {T<:Ma97Data} = ma97_solve(ma97, b)

# function ma97_solve(A::SparseMatrixCSC{T,<:Integer}, b::Array{T}; 
#                     matrix_type::Symbol=:real_indef,
#                     control::Ma97_Control{S}=Ma97_Control(T),
#                     info::Ma97_Info{S}=Ma97_Info(T)) where {T <: Ma97Data, S <: Ma97Real}
#   (m, n) = size(A)
#   m < n && (return ma97_min_norm(A, b))
#   m > n && (return ma97_least_squares(A, b))
#   M = Ma97(A, control=control, info=info)
#   ma97_solve(M, b, matrix_type=matrix_type)
# end

##############################
# C Wrapper Functions
##############################
for (fname, typ) in ((:ma97_free_akeep_s, Float32),
                     (:ma97_free_akeep_d, Float64),
                     (:ma97_free_akeep_c, ComplexF32),
                     (:ma97_free_akeep_z, ComplexF64))
  @eval begin
    function ma97_free_akeep(::Type{$typ}, akeep::AKeep)
      ccall(($(string(fname)), libhsl_ma97), Nothing, (Ptr{Ptr{Nothing}},), akeep)
      akeep.ptr[1] = C_NULL  # Make sure the pointer is NULL after freeing
    end
  end
end

for (fname, typ) in ((:ma97_free_fkeep_s, Float32),
                     (:ma97_free_fkeep_d, Float64),
                     (:ma97_free_fkeep_c, ComplexF32),
                     (:ma97_free_fkeep_z, ComplexF64))
  @eval begin
    function ma97_free_fkeep(::Type{$typ}, fkeep::FKeep)
      ccall(($(string(fname)), libhsl_ma97), Nothing, (Ptr{Ptr{Nothing}},), fkeep)
      fkeep.ptr[1] = C_NULL  # Make sure the pointer is NULL after freeing
    end
  end
end

for (fname, typ) in ((:ma97_finalise_s, Float32),
                     (:ma97_finalise_d, Float64),
                     (:ma97_finalise_c, ComplexF32),
                     (:ma97_finalise_z, ComplexF64))

  @eval begin

    function ma97_finalise(::Type{$typ}, akeep::AKeep, fkeep::FKeep)
      ccall(($(string(fname)), libhsl_ma97), Nothing,
            (Ptr{Ptr{Nothing}}, Ptr{Ptr{Nothing}}),
             akeep, fkeep)
      akeep.ptr[1] = C_NULL  # Make sure the pointer is NULL after freeing
      fkeep.ptr[1] = C_NULL  # Make sure the pointer is NULL after freeing
    end

  end
end

for (fname, typ) in ((:ma97_analyse_s, Float32),
                     (:ma97_analyse_d, Float64),
                     (:ma97_analyse_c, ComplexF32),
                     (:ma97_analyse_z, ComplexF64))
  S = hslrealtype(typ)
  @eval begin

    # need to pass in type because the `val` argument which provides the type can be C_NULL
    function ma97_analyse(::Type{$typ}, check::Bool, n::Int, ptr::Vector{Cint}, 
        row::Vector{Cint}, val::Union{Vector{$typ},Ptr{Cvoid}},
        akeep::AKeep,  control::Ma97_Control{$S}, info::Ma97_Info{$S}, 
        order::VecOrNull{Cint}=C_NULL,
      )
      # Perform symbolic analysis.
      ccall(($(string(fname)), libhsl_ma97), Nothing,
            (Cint, Cint, Ptr{Cint}, Ptr{Cint}, Ptr{$typ}, Ptr{Ptr{Nothing}}, Ref{Ma97_Control{$S}}, Ref{Ma97_Info{$S}}, Ptr{Cint}),
             check,    n,  ptr,        row,  val,    akeep.ptr,      control,         info,         order)

      if info.flag < 0
        ma97_free_akeep($typ, akeep)
        throw(Ma97Exception("Ma97: Error during symbolic analysis", info.flag))
      end

      return nothing
    end
  end
end

for (fname, typ) in ((:ma97_analyse_coord_s, Float32),
                     (:ma97_analyse_coord_d, Float64),
                     (:ma97_analyse_coord_c, ComplexF32),
                     (:ma97_analyse_coord_z, ComplexF64))

  S = hslrealtype(typ)
  @eval begin

    function ma97_analyse_coord(::Type{$typ}, n::Int, row::Vector{Cint}, col::Vector{Cint}, 
                                val::VecOrNull{$typ}, akeep::AKeep,  
                                control::Ma97_Control{$S}, info::Ma97_Info{$S}, 
                                order::VecOrNull{Cint}=C_NULL)
      ne = length(row)
      @assert n >= 0
      @assert ne > 0 "Must have at least 1 nonzero entry."
      @assert ne == length(col) == length(val) "row, col, and val must have the length."

      # Perform symbolic analysis.
      ccall(($(string(fname)), libhsl_ma97), Nothing,
            (Cint, Cint, Ptr{Cint}, Ptr{Cint}, Ptr{$typ}, Ptr{Ptr{Nothing}}, 
            Ref{Ma97_Control{$S}}, Ref{Ma97_Info{$S}}, Ptr{Cint}),
            n, ne, row, col, val, akeep, control, info, C_NULL
      )

      if info.flag < 0
        ma97_free_akeep($typ, akeep)
        throw(Ma97Exception("Ma97: Error during symbolic analysis", info.flag))
      end

    end

  end
end


for (fname, typ) in ((:ma97_factor_s, Float32),
                     (:ma97_factor_d, Float64),
                     (:ma97_factor_c, ComplexF32),
                     (:ma97_factor_z, ComplexF64))

  S = hslrealtype(typ)
  @eval begin

    function ma97_factor(matrix_type::Int, ptr::VecOrNull{Cint}, row::VecOrNull{Cint}, 
      val::Vector{$typ}, akeep::AKeep, fkeep::FKeep,
      control::Ma97_Control, info::Ma97_Info, scale::VecOrNull{Float64},
    )

      ccall(($(string(fname)), libhsl_ma97), Nothing,
            (Cint, Ptr{Cint}, Ptr{Cint}, Ptr{$typ},  Ptr{Ptr{Nothing}}, Ptr{Ptr{Nothing}}, Ref{Ma97_Control{$S}}, Ref{Ma97_Info{$S}}, Ptr{Cdouble}),
             matrix_type, ptr, row,        val,         akeep.ptr,        fkeep.ptr,   control,      info,   scale)

      if info.flag < 0
        ma97_free_akeep($typ, akeep)
        throw(Ma97Exception("Ma97: Error during numerical factorization", info.flag))
      end
    end
  end
end

for (fname, typ) in ((:ma97_solve_s, Float32),
                     (:ma97_solve_d, Float64),
                     (:ma97_solve_c, ComplexF32),
                     (:ma97_solve_z, ComplexF64))
  @eval begin

    function ma97_solve(job::Integer, x::Array{$typ}, akeep::AKeep, fkeep::FKeep,
      control::Ma97_Control, info::Ma97_Info
    )
      # size(x, 1) == ma97.n || throw(Ma97Exception("Ma97: rhs size mismatch", 0))
      nrhs = size(x, 2)
      ldx = size(x,1)

      ccall(($(string(fname)), libhsl_ma97), Nothing,
            (Cint, Cint, Ref{$typ}, Cint,   Ptr{Ptr{Nothing}}, Ptr{Ptr{Nothing}}, Ref{Ma97_Control{$(data_map[typ])}}, Ref{Ma97_Info{$(data_map[typ])}}),
             job,  nrhs, x,         ldx,   akeep.ptr,   fkeep.ptr,   control,      info)

      if info.flag < 0
        ma97_finalise($typ, akeep, fkeep)
        throw(Ma97Exception("Ma97: Error during solve", info.flag))
      end
    end

  end
end



for (fname, typ) in ((:ma97_factor_solve_s, Float32),
                     (:ma97_factor_solve_d, Float64),
                     (:ma97_factor_solve_c, ComplexF32),
                     (:ma97_factor_solve_z, ComplexF64))

  S = hslrealtype(typ)
  @eval begin

    function ma97_factor_solve(matrix_type::Cint, ptr::VecOrNull{Cint}, 
                               row::VecOrNull{Cint}, val::Vector{$typ}, b::Array{$typ}, 
                               akeep::AKeep, fkeep::FKeep, 
                               control::Ma97_Control{$S}, 
                               info::Ma97_Info{$S}, scale::VecOrNull{Cint})
      nrhs = size(b,2)
      ldx = size(b,1)
      ccall(($(string(fname)), libhsl_ma97), Nothing,
        (Cint, Ptr{Cint}, Ptr{Cint}, Ref{$typ}, Cint, Ref{$typ}, Cint, Ptr{Ptr{Cvoid}},
        Ptr{Ptr{Cvoid}}, Ref{Ma97_Control{$S}}, Ref{Ma97_Info{$S}}, Ptr{Cdouble}),
        matrix_type, ptr, row, val, nrhs, b, ldx, akeep, fkeep, control, info, scale
      )
      if info.flag < 0
        ma97_finalise($typ, akeep, fkeep)
      end
    end
  end
end


# ma97_solve(A :: Array{T,2}, b :: Array{T}; matrix_type :: Symbol=:real_indef) where {T <: Ma97Data} = ma97_solve(sparse(A), b, matrix_type=matrix_type)


for (indef, posdef, typ) in ((:ma97_enquire_indef_s, :ma97_enquire_posdef_s, Float32),
                             (:ma97_enquire_indef_d, :ma97_enquire_posdef_d, Float64),
                             (:ma97_enquire_indef_c, :ma97_enquire_posdef_c, ComplexF32),
                             (:ma97_enquire_indef_z, :ma97_enquire_posdef_z, ComplexF64))

  @eval begin

    function ma97_inquire(ma97 :: Ma97{$typ, $(data_map[typ])}; matrix_type :: Symbol=:real_indef)
      if matrix_type in [:real_indef, :herm_indef, :cmpl_indef]
        piv_order = zeros(Cint, ma97.n)
        # AMBUSH ALERT: although Julia will call the C interface of the library
        # Julia stores arrays column-major as Fortran does. Though the C interface
        # documentation says d should be n x 2, we must declare 2 x n.
        d = zeros($typ, 2, ma97.n)
        ccall(($(string(indef)), libhsl_ma97), Nothing,
              (Ptr{Ptr{Nothing}}, Ptr{Ptr{Nothing}}, Ref{Ma97_Control{$(data_map[typ])}}, Ref{Ma97_Info{$(data_map[typ])}}, Ptr{Cint}, Ptr{$typ}),
               ma97.__akeep,   ma97.__fkeep,   ma97.control,      ma97.info,      piv_order, d)
        ret = (piv_order, d)
      else
        d = zeros($typ, ma97.n)
        ccall(($(string(posdef)), libhsl_ma97), Nothing,
              (Ptr{Ptr{Nothing}}, Ptr{Ptr{Nothing}}, Ref{Ma97_Control{$(data_map[typ])}}, Ref{Ma97_Info{$(data_map[typ])}}, Ptr{$typ}),
               ma97.__akeep,   ma97.__fkeep,   ma97.control,      ma97.info,      d)
        ret = d
      end

      if ma97.info.flag < 0
        ma97_finalize(ma97)
        throw(Ma97Exception("Ma97: Error during inquiry", ma97.info.flag))
      end

      return ret
    end

  end
end

ma97_enquire = ma97_inquire


for (fname, typ) in ((:ma97_alter_s, Float32),
                     (:ma97_alter_d, Float64),
                     (:ma97_alter_c, ComplexF32),
                     (:ma97_alter_z, ComplexF64))

  @eval begin

    function ma97_alter!(ma97 :: Ma97{$typ, $(data_map[typ])}, d :: Array{$typ, 2})
      n, m = size(d)
      (m == ma97.n && n == 2) || throw(Ma97Exception("Ma97: input array d must be n x 2", 0))
      ccall(($(string(fname)), libhsl_ma97), Nothing,
            (Ptr{$typ}, Ptr{Ptr{Nothing}}, Ptr{Ptr{Nothing}}, Ref{Ma97_Control{$(data_map[typ])}}, Ref{Ma97_Info{$(data_map[typ])}}),
             d,         ma97.__akeep,   ma97.__fkeep,   ma97.control,      ma97.info)

      if ma97.info.flag < 0
        ma97_finalize(ma97)
        throw(Ma97Exception("Ma97: Error during alteration", ma97.info.flag))
      end
    end

  end
end

# Note: it seems inconvenient to have in-place versions of min_norm and
# least_squares because the user would have to provide a storage array
# of length n+m, which is not the size of the solution x alone.

"""# Solve a minimum-norm problem

    ma97_min_norm(A, b)

solves

    minimize ‖x‖₂  subject to Ax=b,

where A has shape m-by-n with m < n, by solving the saddle-point system

    [ I  A' ] [ x ]   [ 0 ]
    [ A     ] [ y ] = [ b ].

## Input arguments

* `A::SparseMatrixCSC{T<:Ma97Data,Int}`: input matrix of shape m-by-n with m < n. A full matrix will be converted to sparse.
* `b::Vector{T}`: right-hand side vector

## Return value

* `x::Vector{T}`: solution vector.
"""
function ma97_min_norm(A :: SparseMatrixCSC{T,Int}, b :: Vector{T}) where {T <: Ma97Data}
  (m, n) = size(A)
  K = [ sparse(T(1)I, n, n)  spzeros(T, n, m) ; A  sparse(T(0)I, m, m) ]
  rhs = [ zeros(T, n) ; b ]
  xy97 = ma97_solve(K, rhs, matrix_type=T in (ComplexF32, ComplexF64) ? :herm_indef : :real_indef)
  x97 = xy97[1:n]
  y97 = xy97[n+1:n+m]
  return (x97, y97)
end

ma97_min_norm(A :: Array{T,2}, b :: Vector{T}) where {T <: Ma97Data} = ma97_min_norm(sparse(A), b)


"""# Solve least-squares problem

    ma97_least_squares(A, b)

Solve the least-squares problem

    minimize ‖Ax - b‖₂

where A has shape m-by-n with m > n, by solving the saddle-point system

    [ I   A ] [ r ]   [ b ]
    [ A'    ] [ x ] = [ 0 ].

## Input arguments

* `A::SparseMatrixCSC{T<:Ma97Data,Int}`: input matrix of shape m-by-n with m > n. A full matrix will be converted to sparse.
* `b::Vector{T}`: right-hand side vector

## Return value

* `x::Vector{T}`: solution vector.
"""
function ma97_least_squares(A :: SparseMatrixCSC{T,Int}, b :: Vector{T}) where {T <: Ma97Data}
  (m, n) = size(A)
  K = [ sparse(T(1)I, m, m)  spzeros(T, m,n) ; A'  sparse(T(0)I, n, n) ]
  rhs = [ b ; zeros(T, n) ]
  rx97 = ma97_solve(K, rhs, matrix_type=T in (ComplexF32, ComplexF64) ? :herm_indef : :real_indef)
  r97 = rx97[1:m]
  x97 = rx97[m+1:m+n]
  return (r97, x97)
end

ma97_least_squares(A :: Array{T,2}, b :: Vector{T}) where {T <: Ma97Data} = ma97_least_squares(sparse(A), b)


# docstrings

"""# Instantiate and perform symbolic analysis using CSC arrays

    M = ma97_csc(n, colptr, rowval, nzval; kwargs...)

Instantiate an object of type `Ma97` and perform the symbolic analysis on a matrix described in sparse CSC format.

## Input arguments

* `n::Int`: the matrix size
* `colptr::Vector{T<:Integer}`: CSC colptr array for the lower triangle
* `rowval::Vector{T<:Integer}`: CSC rowval array for the lower triangle
* `nzval::Vector{T<:Ma97Data}`: CSC nzval array for the lower triangle

## Keyword arguments

All keyword arguments are passed directly to the `Ma97_Control` constructor.
"""
ma97_csc


"""# Instantiate and perform symbolic analysis using coordinate arrays

    M = ma97_coord(n, cols, rows, nzval; kwargs...)

Instantiate an object of type `Ma97` and perform the symbolic analysis on a matrix described in sparse coordinate format.

## Input arguments

* `n::Int`: the matrix size
* `cols::Vector{T<:Integer}`: array of column indices for the lower triangle
* `rows::Vector{T<:Integer}`: array of row indices for the lower triangle
* `nzval::Vector{T<:Ma97Data}`: array of values for the lower triangle

## Keyword arguments

All keyword arguments are passed directly to the `Ma97_Control` constructor.
"""
ma97_coord


"""# Perform numerical factorization.

    ma97_factorize!(ma97; kwargs...)

The symbolic analysis must have been performed and must have succeeded.

## Input Arguments

* `ma97::Ma97{T<:Ma97Data}`:: an `Ma97` structure for which the analysis has been performed

## Keyword Arguments

* `matrix_type::Symbol=:real_indef`: indicates the matrix type. Accepted values are
  * `:real_spd` for a real symmetric and positive definite matrix
  * `:real_indef` for a real symmetric and indefinite matrix.
"""
ma97_factorize!


"""ma97_factorise!: see the documentation for `ma97_factorize!`.
"""
ma97_factorise!


"""# Combined Analysis and factorization

  M = ma97_factorize(A; kwargs...)

Convenience method that combines the symbolic analysis and numerical
factorization phases. An MA97 instance is returned, that can subsequently
be passed to other functions, e.g., `ma97_solve()`.

## Input Arguments

* `A::SparseMatrixCSC{T<:Ma97Data,Int}`: Julia sparse matrix

## Keyword Arguments

* `matrix_type::Symbol=:real_indef`: indicates the matrix type. Accepted values are
  * `:real_spd` for a real symmetric and positive definite matrix
  * `:real_indef` for a real symmetric and indefinite matrix.
"""
ma97_factorize


"""ma97_factorise: see the documentation for `ma97_factorize`.
"""
ma97_factorise


"""# In-place system solve

See the documentation for `ma97_solve()`. The only difference is that the right-hand side `b` is overwritten with the solution.
"""
ma97_solve!


"""# System solve

## Solve after factorization

    ma97_solve(ma97, b; kwargs...)

### Input arguments

* `ma97::Ma97{T<:Ma97Data}`: an `Ma97` structure for which the analysis and factorization have been performed
* `b::Array{T}`: vector of array of right-hand sides. Note that `b` will be overwritten. To solve a system with multiple right-hand sides, `b` should have size `n` by `nrhs`.

### Keyword arguments

* `job::Symbol=:A`: task to perform. Accepted values are
  * `:A`: solve Ax = b
  * `:PL`: solve PLx = Sb
  * `:D`: solve Dx = b
  * `:LPS`: solve L'P'S⁻¹x = b
  * `:DLPS`: solve DL'P'S⁻¹x = b.

### Return values

* `x::Array{T}`: an array of the same size as `b` containing the solutions.

## Combined analysis, factorization and solve

    ma97_solve(A, b; kwargs...)

### Input arguments

* `A::SparseMatrixCSC{T<:Ma97Data,Int}`: input matrix. A full matrix will be converted to sparse.
* `b::Array{T}`: vector of array of right-hand sides. Note that `b` will be overwritten. To solve a system with multiple right-hand sides, `b` should have size `n` by `nrhs`.

### Keyword arguments

* `matrix_type::Symbol=:real_indef`: indicates the matrix type. Accepted values are
  * `:real_spd` for a real symmetric and positive definite matrix
  * `:real_indef` for a real symmetric and indefinite matrix.

### Return values

* `x::Array{T}`: an array of the same size as `b` containing the solutions.
"""
ma97_solve


"""# Inquire about a factorization or solve

    ma97_inquire(ma97; kwargs...)

Obtain information on the pivots after a successful factorization or solve.

## Input Arguments

* `ma97::Ma97{T<:Ma97Data}`: an `Ma97` structure for which the analysis and factorization have been performed

## Keyword arguments

* `matrix_type::Symbol=:real_indef`: indicates the matrix type. Accepted values are
  * `:real_spd` for a real symmetric and positive definite matrix
  * `:real_indef` for a real symmetric and indefinite matrix.

## Return values

An inquiry on a real or complex indefinite matrix returns two vectors:

* `piv_order`: contains the pivot sequence; a negative value indicates that the
  corresponding variable is part of a 2x2 pivot,
* `d`: a `2` by `n` array whose first row contains the diagonal of D⁻¹ in the
  factorization, and whose nonzeros in the second row contain the off-diagonals.

An inquiry on a positive definite matrix returns one vector with the pivot values.
"""
ma97_inquire


"""ma97_enquire: see the documentation for `ma97_inquire`.
"""
ma97_enquire
