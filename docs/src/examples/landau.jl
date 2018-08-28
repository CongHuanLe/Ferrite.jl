# # Ginzburg-Landau model energy minimization
# In this example a basic Ginzburg-Landau model is solved.
# This example gives an idea of how the API together with ForwardDiff can be leveraged to
# performantly solve non standard problems on a FEM grid.
# A large portion of the code is there only for performance reasons,
# but since this usually really matters and is what takes the most time to optimize,
# it is included.

# The key to using a method like this for minimizing a free energy function directly,
# rather than the weak form, as is usually done with FEM, is to split up the
# gradient and Hessian calculations.
# This means that they are performed for each cell seperately instead of for the
# grid as a whole.

using ForwardDiff
import ForwardDiff: GradientConfig, HessianConfig, Chunk
using JuAFEM
using Optim, LineSearches
using Tensors
using Base.Threads
# ## Energy terms
# ### 4th order Landau free energy
function Fl(P::Vec{3, T}, α::Vec{3}) where T
    P2 = Vec{3, T}((P[1]^2, P[2]^2, P[3]^2))
    return (α[1] * sum(P2) +
           α[2] * (P[1]^4 + P[2]^4 + P[3]^4)) +
           α[3] * ((P2[1] * P2[2]  + P2[2]*P2[3]) + P2[1]*P2[3])
end
# ### Ginzburg free energy
@inline Fg(∇P, G) = 0.5(∇P ⊡ G) ⊡ ∇P
# ### GL free energy
F(P, ∇P, params)  = Fl(P, params.α) + Fg(∇P, params.G)

# ### Parameters that characterize the model
struct ModelParams{V, T}
    α::V
    G::T
end

# ## Caches
# ### Element cache
# This is mainly done so that it's possible to easily
# redefine the elpotential for the AutomaticDifferentiation, and circumvent closure-related
# issues and allocations.
mutable struct CellCache{CV, MP, F <: Function}
    cvP::CV
    params::MP
    elpotential::F
    function CellCache(cvP::CV, params::MP, elpotential::Function) where {CV, MP}
        potfunc = x -> elpotential(x, cvP, params)
        return new{CV, MP, typeof(potfunc)}(cvP, params, potfunc)
    end
end

# ### ThreadCache
# This holds the values that each thread will use during the assembly.
struct ThreadCache{T, DIM, CC <: CellCache, GC <: GradientConfig, HC <: HessianConfig}
    dofindices       ::Vector{Int}
    element_dofs     ::Vector{T}
    element_gradient ::Vector{T}
    element_hessian  ::Matrix{T}
    cellcache        ::CC
    gradconf         ::GC
    hessconf         ::HC
    element_coords   ::Vector{Vec{DIM, T}}
end
function ThreadCache(dpc::Int, nodespercell,  args...)
    dofindices       = zeros(Int, dpc)
    element_dofs     = zeros(dpc)
    element_gradient = zeros(dpc)
    element_hessian  = zeros(dpc, dpc)
    cellcache        = CellCache(args...)
    gradconf         = GradientConfig(nothing, zeros(12), Chunk{12}())
    hessconf         = HessianConfig(nothing, zeros(12), Chunk{12}())
    coords           = zeros(Vec{3}, nodespercell)
    return ThreadCache(dofindices, element_dofs, element_gradient, element_hessian, cellcache, gradconf, hessconf, coords )
end

# ## The Model
# everything is combined into a model.
mutable struct LandauModel{T, DH <: DofHandler, CH <: ConstraintHandler, TC <: ThreadCache}
    dofs          ::Vector{T}
    dofhandler    ::DH
    boundaryconds ::CH
    threadindices ::Vector{Vector{Int}}
    threadcaches  ::Vector{TC}
end

function LandauModel(α, G, gridsize, left::Vec{DIM, T}, right::Vec{DIM, T}, elpotential) where {DIM, T}
    grid = generate_grid(Tetrahedron, gridsize, left, right)
    questionmark, threadindices = JuAFEM.create_coloring(grid)

    qr  = QuadratureRule{DIM, RefTetrahedron}(2)
    cvP = CellVectorValues(qr, Lagrange{DIM, RefTetrahedron, 1}())

    dofhandler = DofHandler(grid)
    push!(dofhandler, :P, 3)
    close!(dofhandler)

    dofvector = zeros(ndofs(dofhandler))
    startingconditions!(dofvector, dofhandler)
    boundaryconds = ConstraintHandler(dofhandler)
    #boundary conditions can be added but aren't necessary for optimization
    #add!(boundaryconds, Dirichlet(:P, getfaceset(grid, "left"), (x, t) -> [0.0,0.0,0.53], [1,2,3]))
    #add!(boundaryconds, Dirichlet(:P, getfaceset(grid, "right"), (x, t) -> [0.0,0.0,-0.53], [1,2,3]))
    close!(boundaryconds)
    update!(boundaryconds, 0.0)

    apply!(dofvector, boundaryconds)

    hessian = create_sparsity_pattern(dofhandler)
    dpc = ndofs_per_cell(dofhandler)
    cpc = length(grid.cells[1].nodes)
    caches = [ThreadCache(dpc, cpc, copy(cvP), ModelParams(α, G), elpotential) for t=1:nthreads()]
    return LandauModel(dofvector, dofhandler, boundaryconds, threadindices, caches)
end

# utility to quickly save a model
function JuAFEM.vtk_save(path, model, dofs=model.dofs)
    vtkfile = vtk_grid(path, model.dofhandler)
    vtk_point_data(vtkfile, model.dofhandler, dofs)
    vtk_save(vtkfile)
