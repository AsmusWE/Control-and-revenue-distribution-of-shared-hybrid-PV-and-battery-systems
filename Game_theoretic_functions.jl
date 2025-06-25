using Combinatorics, NLsolve, HiGHS, JuMP#, Gurobi
# Initializing the Gurobi environment
# This is necessary to surpress some of the Gurobi output
#const GUROBI_ENV = Gurobi.Env()


function calculate_allocations(
    allocations, clients, coalitions, imbalances, hourly_imbalances, systemData; printing = true
    )
    # Refactored: Use a mapping for allocation types to their calculation logic
    allocation_costs = Dict{String, Any}()
    allocation_map = Dict(
        "shapley" => () -> shapley_value(clients, coalitions, imbalances),
        "VCG" => () -> VCG_tax(clients, imbalances, hourly_imbalances, systemData; budget_balance=false),
        "VCG_budget_balanced" => () -> VCG_tax(clients, imbalances, hourly_imbalances, systemData; budget_balance=true),
        "gately_full" => () -> deepcopy(gately_point(clients, imbalances)),
        "gately_daily" => () -> deepcopy(gately_point_daily(clients, hourly_imbalances, systemData)),
        "gately_hourly" => () -> deepcopy(gately_point_hourly(clients, hourly_imbalances, systemData)),
        "full_cost" => () -> deepcopy(full_cost_transfer(clients, hourly_imbalances, systemData)),
        "reduced_cost" => () -> deepcopy(reduced_cost(clients, hourly_imbalances, systemData)),
        "nucleolus" => () -> begin
            _, nucleolus_values = nucleolus(clients, imbalances)
            deepcopy(nucleolus_values)
        end
    )
    allocation_print_map = Dict(
        "shapley" => "Shapley calculation time:",
        "VCG" => "VCG calculation time:",
        "VCG_budget_balanced" => "VCG budget balanced calculation time:",
        "gately_full" => "Gately calculation time, full period:",
        "gately_daily" => "Gately calculation time, daily:",
        "gately_hourly" => "Gately calculation time, hourly:",
        "full_cost" => "Full cost transfer calculation time:",
        "reduced_cost" => "reduced cost calculation time:",
        "nucleolus" => "Nucleolus calculation time:"
    )
    for allocation in allocations
        if haskey(allocation_map, allocation)
            if printing && haskey(allocation_print_map, allocation)
                println(allocation_print_map[allocation])
                allocation_costs[allocation] = @time allocation_map[allocation]()
            else
                allocation_costs[allocation] = allocation_map[allocation]()
            end
        end
    end
    return allocation_costs
    
end

function allocation_variance(
    allocations::Vector{String}, 
    clients::Vector{String}, 
    coalitions::Vector{Vector{String}}, 
    systemData::Dict, 
    start_hour, 
    sim_days::Int
)
    # This function calculates the allocations for each day and returns the costs, imbalances, and hourly imbalances

    # Initialize data structures
    allocation_costs_daily_scaled = Dict{Tuple{String, String, Int}, Float64}()
    allocation_costs = Dict(allocation => Dict(client => 0.0 for client in clients) for allocation in allocations)
    imbalances = Dict(coalition => 0.0 for coalition in coalitions)
    hourly_imbalances = Dict(client => Float64[] for client in clients)

    for day in 1:sim_days
        curr_hour = start_hour + Dates.Hour((day - 1) * 24)
        println("Calculating allocations for day $day")
        imbalances_day, hourly_imbalances_day = period_imbalance(systemData, clients, curr_hour, 1; threads = false, printing = false)
        daily_allocations = calculate_allocations(
            allocations, clients, coalitions, imbalances_day, hourly_imbalances_day, systemData; printing = false
        )
        # Extracting allocations and adding them to total client allocation
        for allocation in allocations
            alloc = daily_allocations[allocation]
            for client in clients
                allocation_costs[allocation][client] += alloc[client]
                # Scale allocations to cost per MWh imbalance
                allocation_costs_daily_scaled[(client, allocation, day)] = alloc[client] / imbalances_day[[client]]
            end
        end
        # Accumulate imbalances and hourly imbalances
        for (coalition, imbalance) in imbalances_day
            imbalances[coalition] += imbalance
        end
        for client in clients
            append!(hourly_imbalances[client], hourly_imbalances_day[[client]])
        end
    end

    return allocation_costs_daily_scaled, allocation_costs, imbalances, hourly_imbalances
