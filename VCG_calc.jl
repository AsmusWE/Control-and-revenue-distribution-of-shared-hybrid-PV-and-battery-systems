include("Bat_arbitrage.jl")
using Dates
using Plots


function generate_coalitions(clients, only_VCG)
    if only_VCG
        n = length(clients)
        result = []
        push!(result, clients) # Add the grand coalition (all clients)
        for i in 1:n
            push!(result, filter(x -> x != clients[i], clients)) # Add coalitions that are the grand coalition without one client
        end
        return result
    else
        # This function generates coalitions of clients by manipulating the bit representation of the coalitions
        # Can be replaced by something from combinatorics package or something more understandable, but low priority
        n = length(clients)
        result = []
        for i in 1:(2^n - 1)
            combo = Int[]
            for j in 1:n
                if (i >> (j - 1)) & 1 == 1
                    push!(combo, clients[j])
                end
            end
            push!(result, combo)
        end
        return result
    end
end

function VCG_value(clients, coalitions, coalition_values)
    # This function calculates the VCG value for each client in the grand coalition
    n = length(clients)
    VCG_vals = Dict()
    grand_coalition_value = coalition_values[end] # The value of the grand coalition is the last element in the coalition_values array
    for (idx,i) in enumerate(clients)
        c_without_i = filter(x -> x != clients[idx], clients)
        c_without_i_idx = findfirst(x -> x == c_without_i, coalitions)
        VCG_vals[i] = grand_coalition_value - coalition_values[c_without_i_idx] 
        println("Client ", i, " VCG value: ", VCG_vals[i], " (Grand coalition value: ", grand_coalition_value, ", Coalition without client: ", coalition_values[c_without_i_idx], ")")
    end
    return VCG_vals
end

function check_stability(payoffs, coalition_values, coalitions)
    # Checks if the value of a coalition is larger than their reward as part of the grand coalition
    instabilities = Dict()
    for (idx, c) in enumerate(coalitions)
        if coalition_values[idx] < sum(payoffs[i] for i in c) - 0.01# Adding a small margin for floating point errors
            #println("Coalition ", c, " is unstable. As standalone coalition value: ", coalition_values[idx], " Shapley derived value: ", sum(shapley_vals[i] for i in c))
            instabilities[c] =  sum(payoffs[i] for i in c) - coalition_values[idx]
        end
    end
    if isempty(instabilities)
        println("No instabilities found.")
        return
    end
    max_instability = maximum(values(instabilities))
    max_instability_key = findfirst(x -> x == max_instability, instabilities)
    println("Maximum instability is for coalition ", max_instability_key, " with value ", max_instability, " corresponding to operating in the grand coalition being ", max_instability/coalition_values[findfirst(x -> x == max_instability_key, coalitions)]*100, "% more expensive than operating in this coalition")
    if !isnothing(max_instability_key)
        for client in max_instability_key
            solo_coalition_idx = findfirst(x -> x == [client], coalitions)
            solo_value = coalition_values[solo_coalition_idx]
            payoff_diff = payoffs[client] - solo_value
            println("Client ", client, ": Payoff = ", payoffs[client], ", Operating alone value = ", solo_value, ", Difference = ", payoff_diff)
        end
    end
    #avg_instability_percentage = sum(instabilities[c] / sum(shapley_vals[i] for i in c) * 100 for c in keys(instabilities)) / length(instabilities)
    #println("Average instability in percentage is ", avg_instability_percentage, "%")
    #avg_instability = sum(values(instabilities))/length(values(instabilities))
    #println("Average instability is ", avg_instability)
end


only_VCG = false # Set to true to only calculate coalitions needed for VCG
# Needs to be false to check if in core

