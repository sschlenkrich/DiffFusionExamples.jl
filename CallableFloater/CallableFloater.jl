using CSV
using DataFrames
using DiffFusion
using Plots
using StatsBase


@info "Execute CallableFloater.jl"

# Model Setup

ch = DiffFusion.correlation_holder("ch/One")

### Rates Model

delta = DiffFusion.flat_parameter(0.0)
chi = DiffFusion.flat_parameter(0.01)
sigma = DiffFusion.flat_volatility(0.01)

mdl_eur = DiffFusion.gaussian_hjm_model(
    "mdl/EUR",
    delta,
    chi,
    sigma,
    ch,
    nothing,  # quanto model
    DiffFusion.DiagonalScaling,
)

### Credit Model

ts_credit = DiffFusion.flat_forward("ts/Credit", 0.05 / (1.0 - 0.4))  # See Brigo approximation
min_short_rate = 1.0e-8
volatility_function = DiffFusion.CirShortRateModelFunction(ts_credit, min_short_rate)

chi_cir = DiffFusion.flat_parameter(0.10)
sigma_cir = DiffFusion.flat_volatility(0.30)

mdl_credit = DiffFusion.quasi_gaussian_short_rate_model(
    "mdl/Credit",
    chi_cir,
    sigma_cir,
    nothing,  # quanto model
    volatility_function,
)

### Hybrid model

mdl_hybrid = DiffFusion.diagonal_model("mdl/Hybrid", [mdl_eur, mdl_credit])

### Simulation

times = 0.0:1.0/48:10.0
n_paths = 2^13
sim = DiffFusion.state_dependent_simulation(
    mdl_hybrid,
    ch,
    times,
    n_paths,
    with_progress_bar = true,
    brownian_increments = DiffFusion.sobol_brownian_increments,
)

### Context and Path

ts_estr = DiffFusion.flat_forward("ts/Estr", 0.0300)
ts_euribor3m = DiffFusion.flat_forward("ts/Euribor3m", 0.0350)

ts_list = [
    ts_estr,
    ts_euribor3m,
    ts_credit,
]

ctx = DiffFusion.context(
    "Std",
    DiffFusion.numeraire_entry("EUR", "mdl/EUR", "ts/Estr"),
    [ 
        DiffFusion.rates_entry("EUR", "mdl/EUR", Dict("ESTR" => "ts/Estr", "EURIBOR3M" => "ts/Euribor3m")),
        DiffFusion.rates_entry("EU_CORP", "mdl/Credit", "ts/Credit"), 
    ],
)

path = DiffFusion.path(
    sim,
    ts_list,
    ctx,
    DiffFusion.LinearPathInterpolation,
)

### Deterministic modelling

sim_0 = DiffFusion.state_dependent_simulation(
    mdl_hybrid,
    ch,
    [0.0],
    1,
    with_progress_bar = true,
    brownian_increments = DiffFusion.sobol_brownian_increments,
)

ctx_0 = DiffFusion.context(
    "Std",
    DiffFusion.numeraire_entry("EUR", nothing, "ts/Estr"),
    [ 
        DiffFusion.rates_entry("EUR", nothing, Dict("ESTR" => "ts/Estr", "EURIBOR3M" => "ts/Euribor3m")),
        DiffFusion.rates_entry("EU_CORP", nothing, "ts/Credit"), 
    ],
)

path_0 = DiffFusion.path(
    sim_0,
    ts_list,
    ctx_0,
    DiffFusion.LinearPathInterpolation,
)


### Floater Cash Flows


### Exercise Cash Flow Leg

