include("Bat_arbitrage.jl")
include("Common_functions.jl")
include("Data_import.jl")
using Plots


systemData, clients_without_missing_data = load_data()

clients = systemData["clients"]
# Set the number of hours for the simulation
hours = 200
systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][1:hours, :]

clients_array = collect(clients)
#clients_without_missing_data_indexes = [findfirst(isequal(client), clients_array) for client in clients_without_missing_data]

for client in clients_without_missing_data
    avg_prod_share = systemData["clientPVOwnership"][client] * sum(systemData["price_prod_demand_df"][!,"PVProduction"])/length(systemData["price_prod_demand_df"][!,"PVProduction"])
    println("Average demand for client ", client, ": ", sum(systemData["price_prod_demand_df"][!, client])/length(systemData["price_prod_demand_df"][!, client]), " Average production share: ", avg_prod_share)
    
end

collective_operation_sum = []
individual_operation_sum = []


battery_sizes = [0, 50, 100, 200]

#clients_without_missing_data = filter(x -> !(x in ["G", "A"]), clients_without_missing_data)

#systemData["price_prod_demand_df"][!, "PVProduction"] = systemData["price_prod_demand_df"][!, "PVProduction"]
#systemData["price_prod_demand_df"][!, "priceExp"] = systemData["price_prod_demand_df"][!, "PriceExp"]
#systemData["price_prod_demand_df"][!, "priceImp"] = systemData["price_prod_demand_df"][!, "PriceImp"]
for client in clients_without_missing_data
    systemData["price_prod_demand_df"][!, client] = systemData["price_prod_demand_df"][!, client] 
end

# Calculating operating costs for each battery size
for batsize in battery_sizes
    println("Calculating for battery size: ", batsize)
    systemData["batCap"] = batsize
    # Calculate operating costs when working together
    push!(collective_operation_sum,solve_coalition(clients_without_missing_data, systemData))

    temp_sum = 0
    # Calculate operating costs when working individually
    for client in clients_without_missing_data
        temp_sum += solve_coalition([client], systemData)
    end
    push!(individual_operation_sum, temp_sum)
end

# Calculating operating costs for individual operation without PV production as baseline

baseline_individual_operation = []
for client in clients_without_missing_data
    println("Calculating baseline for client: ", client)
    systemData["batCap"] = 0
    # Setting PV production to 0
    systemData["price_prod_demand_df"][!, "PVProduction"] = systemData["price_prod_demand_df"][!, "PVProduction"] .* 0
    push!(baseline_individual_operation, solve_coalition([client], systemData))
end
baseline_individual_operation_sum = sum(baseline_individual_operation)

collective_operation_improvement = collective_operation_sum .- baseline_individual_operation_sum
individual_operation_improvement = individual_operation_sum .- baseline_individual_operation_sum

# Subtracting 0 battery size from the rest
#collective_operation_improvement = collective_operation_improvement .+ collective_operation_improvement[1]
#individual_operation_improvement = individual_operation_improvement .+ individual_operation_improvement[1]

plot(battery_sizes, collective_operation_improvement, label="Collective Operation Improvement", lw=2, marker=:o)
plot!(battery_sizes, individual_operation_improvement, label="Individual Operation Improvement", lw=2, marker=:s)
xlabel!("Battery Size (MWh)")
ylabel!("Operation Sum")
title!("Operation Sum vs Battery Size")
display(current())

# Calculating percentage difference between collective and individual operation improvements
percentage_difference = 100 .* (collective_operation_improvement .- individual_operation_improvement) ./ individual_operation_improvement

# Plotting the percentage difference
plot(battery_sizes, percentage_difference, label="Percentage Difference", lw=2, marker=:d, linestyle=:dash)
ylabel!("Operation Sum / Percentage Difference")
display(current())