

"""
    model_parameters(model::DiffFusion.QuasiGaussianMultiFactorModel)

Extract volatility parameter vector from QuasiGaussianMultiFactorModel.
"""
function model_parameters(model::DiffFusion.QuasiGaussianMultiFactorModel)
    sigma_f = model.gaussian_model.sigma_T.sigma_f.values
    slope_d = model.slope_d.values
    slope_u = model.slope_u.values
    return vcat(vec(sigma_f), vec(slope_d), vec(slope_u))
end 


"""
    quasi_gaussian_multi_factor_model(
        x0::Vector,
        model::DiffFusion.QuasiGaussianMultiFactorModel,
    )

Create a QuasiGaussianMultiFactorModel from a parameter vector and a
reference model.
"""
function quasi_gaussian_multi_factor_model(
    x0::Vector,
    model::DiffFusion.QuasiGaussianMultiFactorModel,
    )
    #
    sigma_f_0 = model.gaussian_model.sigma_T.sigma_f  # abbreviation
    (d, n) = size(sigma_f_0.values)
    @assert length(x0) % (d * n * 3) == 0
    param_length = length(x0) ÷ 3
    sigma_f_values = x0[begin+0*param_length:begin+1*param_length-1]
    slope_d_values = x0[begin+1*param_length:begin+2*param_length-1]
    slope_u_values = x0[begin+2*param_length:begin+3*param_length-1]
    #
    times = sigma_f_0.times
    sigma_f = DiffFusion.backward_flat_volatility(
        sigma_f_0.alias,
        times,
        reshape(sigma_f_values, (d, n)),
    )
    slope_d = DiffFusion.backward_flat_parameter(
        sigma_f_0.alias,
        times,
        reshape(slope_d_values, (d, n)),
    )
    slope_u = DiffFusion.backward_flat_parameter(
        sigma_f_0.alias,
        times,
        reshape(slope_u_values, (d, n)),
    )
    #
    gaussian_model = DiffFusion.gaussian_hjm_model(
        model.gaussian_model.alias,
        model.gaussian_model.delta,
        model.gaussian_model.chi,
        sigma_f,  # replace vols
        model.gaussian_model.correlation_holder,
        model.gaussian_model.quanto_model,
        model.gaussian_model.scaling_type,
    )
    qg_model = DiffFusion.quasi_gaussian_multi_factor_model(
        gaussian_model,
        slope_d,  # replace skew
        slope_u,
        model.sigma_min,
        model.sigma_max,
        model.volatility_model,
        model.volatility_function,
    )
    #
    return qg_model
end


function implied_volatilities(
    x0::Vector,
    #
    exercise_times::Vector,
    swap_times::Vector,
    rel_strikes::Vector,
    #
    yts::DiffFusion.YieldTermstructure,
    model::DiffFusion.QuasiGaussianMultiFactorModel,
    #
    end_time::DiffFusion.ModelTime,
    step_size::DiffFusion.ModelTime,
    n_paths::Int,
    brownian_increments = DiffFusion.pseudo_brownian_increments,
    )
    #
    model_1 = quasi_gaussian_multi_factor_model(x0, model)
    sim_times = simulation_times(end_time, step_size)
    sim = DiffFusion.quasi_gaussian_simulation(
        model_1,
        model_1.gaussian_model.correlation_holder,
        sim_times,
        n_paths,
        with_progress_bar = false,
        brownian_increments = brownian_increments,
    )
    table = implied_volatilities(
        sim,
        exercise_times,
        swap_times,
        rel_strikes,
        yts,
    )
    return table
end
