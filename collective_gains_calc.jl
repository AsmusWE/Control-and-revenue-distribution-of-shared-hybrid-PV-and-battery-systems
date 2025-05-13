include("Bat_arbitrage.jl")
include("Common_functions.jl")
include("Data_import.jl")
include("Scenario_creation.jl")
using Plots
using Dates

function calc_operating_costs(systemData, clients, battery_sizes, stochastic)
    # This function calculates the collective gains for a given set of clients and battery size
    # It returns the collective gains and the import change
    collective_operation_sum = []
    collective_operation_import = []
    individual_operation_sum = []
    individual_operation_import = []
    if !stochastic
        for batsize in battery_sizes
            println("Calculating for battery size: ", batsize)
            systemData["batCap"] = batsize
            # Calculate operating costs when working together
            coalition_result, imported_pow = solve_coalition(clients, systemData)
            push!(collective_operation_sum, coalition_result)
            push!(collective_operation_import, imported_pow)
            temp_sum = 0
            temp_import = 0
            # Calculate operating costs when working individually
            for client in clients
                coalition_result, imported_pow = solve_coalition([client], systemData)
                temp_sum += coalition_result
                temp_import += imported_pow
            end
            push!(individual_operation_sum, temp_sum)
            push!(individual_operation_import, temp_import)
        end
    else
        for batsize in battery_sizes
            println("Calculating for battery size: ", batsize)
            systemData["batCap"] = batsize
            systemData["initSoC"] = 0
            # Calculate operating costs when working together
            coalition_result = 0
            imported_pow = 0
            for i in 1:size(systemData["price_prod_demand_df"])[1]
                temp_systemData = deepcopy(systemData)
                temp_systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][i:end, :]
                coalition_result_hour, imported_pow_hour, soc_hour = solve_coalition(clients, temp_systemData, stochastic=stochastic)
                systemData["initSoC"] = soc_hour
                coalition_result += coalition_result_hour
                imported_pow += imported_pow_hour
            end
            push!(collective_operation_sum, coalition_result)
            push!(collective_operation_import, imported_pow)

            # Calculate operating costs when working individually
            temp_sum = 0
            temp_import = 0
            for client in clients
                systemData["initSoC"] = 0
                coalition_result = 0
                imported_pow = 0
                for i in 1:size(systemData["price_prod_demand_df"])[1]
                    temp_systemData = deepcopy(systemData)
                    temp_systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][i:end, :]
                    coalition_result_hour, imported_pow_hour, soc_hour = solve_coalition([client], temp_systemData, stochastic=stochastic)
                    systemData["initSoC"] = soc_hour
                    coalition_result += coalition_result_hour
                    imported_pow += imported_pow_hour
                end
                temp_sum += coalition_result
                temp_import += imported_pow
            end
            push!(individual_operation_sum, temp_sum)
            push!(individual_operation_import, temp_import)
        end
    end
    return collective_operation_sum, individual_operation_sum, collective_operation_import, individual_operation_import
end

function calc_baseline_costs(systemData, clients, stochastic)
    baseline_individual_operation = []
    baseline_individual_operation_import = []
    if !stochastic
        for client in clients
            println("Calculating baseline for client: ", client)
            systemData["batCap"] = 0
            # Setting PV production to 0
            systemData["price_prod_demand_df"][!, "SolarMWh"] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* 0
            coalition_result, imported_pow = solve_coalition([client], systemData)
            push!(baseline_individual_operation, coalition_result)
            push!(baseline_individual_operation_import, imported_pow)
        end
    else
        for client in clients
            println("Calculating baseline for client: ", client)
            systemData["batCap"] = 0
            systemData["initSoC"] = 0
            # Setting PV production to 0
            systemData["price_prod_demand_df"][!, "SolarMWh"] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* 0
            coalition_result = 0
            imported_pow = 0
            for i in 1:size(systemData["price_prod_demand_df"])[1]
                temp_systemData = deepcopy(systemData)
                temp_systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][i:end, :]
                coalition_result_hour, imported_pow_hour, soc_hour = solve_coalition([client], temp_systemData, stochastic=stochastic)
                systemData["initSoC"] = soc_hour
                coalition_result += coalition_result_hour
                imported_pow += imported_pow_hour
            end
            push!(baseline_individual_operation, coalition_result)
            push!(baseline_individual_operation_import, imported_pow)
        end
    end
    baseline_individual_operation_sum = sum(baseline_individual_operation)
    baseline_individual_operation_import_sum = sum(baseline_individual_operation_import)
    return baseline_individual_operation_sum, baseline_individual_operation_import_sum
end

stoch = true # Set to true to solve the problems using forecast
systemData, clients_without_missing_data = load_data()
# Set the number of hours for the simulation
hours = 48*60
systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][1:hours, :]
clients = systemData["clients"]

# Removing clients from cooperation
#clients_without_missing_data = filter(x -> !(x in ["G", "A"]), clients_without_missing_data)
#clients_without_missing_data = filter(x -> !(x in ["Z"]), clients_without_missing_data)

battery_sizes = [0, 15, 30, 60, 120]

# Calculating operating costs for each battery size
collective_operation_sum, individual_operation_sum, collective_operation_import, individual_operation_import = calc_operating_costs(systemData, clients_without_missing_data, battery_sizes, stoch)

# Calculating operating costs for individual operation without PV production as baseline
baseline_individual_operation_sum, baseline_individual_operation_import_sum = calc_baseline_costs(systemData, clients_without_missing_data, stoch)


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