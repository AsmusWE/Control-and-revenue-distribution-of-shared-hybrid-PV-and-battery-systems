include("Bat_arbitrage.jl")
using Dates
using Plots


function generate_coalitions(clients)
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

function shapley_value(clients, coalitions, coalition_values)
    n = length(clients)
    shapley_vals = Dict()
    for client in clients
        shapley_vals[client] = 0.0
    end
    
    for (idx,i) in enumerate(clients)
        i_coalition = [c for c in coalitions if clients[idx] in c]
        # Looping through all coalitions containing client i
        for c in i_coalition
            S = length(c)
            # Finding the index of the coalition in the list of all coalitions
            c_idx = findfirst(x -> x == c, coalitions)
            # Creating the coalition that doesn't contain client i
            c_without_i = filter(x -> x != clients[idx], c)
            c_without_i_idx = findfirst(x -> x == c_without_i, coalitions)
            # If the coalition without client i is empty, set value of empty coalition as 0
            if !isnothing(c_without_i_idx)
                shapley_vals[i] +=  factorial(S - 1) * factorial(n - S) / factorial(n) * (coalition_values[c_idx] - coalition_values[c_without_i_idx])
            else
                shapley_vals[i] +=  factorial(S - 1) * factorial(n - S) / factorial(n) * (coalition_values[c_idx])
            end
            
        end
    end
    return shapley_vals
end

function check_stability(shapley_vals, coalition_values, coalitions)
    # Checks if the value of a coalition is larger than their reward as part of the grand coalition
    instabilities = Dict()
    for (idx, c) in enumerate(coalitions)
        if coalition_values[idx] < sum(shapley_vals[i] for i in c) - 0.01# Adding a small margin for floating point errors
            #println("Coalition ", c, " is unstable. As standalone coalition value: ", coalition_values[idx], " Shapley derived value: ", sum(shapley_vals[i] for i in c))
            instabilities[c] =  sum(shapley_vals[i] for i in c) - coalition_values[idx]
        end
    end
    if isempty(instabilities)
        println("No instabilities found.")
        return
    end
    max_instability = maximum(values(instabilities))
    max_instability_key = findfirst(x -> x == max_instability, instabilities)
    println("Maximum instability is for coalition ", max_instability_key, " with value ", max_instability, " corresponding to operating in the grand coalition being ", max_instability/sum(shapley_vals[i] for i in max_instability_key)*100, "% more expensive than operating in this coalition")
    if !isnothing(max_instability_key)
        for client in max_instability_key
            solo_coalition_idx = findfirst(x -> x == [client], coalitions)
            solo_value = coalition_values[solo_coalition_idx]
            shapley_diff = shapley_vals[client] - solo_value
            println("Client ", client, ": Shapley value = ", shapley_vals[client], ", Operating alone value = ", solo_value, ", Difference = ", shapley_diff)
        end
    end
    #avg_instability_percentage = sum(instabilities[c] / sum(shapley_vals[i] for i in c) * 100 for c in keys(instabilities)) / length(instabilities)
    #println("Average instability in percentage is ", avg_instability_percentage, "%")
    #avg_instability = sum(values(instabilities))/length(values(instabilities))
    #println("Average instability is ", avg_instability)
end


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

start_time_generation = now()
coalitions = generate_coalitions(clients)
end_time_generation = now()
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

start_time_shapley = now()
shapley_vals = shapley_value(clients, coalitions, coalition_values)
end_time_shapley = now()

check_stability(shapley_vals, coalition_values, coalitions)

println("Time taken to generate all coalitions: ", end_time_generation - start_time_generation)
println("Time taken to optimize all coalitions: ", end_time_optimize - start_time_optimize)
println("Time taken to calculate shapley values: ", end_time_shapley - start_time_shapley)

#println("Shapley values: ", shapley_vals)
println("Sum of Shapley values: ", sum(values(shapley_vals)))
println("Discrepancy from grand coalition (should be 0): ", sum(values(shapley_vals)) - coalition_values[end])

println("Sum of single client coalition costs: ", sum(coalition_values[single_client_coalitions_idx]))
println("Sum of grand coalition costs: ", coalition_values[end])
println("Decrease in cost: ", (sum(coalition_values[single_client_coalitions_idx])-coalition_values[end])/coalition_values[end]*100, " %")


# Extract single client coalition values
single_client_values = [coalition_values[findfirst(x -> x == [client], coalitions)] for client in clients]

# Extract shapley values in the same order as clients
shapley_values = [shapley_vals[client] for client in clients]

# Plot the decrease in cost per client
decrease_in_cost_per_client = single_client_values .- shapley_values
bar(clients, decrease_in_cost_per_client, xlabel="Client", ylabel="Decrease in Cost", title="Decrease in Cost per Client")
# Display the first plot
display(current())

# Plot the decrease in cost per client compared to their solo no storage values
decrease_in_cost_per_client_no_storage = transpose(solo_no_storage_values) .- shapley_values
bar(clients, decrease_in_cost_per_client_no_storage, xlabel="Client", ylabel="Decrease in Cost", title="Decrease in Cost per Client Compared to Solo No Storage Values", legend=false, size=(800, 600), xticks=:auto, yticks=:auto, tickfont=font(8), guidefont=font(10), titlefont=font(12))
# Display the second plot
display(current())

