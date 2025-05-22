#include("Bat_arbitrage.jl")
include("Data_import.jl")
include("Scenario_creation.jl")
include("imbalance_functions.jl")
include("Game_theoretic_functions.jl")
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

shapley_values = shapley_value(clients_without_missing_data, coalitions, imbalances)
#println("Shapley values: ", shapley_values)
VCG_taxes, payments = VCG_tax(clients_without_missing_data, imbalances, hourly_imbalances, systemData; alternate_method=false)
cost_VCG = Dict()
for client in clients_without_missing_data
    cost_VCG[client] = sum(payments[client])+VCG_taxes[[client]]
end

# Checking stability
check_stability(shapley_values, imbalances, coalitions)

# Compare the sum of individual client imbalances with the grand coalition imbalance
grand_coalition = clients_without_missing_data
grand_coalition_imbalance = imbalances[grand_coalition]

individual_imbalance_sum = sum(imbalances[[client]] for client in clients_without_missing_data)

println("Grand coalition imbalance: ", grand_coalition_imbalance)
println("Sum of individual client imbalances: ", individual_imbalance_sum)
println("Difference: ", grand_coalition_imbalance - individual_imbalance_sum)
println("Sum of VCG taxes: ", sum(values(VCG_taxes)))

cost_shapley = deepcopy(shapley_values)

start_idx = findfirst(x -> x >= start_hour, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
end_idx = start_idx + sim_days * 24 - 1
dayData = deepcopy(systemData)
dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][start_idx:end_idx, :]
cost_MWh_shapley = scale_distribution(shapley_values, dayData["price_prod_demand_df"], clients_without_missing_data)
cost_MWh_VCG = scale_distribution(cost_VCG, dayData["price_prod_demand_df"], clients_without_missing_data)
# Plot the imbalance fees for each client
# Plot imbalance fees per MWh
p_fees_MWh = plot(title="Imbalance Fees per MWh for Clients", xlabel="Client", ylabel="Imbalance Fee per MWh")
plotKeys = sort(collect(keys(cost_MWh_shapley)))
plotValsMWh_shapley = [cost_MWh_shapley[k] for k in plotKeys]
plotValsMWh_VCG = [cost_MWh_VCG[k] for k in plotKeys]
scatter!(p_fees_MWh, plotKeys, plotValsMWh_shapley, label="Imbalance Fees per MWh Shapley")
scatter!(p_fees_MWh, plotKeys, plotValsMWh_VCG, label="Imbalance Fees per MWh VCG")
display(p_fees_MWh)

# Plot total imbalance fees
p_fees_total = plot(title="Total Imbalance Fees for Clients", xlabel="Client", ylabel="Total Imbalance Fee")
plotValsTotal = [cost_shapley[k] for k in plotKeys]
bar!(p_fees_total, plotKeys, plotValsTotal, label="Total Imbalance Fees")
display(p_fees_total)


# Plot aggregate demand, PV production, bids, and imbalance
p_aggregate = plot(title="Aggregate Demand, PV Production, Bids, and Imbalance", xlabel="Hour", ylabel="Value")
aggregate_demand = sum(dayData["price_prod_demand_df"][!, client] for client in clients_without_missing_data)
aggregate_pvProd = sum(dayData["price_prod_demand_df"][!, "SolarMWh"] .* systemData["clientPVOwnership"][client] for client in clients_without_missing_data)
combined_bids = bids[clients_without_missing_data]
combined_imbalance = combined_bids + aggregate_pvProd - aggregate_demand


n_hours = length(aggregate_demand)
plot!(p_aggregate, 1:n_hours, aggregate_demand, label="Aggregate Demand")
plot!(p_aggregate, 1:n_hours, aggregate_pvProd, label="Aggregate PV Production")
plot!(p_aggregate, 1:n_hours, combined_bids, label="Combined Bids")
plot!(p_aggregate, 1:n_hours, combined_imbalance, label="Combined Imbalance")
display(p_aggregate)

