abstract FunctionSpace{dim, shape, order}

@inline n_dim{dim, shape, order}(fs::FunctionSpace{dim, shape, order}) = dim
@inline ref_shape{order, shape, dim}(fs::FunctionSpace{dim, shape, order}) = shape()
@inline order{dim, shape, order}(fs::FunctionSpace{dim, shape, order}) = order

"""
Computes the value of the shape functions at a point ξ for a given function space
"""
function value(fs::FunctionSpace, ξ::Vector)
    value!(fs, zeros(eltype(ξ), n_basefunctions(fs)), ξ)
end

"""
Computes the gradients of the shape functions at a point ξ for a given function space
"""
function derivative(fs::FunctionSpace, ξ::Vector)
    derivative!(fs, zeros(eltype(ξ), n_dim(fs), n_basefunctions(fs)), ξ)
end

@inline function checkdim_value{dim}(fs::FunctionSpace{dim}, N::Vector, ξ::Vector)
    n_base = n_basefunctions(fs)
    length(N) == n_base || throw(ArgumentError("N must have length $(n_base)"))
    length(ξ) == dim || throw(ArgumentError("ξ must have length $dim"))
end

@inline function checkdim_derivative{dim}(fs::FunctionSpace{dim}, dN::Matrix, ξ::Vector)
    n_base = n_basefunctions(fs)
    size(dN) == (dim, n_base) || throw(ArgumentError("dN must have size ($dim, $n_base)"))
    length(ξ) == dim || throw(ArgumentError("ξ must have length $dim"))
end

############
# Lagrange
############

type Lagrange{dim, shape, order} <: FunctionSpace{dim, shape, order} end

#################################
# Lagrange dim 1 Square order 1 #
#################################

n_basefunctions(::Lagrange{1, Square, 1}) = 2

function value!(fs::Lagrange{1, Square, 1}, N::Vector, ξ::Vector)
    checkdim_value(fs, N, ξ)

    @inbounds begin
        ξ_x = ξ[1]

        N[1] = (1 - ξ_x) * 0.5
        N[2] = (1 + ξ_x) * 0.5
    end

    return N
end

function derivative!(fs::Lagrange{1, Square, 1}, dN::Matrix, ξ::Vector)
    checkdim_derivative(fs, dN, ξ)

    @inbounds begin
        ξ_x = ξ[1]

        dN[1,1] = -0.5
        dN[1,2] =  0.5
    end

    return dN
end

#################################
# Lagrange dim 1 Square order 2 #
#################################

n_basefunctions(::Lagrange{1, Square, 2}) = 3

function value!(fs::Lagrange{1, Square, 2}, N::Vector, ξ::Vector)
    checkdim_value(fs, N, ξ)

    @inbounds begin
        ξ_x = ξ[1]

        N[1] = ξ_x * (ξ_x - 1) * 0.5
        N[2] = 1 - ξ_x^2
        N[3] = ξ_x * (ξ_x + 1) * 0.5
    end

    return N
end



function derivative!(fs::Lagrange{1, Square, 2}, dN::Matrix, ξ::Vector)
    checkdim_derivative(fs, dN, ξ)

    @inbounds begin
        ξ_x = ξ[1]

        dN[1,1] = ξ_x - 0.5
        dN[1,2] = -2 * ξ_x
        dN[1,3] = ξ_x + 0.5
    end

    return dN
end

#################################
# Lagrange dim 2 Square order 1 #
#################################

n_basefunctions(::Lagrange{2, Square, 1}) = 4

function value!(fs::Lagrange{2, Square, 1}, N::Vector, ξ::Vector)
    checkdim_value(fs, N, ξ)

    @inbounds begin
        ξ_x = ξ[1]
        ξ_y = ξ[2]

        N[1] = (1 + ξ_x) * (1 + ξ_y) * 0.25
        N[2] = (1 - ξ_x) * (1 + ξ_y) * 0.25
        N[3] = (1 - ξ_x) * (1 - ξ_y) * 0.25
        N[4] = (1 + ξ_x) * (1 - ξ_y) * 0.25
    end

    return N
end

function derivative!(fs::Lagrange{2, Square, 1}, dN::Matrix, ξ::Vector)
    checkdim_derivative(fs, dN, ξ)

    @inbounds begin
        ξ_x = ξ[1]
        ξ_y = ξ[2]

        dN[1,1] =  (1 + ξ_y) * 0.25
        dN[2,1] =  (1 + ξ_x) * 0.25

        dN[1,2] = -(1 + ξ_y) * 0.25
        dN[2,2] =  (1 - ξ_x) * 0.25

        dN[1,3] = -(1 - ξ_y) * 0.25
        dN[2,3] = -(1 - ξ_x) * 0.25

        dN[1,4] =  (1 - ξ_y) * 0.25
        dN[2,4] = -(1 + ξ_x) * 0.25
    end

    return dN
