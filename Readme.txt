# Control and Revenue Distribution of Shared Hybrid PV and Battery Systems

This repository contains Julia scripts for simulating, analyzing, and visualizing the bidding and revenue distribution in the balancing stage of power delivery based on demand and PV production. The project uses cooperative game theory to allocate costs and revenues among participants, considering imbalances, forecasts, and coalition formation.
The script is based upon a case study, and as such the data is not publicly available. Scripts will therefore not run.

## Repository Structure

- **Data_import.jl**: Handles data loading and preprocessing from various sources (e.g., Excel, CSV).
- **Scenario_creation.jl**: Generates demand scenarios for clients based on historical data and weekdays.
- **Imbalance_functions.jl**: Contains functions for calculating imbalances, optimizing bids, and simulating coalition behavior over time.
- **Game_theoretic_functions.jl**: Implements cooperative game theory allocation methods, including Shapley value, VCG, Gately point, nucleolus, and cost allocation strategies.
- **Imbalance_main.jl**: Main script for running simulations, performing allocation analysis, and generating plots.
- **Plotting.jl**: Functions for visualizing allocation results, client costs, and demand/production statistics.
- **Data/**: Contains input data files such as client master data, consumption data, price data, and solar forecasts.

## Key Features

- **Cooperative Game Theory**: Implements several allocation methods (Shapley, VCG, Gately, Nucleolus, etc.) to distribute costs and revenues among clients.
- **Imbalance Optimization**: Models and optimizes energy imbalances for coalitions using linear programming (JuMP, HiGHS, Gurobi).
- **Scenario-Based Simulation**: Supports perfect, scenario-based, and noisy forecasts for both demand and PV production.
- **Visualization**: Plots results for cost allocation, demand, production, and variance analysis.

## How to Run

1. **Install Julia** and required packages (JuMP, HiGHS, Gurobi, Plots, Combinatorics, StatsPlots, etc.).
2. **Prepare Data**: Place input data files in the `Data/` directory. Note that demand data is not included by default, and it might take some work to format them.
3. **Run Main Script**: Execute `Imbalance_main.jl` to perform the analysis and generate plots.

## Customization
- Adjust the list of clients, forecast types, and simulation parameters in `Imbalance_main.jl` as needed.
- Add or remove allocation methods in the `allocations` array.

## Dependencies
- Julia (recommended version: 1.6 or later)
- JuMP
- HiGHS
- Plots
- Combinatorics
- StatsPlots

## Data Files
- `Asset_master_data_asmus.xlsx`: Asset and client information, not included
- `consumption_data.csv`: Client consumption data
- `Elspotprices.csv`: Market price data
- `ProductionMunicipalityHour.csv`: Hourly production data
- `Solar_Forecasts_Hour.csv`: Solar production forecasts

## Contact
For questions or contributions, please contact the repository owner.
