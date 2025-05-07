include("Bat_arbitrage.jl")
include("Common_functions.jl")
include("Data_import.jl")
using Plots
using Dates

systemData, clients_without_missing_data = load_data()
# Set the number of hours for the simulation
hours = 1000
systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][1:hours, :]
clients = systemData["clients"]

# Removing clients from cooperation
#clients_without_missing_data = filter(x -> !(x in ["G", "A"]), clients_without_missing_data)
clients_without_missing_data = filter(x -> !(x in ["Z"]), clients_without_missing_data)

#systemData["price_prod_demand_df"][!, "priceImp"] = systemData["price_prod_demand_df"][!, "PriceImp"]
#for client in clients_without_missing_data
#    systemData["price_prod_demand_df"][!, client] = systemData["price_prod_demand_df"][!, client] 
#end

collective_operation_sum = []
collective_operation_import = []
individual_operation_sum = []
individual_operation_import = []

battery_sizes = [0, 10, 25, 50, 75, 100, 200, 250]

# Calculating operating costs for each battery size
for batsize in battery_sizes
    println("Calculating for battery size: ", batsize)
    systemData["batCap"] = batsize
    # Calculate operating costs when working together
    coalition_result, imported_pow = solve_coalition(clients_without_missing_data, systemData)
    push!(collective_operation_sum, coalition_result)
    push!(collective_operation_import, imported_pow)
    temp_sum = 0
    temp_import = 0
    # Calculate operating costs when working individually
    for client in clients_without_missing_data
        coalition_result, imported_pow = solve_coalition([client], systemData)
        temp_sum += coalition_result
        temp_import += imported_pow
    end
    push!(individual_operation_sum, temp_sum)
    push!(individual_operation_import, temp_import)
end

# Calculating operating costs for individual operation without PV production as baseline

baseline_individual_operation = []
baseline_individual_operation_import = []
for client in clients_without_missing_data
    println("Calculating baseline for client: ", client)
    systemData["batCap"] = 0
    # Setting PV production to 0
    systemData["price_prod_demand_df"][!, "SolarMWh"] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* 0
    coalition_result, imported_pow = solve_coalition([client], systemData)
    push!(baseline_individual_operation, coalition_result)
    push!(baseline_individual_operation_import, imported_pow)
end
baseline_individual_operation_sum = sum(baseline_individual_operation)
baseline_individual_operation_import_sum = sum(baseline_individual_operation_import)

collective_operation_improvement = collective_operation_sum .- baseline_individual_operation_sum
individual_operation_improvement = individual_operation_sum .- baseline_individual_operation_sum

# Subtracting 0 battery size from the rest
#collective_operation_improvement = collective_operation_improvement .+ collective_operation_improvement[1]
#individual_operation_improvement = individual_operation_improvement .+ individual_operation_improvement[1]

plot(battery_sizes, collective_operation_improvement, label="Collective Operation Improvement tariff", lw=2, marker=:o)
plot!(battery_sizes, individual_operation_improvement, label="Individual Operation Improvement", lw=2, marker=:s)
xlabel!("Battery Size (MWh)")
ylabel!("Profit increase versus Baseline [DKK]")
title!("Profit increase vs Battery Size")
display(current())

# Calculating percentage difference between collective and individual operation improvements
percentage_difference = 100 .* (collective_operation_improvement .- individual_operation_improvement) ./ individual_operation_improvement

# Plotting the percentage difference
plot(battery_sizes, percentage_difference, label="Percentage Difference", lw=2, marker=:d, linestyle=:dash)
ylabel!("Collective operation improvement[%]")
xlabel!("Battery Size (MWh)")
display(current())

collective_import_change = collective_operation_import .- baseline_individual_operation_import_sum
individual_import_change = individual_operation_import .- baseline_individual_operation_import_sum

println("Collective operation import change: ", collective_import_change)
println("Individual operation import change: ", individual_import_change)
println("Percentage difference in import: ", 100 .* (collective_import_change .- individual_import_change) ./ individual_import_change)