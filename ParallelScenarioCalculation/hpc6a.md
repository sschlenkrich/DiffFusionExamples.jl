# Workload Test Execution on hpc6a Instance

This file specifies the workload test runs.

## Multi-threaded Calculation

julia --project=. Workloads.jl -m 6 -M 96 -p 128 -P 1024 -n 8192 -r Workloads.MT.csv -l Workloads.MT.log --strategy MT VanillaSwap

## Multi-processing Calculation

julia --project=. Workloads.jl -m 6 -M 96 -p 128 -P 1024 -n 8192 -r Workloads.MP.csv -l Workloads.MP.log --strategy DIST VanillaSwap

## Mixed Calculation

julia --project=. Workloads.jl -m 1 -M 16 -s 6 -p 128 -P 1024 -n 8192 -r Workloads.MX.csv -l Workloads.MX.log --strategy MIXED VanillaSwap
