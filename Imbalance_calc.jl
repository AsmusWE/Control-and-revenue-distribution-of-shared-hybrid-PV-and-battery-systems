#include("Bat_arbitrage.jl")
include("Common_functions.jl")
include("Data_import.jl")
include("Scenario_creation.jl")
include("imbalance_reduction.jl")
using Plots, Dates, Random

function daily_imbalance(bids, pvProd, demand)
    pvProd = pvProd[1:length(bids)] # Ensure pvProd is the same length as bids
    demand = demand[1:length(bids)] # Ensure demand is the same length as bids
    imbalance = bids + pvProd - demand
    return imbalance
end

function calculate_imbalance(systemData, clients; days = 5, plotting = false)
    bids = zeros(24, days)
    demand_sum = zeros(24, days)
    imbalance = zeros(24, days)
    scaled_pvProd = zeros(24, days)
    for day in 1:days
        tempData = deepcopy(systemData)
        tempData["price_prod_demand_df"] = systemData["price_prod_demand_df"][(day-1)*24+1:day*24, :]
        bids[:,day] = optimize_imbalance(clients, tempData)
        demand_sum[:,day] = sum(tempData["price_prod_demand_df"][!, i] for i in clients)
        scaled_pvProd[:,day] = tempData["price_prod_demand_df"][!, "SolarMWh"] .* sum(tempData["clientPVOwnership"][i] for i in clients)
        imbalance[:,day] = daily_imbalance(bids[:,day], scaled_pvProd[:,day], demand_sum[:,day])
    end

    if plotting
        avg_imbalance = sum(imbalance, dims=2) / size(imbalance, 2)
        avg_demand = sum(demand_sum, dims=2) / size(demand_sum, 2)
        avg_production = sum(scaled_pvProd, dims=2) / size(scaled_pvProd, 2)
        avg_bids = sum(bids, dims=2) / size(bids, 2)
        avg_demand_scenarios = sum(sum(demand_scenarios, dims=3), dims=2) / size(demand_scenarios, 3)

        plot(1:24, avg_imbalance, label="Average Imbalance", xlabel="Hour", ylabel="Value", title="Average Values Over 24 Hours")
        plot!(1:24, avg_demand, label="Average Demand")
        plot!(1:24, avg_production, label="Average Production")
        plot!(1:24, avg_bids, label="Average Bids")
        plot!(1:24, avg_demand_scenarios[:], label="Average Demand Scenarios")
    end

    total_imbalance = sum(imbalance)
    return total_imbalance
end

Random.seed!(1234) # Set seed for reproducibility

systemData, clients_without_missing_data = load_data()
clients_without_missing_data = filter(x -> x != "Z", clients_without_missing_data)
demand_scenarios = generate_scenarios(clients_without_missing_data, systemData["price_prod_demand_df"]; num_scenarios=100)
systemData["demand_scenarios"] = demand_scenarios


imbalance = calculate_imbalance(systemData, clients_without_missing_data; days=5)


