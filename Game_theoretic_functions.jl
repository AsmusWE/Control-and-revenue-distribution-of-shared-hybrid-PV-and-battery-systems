using Combinatorics, NLsolve, HiGHS, JuMP

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

function check_stability(payoffs, coalition_values, clients)
    coalitions = collect(combinations(clients))
    grand_coalition = vec(clients)
    # Remove the grand coalition from the list of coalitions
    coalitions = filter(c -> Set(c) != Set(grand_coalition), coalitions)
    # Checks how the value of a coalition compares to their reward as part of the grand coalition
    instabilities = Dict()
    for c in coalitions 
        instabilities[c] =sum(payoffs[i] for i in c) - coalition_values[c] 
    end
    max_instability = maximum(values(instabilities))
    max_instability_key = findfirst(x -> x == max_instability, instabilities)
    println("Maximum instability is for coalition ", max_instability_key, " with value ", max_instability, " corresponding to a ", max_instability / coalition_values[max_instability_key] * 100, "% lower imbalance compared to the grand coalition")
    #mean_instability = sum(values(instabilities))/ length(instabilities)
    return max_instability
end

function VCG_tax(clients, imbalance_costs, hourly_imbalances, systemData;budget_balance=false)
    # This function calculates the VCG value for each client in the grand coalition
    T = length(hourly_imbalances[[clients[1]]])
    VCG_taxes = Dict()
    grand_coalition = vec(clients)

    # Payments is a dictionary, keys are coalitions, values are member_payments
    # member_payments is a dictionary, keys are clients, values are arrays of payments for each hour
    payments = calculate_payments(clients, hourly_imbalances, systemData["upreg_price"], systemData["downreg_price"])
    if budget_balance
        for t in 1:T
            temp_taxes = Dict()
            for (idx, i) in enumerate(clients)
                coalition_without_i = filter(x -> x != clients[idx], grand_coalition)
                gc_val_minus_i = sum(payments[client][t] for client in grand_coalition if client != i)
                coalition_value_without_i = sum(hourly_imbalances[coalition_without_i][t])
                if coalition_value_without_i < 0
                    coalition_value_without_i = abs(coalition_value_without_i)*systemData["upreg_price"]
                else
                    coalition_value_without_i = coalition_value_without_i*systemData["downreg_price"]
                end
                temp_taxes[i] = -(coalition_value_without_i - gc_val_minus_i)
            end
            if sum(values(temp_taxes)) < -0.0001 # Adding a small tolerance to avoid floating point errors
                subsidies = sum(v for v in values(temp_taxes) if v < 0)
                taxes = sum(v for v in values(temp_taxes) if v > 0; init=0.0)
                ratio = taxes / abs(subsidies)
                for (k, v) in temp_taxes
                    if v < 0
                        temp_taxes[k] *= ratio
                    end
                end
            end
            for i in clients
                # Initialize the key if it doesn't exist
                if !haskey(VCG_taxes, [i])
                    VCG_taxes[[i]] = 0.0
                end
                # If the imbalance is same sign as grand coalition imbalance, prevent subsidy
                VCG_taxes[[i]] += temp_taxes[i]
            end
        end
    else
        for (idx, i) in enumerate(clients)
            gc_val_minus_i = 0
            coalition_without_i = filter(x -> x != clients[idx], grand_coalition)
            coalition_value_without_i = imbalance_costs[coalition_without_i]
            gc_val_minus_i = sum(sum(payments[client] for client in grand_coalition if client != i))
        
            # Multiplying by -1 because this is a cost reduction game
            VCG_taxes[[i]] = -(coalition_value_without_i-gc_val_minus_i)
            #println("Client ", i, " VCG tax: ", VCG_taxes[i], " (Grand coalition value minus i: ", grand_coalition_value_minus_i, ", Coalition value without i: ", coalition_value_without_i, ")")
        end
    end
    return VCG_taxes, payments
end

function calculate_payments(clients, hourly_imbalances, upreg_price, downreg_price)
    T = length(hourly_imbalances[[clients[1]]])

    # Only calculate payments for the grand coalition
    coalition = clients
    member_payments = Dict()
    for m in coalition
        member_payments[m] = zeros(Float64, T)
        for t in 1:T
            total_pos = sum(max(hourly_imbalances[[i]][t], 0) for i in coalition)
            total_neg = sum(-min(hourly_imbalances[[i]][t], 0) for i in coalition)
            member_imb = hourly_imbalances[[m]][t]
            hour_cost = abs(sum(hourly_imbalances[[i]][t] for i in coalition))
            if member_imb > 0 && total_pos > total_neg
                hour_cost = hour_cost * downreg_price
                member_payments[m][t] = hour_cost * (member_imb / total_pos)
            elseif member_imb < 0 && total_neg > total_pos
                hour_cost = hour_cost * upreg_price
                member_payments[m][t] = hour_cost * (abs(member_imb) / total_neg)
            else
                member_payments[m][t] = 0
            end
        end
    end
    return member_payments
end

function gately_point(clients, imbalance_costs)
    A = length(clients)
    v_without = zeros(Float64, length(clients))
    for (idx, i) in enumerate(clients)
        coalition_without_i = filter(x -> x != clients[idx], clients)
        v_without[idx] = imbalance_costs[coalition_without_i]
    end
    v = zeros(Float64, length(clients))
    for (idx, i) in enumerate(clients)
        v[idx] = imbalance_costs[[i]]
    end
    total_imbalance = imbalance_costs[clients]

    function f!(F, x)
        for a in 1:A-1
            F[a] = ((sum(x[b] for b in 1:A if b != a)-v_without[a])/(x[a]-v[a]) 
            - (sum(x[b] for b in 1:A if b != (a+1))-v_without[a+1])/(x[a+1]-v[a+1]))
        end
        F[A] = sum(x) - total_imbalance
    end

    sol = nlsolve(f!, zeros(Float64, A))
    x = sol.zero
    gately_distribution = Dict(zip(clients, x))
    return gately_distribution
