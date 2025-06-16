#include("Bat_arbitrage.jl")
include("Data_import.jl")
include("Scenario_creation.jl")
include("imbalance_functions.jl")
include("Game_theoretic_functions.jl")
include("Plotting.jl")
using Plots, Dates, Random, Combinatorics, StatsPlots


Random.seed!(1) # Set seed for reproducibility

systemData, clients = load_data()
# Removing solar park owner "Z" and other clients as needed
clients = filter(x -> x != "Z", clients)
clients = filter(x -> x != "A", clients)
clients = filter(x -> x != "G", clients)
clients = filter(x -> !(x in ["W", "T", "P", "V", "J", "F","R","K"]), clients)
clients = filter(x -> x != "I", clients)
#clients = filter(x -> x in ["L", "Q"], clients)

coalitions = collect(combinations(clients))

# We assume that upregulation is more expensive than downregulation
#systemData["upreg_price"] = 1
#systemData["downreg_price"] = 1

# First hour 2024-04-16T22:00:00
# Last hour 2025-03-04T11:00:00
# Note that there must be enough data before the start hour to create scenarios
data_start_hour = DateTime(2024, 4, 16, 22, 0, 0) # First hour of data availability
start_hour = DateTime(2025, 2, 03, 0, 0, 0)
sim_days = 29
# Currently, demand and price must have the same amount of scenarios
num_scenarios = 40
demand_scenarios = generate_demand_scenarios(clients, systemData["price_prod_demand_df"], start_hour, data_start_hour; num_scenarios=num_scenarios)
price_scenarios = generate_price_scenarios(systemData["price_prod_demand_df"], start_hour, data_start_hour; num_scenarios= num_scenarios)
systemData["demand_scenarios"] = demand_scenarios
systemData["price_scenarios"] = price_scenarios

# Accepted forecast types: "perfect", "scenarios", "noise"
systemData["demand_forecast"] = "scenarios"
systemData["pv_forecast"] = "noise"
systemData["price_forecast"] = "scenarios"
println("Imbalance calculation time, all coalitions :")
#imbalance_costs, hourly_imbalances, bids  = @time period_imbalance(systemData, clients, start_hour, sim_days; threads = false)

allocations = [
    "shapley",
    #"VCG",
    #"VCG_budget_balanced",
    "gately_full",
    #"gately_daily",
    #"gately_hourly",
    #"full_cost",
    #"reduced_cost",
    #"nucleolus"
]

# Calculating allocations
println("Calculating allocations...")
daily_cost_MWh_imbalance, allocation_costs, imbalance_costs, hourly_imbalances = allocation_variance(allocations, clients, coalitions, systemData, start_hour, sim_days)
#allocation_costs = calculate_allocations(
#    allocations, clients, coalitions, imbalance_costs, hourly_imbalances, systemData
#)

# Checking stability
max_instability = Dict{String, Float64}()
for alloc in allocations
    #println("Checking stability for allocation: ", alloc)
    max_instability[alloc] = check_stability(allocation_costs[alloc], imbalance_costs, clients)
end
println("Max instabilities: ", max_instability)

# Compare the sum of individual client imbalance_costs with the grand coalition imbalance
grand_coalition = clients
grand_coalition_imbalance = imbalance_costs[grand_coalition]

individual_imbalance_sum = sum(imbalance_costs[[client]] for client in clients)

println("Grand coalition imbalance: ", grand_coalition_imbalance)
println("Sum of individual client imbalance_costs: ", individual_imbalance_sum)
println("Difference: ", grand_coalition_imbalance - individual_imbalance_sum)

plot_results(
    allocations,
    systemData,
    allocation_costs,
    imbalance_costs,
    clients,
    start_hour,
    sim_days, 
)
plot_client = "N"

plot_variance(
    allocations,
    allocation_costs,
    daily_cost_MWh_imbalance,
    imbalance_costs,
    plot_client,
    sim_days
)




