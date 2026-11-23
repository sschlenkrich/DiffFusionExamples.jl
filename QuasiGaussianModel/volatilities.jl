
function simulation_times(end_time, step_size, decay = 0.5, min_step = 1.0/365)
    times = Float64[]
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


function swap_flows(exercise_time, swap_time)
    fixed_times = collect(exercise_time:1.0:exercise_time+swap_time)
    fixed_weights = ones(length(fixed_times)-1)
    return (fixed_times = fixed_times, fixed_weights)
end


function swap_rate(yts, exercise_time, swap_time)
    cf = swap_flows(exercise_time, swap_time)
    df = [ yts(t) for t in cf.fixed_times ]
    float_leg = df[begin] - df[end]
    annuity = sum(df[2:end] .* cf.fixed_weights)
    return float_leg / annuity
end


function implied_volatilities(
    sim::DiffFusion.Simulation,
    exercise_time::Float64,
    swap_time::Float64,
    rel_strikes::Array{Float64},
    yts::DiffFusion.YieldTermstructure,
    )
    (fixed_times, fixed_weights) = swap_flows(exercise_time, swap_time)
    local vol
    try
        vol = DiffFusion.implied_swaption_volatilities(
            sim,
            yts,
            exercise_time,
            fixed_times,
            fixed_weights,
            rel_strikes,
        )
    catch
        vol = zeros(size(rel_strikes))
    end
    return vol
end


function implied_volatilities(
    sim::DiffFusion.Simulation,
    exercise_times::Array{Float64},
    swap_times::Array{Float64},
    rel_strikes::Array{Float64},
    yts::DiffFusion.YieldTermstructure,
    )
    data = [
        vcat(
            exercise_time,
            swap_time,
            swap_rate(yts, exercise_time, swap_time),
            implied_volatilities(sim, exercise_time, swap_time, rel_strikes, yts)
        )
        for exercise_time in exercise_times, swap_time in swap_times
    ]
    data = permutedims(hcat(vec(data)...))
    names = [
        "exercise_time",
        "swap_time",
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