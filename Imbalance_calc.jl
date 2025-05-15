#include("Bat_arbitrage.jl")
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

function calculate_imbalance(systemData, clients)
    coalitions = collect(combinations(clients))
    bids = calculate_bids(coalitions, systemData)
    demand_sum = Dict()
    scaled_pvProd = Dict()
    imbalance = Dict()
    for coalition in coalitions
        demand_sum[coalition] = sum(systemData["price_prod_demand_df"][!, i] for i in coalition)
        scaled_pvProd[coalition] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* sum(systemData["clientPVOwnership"][i] for i in coalition)
        imbalance[coalition] = daily_imbalance(bids[coalition], scaled_pvProd[coalition], demand_sum[coalition])
    end
    
    # Calculate the total imbalance for each coalition
    total_imbalance = Dict()
    for coalition in coalitions
        #print("Coalition imbalance: ", coalition, " = ", sum(imbalance[coalition]), "\n")
        total_imbalance[coalition] = sum(abs.(imbalance[coalition]))
    end
    # Calculate the sum of the imbalances of the single client coalitions
    single_client_imbalance_sum = sum(total_imbalance[[client]] for client in clients)

    # Calculate the imbalance of the grand coalition
    grand_coalition = clients
    grand_coalition_imbalance = total_imbalance[grand_coalition]

    return total_imbalance, bids, imbalance
end

function calculate_bids(coalitions, systemData)
    # This function calculates the bids for each coalition combination
    bids = Dict()
    # A different dictionary is initialized for each thread to avoid
    # simultaneous writes to the same dictionary
    #thread_local_bids = Dict(tid => Dict() for tid in 1:Threads.nthreads())
    #Threads.@threads for clients in coalitions
    #    thread_local_bids[Threads.threadid()][clients] = optimize_imbalance(clients, systemData)
    #end
    #for thread_dict in values(thread_local_bids)
    #    merge!(bids, thread_dict)
    #end

    # Instead of explicitly calculating each coalition's bids, we can combine the individual bids
    # Calculate bids for each single client
    for client in coalitions
        if length(client) == 1
            #println("Calculating bids for client: ", client)
            #println(sum(systemData["demand_scenarios"][c] for c in client))
            bids[client] = optimize_imbalance(client, systemData)
        end
    end

    # Calculate bids for each coalition by summing the bids of its members
    for coalition in coalitions
        bids[coalition] = sum(bids[[client]] for client in coalition)
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

function scale_distribution(distribution, demand, clients)
    # Divide distribution factor by the sum of demand for each client
    scaled_distribution = Dict()
    for client in clients
        scaled_distribution[client] = distribution[client]/sum(demand[!,client])
    end
    return scaled_distribution
end

function check_stability(payoffs, coalition_values, coalitions)
    # Checks if the value of a coalition is larger than their reward as part of the grand coalition
    instabilities = Dict()
    for c in coalitions
        if coalition_values[c] < sum(payoffs[i] for i in c)-0.000001 # Adding a small tolerance to avoid floating point errors
            instabilities[c] =sum(payoffs[i] for i in c) - coalition_values[c] 
        end
    end
    if isempty(instabilities)
        println("No instabilities found.")
        return
    end
    max_instability = maximum(values(instabilities))
    max_instability_key = findfirst(x -> x == max_instability, instabilities)
    println("Maximum instability is for coalition ", max_instability_key, " with value ", max_instability, " corresponding to a ", max_instability / coalition_values[max_instability_key] * 100, "% lower imbalance compared to the grand coalition")
    #if !isnothing(max_instability_key)
    #    for client in max_instability_key
    #        solo_value = coalition_values[[client]]
    #        payoff_diff = payoffs[client] - solo_value
    #        println("Client ", client, ": Payoff = ", payoffs[client], ", Operating alone value = ", solo_value, ", Difference = ", payoff_diff)
    #    end
    #end
end

function period_imbalance(systemData, clients, startDay, days)
    # This function calculates the imbalance for a given period
    # It returns the imbalance for the given period
    # The period is given in hours
    start_hour = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
    end_hour = start_hour + 24 * days - 1
    period_imbalances = Dict()
    dayData = deepcopy(systemData)
    dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][start_hour:end_hour, :]
    # Calculate daily imbalances for each day in the period
    for day in 1:days
        println("Calculating imbalances for day ", day, " of ", days)
        day_start = start_hour + (day - 1) * 24
        day_end = day_start + 23
        dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][day_start:day_end, :]
        daily_imbalances, _ = calculate_imbalance(dayData, clients)

        # Sum the daily imbalances into the period_imbalances dictionary
        for (coalition, imbalance) in daily_imbalances
            period_imbalances[coalition] = imbalance
        end
    end

    return period_imbalances