end


function shapley_value(clients, coalitions, imbalances)
    # This function calculates the Shapley value for each client in the grand coalition
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

function check_stability(payoffs, coalition_values, clients)
    # This function checks the stability of the coalition by comparing the excess of each coalition
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
    return max_instability
end

function VCG_tax(clients, imbalance_costs, hourly_imbalances, systemData; budget_balance=false)
    # This function calculates the VCG value for each client in the grand coalition
    # Handles both budget balanced and non-budget balanced cases
    # Done by calculating taxes and value for each client, and then summing them up
    T = length(hourly_imbalances[[clients[1]]])
    grand_coalition = vec(clients)
    payments = calculate_payments(clients, hourly_imbalances, systemData["upreg_price"], systemData["downreg_price"])
    VCG_taxes = Dict{Vector{String}, Float64}()

    # If budget balance is required, subsidies are adjusted to ensure the total taxes equal zero
    if budget_balance
        for t in 1:T
            temp_taxes = Dict{String, Float64}()
            # Calculate unadjusted taxes for each client
            for i in clients
                coalition_wo_i = filter(x -> x != i, grand_coalition)
                gc_val_minus_i = sum(payments[client][t] for client in grand_coalition if client != i)
                coalition_value_wo_i = sum(hourly_imbalances[coalition_wo_i][t])
                price = systemData["downreg_price"]
                if coalition_value_wo_i < 0
                    price = systemData["upreg_price"]
                end
                coalition_value_wo_i = abs(coalition_value_wo_i) * price
                temp_taxes[i] = -(coalition_value_wo_i - gc_val_minus_i)
            end
            # Adjust taxes to ensure budget balance
            total_taxes = sum(values(temp_taxes))
            if total_taxes < -1e-4
                subsidies = sum(v for v in values(temp_taxes) if v < 0)
                taxes = sum(v for v in values(temp_taxes) if v > 0; init=0.0)
                ratio = taxes / abs(subsidies)
                for k in keys(temp_taxes)
                    if temp_taxes[k] < 0
                        temp_taxes[k] *= ratio
                    end
                end
            end
            for i in clients
                VCG_taxes[[i]] = get(VCG_taxes, [i], 0.0) + temp_taxes[i]
            end
        end
    else
        for i in clients
            coalition_wo_i = filter(x -> x != i, grand_coalition)
            coalition_value_wo_i = imbalance_costs[coalition_wo_i]
            gc_val_minus_i = sum(sum(payments[client] for client in grand_coalition if client != i))
            VCG_taxes[[i]] = -(coalition_value_wo_i - gc_val_minus_i)
        end
    end
    # Calculate final utilities
    utilities = Dict(client => sum(payments[client]) + VCG_taxes[[client]] for client in clients)
    return utilities
end