all_clients = range(1, stop=10)
T = 24
C = length(all_clients)
# Clients used for grand coalition
clients = [1 2 3 4 5 6 7 8 9 10]
#clients = [1 2 4]
#clients = [1, 2, 3]
demand = zeros(Float64, C, T)
# Dummy demand data
demand[1, :] = [5, 3, 4, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6]
demand[2, :] = [6, 4, 5, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7]
demand[3, :] = [7, 5, 6, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8]
demand[4, :] = [8, 6, 7, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9]
demand[5, :] = [5, 4, 6, 7, 8, 9, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6]
demand[6, :] = [6, 5, 7, 8, 9, 10, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7]
demand[7, :] = [7, 6, 8, 9, 10, 11, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8]
demand[8, :] = [8, 7, 9, 10, 11, 12, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9]
demand[9, :] = [9, 8, 10, 11, 12, 13, 9, 10, 11, 12, 9, 10, 11, 12, 9, 10, 11, 12, 9, 10, 11, 12, 9, 10]
demand[10, :] = [10, 9, 11, 12, 13, 14, 10, 11, 12, 13, 10, 11, 12, 13, 10, 11, 12, 13, 10, 11, 12, 13, 10, 11]

clientPVOwnership = zeros(Float32, C)
clientPVOwnership = [0.2, 0, 0, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.2]
clientBatteryOwnership = zeros(Float32, C)
clientBatteryOwnership = [0.1, 0.1, 0.1, 0.3, 0.0, 0.0, 0.1, 0.1, 0.1, 0.1]
initSoC = 0
batCap = 25

prod = zeros(Float64, T)
# Dummy production data
prod = 3*[10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8]

#start_time_generation = now()
coalitions = generate_coalitions(clients, only_VCG)
#end_time_generation = now()
single_client_coalitions_idx = [findfirst(x -> x == [client], coalitions) for client in clients]
#println(coalitions)

coalition_values = zeros(Float64, length(coalitions))
start_time_optimize = now()
for i in eachindex(coalitions)
    coalition_values[i] = solve_coalition(coalitions[i], demand, clientPVOwnership, clientBatteryOwnership, prod, initSoC, batCap)
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

check_stability(VCG_vals, coalition_values, coalitions)

#println("Time taken to generate all coalitions: ", end_time_generation - start_time_generation)
println("Time taken to optimize all coalitions: ", end_time_optimize - start_time_optimize)
println("Time taken to calculate VCG values: ", end_time_VCG - start_time_VCG)

#println("Shapley values: ", shapley_vals)
println("Sum of VCG values: ", sum(values(VCG_vals)))
println("Discrepancy from grand coalition cost (should be 0): ", sum(values(VCG_vals)) - coalition_values[end])

println("Sum of single client coalition costs: ", sum(coalition_values[single_client_coalitions_idx]))
println("Sum of grand coalition costs: ", coalition_values[end])
println("Decrease in cost: ", (sum(coalition_values[single_client_coalitions_idx])-coalition_values[end])/sum(coalition_values[single_client_coalitions_idx])*100, " %")


# Extract single client coalition values
#single_client_values = [coalition_values[findfirst(x -> x == [client], coalitions)] for client in clients]



# Extract shapley values in the same order as clients
#shapley_values = [shapley_vals[client] for client in clients]

# Plot the decrease in cost per client
#decrease_in_cost_per_client = single_client_values .- shapley_values
#bar(clients, decrease_in_cost_per_client, xlabel="Client", ylabel="Decrease in Cost", title="Decrease in Cost per Client")
# Display the first plot
#display(current())

# Plot the decrease in cost per client compared to their solo no storage values
#decrease_in_cost_per_client_no_storage = transpose(solo_no_storage_values) .- shapley_values
#bar(clients, decrease_in_cost_per_client_no_storage, xlabel="Client", ylabel="Decrease in Cost", title="Decrease in Cost per Client Compared to Solo No Storage Values", legend=false, size=(800, 600), xticks=:auto, yticks=:auto, tickfont=font(8), guidefont=font(10), titlefont=font(12))
# Display the second plot
#display(current())

