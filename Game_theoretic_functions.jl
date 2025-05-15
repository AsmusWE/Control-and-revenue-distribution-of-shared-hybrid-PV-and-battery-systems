function shapley_value(clients, coalitions, imbalances)
    n = length(clients)
    shapley_vals = Dict()
    for client in clients
        shapley_vals[client] = 0.0
    end

    for (idx, i) in enumerate(clients)
        i_coalition = [c for c in coalitions if clients[idx] in c]
        # Looping through all coalitions containing client i
        for c in i_coalition
            S = length(c)
            # Creating the coalition that doesn't contain client i
            c_without_i = filter(x -> x != clients[idx], c)
            # If the coalition without client i is empty, set value of empty coalition as 0
            if isempty(c_without_i)
                imbalance_without_i = 0.0
            else
                imbalance_without_i = imbalances[c_without_i]
            end

            # Calculate the Shapley value contribution for client i in coalition c
            shapley_vals[i] += factorial(S - 1) * factorial(n - S) / factorial(n) * (imbalances[c] - imbalance_without_i)
        end
    end

    return shapley_vals
end

function scale_distribution(distribution, demand, clients)
    # Divide distribution factor by the sum of demand for each client
    scaled_distribution = Dict()
    for client in clients
        scaled_distribution[client] = distribution[client]/sum(demand[!,client])
    end
    return scaled_distribution
end

function check_stability(payoffs, coalition_values, coalitions)
    # Checks if the value of a coalition is larger than their reward as part of the grand coalition
    instabilities = Dict()
    for c in coalitions
        if coalition_values[c] < sum(payoffs[i] for i in c)-0.000001 # Adding a small tolerance to avoid floating point errors
            instabilities[c] =sum(payoffs[i] for i in c) - coalition_values[c] 
        end
    end
    if isempty(instabilities)
        println("No instabilities found.")
        return
    end
    max_instability = maximum(values(instabilities))
    max_instability_key = findfirst(x -> x == max_instability, instabilities)
    println("Maximum instability is for coalition ", max_instability_key, " with value ", max_instability, " corresponding to a ", max_instability / coalition_values[max_instability_key] * 100, "% lower imbalance compared to the grand coalition")
    #if !isnothing(max_instability_key)
    #    for client in max_instability_key
    #        solo_value = coalition_values[[client]]
    #        payoff_diff = payoffs[client] - solo_value
    #        println("Client ", client, ": Payoff = ", payoffs[client], ", Operating alone value = ", solo_value, ", Difference = ", payoff_diff)
    #    end
    #end
end

function VCG_tax(clients, imbalances, hourly_imbalances, client_signs, systemData)
    # This function calculates the VCG value for each client in the grand coalition
    T = length(hourly_imbalances[[clients[1]]])
    VCG_taxes = Dict()
    grand_coalition = vec(clients)
    for (idx, i) in enumerate(clients)
        gc_val_minus_i = 0
        for t in 1:T
            # Client_signs = 1 for overshoot, 0 for undershoot
            if client_signs[[i]][t] != client_signs[grand_coalition][t]
                client_price = 0
                grand_coalition_price = 0
                # If the client needs downregulation and the grand coalition needs upregulation
                if client_signs[[i]][t]
                    client_price = systemData["downreg_price"]
                    grand_coalition_price = systemData["upreg_price"]
                else
                    client_price = systemData["upreg_price"]
                    grand_coalition_price = systemData["downreg_price"]
                end
                # The maximum change will be from canceling out the grand coalitions imbalance
                max_change = hourly_imbalances[grand_coalition][t]
                # Converting from client price to grand coalition price
                client_change = hourly_imbalances[[i]][t]/client_price*grand_coalition_price
                # Change will be minimum of these
                change = min(max_change, client_change)

                gc_val_minus_i += hourly_imbalances[grand_coalition][t] - change
            else
                # If the client and grand coalition have the same sign, the client will not be able to cancel out the grand coalitions imbalance
                gc_val_minus_i += hourly_imbalances[grand_coalition][t]
            end
        end
        
        coalition_without_i = filter(x -> x != clients[idx], grand_coalition)
        coalition_value_without_i = imbalances[coalition_without_i]
        VCG_taxes[[i]] = (coalition_value_without_i-gc_val_minus_i)
        #println("Client ", i, " VCG tax: ", VCG_taxes[i], " (Grand coalition value minus i: ", grand_coalition_value_minus_i, ", Coalition value without i: ", coalition_value_without_i, ")")
    end
    return VCG_taxes
end

