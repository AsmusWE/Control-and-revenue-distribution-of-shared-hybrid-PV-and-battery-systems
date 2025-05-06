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
        if coalition_values[c] > sum(payoffs[i] for i in c)+0.01 # Adding a small tolerance to avoid floating point errors
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


function test_load_data()
    all_clients = range(1, stop=10)
    T = 24
    C = length(all_clients)
    # Clients used for grand coalition
    clients = [1 2 3 4 5 6 7 8 9 10]

    #clients = [1 2]
    #clients = [1 2 3]
    demand = zeros(Float64, C, T)
    # Dummy demand data
    demand[1, :] = 1 * [0.5, 0.3, 0.4, 0.6, 0.7, 0.8, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6]
    demand[2, :] = 1 * [0.6, 0.4, 0.5, 0.7, 0.8, 0.9, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7]
    demand[3, :] = 1 * [0.7, 0.5, 0.6, 0.8, 0.9, 1.0, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8]
    demand[4, :] = 1 * [0.8, 0.6, 0.7, 0.9, 1.0, 1.1, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9]
    demand[5, :] = 1 * [0.5, 0.4, 0.6, 0.7, 0.8, 0.9, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6, 0.7, 0.8, 0.5, 0.6]
    demand[6, :] = 1 * [0.6, 0.5, 0.7, 0.8, 0.9, 1.0, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7, 0.8, 0.9, 0.6, 0.7]
    demand[7, :] = 1 * [0.7, 0.6, 0.8, 0.9, 1.0, 1.1, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8, 0.9, 1.0, 0.7, 0.8]
    demand[8, :] = 1 * [0.8, 0.7, 0.9, 1.0, 1.1, 1.2, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9, 1.0, 1.1, 0.8, 0.9]
    demand[9, :] = 1 * [0.9, 0.8, 1.0, 1.1, 1.2, 1.3, 0.9, 1.0, 1.1, 1.2, 0.9, 1.0, 1.1, 1.2, 0.9, 1.0, 1.1, 1.2, 0.9, 1.0, 1.1, 1.2, 0.9, 1.0]
    demand[10, :] = 1 * [1.0, 0.9, 1.1, 1.2, 1.3, 1.4, 1.0, 1.1, 1.2, 1.3, 1.0, 1.1, 1.2, 1.3, 1.0, 1.1, 1.2, 1.3, 1.0, 1.1, 1.2, 1.3, 1.0, 1.1]
    demand = demand.*1.5

    clientPVOwnership = zeros(Float32, C)
    clientPVOwnership =         [0.1, 0.1, 0.1, 0.1, 0.0, 0.3, 0.0, 0.1, 0.1, 0.1]
    clientBatteryOwnership = zeros(Float32, C)
    clientBatteryOwnership =    [0.1, 0.1, 0.1, 0.3, 0.0, 0.0, 0.1, 0.1, 0.1, 0.1]
    initSoC = 0
    batCap = 200

    prod = zeros(Float64, T)
    # Dummy production data MW, plant size: 14 MW
    prod = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 14, 14, 14, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4]

    priceImp = zeros(Float64, T)
    priceImp = 0.5*[50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300]
    priceExp = 0.5*priceImp
    systemData = Dict("demand" => demand, "clientPVOwnership" => clientPVOwnership, "clientBatteryOwnership" => clientBatteryOwnership, "pvProduction" => prod, "initSoC" => initSoC, "batCap" => batCap, "priceImp" => priceImp, "priceExp" => priceExp, "clients" => clients)
    return systemData
end
