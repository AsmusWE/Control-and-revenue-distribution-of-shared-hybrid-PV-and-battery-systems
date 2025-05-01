include("Bat_arbitrage.jl")
include("Common_functions.jl")
using Dates
using Plots


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
                shapley_vals[i] +=  factorial(S - 1) * factorial(n - S) / factorial(n) * (coalition_values[c] - coalition_values[c_without_i])
            else
                shapley_vals[i] +=  factorial(S - 1) * factorial(n - S) / factorial(n) * (coalition_values[c])
            end
            
        end
    end
    return shapley_vals
end

systemData = load_data()
clients = systemData["clients"]

#start_time_generation = now()
coalitions = generate_coalitions(clients)
grand_coalition = vec(clients)
#end_time_generation = now()
single_client_coalitions_idx = [findfirst(x -> x == [client], coalitions) for client in clients]
#println(coalitions)

coalition_values = Dict{Vector{Int}, Float64}() # Initialize as a dictionary
start_time_optimize = now()
for coalition in coalitions
    coalition_values[coalition] = solve_coalition(coalition, systemData)
end
end_time_optimize = now()

# Finding value of clients operating solo without storage
solo_no_storage_values = zeros(Float64, length(clients))
systemData["initSoC"] = 0
systemData["batCap"] = 0
for (idx, client) in enumerate(clients)
    solo_no_storage_values[idx] = solve_coalition([client], systemData)
end

start_time_shapley = now()
shapley_vals = shapley_value(clients, coalitions, coalition_values)
end_time_shapley = now()

check_stability(shapley_vals, coalition_values, coalitions)

#println("Time taken to generate all coalitions: ", end_time_generation - start_time_generation)
println("Time taken to optimize all coalitions: ", end_time_optimize - start_time_optimize)
println("Time taken to calculate shapley values: ", end_time_shapley - start_time_shapley)

#println("Shapley values: ", shapley_vals)
println("Sum of Shapley values: ", sum(values(shapley_vals)))
println("Discrepancy from grand coalition cost (should be 0): ", sum(values(shapley_vals)) - coalition_values[grand_coalition])

sum_single_client_costs = sum(coalition_values[[client]] for client in clients)

println("Sum of single client coalition revenue: ", sum_single_client_costs)
println("Sum of grand coalition revenue: ", coalition_values[grand_coalition])
println("Change in profit: ", (sum(coalition_values[coalitions[i]] for i in single_client_coalitions_idx)-coalition_values[grand_coalition])/sum(coalition_values[coalitions[i]] for i in single_client_coalitions_idx)*100, " %")

# Extract single client coalition values
single_client_values = [coalition_values[[client]] for client in clients]

# Extract Shapley values in the same order as clients
shapley_values = [shapley_vals[client] for client in clients]

# Plot the change in revenue per client compared to their solo values
change_in_revenue_per_client = shapley_values .- single_client_values
bar(clients, change_in_revenue_per_client, xlabel="Client", ylabel="Change in Revenue", title="Change in Revenue per Client Shapley")
# Display the first plot
display(current())

# Plot the decrease in cost per client compared to their solo no storage values
#decrease_in_cost_per_client_no_storage = transpose(solo_no_storage_values) .- vcg_values
#bar(clients, decrease_in_cost_per_client_no_storage, xlabel="Client", ylabel="Decrease in Cost", title="Decrease in Cost per Client Compared to Solo No Storage Values", legend=false, size=(800, 600), xticks=:auto, yticks=:auto, tickfont=font(8), guidefont=font(10), titlefont=font(12))
# Display the second plot
#display(current())

