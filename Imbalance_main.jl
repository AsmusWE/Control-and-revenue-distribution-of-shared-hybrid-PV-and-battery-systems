#include("Bat_arbitrage.jl")
include("Data_import.jl")
include("Scenario_creation.jl")
include("imbalance_functions.jl")
include("Game_theoretic_functions.jl")
include("Plotting.jl")
using Plots, Dates, Random, Combinatorics







Random.seed!(1) # Set seed for reproducibility

systemData, clients_without_missing_data = load_data()
clients_without_missing_data = filter(x -> x != "Z", clients_without_missing_data)
#clients_without_missing_data = filter(x -> x != "A", clients_without_missing_data)
#clients_without_missing_data = filter(x -> x != "G", clients_without_missing_data)

#clients_without_missing_data = filter(x -> !(x in ["W", "T", "P", "V", "J", "F","R","K","U","Y","O"]), clients_without_missing_data)
#clients_without_missing_data = filter(x -> x in ["L", "Q"], clients_without_missing_data)

coalitions = collect(combinations(clients_without_missing_data))
demand_scenarios = generate_scenarios(clients_without_missing_data, systemData["price_prod_demand_df"]; num_scenarios=100)
systemData["demand_scenarios"] = demand_scenarios
# We assume that upregulation is more expensive than downregulation
systemData["upreg_price"] = 1
systemData["downreg_price"] = 1

# First hour 2024-04-16T22:00:00
# Last hour 2025-04-25T23:00:00
start_hour = DateTime(2024, 8, 12, 0, 0, 0)
sim_days = 6

systemData["perfect_demand_forecast"] = false
systemData["perfect_pv_forecast"] = false

imbalances, hourly_imbalances, bids  = @time period_imbalance(systemData, clients_without_missing_data, start_hour, sim_days)

allocation_costs = Dict{String, Dict{String, Float64}}()
# Calculating allocations
shapley_values = shapley_value(clients_without_missing_data, coalitions, imbalances)
allocation_costs["shapley"] = deepcopy(shapley_values)
#println("Shapley values: ", shapley_values)
VCG_taxes, payments = VCG_tax(clients_without_missing_data, imbalances, hourly_imbalances, systemData; budget_balance=true)
allocation_costs["VCG"] = Dict()
for client in clients_without_missing_data
    allocation_costs["VCG"][client] = sum(payments[client])+VCG_taxes[[client]]
end
gately_values = gately_point(clients_without_missing_data, imbalances)
allocation_costs["gately"] = deepcopy(gately_values)
full_cost_transfer_values = full_cost_transfer(clients_without_missing_data, hourly_imbalances, systemData)
allocation_costs["full_cost"] = deepcopy(full_cost_transfer_values)

# Checking stability
max_instability = Dict{String, Float64}()
max_instability["shapley"] = check_stability(allocation_costs["shapley"], imbalances, clients_without_missing_data)
max_instability["VCG"] = check_stability(allocation_costs["VCG"], imbalances, clients_without_missing_data)
max_instability["gately"] = check_stability(allocation_costs["gately"], imbalances, clients_without_missing_data)
max_instability["full_cost"] = check_stability(allocation_costs["full_cost"], imbalances, clients_without_missing_data)
println("Max instabilities: ", max_instability)

# Compare the sum of individual client imbalances with the grand coalition imbalance
grand_coalition = clients_without_missing_data
grand_coalition_imbalance = imbalances[grand_coalition]

individual_imbalance_sum = sum(imbalances[[client]] for client in clients_without_missing_data)

println("Grand coalition imbalance: ", grand_coalition_imbalance)
println("Sum of individual client imbalances: ", individual_imbalance_sum)
println("Difference: ", grand_coalition_imbalance - individual_imbalance_sum)
println("Sum of VCG taxes: ", sum(values(VCG_taxes)))

plot_results(
    systemData,
    allocation_costs,
    bids,
    imbalances,
    clients_without_missing_data,
    start_hour,
    sim_days
)

