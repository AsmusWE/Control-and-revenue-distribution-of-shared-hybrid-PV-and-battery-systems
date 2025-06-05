#include("Bat_arbitrage.jl")
include("Data_import.jl")
include("Scenario_creation.jl")
include("imbalance_functions.jl")
include("Game_theoretic_functions.jl")
include("Plotting.jl")
using Plots, Dates, Random, Combinatorics


Random.seed!(1) # Set seed for reproducibility

systemData, clients = load_data()
# Removing solar park owner "Z" and other clients as needed
clients = filter(x -> x != "Z", clients)
clients = filter(x -> x != "A", clients)
clients = filter(x -> x != "G", clients)
#clients = filter(x -> !(x in ["W", "T", "P", "V", "J", "F","R","K","U","Y","O"]), clients)
#clients = filter(x -> x in ["L", "Q"], clients)

coalitions = collect(combinations(clients))
demand_scenarios = generate_scenarios(clients, systemData["price_prod_demand_df"]; num_scenarios=200)
systemData["demand_scenarios"] = demand_scenarios
# We assume that upregulation is more expensive than downregulation
systemData["upreg_price"] = 1
systemData["downreg_price"] = 1

# First hour 2024-04-16T22:00:00
# Last hour 2025-04-25T23:00:00
start_hour = DateTime(2024, 8, 12, 0, 0, 0)
sim_days = 36

# Accepted forecast types: "perfect", "scenarios", "noise"
systemData["demand_forecast"] = "noise"
systemData["pv_forecast"] = "noise"
println("Imbalance calculation time, all coalitions :")
imbalances, hourly_imbalances, bids  = @time period_imbalance(systemData, clients, start_hour, sim_days; threads = false)

allocation_costs = Dict{String, Dict{String, Float64}}()
# Calculating allocations
println("Calculating allocations...")
println("Shapley calculation time:")
shapley_values = @time shapley_value(clients, coalitions, imbalances)
allocation_costs["shapley"] = deepcopy(shapley_values)
#println("Shapley values: ", shapley_values)
println("VCG calculation time:")
VCG_taxes, payments = @time VCG_tax(clients, imbalances, hourly_imbalances, systemData; budget_balance=true)
allocation_costs["VCG"] = Dict()
for client in clients
    allocation_costs["VCG"][client] = sum(payments[client])+VCG_taxes[[client]]
end
println("Gately calculation time:")
gately_values = @time gately_point(clients, imbalances)
allocation_costs["gately"] = deepcopy(gately_values)
println("Full cost transfer calculation time:")
full_cost_transfer_values = @time full_cost_transfer(clients, hourly_imbalances, systemData)
allocation_costs["full_cost"] = deepcopy(full_cost_transfer_values)
println("Nucleolus calculation time:")
___ , nucleolus_values = @time nucleolus(clients, imbalances)
allocation_costs["nucleolus"] = deepcopy(nucleolus_values)

# Checking stability
max_instability = Dict{String, Float64}()
max_instability["shapley"] = check_stability(allocation_costs["shapley"], imbalances, clients)
max_instability["VCG"] = check_stability(allocation_costs["VCG"], imbalances, clients)
max_instability["gately"] = check_stability(allocation_costs["gately"], imbalances, clients)
max_instability["full_cost"] = check_stability(allocation_costs["full_cost"], imbalances, clients)
max_instability["nucleolus"] = check_stability(allocation_costs["nucleolus"], imbalances, clients)
println("Max instabilities: ", max_instability)

# Compare the sum of individual client imbalances with the grand coalition imbalance
grand_coalition = clients
grand_coalition_imbalance = imbalances[grand_coalition]

individual_imbalance_sum = sum(imbalances[[client]] for client in clients)

println("Grand coalition imbalance: ", grand_coalition_imbalance)
println("Sum of individual client imbalances: ", individual_imbalance_sum)
println("Difference: ", grand_coalition_imbalance - individual_imbalance_sum)
println("Sum of VCG taxes: ", sum(values(VCG_taxes)))

plot_results(
    systemData,
    allocation_costs,
    bids,
    imbalances,
    clients,
    start_hour,
    sim_days
)