end

# ## Assembly
# This macro defines most of the assembly step, since the structure is the same for
# the energy, gradient and Hessian calculations.
macro assemble!(innerbody)
    esc(quote
        dofhandler = model.dofhandler
        for indices in model.threadindices
            @threads for i in indices
                cache  = model.threadcaches[threadid()]
                cellcache = cache.cellcache
                eldofs = cache.element_dofs
                nodeids = dofhandler.grid.cells[i].nodes
                for j=1:length(cache.element_coords)
                    cache.element_coords[j] = dofhandler.grid.nodes[nodeids[j]].x
                end
                reinit!(cellcache.cvP, cache.element_coords)

                celldofs!(cache.dofindices, dofhandler, i)
                for j=1:length(cache.element_dofs)
                    eldofs[j] = dofvector[cache.dofindices[j]]
                end
                $innerbody
            end
        end
    end)
end

# This calculates the total energy calculation of the grid
function F(dofvector::Vector{T}, model) where T
    outs = fill(zero(T), nthreads())
    @assemble! begin
        outs[threadid()] += cache.cellcache.elpotential(eldofs)
    end
    return sum(outs)
end

# The gradient calculation for each dof
function ∇F!(∇f::Vector{T}, dofvector::Vector{T}, model::LandauModel{T}) where T
    fill!(∇f, zero(T))
    @assemble! begin
        ForwardDiff.gradient!(cache.element_gradient, cellcache.elpotential, eldofs, cache.gradconf)

        @inbounds assemble!(∇f, cache.dofindices, cache.element_gradient)
    end
end

# The Hessian calculation for the whole grid
function ∇²F!(∇²f::SparseMatrixCSC, dofvector::Vector{T}, model::LandauModel{T}) where T
    assemblers = [start_assemble(∇²f) for t=1:nthreads()]
    @assemble! begin
        ForwardDiff.hessian!(cache.element_hessian, cellcache.elpotential, eldofs, cache.hessconf)
        @inbounds assemble!(assemblers[threadid()], cache.dofindices, cache.element_hessian)
    end
end

# ## Minimization
# Now everything can be combined to minimize the energy, and find the equilibrium
# configuration.
function minimize!(model; kwargs...)
    dh = model.dofhandler
    dofs = model.dofs
    ∇f = fill(0.0, length(dofs))
    ∇²f = create_sparsity_pattern(dh)
    function g!(storage, x)
        ∇F!(storage, x, model)
        apply_zero!(storage, model.boundaryconds)
    end
    function h!(storage, x)
        ∇²F!(storage, x, model)
        apply!(storage, model.boundaryconds)
    end
    f(x) = F(x, model)

    od = TwiceDifferentiable(f, g!, h!, model.dofs, 0.0, ∇f, ∇²f)

    #this way of minimizing is kind of beneficial when the initial guess is completely off,
    #quick couple of ConjuageGradient steps brings us easily closer to the minimum.
    res = optimize(od, model.dofs, ConjugateGradient(linesearch=BackTracking()), Optim.Options(show_trace=true, show_every=1, g_tol=1e-20, iterations=50))
    model.dofs .= res.minimizer
    #to get the final convergence, Newton's method is more ideal since the energy landscape should be almost parabolic
    res = optimize(od, model.dofs, Newton(linesearch=BackTracking()), Optim.Options(show_trace=true, show_every=1, g_tol=1e-20))
    model.dofs .= res.minimizer
    return res
end

# ## Testing it
# This calculates the contribution of each element to the total energy,
# it is also the function that will be put through ForwardDiff for the gradient and Hessian.
function element_potential(eldofs::AbstractVector{T}, cvP, params) where T
    energy = zero(T)
    for qp=1:getnquadpoints(cvP)
        P  = function_value(cvP, qp, eldofs)
        ∇P = function_gradient(cvP, qp, eldofs)
        energy += F(P, ∇P, params) * getdetJdV(cvP, qp)
    end
    return energy
end

# now we define some starting conditions
function startingconditions!(dofvector, dofhandler)
    for cell in CellIterator(dofhandler)
        globaldofs = celldofs(cell)
        it = 1
        for i=1:3:length(globaldofs)
            dofvector[globaldofs[i]]   = -2.0
            dofvector[globaldofs[i+1]] = 2.0
            dofvector[globaldofs[i+2]] = -2.0tanh(cell.coords[it][1]/20)
            it += 1
        end
    end
end

δ(i, j) = i == j ? one(i) : zero(i)
V2T(p11, p12, p44) = Tensor{4, 3}((i,j,k,l) -> p11 * δ(i,j)*δ(k,l)*δ(i,k) + p12*δ(i,j)*δ(k,l)*(1 - δ(i,k)) + p44*δ(i,k)*δ(j,l)*(1 - δ(i,j)))

const G = V2T(1.0e2, 0.0, 1.0e2)
const α = Vec{3}((-1.0, 1.0, 1.0))
left = Vec{3}((-75.,-25.,-2.))
right = Vec{3}((75.,25.,2.))
model = LandauModel(alphatest, Gtest, (10, 10, 2), left, right, element_potential)

vtk_save(homedir()*"/landauorig", model)
minimize!(model)
vtk_save(homedir()*"/landaufinal", model)

# as we can see this runs very quickly even for relatively large gridsizes.
# The key to get high performance like this is to minimize the allocations inside the threaded loops,
# ideally to 0.