function exercise_legs(
    exercise_time,
    coupon_schedule,
    spread_rate,
    recovery_rate,
    )
    times = [ t for t in coupon_schedule if t > exercise_time ]
    #
    coupons = DiffFusion.CashFlow[
        DiffFusion.SimpleRateCoupon(s, s, e, e, e - s, "EUR:EURIBOR3M", nothing, spread_rate)
        for (s, e) in zip(times[1:end-1], times[2:end])
    ]
    euribor_flows = DiffFusion.CashFlow[
        DiffFusion.SimpleRateCoupon(s, s, e, e, e - s, "EUR:EURIBOR3M", nothing, 0.0)
        for (s, e) in zip(times[1:end-1], times[2:end])
    ]
    annuity_flows = DiffFusion.CashFlow[
        DiffFusion.FixedRateCoupon(e, 1.0, e - s, s)
        for (s, e) in zip(times[1:end-1], times[2:end])
    ]
    #
    strike = DiffFusion.FixedCashFlow(times[begin], -1.0)  # make sure after exercise time
    redemption = DiffFusion.FixedCashFlow(times[end], 1.0)
    #
    floater_leg = DiffFusion.cashflow_leg(
        "leg/Floater",
        vcat(strike, coupons, redemption),
        100.0,
        "EUR:ESTR",
        nothing,
        1.0,  # receive coupons/notional
    )
    euribor_leg = DiffFusion.cashflow_leg(
        "leg/Euribor",
        vcat(strike, euribor_flows, redemption),
        100.0,
        "EUR:ESTR",
        nothing,
        -1.0,  # payer for positive leg npv
    )
    annuity_leg = DiffFusion.cashflow_leg(
        "leg/Annuity",
        annuity_flows,
        100.0,
        "EUR:ESTR",
        nothing,
        1.0, #  receiver for positive leg npv
    )
    #
    floater_leg = DiffFusion.credit_risky_cashflow_leg(floater_leg, "EU_CORP", recovery_rate)
    euribor_leg = DiffFusion.credit_risky_cashflow_leg(euribor_leg, "EU_CORP", recovery_rate)
    annuity_leg = DiffFusion.credit_risky_cashflow_leg(annuity_leg, "EU_CORP", 0.0)  # no redemption flows here
    #
    return floater_leg, euribor_leg, annuity_leg
end


### Valuations


function european_option_valuation(
    exercise_time,
    coupon_schedule,
    spread_rate,
    recovery_rate,
    )
    floater_leg, euribor_leg, annuity_leg = exercise_legs(exercise_time, coupon_schedule, spread_rate, recovery_rate)
    floater_leg_payoffs = DiffFusion.discounted_cashflows(floater_leg, exercise_time)
    option_payoff = DiffFusion.Max(0.0, sum(floater_leg_payoffs))
    #
    npv_option = DiffFusion.model_price(
        [option_payoff],
        path,
        exercise_time,
        "EUR",
    )
    npv_floater_leg = DiffFusion.model_price(
        floater_leg_payoffs,
        path,
        exercise_time,
        "EUR",
    )
    npv_euribor_leg = DiffFusion.model_price(
        DiffFusion.discounted_cashflows(euribor_leg, exercise_time),
        path,
        exercise_time,
        "EUR",
    )
    npv_annuity_leg = DiffFusion.model_price(
        DiffFusion.discounted_cashflows(annuity_leg, exercise_time),
        path,
        exercise_time,
        "EUR",
    )
    return npv_option, npv_floater_leg, npv_euribor_leg, npv_annuity_leg
end


function bermudan_option_valuation(
    exercise_times,
    coupon_schedule,
    spread_rate,
    recovery_rate,
    )
    #
    make_regression_variables(t) = [
        DiffFusion.LiborRate(t, t, coupon_schedule[end], "EUR:EURIBOR3M"),
        DiffFusion.LiborRate(t, t, coupon_schedule[end], "EU_CORP"),  # a credit rate
        DiffFusion.Max(
            0.0,
            spread_rate - DiffFusion.LiborRate(t, t, coupon_schedule[end], "EU_CORP")
        ),
    ]
    # make_regression = (C, O) -> DiffFusion.polynomial_regression(C, O, 2)
    make_regression = (C, O) -> DiffFusion.piecewise_regression(C, O, 2, [1, 3, 3])
    #
    exercises = DiffFusion.BermudanExercise[]
    for exercise_time in exercise_times
        floater_leg, _, _ = exercise_legs(exercise_time, coupon_schedule, spread_rate, recovery_rate)
        exercise = DiffFusion.bermudan_exercise(
            exercise_time,
            [floater_leg],
            make_regression_variables
        )
        push!(exercises, exercise)
    end
    #
    berm = DiffFusion.bermudan_swaption_leg(
        "berm/floater",
        exercises,
        1.0, # long option
        "EUR", # default discounting
        make_regression_variables,
        nothing, # path
        nothing, # make_regression
    )
    DiffFusion.reset_regression!(berm, path, make_regression)
    #
    berm_payoff = berm.hold_values[1]
    berm_npv = DiffFusion.model_price(
        [berm_payoff],
        path,
        DiffFusion.obs_time(berm_payoff),
        "EUR"
    )
    return berm_npv
