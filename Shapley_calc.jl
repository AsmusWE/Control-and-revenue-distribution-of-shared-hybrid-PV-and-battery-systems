include("Bat_arbitrage.jl")

function generate_coalitions(clients)
    # This function generates coalitions of clients by manipulating the bit representation of the coalitions
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
    shapley_vals = zeros(Float64, n)
    
    for i in 1:n
        i_coalition = [c for c in coalitions if clients[i] in c]
        # Looping through all coalitions containing client i
        for c in i_coalition
            S = length(c)
            # Finding the index of the coalition in the list of all coalitions
            c_idx = findfirst(x -> x == c, coalitions)
            # Creating the coalition that doesn't contain client i
            c_without_i = filter(x -> x != clients[i], c)
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


clients = [1 2 3 4 5 6 7 8 9 10]
C = length(clients)
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
clientPVOwnership = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]
clientBatteryOwnership = zeros(Float32, C)
clientBatteryOwnership = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]
initSoC = 5

prod = zeros(Float64, T)
# Dummy production data
prod = 3*[10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8]


coalitions = generate_coalitions(clients)
#println(coalitions)

coalition_values = zeros(Float64, length(coalitions))
start_time_optimize = now()
for i in eachindex(coalitions)
    coalition_values[i] = solve_coalition(coalitions[i], demand, clientPVOwnership, clientBatteryOwnership, prod, initSoC)
end
end_time_optimize = now()

start_time_shapley = now()
shapley_vals = shapley_value(clients, coalitions, coalition_values)
end_time_shapley = now()

println("Time taken to optimize all coalitions: ", end_time_optimize - start_time_optimize)
println("Time taken to calculate shapley values: ", end_time_shapley - start_time_shapley)

println("Shapley values: ", shapley_vals)
println("Sum of Shapley values: ", sum(shapley_vals))
println("Discrepancy from grand coalition (should be 0): ", sum(shapley_vals) - coalition_values[end])