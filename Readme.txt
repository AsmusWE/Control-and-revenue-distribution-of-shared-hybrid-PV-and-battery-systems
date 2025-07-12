# Control and Revenue Distribution of Shared Hybrid PV and Battery Systems

This repository contains Julia scripts for simulating, analyzing, and visualizing the risk distribution for a balancing responsible party with a portfolio that owns a shared PV system. The project uses cooperative game theory to allocate costs and revenues among participants, focusing on imbalance management and risk assessment through Conditional Value-at-Risk (CVaR) optimization.

The implementation is based on a case study, and as such the data is not publicly available. Scripts will therefore not run without the proper data files.

## Repository Structure

### Core Scripts
- **Imbalance_main.jl**: Main script for running CVaR-based imbalance analysis, allocation calculations, and stability checks.
- **Data_import.jl**: Handles data loading and preprocessing from various sources, including demand data, PV production, price data, and forecasts with 15-minute resolution support.
- **Scenario_creation.jl**: Generates rolling demand scenarios for clients based on historical data and weekdays.
- **Imbalance_functions.jl**: Contains optimization functions for calculating imbalances and CVaR using linear programming (JuMP, HiGHS).
- **Game_theoretic_functions.jl**: Implements cooperative game theory allocation methods including Shapley value, VCG, Gately point, nucleolus, and a cost-based allocation.
- **Plotting.jl**: Functions for visualizing allocation results, client costs, and demand/production statistics.

### Visualization and Analysis
- **Plot_results.py**: Python script for generating higher-quality plots NOT USED FOR CVaR IMPLEMENTATION
- **Export_plot_data.jl**: Exports simulation results to CSV format for further analysis and visualization in python NOT USED FOR CVaR IMPLEMENTATION

### Testing and Validation
- **VCG_testing.jl**: Testing implementation for VCG (Vickrey-Clarke-Groves) mechanism.
- **Gately_test.jl**: Testing implementation for Gately point calculation using nonlinear optimization.
- **Nucleolus_testing.jl**: Testing implementation for nucleolus solution with stability analysis.

### Data Storage
- **Data/**: Contains input data files (consumption data, PV production, price data, solar forecasts).
- **Results/**: Contains simulation outputs, serialized results, and generated plots.

## Key Features

- **Scenario-Based Forecasting**: Supports perfect forecasts, rolling scenario generation, and noise-based forecasting for both demand and PV production.
- **Shapley Value**: Fair allocation based on marginal contributions.
- **VCG Mechanism**: Incentive-compatible mechanism with optional budget balancing.
- **Gately Point**: Proportional to nonseparable costs allocation.
- **Nucleolus**: Lexicographically minimal excess solution.
- **Cost-Based Allocation**: Direct cost allocation based on historical imbalances.
- **Excess Calculation**: Measures coalition dissatisfaction with proposed allocations and stability.

## How to Run

1. **Install Julia** (version 1.6 or later) and required packages (package list is currently large, will get reduced in final project):
   ```julia
   using Pkg
   Pkg.add(["JuMP", "HiGHS", "Plots", "Combinatorics", "StatsPlots", "CSV", "DataFrames", "Dates", "TimeZones", "Serialization"])
   ```

2. **Prepare Data**: Place the required data files in the `Data/` directory:
   - `Asset_master_data_asmus.csv`: Client and asset information
   - `consumption_data.csv`: Client consumption data
   - `ImbalancePrice.csv`: Imbalance and spot price data
   - `ProductionMunicipalityHour.csv`: Hourly PV production data
   - `Solar_Forecasts_Hour.csv`: Solar production forecasts

3. **Configure Simulation**: Edit parameters in `Imbalance_main.jl`:
   - `start_hour`: Simulation start time
   - `sim_days`: Number of simulation days
   - `num_scenarios`: Number of demand scenarios
   - `alpha`: CVaR confidence level (default: 0.05)
   - Forecast types: "perfect", "scenarios", or "noise"

4. **Run Analysis**: Execute the main script:
   ```julia
   julia Imbalance_main.jl
   ```

## Customization

### Allocation Methods
Modify the `allocations` array in `Imbalance_main.jl` to include/exclude specific allocation methods:
- `"shapley"`: Shapley value
- `"VCG"`: VCG mechanism
- `"gately"`: Gately point
- `"nucleolus"`: Nucleolus solution
- `"cost_based"`: Cost-based allocation

### Forecasting Parameters
- **Demand Forecast**: Set noise standard deviation (default: 0.17 for 7-10% MAE)
- **PV Forecast**: Set noise standard deviation (default: 0.32 for 22.5-25% MAE)
- **Scenario Generation**: Configure rolling window parameters for demand scenarios

### Client Selection
Filter clients by modifying the client list in `Imbalance_main.jl` to exclude specific participants or focus on subsets.

## Dependencies

### Core Julia Packages
- **JuMP**: Mathematical optimization modeling
- **HiGHS**: High-performance linear programming solver
- **Combinatorics**: Coalition enumeration
- **CSV, DataFrames**: Data handling
- **Dates, TimeZones**: Time series processing
- **Serialization**: Result storage

### Visualization
- **Plots, StatsPlots**: Julia plotting (for internal visualization)
- **matplotlib, pandas**: Python plotting (for publication-quality figures)

### Optional
- **Gurobi**: Alternative optimization solver (commercial)
- **NLsolve**: Nonlinear equation solving (for Gately point)

## Contact

For questions or contributions, please contact the repository owner.
