
"""
    simulation_times(
        end_time::DiffFusion.ModelTime,
        step_size::DiffFusion.ModelTime,
        decay::DiffFusion.ModelTime = 0.5,
        min_step::DiffFusion.ModelTime = 1.0/365
    )

Generate Monte-Carlo simulation times.
"""
function simulation_times(
    end_time::DiffFusion.ModelTime,
    step_size::DiffFusion.ModelTime,
    decay::DiffFusion.ModelTime = 0.5,
    min_step::DiffFusion.ModelTime = 1.0/365
    )
    #
    times = DiffFusion.ModelTime[]
    t = step_size
    while t > min_step
        push!(times, t *= decay)
    end
    times = vcat(
        [0.0],
        reverse(times),
        collect(step_size:step_size:end_time)
    )
    return times
end


"""
    swap_cash_flows(
        exercise_time::DiffFusion.ModelTime,
        swap_time::DiffFusion.ModelTime,
    )

Generate fixed leg cash flow times and annuity weights.

We apply the following simplifying assumptions:
  - annual cash flows,
  - unit day count convention,
  - no settlement offset.

Change or replace this function to incorporate actual market conventions.
"""
function swap_cash_flows(
    exercise_time::DiffFusion.ModelTime,
    swap_time::DiffFusion.ModelTime,
    )
    #
    fixed_times = collect(exercise_time:1.0:exercise_time+swap_time)
    fixed_weights = ones(length(fixed_times)-1)
    return (fixed_times = fixed_times, fixed_weights)
end


"""
    implied_volatilities(
        sim::DiffFusion.Simulation,
        exercise_time::DiffFusion.ModelTime,
        swap_time::DiffFusion.ModelTime,
        rel_strikes::Vector,
        yts::DiffFusion.YieldTermstructure,
    )

Calculate implied volatility smile and swap rates from a simulation
and exercise time and swap time.
"""
function implied_volatilities(
    sim::DiffFusion.Simulation,
    exercise_time::DiffFusion.ModelTime,
    swap_time::DiffFusion.ModelTime,
    rel_strikes::Vector,
    yts::DiffFusion.YieldTermstructure,
    )
    (fixed_times, fixed_weights) = swap_cash_flows(exercise_time, swap_time)
    (vol, swap_rate, swap_rate_yts) = DiffFusion.implied_swaption_volatilities(
            sim,
            yts,
            exercise_time,
            fixed_times,
            fixed_weights,
            rel_strikes,
        )
    return (swap_rate, swap_rate_yts, vol)
end


"""
    implied_volatilities(
        sim::DiffFusion.Simulation,
        exercise_times::Vector,
        swap_times::Vector,
        rel_strikes::Vector,
        yts::DiffFusion.YieldTermstructure,
    )

Calculate implied volatility smiles and swap rates from a simulation
and exercise times and swap times.

Returns result as DataFrame.
"""
function implied_volatilities(
    sim::DiffFusion.Simulation,
    exercise_times::Vector,
    swap_times::Vector,
    rel_strikes::Vector,
    yts::DiffFusion.YieldTermstructure,
    )
    data = [
        vcat(
            exercise_time,
            swap_time,
            implied_volatilities(sim, exercise_time, swap_time, rel_strikes, yts)...
        )
        for exercise_time in exercise_times, swap_time in swap_times
    ]
    data = permutedims(hcat(vec(data)...))
    names = [
        "exercise_time",
        "swap_time",
        "forward_sim",
        "forward",
    ]
    rel_strikes_str = [
        @sprintf("%.0f", rel_strike * 1e+4)  # in bp
        for rel_strike in rel_strikes
    ]
    names = vcat(names, rel_strikes_str)
    data = DataFrame(data, names)
    return data
end