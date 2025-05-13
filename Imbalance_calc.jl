#include("Bat_arbitrage.jl")
include("Common_functions.jl")
include("Data_import.jl")
include("Scenario_creation.jl")
include("imbalance_reduction.jl")
using Plots, Dates, Random, Combinatorics

function daily_imbalance(bids, pvProd, demand)
    pvProd = pvProd[1:length(bids)] # Ensure pvProd is the same length as bids
    demand = demand[1:length(bids)] # Ensure demand is the same length as bids
    imbalance = bids + pvProd - demand
    return imbalance
end

function calculate_imbalance(systemData, clients; plotting = false)
    coalitions = collect(combinations(clients))
    @time begin
    bids = calculate_bids(coalitions, systemData)
    end
    demand_sum = Dict()
    scaled_pvProd = Dict()
    imbalance = Dict()
    for coalition in coalitions
        demand_sum[coalition] = sum(systemData["price_prod_demand_df"][!, i] for i in coalition)
        scaled_pvProd[coalition] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* sum(systemData["clientPVOwnership"][i] for i in coalition)
        imbalance[coalition] = daily_imbalance(bids[coalition], scaled_pvProd[coalition], demand_sum[coalition])
    end
    
    if plotting
        avg_imbalance = sum(imbalance, dims=2) / size(imbalance, 2)
        avg_demand = sum(demand_sum, dims=2) / size(demand_sum, 2)
        avg_production = sum(scaled_pvProd, dims=2) / size(scaled_pvProd, 2)
        avg_bids = sum(bids, dims=2) / size(bids, 2)
        demand_scens_sum = sum(systemData["demand_scenarios"][c] for c in clients)
        avg_demand_scenarios = sum(demand_scens_sum, dims=2) / size(demand_scens_sum, 2)

        p = plot(1:24, avg_imbalance, label="Average Imbalance", xlabel="Hour", ylabel="Value", title="Average Values Over 24 Hours")
        plot!(p, 1:24, avg_demand, label="Average Demand")
        plot!(p, 1:24, avg_production, label="Average Production")
        plot!(p, 1:24, avg_bids, label="Average Bids")
        plot!(p, 1:24, avg_demand_scenarios[:], label="Average Demand Scenarios")
        
        display(p)
    end

    return imbalance, bids
end

function calculate_bids(coalitions, systemData)
    # This function calculates the bids for each coalition combination
    bids = Dict()
    Threads.@threads for clients in coalitions
        bids[clients] = optimize_imbalance(clients,systemData)
    end
    return bids
end

Random.seed!(12) # Set seed for reproducibility

systemData, clients_without_missing_data = load_data()
clients_without_missing_data = filter(x -> x != "Z", clients_without_missing_data)
clients_without_missing_data = filter(x -> !(x in ["W", "T", "P", "V", "J", "F","R","K","U","Y","O","A"]), clients_without_missing_data)

coalitions = collect(combinations(clients_without_missing_data))
demand_scenarios = generate_scenarios(clients_without_missing_data, systemData["price_prod_demand_df"]; num_scenarios=200)
systemData["demand_scenarios"] = demand_scenarios

simulation_days = 1

imbalance_results = Dict()

dayData = deepcopy(systemData)
dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][1:24, :]
imbalances, bids = calculate_imbalance(dayData, clients_without_missing_data; plotting=false)
println("Test")
#total_imbalance, bids = calculate_imbalance(systemData, clients_without_missing_data; days=simulation_days, plotting=false)

#for (idx,clients) in enumerate(client_combinations)
#    if idx % 1000 == 0
#        println("Processing combination: ", idx, " of ", length(client_combinations))
#    end
#    total_imbalance, bids = calculate_imbalance(systemData, clients; days=simulation_days, plotting=false)
#    imbalance_results[clients] = total_imbalance
#end