end

###################################
# Lagrange dim 2 Triangle order 1 #
###################################

n_basefunctions(::Lagrange{2, Triangle, 1}) = 3

function value!(fs::Lagrange{2, Triangle, 1}, N::Vector, ξ::Vector)
    checkdim_value(fs, N, ξ)

    @inbounds begin
        ξ_x = ξ[1]
        ξ_y = ξ[2]

        N[1] = ξ_x
        N[2] = ξ_y
        N[3] = 1.0 - ξ_x - ξ_y
    end

    return N
end

function derivative!(fs::Lagrange{2, Triangle, 1}, dN::Matrix, ξ::Vector)
    checkdim_derivative(fs, dN, ξ)

    @inbounds begin
        dN[1,1] =  1.0
        dN[2,1] =  0.0

        dN[1,2] = 0.0
        dN[2,2] = 1.0

        dN[1,3] = -1.0
        dN[2,3] = -1.0
    end

    return dN
end

###################################
# Lagrange dim 2 Triangle order 2 #
###################################

n_basefunctions(::Lagrange{2, Triangle, 2}) = 6

function value!(fs::Lagrange{2, Triangle, 2}, N::Vector, ξ::Vector)
    checkdim_value(fs, N, ξ)

    @inbounds begin
        ξ_x = ξ[1]
        ξ_y = ξ[2]

        γ = 1 - ξ_x - ξ_y

        N[1] = ξ_x * (2ξ_x - 1)
        N[2] = ξ_y * (2ξ_y - 1)
        N[3] = γ * (2γ - 1)
        N[4] = 4ξ_x * ξ_y
        N[5] = 4ξ_y * γ
        N[6] = 4ξ_x * γ
    end

    return N
end

function derivative!(fs::Lagrange{2, Triangle, 2}, dN::Matrix, ξ::Vector)
    checkdim_derivative(fs, dN, ξ)

    @inbounds begin

        ξ_x = ξ[1]
        ξ_y = ξ[2]

        γ = 1 - ξ_x - ξ_y

        dN[1, 1] = 4ξ_x - 1
        dN[1, 2] = 0
        dN[1, 3] = -4γ + 1
        dN[1, 4] = 4ξ_y
        dN[1, 5] = -4ξ_y
        dN[1, 6] = 4(γ - ξ_x)

        dN[2, 1] = 0
        dN[2, 2] = 4ξ_y - 1
        dN[2, 3] = -4γ + 1
        dN[2, 4] = 4ξ_x
        dN[2, 5] = 4(γ - ξ_y)
        dN[2, 6] = -4ξ_x
    end

    return dN
end


###################################
# Lagrange dim 3 Square order 1 #
###################################

n_basefunctions(::Lagrange{3, Square, 1}) = 8

function value!(fs::Lagrange{3, Square, 1}, N::Vector, ξ::Vector)
    checkdim_value(fs, N, ξ)

    @inbounds begin
        ξ_x = ξ[1]
        ξ_y = ξ[2]
        ξ_z = ξ[3]

        N[1]  = 0.125(1 - ξ_x) * (1 - ξ_y) * (1 - ξ_z)
        N[2]  = 0.125(1 + ξ_x) * (1 - ξ_y) * (1 - ξ_z)
        N[3]  = 0.125(1 + ξ_x) * (1 + ξ_y) * (1 - ξ_z)
        N[4]  = 0.125(1 - ξ_x) * (1 + ξ_y) * (1 - ξ_z)
        N[5]  = 0.125(1 - ξ_x) * (1 - ξ_y) * (1 + ξ_z)
        N[7]  = 0.125(1 + ξ_x) * (1 + ξ_y) * (1 + ξ_z)
        N[6]  = 0.125(1 + ξ_x) * (1 - ξ_y) * (1 + ξ_z)
        N[8]  = 0.125(1 - ξ_x) * (1 + ξ_y) * (1 + ξ_z)
    end

    return N
end

