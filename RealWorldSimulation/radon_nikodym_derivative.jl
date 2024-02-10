
"""
    radon_nikodym_derivative(
        x::AbstractMatrix,
        μ::AbstractVector,
        ν::AbstractVector;
        w_min::Number = 1.0e-2,
        ϵ::Number = 1.0e-3,
        y_tol::Number = 1.0e-4,
        s_tol::Number = 1.0e-4,
        arc_tol::Number = 1.0e-4,
        step_tol_y::Number = 1.0e-8,
        step_tol_s::Number = 1.0e-8,
        max_iter::Integer = 100,
        )

Calculate the Radon-Nikodyn derivative.

`x` is a matrix of realisations sampled in original probability measure.
Size of `x` is (p, n). Here, p is the number of sample paths and n is
the number of random variables.

`μ` is a vector of target expectations with size (n,).

`ν` is a vector of target standard deviations with size (n,). If
elements in `ν` are less or equal zero then this element is excluded
from optimisation.

`w_min` is the minimum value for Radon-Nikodyn derivative.

`ϵ` is a floor to calculate the scaling coefficients for target values. 

`y_tol` is optimisation tolerance for residuum.

`s_tol` is optimisation tolerance for step direction.

`arc_tol` is optimisation tolerance for angle of step direction and
equality constraint sub-space.

`step_tol_y` is optimisation tolerance on improvement in residuum
minimisation.

`step_tol_s` is optimistion tolerance on iteration steps.

`max_iter` is the maximum number of iterations.

`method` specifies the variant of step direction calculation for
optimisation. Supported values are `LEASTSQARES` and `GRADIENT`.

Tolerances are tested against ||.||_∞ norm.

Method returns a named tuple with the folowing elements:

A vector `w` of length p representing the Radon-Nikodyn derivative.

A scalar element `convergene` which encodes the condition that is used
to determine convergence of the iteration.

A vector of named tuples `history` which encodes the convergence
histor of the iteration.
"""
function radon_nikodym_derivative(
    x::AbstractMatrix,
    μ::AbstractVector,
    ν::AbstractVector;
    w_min::Number = 1.0e-2,
    ϵ::Number = 1.0e-3,
    y_tol::Number = 1.0e-4,
    s_tol::Number = 1.0e-4,
    arc_tol::Number = 1.0e-4,
    step_tol_y::Number = 1.0e-8,
    step_tol_s::Number = 1.0e-8,
    max_iter::Integer = 100,
    method::String = "LEASTSQUARES"
    )
    #
    (p, n) = size(x)
    @assert p > 0
    @assert n > 0
    @assert length(μ) == n
    @assert length(ν) == n
    method = uppercase(method)
    @assert method in ("LEASTSQUARES", "GRADIENT")
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
    # add equality constraint for initial iteration
    M = vcat(a0', M)
    e = vcat(1.0, e)
    # initial iteration
    w0 = ones(p)
    r0 = M * w0 - e
    s = - pinv(M) * r0
    w1 = w0 + s
    # for subsequent iterations
    M = d1 .* a1'
    e = d1 .* b1
    r0 = M * w0 - e
    Mplus = pinv(M)
    history = []
    convergence = -1 # fall-back, no convergence after max_iter iterations
    for iter in 1:max_iter
        # project new iteration
        # ensure equality contraint
        w1 = w1 .+ (1.0 - sum(w1)/p)
        if any(w1 .< w_min)
            # ensure inequality constrains
            f(λ) = sum(max.(w1 .+ λ, w_min)) / p - 1.0
            λ0 = 1.0 - maximum(w1)
            λ1 = 0.0
            λ = find_zero(f, (λ0, λ1), Roots.Brent(), xatol=1.0e-8)
            w1 = max.(w1 .+ λ, w_min)
        end
        # calculate new step direction
        r1 = M * w1 - e
        if method == "LEASTSQUARES"
            s = -Mplus * r1
        end
        if method == "GRADIENT"
            g = M' * r1
            Mg = M * g
            λ = (g' * g) / (Mg' * Mg)
            s = -λ * g  # Cauchy point
        end
        # gradient step calculations
        #

        arc = sum(s) / sqrt(s' * s) / sqrt(p)
        step_y = r1 - r0
        step_s = w1 - w0
        state = (
            i = iter,
            y = maximum(abs.(r1)),
            s = maximum(abs.(s)),
            arc = arc,
            step_y = maximum(abs.(step_y)),
            step_s = maximum(abs.(step_s)),
        )
        push!(history, state)
        # println(state)
        #
        w0 = w1
        r0 = r1
        w1 = w1 + s
        # check convergence
        if state.y ≤ y_tol
            convergence = 1
            break
        end
        if state.s ≤ s_tol
            convergence = 2
            break
        end
        if abs(abs(state.arc) - 1.0) ≤ arc_tol
            convergence = 3
            break
        end
        if state.step_y ≤ step_tol_y
            convergence = 4
            break
        end
        if state.step_s ≤ step_tol_s
            convergence = 5
            break
        end
    end
    return (
        w = w0,
        convergence = convergence,
        history = history,
    )
end
