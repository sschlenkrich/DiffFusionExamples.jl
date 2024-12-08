
"""
    const product_types

Specify available product types for workloads.
"""
const product_types = [
    "VANILLASWAP",
    "EUROPEANSWAPTION",
    "BERMUDANSWAPTION"
]


"""
    const mt_strategy_types

Specify available multi-threading strategies.
"""
const mt_strategy_types = [
    "MT",
    "DIST",
    "MIXED",
]

"""
    const config_names

Specify available configuration (yaml) files.
"""
const config_names = [
    "G3_1FACTOR_FLAT",
    "G3_1FACTOR_TS",
    "G3_3FACTOR_TS",
]

"""
    portfolio(
        obj_dict::AbstractDict,
        produt_type::String,
        n_products::Int,
        )

Generate a portfolio of random products for a given
product type.
"""
function portfolio(
    obj_dict::AbstractDict,
    produt_type::String,
    n_products::Int,
    )
    @assert produt_type in product_types
    config = obj_dict["config/instruments"]
    if haskey(config, "seed")
        Random.seed!(config["seed"])
    end
    get_product = nothing
    if produt_type == "VANILLASWAP"
        get_product = DiffFusion.Examples.random_swap
    end
    if produt_type == "EUROPEANSWAPTION"
        get_product = DiffFusion.Examples.random_swaption
    end
    if produt_type == "BERMUDANSWAPTION"
        get_product = DiffFusion.Examples.random_bermudan
    end
    if !isnothing(get_product)
        prod_list = [ get_product(obj_dict) for k in 1:n_products ]
        legs = vcat(prod_list...)
        return legs
    end
    error("Cannot get portfolio for produt_type " * produt_type * ".")
end

"""
    cash_asset()

Generate a cash asset leg, i.e. inverse numeraire asset.

This is used for discounting subsequent to collateral balance
calculation.
"""
function cash_asset()
    return [ DiffFusion.cash_balance_leg("OneUsd", 1.0) ]
end

"""
    reset_discount_key(scens::DiffFusion.ScenarioCube)

Reset discount_curve_key to allow Cube arithmetics.
"""
function reset_discount_key(scens::DiffFusion.ScenarioCube)
    return DiffFusion.ScenarioCube(
        scens.X,
        scens.times,
        scens.leg_aliases,
        scens.numeraire_context_key,
        nothing,
    )
end

"""
    collateralised_portfolio(
        scens::DiffFusion.ScenarioCube,
        discf::DiffFusion.ScenarioCube,
        )

Calculate the discounted collateralised portfolio.

We configure collateral calculation here.
"""
function collateralised_portfolio(
    scens::DiffFusion.ScenarioCube,
    discf::DiffFusion.ScenarioCube,
    )
    #
    margin_times = DiffFusion.collateral_call_times(0.25, 0.00, 20.00)
    scens_w_cb = DiffFusion.collateralised_portfolio(
        scens,
        nothing,
        margin_times,
        0.0, # initial_collateral_balance
        0.0, # minimum_transfer_amount
        0.0, # threshold_amount
        0.0, # independent_amount
        2/48.0, # 2 weeks mpr
    )
    scens_w_cb_disc = scens_w_cb * discf
    return scens_w_cb_disc
end


"""
    cva_adjustment(scens::DiffFusion.ScenarioCube)

Calculate CVA for specified parameters
"""
function cva_adjustment(
    spread_curve::DiffFusion.CreditDefaultTermstructure,
    scens::DiffFusion.ScenarioCube,
    )
    #
    return DiffFusion.valuation_adjustment(
        spread_curve,
        0.4,  # recovery rate
        1.0,  # CVA
        scens,
    )
end

