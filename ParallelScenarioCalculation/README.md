# Parallel Scenario Generation

This folder contains scripts to test parallel scenario calculation with [DiffFusion.jl](https://github.com/frame-consulting/DiffFusion.jl).

The scripts are intended to run on large AWS EC2 machines.

## Setup Machine

In this section, we specify how to setup the Linux machine.

### Setup AWS Machine

We use AWS EC2 instances for testing workloads. For this test, we use a *hpc6a* instance.

Some details for setting up the AWS instance are documented [here](aws_setup.md).


### Install Software and Initialise Repository

We use Docker for development and testing. Once everything is working as intended  we move to AWS.

The setup process is specified in the shell script `docker/init.sh`. This shell script must be copied to the target machine if working on AWS.

Once `init.sh` is available on the target machine, the machine can be initialised via

```
./init.sh
```

The `init.sh` script then performs the following tasks:

  - install required software,
  - clone this repository,
  - instantiate Julia environment.

## Run Workloads

Workloads are implemented in script `Workloads.jl`. The script can be configured via several parameters.

From `/home/celery/DiffFusionParallel/src` run

```
julia --project=. Workloads.jl -h
```

This will produce the following output

```
usage: Workloads.jl [-m m] [-M M] [-s s] [-p p] [-P P] [-n n] [-r R]
                    [-l L] [-c C] [--with-single-thread]
                    [--run-in-parallel] [--strategy STRATEGY] [-h]
                    Workload

positional arguments:
  Workload              workload to run; must be one of VANILLASWAP,
                        EUROPEANSWAPTION, BERMUDANSWAPTION or ALL

optional arguments:
  -m m                  minimum number of threads or processes (type:
                        Int64, default: 2)
  -M M                  maximum number of threads or processes (type:
                        Int64, default: 2)
  -s s                  additional number of threads parameters for
                        MIXED (type: Int64, default: 2)
  -p p                  minimum number of products (type: Int64,
                        default: 8)
  -P P                  maximum number of products (type: Int64,
                        default: 8)
  -n n                  number of MC paths (type: Int64, default:
                        1024)
  -r R                  result file name (default: "Workloads.csv")
  -l L                  log file name (default: "Workloads.log")
  -c C                  configuration name; must be one of
                        G3_1FACTOR_FLAT, G3_1FACTOR_TS or G3_3FACTOR_TS
                        (default: "G3_1FACTOR_TS")
  --with-single-thread  compare with single-threaded valuation
  --run-in-parallel     run products for all available threads/workers
  --strategy STRATEGY   parallel strategy; must be one of MT, DIST or
                        MIXED (default: "MT")
  -h, --help            show this help message and exit
```

A concrete run can be executed, for example, via

```
julia --project=. Workloads.jl -m 1 -M 8 -s 2 -p 128 -P 512 -n 1024 --strategy MIXED VanillaSwap
```

This command will start the following calculations and measure run time:

  - Simulate 1024 Monte Carlo paths.
  - Price portfolios of 128, 256 and 512 Vanilla interest rate swaps.
  - Use a combination of multi-threading and multi-processing (MIXED) with 2 threads per process (-s 2) and 1, 2, 4 and 8 processes.

Run time results are summarised in `Workloads.csv`.

For example, on an AWS c6a.4xlarge instance with 16 vCPU, file `Workload.csv` shows the following run times in seconds:

```
product,n_prods,n_threads,n_workers,run_time
VANILLASWAP,128,2,1,5.223653086
VANILLASWAP,256,2,1,8.582740554
VANILLASWAP,512,2,1,15.780449024
VANILLASWAP,128,2,2,3.337192666
VANILLASWAP,256,2,2,4.649475022
VANILLASWAP,512,2,2,9.021443096
VANILLASWAP,128,2,4,2.543919766
VANILLASWAP,256,2,4,2.851625778
VANILLASWAP,512,2,4,5.176923152
VANILLASWAP,128,2,8,2.974693992
VANILLASWAP,256,2,8,2.804099828
VANILLASWAP,512,2,8,4.557568791
```

## Parallel Scenario Calculation Implementations

Parallel calculations via multi-threading and multi-processing is implemented in `Scenarios.jl`.