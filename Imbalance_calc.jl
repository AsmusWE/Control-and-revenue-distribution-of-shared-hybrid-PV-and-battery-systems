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
    # Calculate the total imbalance for each coalition
    total_imbalance = Dict()
    for coalition in coalitions
        total_imbalance[coalition] = sum(imbalance[coalition])
    end
    return total_imbalance, bids
end

function calculate_bids(coalitions, systemData)
    # This function calculates the bids for each coalition combination
    bids = Dict()
    # A different dictionary is initialized for each thread to avoid
    # simultaneous writes to the same dictionary
    thread_local_bids = Dict(tid => Dict() for tid in 1:Threads.nthreads())
    Threads.@threads for clients in coalitions
        thread_local_bids[Threads.threadid()][clients] = optimize_imbalance(clients, systemData)
    end
    for thread_dict in values(thread_local_bids)
        merge!(bids, thread_dict)
    end
    return bids
end

function shapley_value(clients, coalitions, imbalances)
    n = length(clients)
    shapley_vals = Dict()
    for client in clients
        shapley_vals[client] = 0.0
    end

    for (idx, i) in enumerate(clients)
        i_coalition = [c for c in coalitions if clients[idx] in c]
        # Looping through all coalitions containing client i
        for c in i_coalition
            S = length(c)
            # Creating the coalition that doesn't contain client i
            c_without_i = filter(x -> x != clients[idx], c)
            # If the coalition without client i is empty, set value of empty coalition as 0
            if isempty(c_without_i)
                imbalance_without_i = 0.0
            else
                imbalance_without_i = imbalances[c_without_i]
            end

            # Calculate the Shapley value contribution for client i in coalition c
            shapley_vals[i] += factorial(S - 1) * factorial(n - S) / factorial(n) * (imbalances[c] - imbalance_without_i)
        end
    end

    return shapley_vals
end

Random.seed!(12) # Set seed for reproducibility

systemData, clients_without_missing_data = load_data()
clients_without_missing_data = filter(x -> x != "Z", clients_without_missing_data)
clients_without_missing_data = filter(x -> !(x in ["W", "T", "P", "V", "J", "F","R","K","U","Y","O"]), clients_without_missing_data)

coalitions = collect(combinations(clients_without_missing_data))
demand_scenarios = generate_scenarios(clients_without_missing_data, systemData["price_prod_demand_df"]; num_scenarios=200)
systemData["demand_scenarios"] = demand_scenarios

simulation_days = 1

imbalance_results = Dict()

dayData = deepcopy(systemData)
dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][1:24, :]
imbalances, bids = calculate_imbalance(dayData, clients_without_missing_data; plotting=false)

shapley_values = shapley_value(clients_without_missing_data, coalitions, imbalances)
println("Shapley values: ", shapley_values)

#total_imbalance, bids = calculate_imbalance(systemData, clients_without_missing_data; days=simulation_days, plotting=false)

#for (idx,clients) in enumerate(client_combinations)
#    if idx % 1000 == 0
#        println("Processing combination: ", idx, " of ", length(client_combinations))
#    end
#    total_imbalance, bids = calculate_imbalance(systemData, clients; days=simulation_days, plotting=false)
#    imbalance_results[clients] = total_imbalance
#end