"""
    run_products(parsed_args)

Run workloads for a given setting and fixed number of threads.
"""
function run_products(parsed_args)
    pinthreads(:cores)
    n_threads = Threads.nthreads()
    n_workers = nworkers()
    strategy = uppercase(parsed_args["strategy"])
    @info "Ignoring options m/M/s and run with $n_threads threads, $n_workers workers and strategy $strategy."
    #
    #
    #
    if "OMP_NUM_THREADS" in keys(ENV)
        @info "ENV[OMP_NUM_THREADS]: " * string(ENV["OMP_NUM_THREADS"])
    else
        @info "OMP_NUM_THREADS is not set. You should consider 'export OMP_NUM_THREADS=1'."
    end
    @info "LinearAlgebra.BLAS.get_num_threads: " * string(LinearAlgebra.BLAS.get_num_threads())
    #
    # Specify config yaml file
    #
    config_string = parsed_args["c"]
    @info "Load config " * config_string * "."
    dict_list = DiffFusion.Examples.load(lowercase(config_string))
    obj_dict = DiffFusion.deserialise_from_list(dict_list)
    #
    # Specify list of products to be run
    #
    wl_string = uppercase(parsed_args["Workload"])
    if wl_string == "ALL"
        run_prods = product_types
    else
        run_prods = [ wl_string ]
    end
    #
    # Specify number of products to be run
    #
    n_prods_list = [ parsed_args["p"] ]
    while 2*n_prods_list[end] <= parsed_args["P"]
        push!(n_prods_list, n_prods_list[end] * 2)
    end
    #
    # Specify scanrio valuation function / multi-threading strategy
    #
    scenarios = nothing
    if strategy == "MT"
        scenarios = DiffFusion.scenarios_multi_threaded
    end
    if strategy == "DIST"
        scenarios = DiffFusion.scenarios_distributed
    end
    if strategy == "MIXED"
        scenarios = DiffFusion.scenarios_parallel
    end
    if isnothing(scenarios)
        error("Cannot get scenarios function for strategy " * strategy * ".")
    end
    #
    # Run MC risk factor simulation
    #
    @info "Simlate MC paths..."
    obj_dict["config/simulation"]["simulation_times"]["start"] = 0.0
    obj_dict["config/simulation"]["simulation_times"]["step"]  = 0.25
    obj_dict["config/simulation"]["simulation_times"]["stop"]  = 10.0
    obj_dict["config/simulation"]["n_paths"] = parsed_args["n"]
    time_ = @elapsed @time path_ = DiffFusion.Examples.path!(obj_dict)
    @info "Simulated " * string(DiffFusion.length(path_)) * " paths."
    open(parsed_args["l"], "a") do f
        write(f, "Run MC simulation in " * string(time_) * " sec.\n")
    end
    #
    # Calculate random discout factors
    #
    obs_times = path_.sim.times
    time_ = @elapsed @time scens_cash = reset_discount_key(scenarios(cash_asset(), obs_times, path_, obj_dict["config/instruments"]["discount_curve_key"]))
    @info "Run parallel calculation for cash asset leg."
    open(parsed_args["l"], "a") do f
        write(f, "Run parallel calculation for cash asset in " * string(time_) * " sec.\n")
    end
    #
    # Run scenario pricing
    #
    results = OrderedDict[]
    for (n_prods, product) in Iterators.product(n_prods_list, run_prods)
        #
        GC.gc()
        #
        legs_ = portfolio(obj_dict, product, n_prods)
        @info "Run parallel calculation for $product, n_prods $n_prods, n_threads $n_threads, n_workers $n_workers."
        open(parsed_args["l"], "a") do f
            write(f, "Run parallel calculation for $product, n_prods $n_prods, n_threads $n_threads, n_workers $n_workers ... ")
        end
        time_ = @elapsed @time scens_mt = scenarios(legs_, obs_times, path_, nothing)
        open(parsed_args["l"], "a") do f
            write(f, "Done in $time_ sec.\n")
        end
        push!(
            results,
            OrderedDict(
                "product"   => product,
                "n_prods"   => n_prods,
                "n_threads" => n_threads,
                "n_workers" => n_workers,
                "run_time"  => time_,
            )
        )
        #
        @info "Aggregate portfolio legs."
        time_ = @elapsed @time scens_agg = DiffFusion.aggregate(scens_mt, false, true)
        open(parsed_args["l"], "a") do f
            write(f, "Aggregate portfolio legs in " * string(time_) * " sec.\n")
        end
        @info "Calculate collateralised portfolio."
        time_ = @elapsed @time scens_w_cb = collateralised_portfolio(scens_agg, scens_cash)
        open(parsed_args["l"], "a") do f
            write(f, "Calculate collateralised portfolio in " * string(time_) * " sec.\n")
        end
        #
        @info "Calculate CVA for portfolio."
        time_ = @elapsed @time scens_cva = cva_adjustment(obj_dict["sc/SingleA"], scens_w_cb)
        open(parsed_args["l"], "a") do f
            write(f, "Calculate CVA for portfolio in " * string(time_) * " sec.\n")
        end
        #
        if parsed_args["with-single-thread"]
            @info "Run s/t calculation for $product, n_prods $n_prods."
            time_ = @elapsed @time scens_st = DiffFusion.scenarios(legs_, obs_times, path_, nothing, with_progress_bar=false)
            residuum = maximum(abs.(scens_mt.X - scens_st.X))
            @info "Residuum $residuum."
            open(parsed_args["l"], "a") do f
                write(f, "Run s/t calculation for $product, n_prods $n_prods in " * string(time_) * " sec. with residuum $residuum.\n")
            end
        end
    end
    result_table = DataFrame(results)
    println(result_table)
    CSV.write(parsed_args["r"], result_table)
    return path_