function derivative!(fs::Lagrange{3, Square, 1}, dN::Matrix, ξ::Vector)
    checkdim_derivative(fs, dN, ξ)

    @inbounds begin
        ξ_x = ξ[1]
        ξ_y = ξ[2]
        ξ_z = ξ[3]

        dN[1, 1] = -0.125(1 - ξ_y) * (1 - ξ_z)
        dN[1, 2] =  0.125(1 - ξ_y) * (1 - ξ_z)
        dN[1, 3] =  0.125(1 + ξ_y) * (1 - ξ_z)
        dN[1, 4] = -0.125(1 + ξ_y) * (1 - ξ_z)
        dN[1, 5] = -0.125(1 - ξ_y) * (1 + ξ_z)
        dN[1, 6] =  0.125(1 - ξ_y) * (1 + ξ_z)
        dN[1, 7] =  0.125(1 + ξ_y) * (1 + ξ_z)
        dN[1, 8] = -0.125(1 + ξ_y) * (1 + ξ_z)

        dN[2, 1] = -0.125(1 - ξ_x) * (1 - ξ_z)
        dN[2, 2] = -0.125(1 + ξ_x) * (1 - ξ_z)
        dN[2, 3] =  0.125(1 + ξ_x) * (1 - ξ_z)
        dN[2, 4] =  0.125(1 - ξ_x) * (1 - ξ_z)
        dN[2, 5] = -0.125(1 - ξ_x) * (1 + ξ_z)
        dN[2, 6] = -0.125(1 + ξ_x) * (1 + ξ_z)
        dN[2, 7] =  0.125(1 + ξ_x) * (1 + ξ_z)
        dN[2, 8] =  0.125(1 - ξ_x) * (1 + ξ_z)

        dN[3, 1] = -0.125(1 - ξ_x) * (1 - ξ_y)
        dN[3, 2] = -0.125(1 + ξ_x) * (1 - ξ_y)
        dN[3, 3] = -0.125(1 + ξ_x) * (1 + ξ_y)
        dN[3, 4] = -0.125(1 - ξ_x) * (1 + ξ_y)
        dN[3, 5] =  0.125(1 - ξ_x) * (1 - ξ_y)
        dN[3, 6] =  0.125(1 + ξ_x) * (1 - ξ_y)
        dN[3, 7] =  0.125(1 + ξ_x) * (1 + ξ_y)
        dN[3, 8] =  0.125(1 - ξ_x) * (1 + ξ_y)
    end

    return dN
end


####################################
# Serendipity dim 2 Square order 2 #
####################################

type Serendipity{dim, shape, order} <: FunctionSpace{dim, shape, order} end

n_basefunctions(::Serendipity{2, Square, 2}) = 8

function value!(fs::Serendipity{2, Square, 2}, N::Vector, ξ::Vector)
    checkdim_value(fs, N, ξ)

    ξ_x = ξ[1]
    ξ_y = ξ[2]

    @inbounds begin
        N[1] = (1 - ξ_x) * (1 - ξ_y) * 0.25(-ξ_x - ξ_y - 1)
        N[2] = (1 + ξ_x) * (1 - ξ_y) * 0.25( ξ_x - ξ_y - 1)
        N[3] = (1 + ξ_x) * (1 + ξ_y) * 0.25( ξ_x + ξ_y - 1)
        N[4] = (1 - ξ_x) * (1 + ξ_y) * 0.25(-ξ_x + ξ_y - 1)
        N[6] = 0.5(1 + ξ_x) * (1 - ξ_y * ξ_y)
        N[5] = 0.5(1 - ξ_x * ξ_x) * (1 - ξ_y)
        N[7] = 0.5(1 - ξ_x * ξ_x) * (1 + ξ_y)
        N[8] = 0.5(1 - ξ_x) * (1 - ξ_y * ξ_y)
    end
    return N
end

function derivative!(fs::Serendipity{2, Square, 2}, dN::Matrix, ξ::Vector)
    checkdim_derivative(fs, dN, ξ)

    ξ_x = ξ[1]
    ξ_y = ξ[2]

    @inbounds begin
        dN[1, 1] = -0.25(1 - ξ_y) * (-2ξ_x - ξ_y)
        dN[1, 2] =  0.25(1 - ξ_y) * ( 2ξ_x - ξ_y)
        dN[1, 3] =  0.25(1 + ξ_y) * ( 2ξ_x + ξ_y)
        dN[1, 4] = -0.25(1 + ξ_y) * (-2ξ_x + ξ_y)
        dN[1, 5] = -ξ_x*(1 - ξ_y)
        dN[1, 6] =  0.5(1 - ξ_y * ξ_y)
        dN[1, 7] = -ξ_x*(1 + ξ_y)
        dN[1, 8] = -0.5(1 - ξ_y * ξ_y)

        dN[2, 1] = -0.25(1 - ξ_x) * (-2ξ_y - ξ_x)
        dN[2, 2] = -0.25(1 + ξ_x) * (-2ξ_y + ξ_x)
        dN[2, 3] =  0.25(1 + ξ_x) * ( 2ξ_y + ξ_x)
        dN[2, 4] =  0.25(1 - ξ_x) * ( 2ξ_y - ξ_x)
        dN[2, 5] = -0.5(1 - ξ_x * ξ_x)
        dN[2, 6] = -ξ_y*(1 + ξ_x)
        dN[2, 7] =  0.5(1 - ξ_x * ξ_x)
        dN[2, 8] = -ξ_y*(1 - ξ_x)
    end
    return dN
end