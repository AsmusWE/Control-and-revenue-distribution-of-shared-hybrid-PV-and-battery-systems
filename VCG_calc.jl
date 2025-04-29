include("Bat_arbitrage.jl")
include("Common_functions.jl")
using Dates
using Plots

function VCG_value(clients, coalitions, coalition_values)
    # This function calculates the VCG value for each client in the grand coalition
    n = length(clients)
    VCG_vals = Dict()
    grand_coalition = vec(clients)
    grand_coalition_value = coalition_values[grand_coalition] 
    for (idx, i) in enumerate(clients)
        c_without_i = filter(x -> x != clients[idx], clients)
        VCG_vals[i] = grand_coalition_value - coalition_values[c_without_i]
        #println("Client ", i, " VCG value: ", VCG_vals[i], " (Grand coalition value: ", grand_coalition_value, ", Coalition without client: ", coalition_values[c_without_i], ")")
    end
    return VCG_vals
end

only_VCG = false # Set to true to only calculate coalitions needed for VCG
# Needs to be false to check for stability

clients, demand, clientPVOwnership, clientBatteryOwnership, prod, initSoC, batCap = load_data()

#start_time_generation = now()
coalitions = generate_coalitions(clients, only_VCG)
grand_coalition = vec(clients)
#end_time_generation = now()
#single_client_coalitions_idx = [findfirst(x -> x == [client], coalitions) for client in clients]
#println(coalitions)

coalition_values = Dict{Vector{Int}, Float64}() # Initialize as a dictionary
start_time_optimize = now()
for coalition in coalitions
    coalition_values[coalition] = solve_coalition(coalition, demand, clientPVOwnership, clientBatteryOwnership, prod, initSoC, batCap)
end
end_time_optimize = now()

# Finding value of clients operating solo without storage
solo_no_storage_values = zeros(Float64, length(clients))
for (idx, client) in enumerate(clients)
    solo_no_storage_values[idx] = solve_coalition([client], demand, clientPVOwnership, clientBatteryOwnership, prod, 0, 0)
end

start_time_VCG = now()
VCG_vals = VCG_value(clients, coalitions, coalition_values)
end_time_VCG = now()
if !only_VCG
    check_stability(VCG_vals, coalition_values, coalitions)
else
    print("Cannot check stability as all coalitions are not generated")
end

#println("Time taken to generate all coalitions: ", end_time_generation - start_time_generation)
println("Time taken to optimize all coalitions: ", end_time_optimize - start_time_optimize)
println("Time taken to calculate VCG values: ", end_time_VCG - start_time_VCG)

#println("Shapley values: ", shapley_vals)
println("Sum of VCG values: ", sum(values(VCG_vals)))
println("Discrepancy from grand coalition cost (should be 0): ", sum(values(VCG_vals)) - coalition_values[grand_coalition])

println("Sum of grand coalition costs: ", coalition_values[grand_coalition])
# Calculate the sum of the costs for all the coalitions who are only single clients
if !only_VCG
    sum_single_client_costs = sum(coalition_values[[client]] for client in clients)
    println("Sum of costs for all single client coalitions: ", sum_single_client_costs)
    # Extract single client coalition values
    single_client_values = [coalition_values[[client]] for client in clients]

    # Extract VCG values in the same order as clients
    vcg_values = [VCG_vals[client] for client in clients]

    # Plot the change in revenue per client compared to their solo values
    change_in_revenue_per_client = vcg_values.-single_client_values 
    bar(clients, change_in_revenue_per_client, xlabel="Client", ylabel="Change in revenue", title="Change in revenue per Client VCG")
    # Display the first plot
    display(current())

    # Plot the decrease in cost per client compared to their solo no storage values
    #decrease_in_cost_per_client_no_storage = transpose(solo_no_storage_values) .- vcg_values
    #bar(clients, decrease_in_cost_per_client_no_storage, xlabel="Client", ylabel="Decrease in Cost", title="Decrease in Cost per Client Compared to Solo No Storage Values", legend=false, size=(800, 600), xticks=:auto, yticks=:auto, tickfont=font(8), guidefont=font(10), titlefont=font(12))
    # Display the second plot
    #display(current())
end
