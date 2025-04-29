function generate_coalitions(clients, only_VCG=false)
    if only_VCG
        n = length(clients)
        result = []
        push!(result, vec(clients)) # Add the grand coalition (all clients)
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

function check_stability(payoffs, coalition_values, coalitions)
    # Checks if the value of a coalition is larger than their reward as part of the grand coalition
    instabilities = Dict()
    for c in coalitions
        if coalition_values[c] > sum(payoffs[i] for i in c)
            instabilities[c] = coalition_values[c] - sum(payoffs[i] for i in c) 
        end
    end
    if isempty(instabilities)
        println("No instabilities found.")
        return
    end
    max_instability = maximum(values(instabilities))
    max_instability_key = findfirst(x -> x == max_instability, instabilities)
    println("Maximum instability is for coalition ", max_instability_key, " with value ", max_instability, " corresponding to operating in the grand coalition giving ", 100+max_instability / coalition_values[max_instability_key] * 100, "% of the revenue of operating in this coalition")
    #if !isnothing(max_instability_key)
    #    for client in max_instability_key
    #        solo_value = coalition_values[[client]]
    #        payoff_diff = payoffs[client] - solo_value
    #        println("Client ", client, ": Payoff = ", payoffs[client], ", Operating alone value = ", solo_value, ", Difference = ", payoff_diff)
    #    end
    #end
end

function load_data()
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
    batCap = 200

    prod = zeros(Float64, T)
    # Dummy production data
    prod = 3*[10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8]

    return clients, demand, clientPVOwnership, clientBatteryOwnership, prod, initSoC, batCap
end
