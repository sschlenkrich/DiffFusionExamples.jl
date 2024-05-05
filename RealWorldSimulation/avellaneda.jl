
"""
    weights(λ, M)

Calculate Radon Nikodym weights using Avellaneda parametrisation.

See Avellaneda et.al, 2001, equation (17).
"""
function weights(λ, M)
    w = exp.(M' * λ)
    return w ./ sum(w) .* length(w)
end


"""
    objective_F(λ, p)

Objective function for F(λ) = 0. This function is the input to the
least squares problem specification. 
"""
function objective_F(λ, p)
    w = weights(λ, p.M)
    return p.M * w .- p.e
end


"""
    avellaneda(
        x::AbstractMatrix,
        μ::AbstractVector,
        ν::AbstractVector;
        ϵ::Number = 1.0e-3,
        reltol = 1e-8,
        abstol = 1e-8,
        method = FastShortcutNLLSPolyalg(),
        )

Calculate the Radon-Nikodyn derivative using the weight parametrisation from
M. Avellaneda et.al., Weighted Monte Carlo, Journal of Theoretical and
Applied Finance, 2001.

`x` is a matrix of realisations sampled in original probability measure.
Size of `x` is (p, n). Here, p is the number of sample paths and n is
the number of random variables.

`μ` is a vector of target expectations with size (n,).

`ν` is a vector of target standard deviations with size (n,). If
elements in `ν` are less or equal zero then this element is excluded
from optimisation.

`ϵ` is a floor to calculate the scaling coefficients for target values. 

`reltol`, `abstol` and `method` are passed on to the `solve(...)`
function from NonlinearSolve.jl.
"""
function avellaneda(
    x::AbstractMatrix,
    μ::AbstractVector,
    ν::AbstractVector;
    ϵ::Number = 1.0e-3,
    reltol = 1e-8,
    abstol = 1e-8,
    method = FastShortcutNLLSPolyalg(),
    )
    #
    (p, n) = size(x)
    @assert p > 0
    @assert n > 0
    @assert length(μ) == n
    @assert length(ν) == n
    #
    a0 = ones(p) ./ p
    b0 = 1.0
    #
    a1 = x ./ p
    b1 = μ
    d1 = sign.(b1) ./ max.(abs.(b1), ϵ)
    #
    for k in 1:n
        if ν[k] > 0.0
            a2 = x[:,k] .* x[:,k] ./ p
            b2 = ν[k]^2 + μ[k]^2
            d2 = sign(b2) / max(abs(b2), ϵ^2)
            #
            a1 = hcat(a1, a2)
            b1 = vcat(b1, b2)
            d1 = vcat(d1, d2)
        end
    end
    # @info "" size(a1) size(b1)
    #
    M = d1 .* a1'
    e = d1 .* b1
    #
    λ = zeros(length(e))
    p = (M = M, e = e)
    prob = NonlinearLeastSquaresProblem(NonlinearFunction(objective_F), λ, p)
    res = solve(prob, method, reltol = reltol, abstol = abstol)
    #
    w = weights(res.u, p.M)
    return (
        w = w,
        convergence = res.retcode,
        details = res,
    )
end