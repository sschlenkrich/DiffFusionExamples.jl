using DataFrames
using DiffFusion
using ForwardDiff
using Printf

include("volatilities.jl")
include("quasi_gaussian.jl")

@info "Run Quasi-Gaussian Calibration."

ch = DiffFusion.correlation_holder("Std")
DiffFusion.set_correlation!(ch, "EUR_f_1", "EUR_f_2", 0.8)
DiffFusion.set_correlation!(ch, "EUR_f_2", "EUR_f_3", 0.8)
DiffFusion.set_correlation!(ch, "EUR_f_1", "EUR_f_3", 0.5)
#
delta = DiffFusion.flat_parameter([ 1., 7., 15. ])
chi = DiffFusion.flat_parameter([ 0.01, 0.10, 0.30 ])
quanto_model = nothing

# volatility parameters
model_times = [1.0, 2.0, 5.0, 10.0]
d = size(delta.values, 1)
n = length(model_times)

sigma_f = DiffFusion.backward_flat_volatility(
    "Std",
    model_times,
    80.0e-4 .* ones(d, n),
)

slope_d = DiffFusion.backward_flat_parameter(
    "Std",
    model_times,
    -5.0e-2 .* ones(d, n),
)

slope_u = DiffFusion.backward_flat_parameter(
    "Std",
    model_times,
    5.0e-2 .* ones(d, n),
)

sigma_min = 1.0e-4
sigma_max = 500. * 1.0e-4

# an initial reference model
model = DiffFusion.quasi_gaussian_multi_factor_model(
    "Std",
    delta,
    chi,
    sigma_f,
    slope_d,
    slope_u,
    sigma_min,
    sigma_max,
    ch,
    nothing,                       # quanto_model
    DiffFusion.ForwardRateScaling, # scaling_type
    nothing,                       # volatility_model
    nothing,                       # volatility_function
)

# parameters
exercise_times = [ 5.0, 10.0 ]
swap_times = [1.0, 2.0, 5.0, 10.0]
rel_strikes = [ -100., -50., -20., 0.0, 20., 50., 100. ] .* 1e-4
yts = DiffFusion.flat_forward(0.0400)
end_time = 10.0
step_size = 1.0
n_paths = 2^10

# objective function
function F_implied_volatilities(x)
    return implied_volatilities(
        x,
        exercise_times,
        swap_times,
        rel_strikes,
        yts,
        model,
        end_time,
        step_size,
        n_paths,
    ) |> Matrix |> vec
end

x0 = model_parameters(model)
y0 = F_implied_volatilities(x0)