end

Random.seed!(1) # Set seed for reproducibility

systemData, clients_without_missing_data = load_data()
clients_without_missing_data = filter(x -> x != "Z", clients_without_missing_data)
#clients_without_missing_data = filter(x -> !(x in ["W", "T", "P", "V", "J", "F","R","K","U","Y","O"]), clients_without_missing_data)
#clients_without_missing_data = filter(x -> x in ["A", "S"], clients_without_missing_data)

coalitions = collect(combinations(clients_without_missing_data))
demand_scenarios = generate_scenarios(clients_without_missing_data, systemData["price_prod_demand_df"]; num_scenarios=600)
systemData["demand_scenarios"] = demand_scenarios

#dayData = deepcopy(systemData)
#dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][25:48, :]

#imbalances, bids, hourly_imbalance = calculate_imbalance(dayData, clients_without_missing_data)
start_hour = DateTime(2023, 7, 1, 0, 0, 0)
sim_days = 5

imbalances = period_imbalance(systemData, clients_without_missing_data, start_hour, sim_days)

bids["sum"] = bids[collect(keys(bids))[2]] + bids[collect(keys(bids))[3]] - bids[collect(keys(bids))[1]]
shapley_values = shapley_value(clients_without_missing_data, coalitions, imbalances)
println("Shapley values: ", shapley_values)

# Checking stability
check_stability(shapley_values, imbalances, coalitions)

# Compare the sum of individual client imbalances with the grand coalition imbalance
grand_coalition = clients_without_missing_data
grand_coalition_imbalance = imbalances[grand_coalition]

individual_imbalance_sum = sum(imbalances[[client]] for client in clients_without_missing_data)

println("Grand coalition imbalance: ", grand_coalition_imbalance)
println("Sum of individual client imbalances: ", individual_imbalance_sum)

if grand_coalition_imbalance < individual_imbalance_sum
    println("The grand coalition achieves a lower total imbalance compared to individual clients.")
else
    println("The sum of individual client imbalances is less than or equal to the grand coalition imbalance.")
end

imbalance_fee_total = deepcopy(shapley_values)
imbalance_fee_MWh = scale_distribution(shapley_values, dayData["price_prod_demand_df"], clients_without_missing_data)
# Plot the imbalance fees for each client
# Plot imbalance fees per MWh
p_fees_MWh = plot(title="Imbalance Fees per MWh for Clients", xlabel="Client", ylabel="Imbalance Fee per MWh")
plotKeys = sort(collect(keys(imbalance_fee_MWh)))
plotValsMWh = [imbalance_fee_MWh[k] for k in plotKeys]
bar!(p_fees_MWh, plotKeys, plotValsMWh, label="Imbalance Fees per MWh")
display(p_fees_MWh)

# Plot total imbalance fees
p_fees_total = plot(title="Total Imbalance Fees for Clients", xlabel="Client", ylabel="Total Imbalance Fee")
plotValsTotal = [imbalance_fee_total[k] for k in plotKeys]
bar!(p_fees_total, plotKeys, plotValsTotal, label="Total Imbalance Fees")
display(p_fees_total)


# Plot aggregate demand, PV production, bids, and imbalance
p_aggregate = plot(title="Aggregate Demand, PV Production, Bids, and Imbalance", xlabel="Hour", ylabel="Value")
aggregate_demand = sum(dayData["price_prod_demand_df"][!, client] for client in clients_without_missing_data)
aggregate_pvProd = sum(dayData["price_prod_demand_df"][!, "SolarMWh"] .* systemData["clientPVOwnership"][client] for client in clients_without_missing_data)
combined_bids = bids[clients_without_missing_data]
combined_imbalance = combined_bids + aggregate_pvProd - aggregate_demand


plot!(p_aggregate, 1:24, aggregate_demand, label="Aggregate Demand")
plot!(p_aggregate, 1:24, aggregate_pvProd, label="Aggregate PV Production")
plot!(p_aggregate, 1:24, combined_bids, label="Combined Bids")
plot!(p_aggregate, 1:24, combined_imbalance, label="Combined Imbalance")
display(p_aggregate)

