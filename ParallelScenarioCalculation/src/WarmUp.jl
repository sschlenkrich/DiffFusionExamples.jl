
# Load packages and run warm-up calculation

using Distributed

using Base.Threads
using ArgParse
using CSV
using DataFrames
@everywhere using DiffFusion
using LinearAlgebra
using OrderedCollections
using Random
@everywhere using SharedArrays
@everywhere using ThreadPinning
using YAML

LinearAlgebra.BLAS.set_num_threads(1)

include("RunProducts.jl")

input_args = Dict(
    "c" => "G3_1FACTOR_TS",
    "r" => "Workloads.csv",
    "l" => "Workloads.log",
    "with-single-thread" => false,
    "Workload" => "VANILLASWAP",
    "n" => 1024,
    "p" => 60,
    "P" => 60,
    "strategy" => "MT",
)

# initial run compiles all 'inner' functions and calculates path_
path_ = run_products(input_args)

# second run compiles 'run_products_slim' 
path_ = run_products_slim(input_args, path_)

@info "Warm-up complete. Execute `run_products_slim(input_args, path_);`."
