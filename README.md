# DiffFusionExamples.jl

This repository contains example notebooks utilizing the [DiffFusion.jl](https://github.com/frame-consulting/DiffFusion.jl) simulation framework.

## How To Run The Examples?

The notebooks can be executed locally. Julia package dependencies are specified in `Project.toml`.

Alternatively, the notebooks can also be executed online via [![Binder](https://mybinder.org/badge_logo.svg)](https://mybinder.org/v2/gh/sschlenkrich/DiffFusionExamples.jl/HEAD).

Note that *binder* is sometimes a bit unstable. If it does not load or the JupyterLab freezes then give it another try a few seconds later.

## Bermudan Swaption Exposure Calculation

See folder [BermudanSwaption](BermudanSwaption) and notebook [BermudanSwaption.ipynb](BermudanSwaption/BermudanSwaption.ipynb).

This example illustrates the pricing and exposure simulation of Bermudan swaptions in [DiffFusion.jl](https://github.com/frame-consulting/DiffFusion.jl).

As part of this example, we show model setup, financial instrument setup and the configuration of American Monte Carlo.

## Collateral Simulation for Cross Currency Swaps

See folder [CollateralisedCrossCurrencySwap](CollateralisedCrossCurrencySwap/) and notebook [CollateralisedCrossCurrencySwap.ipynb](CollateralisedCrossCurrencySwap/CollateralisedCrossCurrencySwap.ipynb).

This example illustrates the modelling of mark-to-market cross currency swaps (with standard and exotic coupon feature).

Furthermore, we use the swaps to illustrate the collateral model and the methodologies to simulate collateralised portfolios with [DiffFusion.jl](https://github.com/frame-consulting/DiffFusion.jl).

## Hybrid Model Calibration

See folder [ModelCalibration](ModelCalibration).

This example illustrates the calibration of multi-factor interest rate models (see [RatesModelCalibration.ipynb](ModelCalibration/RatesModelCalibration.ipynb)) and hybrid cross asset models (see [HybridModelCalibration.ipynb](ModelCalibration/HybridModelCalibration.ipynb)).

As calibration objectives we use volatilities and correlations observed from historical time series of financial risk factors.
