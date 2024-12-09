using Distributed

using Base.Threads
using ArgParse
using CSV
using DataFrames
using Dates
@everywhere using DiffFusion
using LinearAlgebra
using OrderedCollections
using Printf
using Random
@everywhere using SharedArrays
@everywhere using ThreadPinning
using YAML

LinearAlgebra.BLAS.set_num_threads(1)

include("RunProducts.jl")

# Execute script via `julia --project=. Workloads.jl [ARGS]`.
# Use `julia --project=. Workloads.jl -h` for details.


"""
    parse_commandline()

Specify command line arguments and perform command line parsing.
"""
function parse_commandline()
    wl_choices = vcat(product_types, "ALL")
    st_choices = mt_strategy_types
    #
    s = ArgParseSettings()
    @add_arg_table s begin
        "Workload"
            help = "workload to run; must be one of " * join(wl_choices, ", ", " or ")
            required = true
            range_tester = (x->uppercase(x) ∈ wl_choices)
        "-m"
            help = "minimum number of threads or processes"
            arg_type = Int
            default = 2
            metavar = "m"
        "-M"
            help = "maximum number of threads or processes"
            arg_type = Int
            default = 2
            metavar = "M"
        "-s"
            help = "additional number of threads parameters for MIXED"
            arg_type = Int
            default = 2
            metavar = "s"
        "-p"
            help = "minimum number of products"
            arg_type = Int
            default = 8
            metavar = "p"
        "-P"
            help = "maximum number of products"
            arg_type = Int
            default = 8
            metavar = "P"
        "-n"
            help = "number of MC paths"
            arg_type = Int
            default = 1024
            metavar = "n"
        "-r"
            help = "result file name"
            arg_type = String
            default = "Workloads.csv"
        "-l"
            help = "log file name"
            arg_type = String
            default = "Workloads.log"
        "-c"
            help = "configuration name; must be one of " * join(config_names, ", ", " or ")
            arg_type = String
            default = "G3_1FACTOR_TS"
            range_tester = (x->uppercase(x) ∈ config_names)
        "--with-single-thread"
            help = "compare with single-threaded valuation"
            action = :store_true
        "--run-in-parallel"
            help = "run products for all available threads/workers"
            action = :store_true
        "--strategy"
            help = "parallel strategy; must be one of " * join(st_choices, ", ", " or ")
            arg_type = String
            default = "MT"
            range_tester = (x->uppercase(x) ∈ st_choices)
    end
    #
    return parse_args(s)
end


"""
    main()

Script entry function.

Based on `run-in-parallel` flag, we decide whether to execute an actual run or
schedule a sequence of (recursive) `Workloads.jl` calls with various number of
threads/workers in Julia call.
"""
function main()
    parsed_args = parse_commandline()
    @info "Start Workloads.jl with arguments " * string(parsed_args)
    if parsed_args["run-in-parallel"]
        run_products(parsed_args)
        return
    end
    open(parsed_args["l"], "w") do f
        write(f, "Start Workloads.jl with arguments " * string(parsed_args) * "\n")
    end
    #
    # Specify number of threads/processes to be run
    #
    n_threads_processes_list = [ parsed_args["m"] ]
    while 2*n_threads_processes_list[end] <= parsed_args["M"]
        push!(n_threads_processes_list, n_threads_processes_list[end] * 2)
    end
    strategy = uppercase(parsed_args["strategy"])
    for n_threads_processes in n_threads_processes_list
        GC.gc()
        run_string = "julia --project=."
        if strategy in ("DIST",)
            run_string = run_string * " -p $n_threads_processes"
        elseif strategy in ("MIXED",)
            n_add_threads = parsed_args["s"]
            run_string = run_string * " -p $n_threads_processes -t $n_add_threads"
        else # assume multi-threaded
            run_string = run_string * " -t $n_threads_processes"
        end
        run_string = run_string * " Workloads.jl -m 0 -M 0 -s 0"
        run_string = run_string * " --run-in-parallel"
        run_string = run_string * " -p " * string(parsed_args["p"]) * " -P " * string(parsed_args["P"])
        run_string = run_string * " -n " * string(parsed_args["n"])
        run_string = run_string * " -r " * string(parsed_args["r"]) * "." * string(n_threads_processes)
        run_string = run_string * " -l " * string(parsed_args["l"])
        run_string = run_string * " -c " * uppercase(parsed_args["c"])
        run_string = run_string * " --strategy " * strategy
        if parsed_args["with-single-thread"]
            run_string = run_string * " --with-single-thread"
        end
        run_string = run_string * " " * uppercase(parsed_args["Workload"])
        #
        @info "Execute " * run_string
        split_string = split(run_string, " ")
        open(parsed_args["l"], "a") do f
            write(f, "Execute " * run_string * "\n")
        end
        run(`$split_string`)
    end
    results = DataFrame()
    for n_threads_processes in n_threads_processes_list
        df = DataFrame(CSV.File(parsed_args["r"] * "." * string(n_threads_processes)))
        append!(results, df)
        rm(parsed_args["r"] * "." * string(n_threads_processes))
    end
    results[!, "n_paths"] .= parsed_args["n"]
    results[!, "strategy"] .= strategy
    results[!, "now_time"] .= now()
    CSV.write(parsed_args["r"], results)
end

main()