end



"""
    run_products_slim(path_::DiffFusion.Path)

Only run scenario simulation for products.
"""
function run_products_slim(
    parsed_args::AbstractDict,
    path_::DiffFusion.Path,
    )
    #
    pinthreads(:cores)
    n_threads = Threads.nthreads()
    n_workers = nworkers()
    strategy = uppercase(parsed_args["strategy"])
    #
    # Specify config yaml file
    #
    config_string = parsed_args["c"]
    @info "Load config " * config_string * "."
    dict_list = DiffFusion.Examples.load(lowercase(config_string))
    obj_dict = DiffFusion.deserialise_from_list(dict_list)
    #
    # Specify list of products to be run
    #
    wl_string = uppercase(parsed_args["Workload"])
    if wl_string == "ALL"
        run_prods = product_types
    else
        run_prods = [ wl_string ]
    end
    #
    # Specify number of products to be run
    #
    n_prods_list = [ parsed_args["p"] ]
    while 2*n_prods_list[end] <= parsed_args["P"]
        push!(n_prods_list, n_prods_list[end] * 2)
    end
    #
    # Specify scanrio valuation function / multi-threading strategy
    #
    scenarios = nothing
    if strategy == "MT"
        scenarios = DiffFusion.scenarios_multi_threaded
    end
    if strategy == "DIST"
        scenarios = DiffFusion.scenarios_distributed
    end
    if strategy == "MIXED"
        scenarios = DiffFusion.scenarios_parallel
    end
    if isnothing(scenarios)
        error("Cannot get scenarios function for strategy " * strategy * ".")
    end
    #
    obs_times = path_.sim.times
    #
    # Run scenario pricing
    #
    results = OrderedDict[]
    for (n_prods, product) in Iterators.product(n_prods_list, run_prods)
        #
        GC.gc()
        #
        legs_ = portfolio(obj_dict, product, n_prods)
        @info "Run parallel calculation for $product, n_prods $n_prods, n_threads $n_threads, n_workers $n_workers."
        open(parsed_args["l"], "a") do f
            write(f, "Run parallel calculation for $product, n_prods $n_prods, n_threads $n_threads, n_workers $n_workers ... ")
        end
        time_ = @elapsed @time scens_mt = scenarios(legs_, obs_times, path_, nothing)
        open(parsed_args["l"], "a") do f
            write(f, "Done in $time_ sec.\n")
        end
        push!(
            results,
            OrderedDict(
                "product"   => product,
                "n_prods"   => n_prods,
                "n_threads" => n_threads,
                "n_workers" => n_workers,
                "run_time"  => time_,
            )
        )
        #
    end
    result_table = DataFrame(results)
    println(result_table)
    CSV.write(parsed_args["r"], result_table)
    return path_
end
