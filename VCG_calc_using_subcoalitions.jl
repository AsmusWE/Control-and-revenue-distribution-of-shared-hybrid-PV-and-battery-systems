include("Bat_arbitrage.jl")
include("Common_functions.jl")
using Dates
using Plots

function VCG_tax(clients, coalition_val, import_util, export_util)
    # This function calculates the VCG value for each client in the grand coalition
    n = length(clients)
    VCG_taxes = Dict()
    grand_coalition = vec(clients)
    for (idx, i) in enumerate(clients)
        grand_coalition_value_minus_i = sum(export_util[grand_coalition][c] for c in grand_coalition if c!=i) - sum(import_util[grand_coalition][c] for c in grand_coalition if c!=i)
        coalition_without_i = filter(x -> x != clients[idx], grand_coalition)
        coalition_value_without_i = coalition_val[coalition_without_i]
        VCG_taxes[i] = (coalition_value_without_i-grand_coalition_value_minus_i)
        #println("Client ", i, " VCG tax: ", VCG_taxes[i], " (Grand coalition value minus i: ", grand_coalition_value_minus_i, ", Coalition value without i: ", coalition_value_without_i, ")")
    end
    return VCG_taxes
end

only_VCG = false # Set to true to only calculate coalitions needed for VCG
# Needs to be false to check for stability

systemData = test_load_data()

#start_time_generation = now()
clients = systemData["clients"]
coalitions = generate_coalitions(clients, only_VCG)
grand_coalition = vec(clients)
#end_time_generation = now()
#single_client_coalitions_idx = [findfirst(x -> x == [client], coalitions) for client in clients]
#println(coalitions)

coalition_values = Dict{Vector{Int}, Float64}() # Initialize as a dictionary
#coalition_val_disregarding_player = Dict{Any, Float64}()
#import_util_disregarding_player = Dict{Any, Dict{Int64, Float64}}()
#export_util_disregarding_player = Dict{Any, Dict{Int64, Float64}}()
import_util = Dict{Vector{Int}, Dict{Int64, Float64}}()
export_util = Dict{Vector{Int}, Dict{Int64, Float64}}()
start_time_optimize = now()
for coalition in coalitions
    # For the grand coalition, we need to calculate the utilities for all clients, so the complete model is needed
    if coalition == grand_coalition
        coalition_values[coalition], import_util[coalition], export_util[coalition] = solve_coalition(coalition, systemData, "Complete", false, nothing)
    else
        # For all other coalitions, we can use the simplified model that pools demands and productions
        coalition_values[coalition] = solve_coalition(coalition, systemData)
    end
end

#coalition_val_disregarding_player[nothing], import_util_disregarding_player[nothing], export_util_disregarding_player[nothing] = solve_coalition(grand_coalition, demand, clientPVOwnership, clientBatteryOwnership, prod, initSoC, batCap, "VCG", false, nothing)
#for vcg_player in clients
#    coalition_val_disregarding_player[vcg_player], import_util_disregarding_player[vcg_player], export_util_disregarding_player[vcg_player] = solve_coalition(grand_coalition, demand, clientPVOwnership, clientBatteryOwnership, prod, initSoC, batCap, "VCG", false, vcg_player)
#end

end_time_optimize = now()

grand_coalition_value = coalition_values[grand_coalition]

println("Grand coalition value: ", grand_coalition_value)

# Finding value of clients operating solo without storage
#solo_no_storage_values = zeros(Float64, length(clients))
#for (idx, client) in enumerate(clients)
#    solo_no_storage_values[idx] = solve_coalition([client], demand, clientPVOwnership, clientBatteryOwnership, prod, 0, 0)
#end

start_time_VCG = now()
VCG_taxes = VCG_tax(clients, coalition_values, import_util, export_util)
end_time_VCG = now()

utilities = Dict{Int, Float64}()
for client in clients
    utilities[client] = export_util[grand_coalition][client]-import_util[grand_coalition][client]-VCG_taxes[client]
end



if !only_VCG
    check_stability(utilities, coalition_values, coalitions)
else
    println("Cannot check stability as all coalitions are not generated")
end
#println("Time taken to generate all coalitions: ", end_time_generation - start_time_generation)
println("Time taken to optimize all coalitions: ", end_time_optimize - start_time_optimize)
println("Time taken to calculate VCG taxes: ", end_time_VCG - start_time_VCG)

#println("Shapley values: ", shapley_vals)
println("Sum of VCG taxes (Negative means shareholders are subsidized): ", sum(values(VCG_taxes)))
println("sum of utilities: ", sum(values(utilities)))

# Calculate the sum of the costs for all the coalitions who are only single clients
if !only_VCG
    sum_single_client_costs = sum(coalition_values[[client]] for client in clients)
    println("Sum of costs for all single client coalitions: ", sum_single_client_costs)
    # Extract single client coalition values
    single_client_values = [coalition_values[[client]] for client in clients]

    # Extract utility values in the same order as clients
    utility_values = [utilities[client] for client in clients]

    # Plot the change in revenue per client compared to their solo values
    change_in_revenue_per_client = utility_values.-single_client_values 
    bar(clients, change_in_revenue_per_client, xlabel="Client", ylabel="Change in revenue", title="Change in revenue per Client VCG")
    # Display the first plot
    display(current())

    # Plot the decrease in cost per client compared to their solo no storage values
    #decrease_in_cost_per_client_no_storage = transpose(solo_no_storage_values) .- vcg_values
    #bar(clients, decrease_in_cost_per_client_no_storage, xlabel="Client", ylabel="Decrease in Cost", title="Decrease in Cost per Client Compared to Solo No Storage Values", legend=false, size=(800, 600), xticks=:auto, yticks=:auto, tickfont=font(8), guidefont=font(10), titlefont=font(12))
    # Display the second plot
    #display(current())
end
