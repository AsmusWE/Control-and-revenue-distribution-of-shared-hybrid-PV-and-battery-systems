# Imbalance_main.jl
# Main script for running coalition imbalance and allocation analysis
# Author: Asmus Winther Eriksen

# --- Project Modules ---
include("Data_import.jl")
include("Scenario_creation.jl")
include("imbalance_functions.jl")
include("Game_theoretic_functions.jl")
include("Plotting.jl")

# --- External Packages ---
using Plots, Dates, Random, Combinatorics, StatsPlots, Serialization


Random.seed!(1) # Set seed for reproducibility

# =========================
# 1. Data Loading & Setup
# =========================
systemData, clients = load_data()
clients = filter(x -> x != "G", clients)
clients = filter(x -> !(x in ["W", "N", "V", "J", "O", "T"]), clients)
#clients = filter(x -> !(x in ["L", "U"]), clients)
coalitions = collect(combinations(clients))

# First hour 2024-03-04T12:00:00
# Last hour 2025-04-26T03:45:00
start_hour = DateTime(2025, 4, 10, 0, 0, 0)
sim_days = 1
num_scenarios = 5
demand_scenarios = generate_scenarios(clients, systemData["price_prod_demand_df"], start_hour; num_scenarios=num_scenarios)
systemData["demand_scenarios"] = demand_scenarios

# Accepted forecast types: "perfect", "scenarios", "noise"
systemData["demand_forecast"] = "noise"
systemData["pv_forecast"] = "noise"
# Set standard deviations for noise
# Adjusting so demand MAE is 7-10% and PV MAE is 22.5-25%
systemData["demand_noise_std"] = 0.15
systemData["pv_noise_std"] = 0.55

allocations = [
    "shapley",
    "VCG",
    #"VCG_budget_balanced",
    "gately",
    #"gately_daily",
    #"gately_interval",
    #"full_cost",
    #"reduced_cost",
    "nucleolus",
    #"equal_share"
]

# =========================
# 2. Imbalance Calculation and allocation
# =========================
# Calculating CVaR
println("Calculating CVaR for coalitions...")
coalitionCVaR, imbalances, demandForecast, pvForecast = @time calculate_CVaR(systemData, clients, start_hour, sim_days; alpha=0.1)

# Checking MAE
MAE_demand, MAE_pv = calculate_MAE(systemData, demandForecast, pvForecast, clients, start_hour, sim_days)
println("MAE Demand: ", MAE_demand)
println("MAE PV: ", MAE_pv)

# Calculating allocations
println("Calculating allocations...")
#daily_cost_MWh_imbalance, allocation_costs, imbalances, hourly_imbalances = @time allocation_variance(allocations, clients, coalitions, systemData, start_hour, sim_days)
allocation_costs = calculate_allocations(
    allocations, clients, coalitions, coalitionCVaR, 0, systemData; printing = true
    )


# Checking stability
max_instability = Dict{String, Float64}()
for alloc in allocations
    println("Checking stability for allocation: ", alloc)
    max_instability[alloc] = check_stability(allocation_costs[alloc], coalitionCVaR, clients)
end
println("Max instabilities: ", max_instability)

# Compare the sum of individual client CVaR with the grand coalition CVaR
grand_coalition = clients
grand_coalition_CVaR = coalitionCVaR[grand_coalition]

individual_CVaR_sum = sum(coalitionCVaR[[client]] for client in clients)
VCG_cost = sum(values(allocation_costs["VCG"]))

println("Grand coalition CVaR: ", grand_coalition_CVaR)
println("Sum of individual client CVaR (THIS IS PROBABLY NOT A USEFUL MEASUREMENT): ", individual_CVaR_sum)
#println("Difference: ", grand_coalition_imbalance - individual_imbalance_sum)
println("VCG cost: ", VCG_cost)
println("VCG subsidies: ", grand_coalition_CVaR - VCG_cost)

# Define a struct to hold all relevant plotting data
struct PlotData
    allocations::Vector{String}
    systemData::Dict{String, Any}
    allocation_costs::Dict{String, Any}
    imbalances::Dict{Any, Any}
    clients::Vector{String}
    start_hour::DateTime
    sim_days::Int
    daily_cost_MWh_imbalance::Any
end

# Create an instance of PlotData
plot_data = PlotData(
    allocations,
    systemData,
    allocation_costs,
    coalitionCVaR,
    clients,
    start_hour,
    sim_days,
    0 # Placeholder for daily_cost_MWh_imbalance, as it is not calculated in this script
)
# Save plot_data to the "Results" subfolder
serialize("Results/temp.jls", plot_data)

# Use the struct for plotting
plot_results(
    plot_data.allocations,
    plot_data.systemData,
    plot_data.allocation_costs,
    plot_data.imbalances,
    plot_data.clients,
    plot_data.start_hour,
    plot_data.sim_days
)

#plot_client = "U"
#plot_variance(
#    plot_data.allocations,
#    plot_data.allocation_costs,
#    plot_data.daily_cost_MWh_imbalance,
#    plot_data.imbalances,
#    plot_client,
#    plot_data.sim_days;
#    outliers = false
#)



