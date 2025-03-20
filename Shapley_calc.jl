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

coalitions = generate_coalitions(clients)
#println(coalitions)

coalition_values = zeros(Float64, length(coalitions))
for i in eachindex(coalitions)
    coalition_values[i] = solve_coalition(coalitions[i])
end

shapley_vals = shapley_value(clients, coalitions, coalition_values)
println("Shapley values: ", shapley_vals)
println("Sum of Shapley values: ", sum(shapley_vals))
println("Discrepancy from expected value: ", sum(shapley_vals) - coalition_values[end])