function calculate_payments(clients, hourly_imbalances, upreg_price, downreg_price)
    # This function calculates the payments for each client in the grand coalition
    # Used for VCG calculation
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
    # This function calculates the Gately point for the given clients and their imbalance costs
    A = length(clients)
    v_without = [imbalance_costs[filter(x -> x != client, clients)] for client in clients]
    v = [imbalance_costs[[client]] for client in clients]
    total_imbalance = imbalance_costs[clients]
    gately_distribution = Dict{String, Float64}()

    # Finding propensity to disrupt with the closed form solution
    d = ((A-1)*total_imbalance-sum(v_without))/(total_imbalance-sum(v))
    if isnan(d) || isinf(d)
        #println("d is NaN or infinite")
        #println("Likely cause: all imbalances have the same sign, or no imbalance at all")
        #println("Returning solitary client imbalance costs")
        for (idx, client) in enumerate(clients)
            gately_distribution[client] = v[idx]
            #println("Client: ", client, ", Gately distribution: ", gately_distribution[client])
        end
        return gately_distribution
    end

    # Calculating allocation using the found propensity to disrupt
    for (idx,client) in enumerate(clients)
        # d = ((total_imbalance-v_without(client)) - x)/(x-v[client])        
        gately_distribution[client] = (d*v[idx] + total_imbalance - v_without[idx]) / (d + 1)
    end

    return gately_distribution
end

function gately_point_hourly(clients, hourly_imbalances, systemData)
    # This function applies the Gately point calculation for each hour
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    coalitions = collect(combinations(clients))
    T = length(hourly_imbalances[[clients[1]]])
    gately_distribution = Dict(client => 0.0 for client in clients)

    for t in 1:T
        # Build imbalance_costs for the current hour
        imbalance_costs = Dict{Vector{String}, Float64}()
        for coalition in coalitions
            temp_cost = sum(hourly_imbalances[[c]][t] for c in coalition)
            if temp_cost < 0
                imbalance_costs[coalition] = abs(temp_cost) * upreg_price
            else
                imbalance_costs[coalition] = temp_cost * downreg_price
            end
        end
        # Calculate Gately point for the current hour and add to the distribution
        gately_hour = gately_point(clients, imbalance_costs)
        # Check for NaN values in the Gately distribution for the current hour
        if any(isnan, values(gately_hour))
            println("Warning: NaN detected in Gately distribution for hour $t.")
        end
        for client in clients
            gately_distribution[client] += gately_hour[client]
        end
    end
    return gately_distribution
end

function full_cost_transfer(clients, hourly_imbalances, systemData)
    # Initializing
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    client_cost = Dict(client => 0.0 for client in clients)
    # Calculating cost for every hour
    for t in 1:length(hourly_imbalances[[clients[1]]])
        net_imbalance = hourly_imbalances[clients][t]
        # # Calculate how much each helping client should get per imbalance
        imbalance_price = net_imbalance > 0 ? downreg_price : upreg_price
        # Check each client if they are helping or not, and calculate their cost
        for client in clients
            if hourly_imbalances[[client]][t] * net_imbalance > 0
                # Client has an imbalance in the same direction as the net imbalance
                # Client pays their full cost
                client_cost[client] += abs(hourly_imbalances[[client]][t]) * imbalance_price
            else
                # Client counteracts the net imbalance
                # Client pays nothing and gets compensated for reducing the imbalance
                client_cost[client] += -(abs(hourly_imbalances[[client]][t]) * imbalance_price)
            end
        end
    end
    return client_cost
end

function reduced_cost(clients, hourly_imbalances, systemData)
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    client_cost = Dict{String, Float64}()
    for client in clients
        client_cost[client] = 0.0
    end
    for t in 1:length(hourly_imbalances[[clients[1]]])
        net_imbalance = hourly_imbalances[clients][t]
        positive_imbalance = sum(max(hourly_imbalances[[client]][t], 0) for client in clients)
        negative_imbalance = sum(-min(hourly_imbalances[[client]][t], 0) for client in clients)
        if net_imbalance > 0
            imbalance_price = downreg_price
            #net_imbalance_cost = net_imbalance * downreg_price
            cost_per_imbalance = (net_imbalance/positive_imbalance) * imbalance_price
        else
            imbalance_price = upreg_price
            #net_imbalance_cost = abs(net_imbalance) * upreg_price
            cost_per_imbalance = (abs(net_imbalance)/negative_imbalance) * imbalance_price
        end
        for client in clients
            client_imb = hourly_imbalances[[client]][t]
            # Check if client harms (same sign as net imbalance and not zero)
            if client_imb * net_imbalance > 0 && net_imbalance != 0
                client_cost[client] += abs(client_imb) * cost_per_imbalance
            else
                # Helping clients pay 0
                client_cost[client] += 0.0
            end
        end
    end
    return client_cost