end

function full_cost_transfer(clients, hourly_imbalances, systemData)
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    client_cost = Dict{String, Float64}()
    imbalance_price = 0
    for client in clients
        client_cost[client] = 0.0
    end
    for t in 1:length(hourly_imbalances[[clients[1]]])
        net_imbalance = hourly_imbalances[clients][t]
        positive_imbalance = sum(max(hourly_imbalances[[client]][t], 0) for client in clients)
        negative_imbalance = sum(-min(hourly_imbalances[[client]][t], 0) for client in clients)
        if net_imbalance > 0
            imbalance_price = downreg_price
            net_imbalance_cost = net_imbalance * downreg_price
            # Calculate how much each helping client should get per imbalance
            compensation_per_imbalance = (positive_imbalance-net_imbalance)*imbalance_price / negative_imbalance
        else
            imbalance_price = upreg_price
            net_imbalance_cost = abs(net_imbalance) * upreg_price
            compensation_per_imbalance = (negative_imbalance+net_imbalance)*imbalance_price / positive_imbalance
        end
        
        for client in clients
            if hourly_imbalances[[client]][t]* net_imbalance > 0
                # Client has an imbalance in the same direction as the net imbalance
                # Client pays their full cost
                client_cost[client] += abs(hourly_imbalances[[client]][t]) * imbalance_price 
            else 
                # Client counteracts the net imbalance
                # Client pays nothing and receives what harming clients overpaid
                client_cost[client] += -(abs(hourly_imbalances[[client]][t]) * compensation_per_imbalance)
            end
        end
    end

    return client_cost
end

function nucleolus(clients, imbalances)
    coalitions = collect(combinations(clients))
    locked_excesses = Dict{Vector{String}, Float64}()
    payments = Dict{Vector{String}, Float64}()
    new_locked_excesses = Dict{Vector{String}, Float64}()
    while true
        try
            max_excess, new_locked_excesses, payments = nucleolus_optimize(clients, imbalances, locked_excesses)
        catch e
            if length(locked_excesses) == length(coalitions) - 1
                println("All coalitions are locked, the nucleolus has been found")
                return locked_excesses, payments
            else
                println("An error occurred: ", e)
                return nothing, nothing
            end
        end
        # Update locked excesses with the new ones
        for (coalition, excess) in new_locked_excesses
            locked_excesses[coalition] = excess
        end
        #println("Locked excesses updated: ", locked_excesses)
    end
end

function nucleolus_optimize(clients, imbalances, locked_excesses)
    # This function calculates the nucleolus for the given clients and imbalances
    coalitions = collect(combinations(clients))
    coalition_indices = [findall(x -> x in c, clients) for c in coalitions]
    locked_coalitions = keys(locked_excesses)
    locked_indices = [findfirst(x -> Set(x) == Set(c), coalitions) for c in locked_coalitions]
    grand_coalition = vec(clients)
    gc_idx = findfirst(x -> Set(x) == Set(grand_coalition), coalitions)
    A = length(clients)
    C = length(coalitions)

    # Initialize the optimization model
    model = Model(HiGHS.Optimizer)
    #model = Model(Gurobi.Optimizer)
    #set_optimizer_attribute(model, "OutputFlag", 0)
    set_silent(model)

    @variable(model, payment[1:A]) # Payments for each agent
    @variable(model, max_excess) # Maximum excess for the nucleolus 

    @objective(model, Min, max_excess) # Objective function

    # Calculate excess for each coalition
    # Excess is how much more the coalitions pays as part of the grand coalition compared to the coalition value
    # The excess of each coalition must be less than or equal to the maximum excess
    @constraint(model, excess_cons[c = 1:C; c != gc_idx && !(c in locked_indices)],
                sum(payment[i] for i in coalition_indices[c]) - imbalances[coalitions[c]] <=  max_excess)
    
    # Enforce collective rationality
    @constraint(model, sum(payment) == imbalances[grand_coalition])

    # Enforce locked excesses
    @constraint(model, [c = locked_indices],
                sum(payment[i] for i in coalition_indices[c]) - imbalances[coalitions[c]] == locked_excesses[coalitions[c]])

    solution = optimize!(model)
    if termination_status(model) == MOI.OPTIMAL
        #println("Optimal solution found")
        #println("Objective value: ", objective_value(model))
        #println("Dual values of excess constraints: ", dual.(excess_cons))
        dual_values = dual.(excess_cons)
        new_locked_excesses = Dict{Vector{String}, Float64}()
        for i in eachindex(dual_values)
            if dual_values[i] < -1e-6 # Check if the dual value is negative
                #println("Negative dual value for coalition ", coalitions[i[1]], ": ", dual_values[i])
                # Lock the excess for this coalition
                new_locked_excesses[coalitions[i[1]]] = objective_value(model)
            end
        end
        payments = Dict{Vector{String}, Float64}()
        for (idx, client) in enumerate(clients)
            payments[[client]] = value.(payment[idx])
        end
        return objective_value(model), new_locked_excesses, payments
    else
        println("No optimal solution found")
        println("Checking if all coalitions are locked...")
        found = false
        # The problem is unbounded if all coalitions are locked, so we check if that is the case
        for c in 1:C
            if c != gc_idx && !(c in locked_indices)
                println(coalitions[c])
                found = true
            end
        end
        if found
            println("Not all coalitions are locked, the problem is unbounded and there is an error")
        else
            println("All coalitions are locked, the nucleolus has been found")
        end
    end
end
