
# install software
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
   git \
   wget \
   vim
sudo apt-get clean
rm -rf /var/lib/apt/lists/*

# get Julia 1.10.4
wget https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.4-linux-x86_64.tar.gz

# extract binary etc.
tar zxvf julia-1.10.4-linux-x86_64.tar.gz

# make Julia accessible
sudo ln -s /home/celery/julia-1.10.4/bin/julia /usr/local/bin/

git config --global core.autocrlf input

# get repo
git clone https://github.com/sschlenkrich/DiffFusionExamples.jl --branch wip/parallel-scenarios

julia --project=DiffFusionExamples.jl/ParallelScenarioCalculation/src/. -e "using Pkg; Pkg.instantiate()"