end


function nucleolus(clients, imbalances)
    # Use sorted tuples for coalition keys and arrays for fast access
    coalitions = [Tuple(sort(c)) for c in collect(combinations(clients))]
    coalition_index = Dict(c => i for (i, c) in enumerate(coalitions))
    # Build imbalances as a vector
    imbalances_vec = zeros(Float64, length(coalitions))
    for (i, c) in enumerate(coalitions)
        if haskey(imbalances, c)
            imbalances_vec[i] = imbalances[c]
        elseif haskey(imbalances, collect(c))
            imbalances_vec[i] = imbalances[collect(c)]
        else
            imbalances_vec[i] = 0.0
        end
    end
    # locked_excesses: nothing means not locked, otherwise Float64
    locked_excesses_vec = Vector{Union{Nothing, Float64}}(undef, length(coalitions))
    fill!(locked_excesses_vec, nothing)
    payments = Dict{String, Float64}()
    while true
        try
            max_excess, new_locked_excesses, payments = nucleolus_optimize(clients, imbalances_vec, locked_excesses_vec, coalitions, coalition_index)
            # Only update if optimization was successful
            for (idx, val) in new_locked_excesses
                locked_excesses_vec[idx] = val
            end
        catch e
            # Handle the case where no optimal solution is found
            nlocked = count(!isnothing, locked_excesses_vec)
            if nlocked == length(coalitions) - 1
                # If all coalitions except grand coalition are locked, we can return the nucleolus
                # Return as Dict for compatibility
                locked_dict = Dict(coalitions[i] => v for (i, v) in enumerate(locked_excesses_vec) if !isnothing(v))
                return locked_dict, payments
            else
                println("An error occurred: ", e)
                return nothing, nothing
            end
        end
    end
end

function nucleolus_optimize(clients, imbalances_vec, locked_excesses_vec, coalitions, coalition_index)
    # Use arrays for imbalances and locked_excesses
    coalition_indices = [findall(x -> x in c, clients) for c in coalitions]
    locked_indices = findall(!isnothing, locked_excesses_vec)
    grand_coalition = Tuple(sort(clients))
    gc_idx = coalition_index[grand_coalition]
    A = length(clients)
    C = length(coalitions)

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    #model = Model(() -> Gurobi.Optimizer(GUROBI_ENV))
    #set_optimizer_attribute(model, "OutputFlag", 0)

    @variable(model, payment[1:A])
    @variable(model, max_excess)
    @objective(model, Min, max_excess)

    @constraint(model, excess_cons[c = 1:C; c != gc_idx && !(c in locked_indices)],
                sum(payment[i] for i in coalition_indices[c]) - imbalances_vec[c] <= max_excess)
    @constraint(model, sum(payment) == imbalances_vec[gc_idx])
    @constraint(model, [c = locked_indices],
                sum(payment[i] for i in coalition_indices[c]) - imbalances_vec[c] == locked_excesses_vec[c])

    solution = optimize!(model)
    if termination_status(model) == MOI.OPTIMAL
        dual_values = dual.(excess_cons)
        new_locked_excesses = Dict{Int, Float64}()
        for i in eachindex(dual_values)
            if dual_values[i] < -1e-6
                new_locked_excesses[i[1]] = objective_value(model)
            end
        end
        payments = Dict{String, Float64}()
        for (idx, client) in enumerate(clients)
            payments[client] = value.(payment[idx])
        end
        return objective_value(model), new_locked_excesses, payments
    else
        println("No optimal solution found")
        println("Checking if all coalitions are locked...")
        found = false
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
