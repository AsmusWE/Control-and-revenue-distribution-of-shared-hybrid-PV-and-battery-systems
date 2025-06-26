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
# Removing solar park owner "Z" and other clients as needed
clients = filter(x -> x != "Z", clients)
clients = filter(x -> !(x in ["W", "N", "V", "J", "O", "T", "Y"]), clients)
clients = filter(x -> !(x in ["L", "U"]), clients)
coalitions = collect(combinations(clients))

# We assume that upregulation is more expensive than downregulation
systemData["upreg_price"] = 1
systemData["downreg_price"] = 1

# First hour 2024-04-16T22:00:00
# Last hour 2025-04-25T23:00:00
start_hour = DateTime(2025, 3, 1, 0, 0, 0)
sim_days = 31
num_scenarios = 60
demand_scenarios = generate_scenarios(clients, systemData["price_prod_demand_df"], start_hour; num_scenarios=num_scenarios)
systemData["demand_scenarios"] = demand_scenarios

# Accepted forecast types: "perfect", "scenarios", "noise"
systemData["demand_forecast"] = "noise"
systemData["pv_forecast"] = "noise"

allocations = [
    #"shapley",
    "VCG",
    #"VCG_budget_balanced",
    #"gately_full",
    #"gately_daily",
    #"gately_hourly",
    #"full_cost",
    #"reduced_cost",
    #"nucleolus",
    #"equal_share"
]

# =========================
# 2. Imbalance Calculation and allocation
# =========================
# Calculating allocations
println("Calculating allocations...")
daily_cost_MWh_imbalance, allocation_costs, imbalances, hourly_imbalances = @time allocation_variance(allocations, clients, coalitions, systemData, start_hour, sim_days)

# Checking stability
max_instability = Dict{String, Float64}()
for alloc in allocations
    println("Checking stability for allocation: ", alloc)
    max_instability[alloc] = check_stability(allocation_costs[alloc], imbalances, clients)
end
println("Max instabilities: ", max_instability)

# Compare the sum of individual client imbalances with the grand coalition imbalance
grand_coalition = clients
grand_coalition_imbalance = imbalances[grand_coalition]

individual_imbalance_sum = sum(imbalances[[client]] for client in clients)
VCG_cost = sum(values(allocation_costs["VCG"]))

println("Grand coalition imbalance: ", grand_coalition_imbalance)
println("Sum of individual client imbalances: ", individual_imbalance_sum)
println("Difference: ", grand_coalition_imbalance - individual_imbalance_sum)
println("VCG cost: ", VCG_cost)
println("VCG subsidies: ", grand_coalition_imbalance - VCG_cost)

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
    imbalances,
    clients,
    start_hour,
    sim_days,
    daily_cost_MWh_imbalance
)
# Save plot_data to the "Results" subfolder
serialize("Results/plot_data_temp.jls", plot_data)

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

#plot_client = "N"

#plot_variance(
#    plot_data.allocations,
#    plot_data.allocation_costs,
#    plot_data.daily_cost_MWh_imbalance,
#    plot_data.imbalances,
#    plot_client,
#    plot_data.sim_days;
#    outliers = false
#)



