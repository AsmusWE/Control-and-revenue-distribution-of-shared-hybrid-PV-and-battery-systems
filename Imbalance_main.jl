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
systemData["upreg_price"] = 1
systemData["downreg_price"] = 1

# First hour 2024-04-16T22:00:00
# Last hour 2025-04-25T23:00:00
start_hour = DateTime(2024, 8, 12, 0, 0, 0)
sim_days = 36

demand_scenarios = generate_scenarios(clients, systemData["price_prod_demand_df"], start_hour; num_scenarios=100)
systemData["demand_scenarios"] = demand_scenarios

# Accepted forecast types: "perfect", "scenarios", "noise"
systemData["demand_forecast"] = "scenarios"
systemData["pv_forecast"] = "scenarios"
println("Imbalance calculation time, all coalitions :")
#imbalances, hourly_imbalances, bids  = @time period_imbalance(systemData, clients, start_hour, sim_days; threads = false)

allocations = [
    "shapley",
    "VCG",
    "VCG_budget_balanced",
    "gately_full",
    #"gately_daily",
    #"gately_hourly",
    "full_cost",
    "reduced_cost",
    "nucleolus"
]

# Calculating allocations
println("Calculating allocations...")
daily_cost_MWh_imbalance, allocation_costs, imbalances, hourly_imbalances = allocation_variance(allocations, clients, coalitions, systemData, start_hour, sim_days)
#allocation_costs = calculate_allocations(
#    allocations, clients, coalitions, imbalances, hourly_imbalances, systemData
#)

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

println("Grand coalition imbalance: ", grand_coalition_imbalance)
println("Sum of individual client imbalances: ", individual_imbalance_sum)
println("Difference: ", grand_coalition_imbalance - individual_imbalance_sum)

plot_results(
    allocations,
    systemData,
    allocation_costs,
    imbalances,
    clients,
    start_hour,
    sim_days
)

plot_client = "N"
allocation_labels = Dict(
    "shapley" => ("Shapley", :red),
    "VCG" => ("VCG", :yellow),
    "VCG_budget_balanced" => ("VCG Budget Balanced", :orange),
    "gately_full" => ("Gately Full", :grey),
    "gately_daily" => ("Gately Daily", :black),
    "gately_hourly" => ("Gately Hourly", :lightgrey),
    "full_cost" => ("Full Cost", :pink),
    "reduced_cost" => ("Reduced Cost", :lightblue),
    "nucleolus" => ("Nucleolus", :green)
)
p_variance = plot(
    title = "Daily Cost per Allocation for Client $plot_client",
    xlabel = "Allocation",
    ylabel = "Cost compared to no cooperation",
    xticks = (1:length(allocations), [allocation_labels[a][1] for a in allocations]),
    legend = false,
    #legend=:outertopright,
    xrotation = 45
)
# Cost per MWh imbalance
cost_imbalance = Dict{String, Dict{String, Float64}}()

for (i, alloc) in enumerate(allocations)
    label, color = allocation_labels[alloc]
    plotVals = [daily_cost_MWh_imbalance[plot_client, alloc, day] for day in 1:sim_days]
    boxplot!(fill(i, sim_days), plotVals; color=color, markerstrokecolor=:black, label=label)
    mean_val_unweighted = sum(plotVals) / length(plotVals)
    mean_val_weighted = allocation_costs[alloc][plot_client]/imbalances[[plot_client]]
    #annotate!(i, mean_val_unweighted, text(string(round(mean_val_unweighted, digits=4)), :black, :center, 8))
    # Add a red line for the weighted mean
    plot!([i-0.4, i+0.4], [mean_val_weighted, mean_val_weighted], color=:blue, linewidth=2, label=false)
end
display(p_variance)