end


function spread_rate_scenarios(
    exercise_time,
    coupon_schedule,
    spread_rate,
    recovery_rate
    )
    _, euribor_leg, annuity_leg = exercise_legs(exercise_time, coupon_schedule, spread_rate, recovery_rate)
    euribor_leg = sum(DiffFusion.discounted_cashflows(euribor_leg, exercise_time))
    annuity_leg = sum(DiffFusion.discounted_cashflows(annuity_leg, exercise_time))
    spread_rate = euribor_leg / annuity_leg
    return spread_rate(path)
end


### Setup Floater and Option

effective_time = 0.0
maturity_time = 10.0
term = 0.25
spread_rate = 0.05 # 0.035

recovery_rate = 0.4

coupon_schedule = effective_time:term:maturity_time

floater_leg, euribor_leg, annuity_leg = exercise_legs(-1.0, coupon_schedule, spread_rate, recovery_rate)

npv_floater_leg = DiffFusion.model_price(
    DiffFusion.discounted_cashflows(floater_leg, 0.0),
    path_0,
    0.0,
    "EUR",
)
npv_euribor_leg = DiffFusion.model_price(
    DiffFusion.discounted_cashflows(euribor_leg, 0.0),
    path_0,
    0.0,
    "EUR",
)
npv_annuity_leg = DiffFusion.model_price(
    DiffFusion.discounted_cashflows(annuity_leg, 0.0),
    path_0,
    0.0,
    "EUR",
)

fair_spread_rate = (100.0 + npv_euribor_leg) / npv_annuity_leg

println("Floater Leg NPV: $(npv_floater_leg)")
println("Euribor Leg NPV: $(npv_euribor_leg)")
println("Annuity Leg NPV: $(npv_annuity_leg)")
println("Fair Spread Rate: $(fair_spread_rate)")

spread_rates_5y = spread_rate_scenarios(5.0, coupon_schedule, spread_rate, recovery_rate)
spread_vol_5y = std(spread_rates_5y) / sqrt(5.0) / mean(spread_rates_5y)
println("Spread Rate Volatility (5y): $(spread_vol_5y)")
histogram(spread_rates_5y, bins=50, title="Spread Rate Scenarios (5y)", xlabel="Spread Rate", ylabel="Frequency")


ε = 1.0 / 365 / 24 / 3600  # 1 second in years
exersise_times = (1.0:1.0:9.0) .- ε  # exercise just before the coupon date


result_table = DataFrame()
for spread_rate in 0.01:0.01:0.10
    results = []
    for exercise_time in exersise_times
        local term, npv_option, npv_floater_leg, npv_euribor_leg, npv_annuity_leg
        expiry = Int(round(exercise_time, digits=0))
        term   = Int(round(coupon_schedule[end] - exercise_time, digits=0))
        npv_option, npv_floater_leg, npv_euribor_leg, npv_annuity_leg = european_option_valuation(
            exercise_time,
            coupon_schedule,
            spread_rate,
            recovery_rate,
        )
        result = (
            expiry = "$(expiry)y",
            term = "$(term)y",
            payer_or_receiver = -1.0,  # Payer
            strike_rate = spread_rate,
            fair_rate = npv_euribor_leg / npv_annuity_leg,
            annuity = npv_annuity_leg,
            exercise_time = exercise_time,
            european_npv = npv_option,
        )
        push!(results, result)
    end
    table = DataFrame(results)
    #
    npv_berm = bermudan_option_valuation(
        exersise_times,
        coupon_schedule,
        spread_rate,
        recovery_rate,
    )
    table[!, :bermudan_npv] .= npv_berm
    #
    println(table)
    global result_table = vcat(result_table, table)
end

file_name = "CallableFloater/CallableFloater_Results.csv"
CSV.write(file_name, result_table)

