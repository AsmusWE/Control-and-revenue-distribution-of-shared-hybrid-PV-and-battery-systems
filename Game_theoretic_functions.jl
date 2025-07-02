using Combinatorics, HiGHS, JuMP#, Gurobi, NLsolve,
# Initializing the Gurobi environment
# This is necessary to surpress some of the Gurobi output
#const GUROBI_ENV = Gurobi.Env()


function calculate_allocations(
    allocations, clients, coalitions, coalitionCVaR, hourly_imbalances, systemData; printing = true
    )
    allocation_costs = Dict{String, Any}()
    allocation_map = Dict(
        "shapley" => () -> shapley_value(clients, coalitions, coalitionCVaR),
        #"VCG" => () -> VCG_tax(clients, coalitionCVaR, hourly_imbalances, systemData; budget_balance=false),
        "VCG" => () -> simple_VCG(clients, coalitionCVaR),
        "VCG_budget_balanced" => () -> VCG_tax(clients, coalitionCVaR, hourly_imbalances, systemData; budget_balance=true),
        "gately" => () -> deepcopy(gately_point(clients, coalitionCVaR)),
        #"gately_daily" => () -> deepcopy(gately_point_daily(clients, hourly_imbalances, systemData)),
        "gately_interval" => () -> deepcopy(gately_point_interval(clients, hourly_imbalances, systemData)),
        "full_cost" => () -> deepcopy(full_cost_transfer(clients, hourly_imbalances, systemData)),
        "reduced_cost" => () -> deepcopy(reduced_cost(clients, hourly_imbalances, systemData)),
        "nucleolus" => () -> begin
            _, nucleolus_values = nucleolus(clients, coalitionCVaR)
            deepcopy(nucleolus_values)
        end,
        "equal_share" => () -> deepcopy(equal_allocation(clients, coalitionCVaR))
    )
    allocation_print_map = Dict(
        "shapley" => "Shapley calculation time:",
        "VCG" => "VCG calculation time:",
        "VCG_budget_balanced" => "VCG budget balanced calculation time:",
        "gately" => "Gately calculation time:",
        #"gately_daily" => "Gately calculation time, daily:",
        "gately_interval" => "Gately calculation time, interval:",
        "full_cost" => "Full cost transfer calculation time:",
        "reduced_cost" => "reduced cost calculation time:",
        "nucleolus" => "Nucleolus calculation time:",
        "equal_share" => "Equal share calculation time:"
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
    systemData, 
    start_hour, 
    sim_days::Int
)
    # This function calculates the allocations for each day and returns the costs, imbalances, and interval (15-min) imbalances

    intervals_per_day = 96 # 15-min intervals per day
    # Initialize data structures
    allocation_costs_daily_scaled = Dict{Tuple{String, String, Int}, Float64}()
    allocation_costs = Dict(allocation => Dict(client => 0.0 for client in clients) for allocation in allocations)
    imbalances = Dict(coalition => 0.0 for coalition in coalitions)
    interval_imbalances = Dict(client => Float64[] for client in clients)

    for day in 1:sim_days
        curr_interval = start_hour + Dates.Minute((day - 1) * intervals_per_day * 15)
        println("Calculating allocations for day $day")
        imbalances_day, interval_imbalances_day = period_imbalance(systemData, clients, curr_interval, 1; threads = false, printing = false)
        daily_allocations = calculate_allocations(
            allocations, clients, coalitions, imbalances_day, interval_imbalances_day, systemData; printing = false
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
        # Accumulate imbalances and interval imbalances
        for (coalition, imbalance) in imbalances_day
            imbalances[coalition] += imbalance
        end
        for client in clients
            append!(interval_imbalances[client], interval_imbalances_day[[client]])
        end
    end

    return allocation_costs_daily_scaled, allocation_costs, imbalances, interval_imbalances
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

function simple_VCG(clients, coalitionCVaR)
    # This function calculates the VCG value for each client in the grand coalition
    grand_coalition = vec(clients)
    grand_coalition_CVaR = coalitionCVaR[grand_coalition]
    utilities = Dict{String, Float64}()
    for client in clients
        coalition_wo_client = filter(x -> x != client, grand_coalition)
        coalition_value_wo_client = coalitionCVaR[coalition_wo_client]
        # Calculate the VCG value for the client
        VCG_value = (grand_coalition_CVaR-coalition_value_wo_client)
        # Store the VCG value in a dictionary
        utilities[client] = VCG_value
    end
    return utilities
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

function gately_point_interval(clients, interval_imbalances, systemData)
    # This function applies the Gately point calculation for each interval (15-min)
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    coalitions = collect(combinations(clients))
    T = length(interval_imbalances[[clients[1]]])
    gately_distribution = Dict(client => 0.0 for client in clients)

    for t in 1:T
        # Build imbalance_costs for the current interval
        imbalance_costs = Dict{Vector{String}, Float64}()
        for coalition in coalitions
            temp_cost = sum(interval_imbalances[[c]][t] for c in coalition)
            if temp_cost < 0
                imbalance_costs[coalition] = abs(temp_cost) * upreg_price
            else
                imbalance_costs[coalition] = temp_cost * downreg_price
            end
        end
        # Calculate Gately point for the current interval and add to the distribution
        gately_interval = gately_point(clients, imbalance_costs)
        # Check for NaN values in the Gately distribution for the current interval
        if any(isnan, values(gately_interval))
            println("Warning: NaN detected in Gately distribution for interval $t.")
        end
        for client in clients
            gately_distribution[client] += gately_interval[client]
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
    # Optimized nucleolus computation with reduced memory allocations
    n_clients = length(clients)
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    
    # Pre-allocate and cache coalition indices for faster access
    client_to_idx = Dict(client => i for (i, client) in enumerate(clients))
    coalition_indices = Vector{Vector{Int}}(undef, n_coalitions)
    
    # Build coalition indices and imbalances vector more efficiently
    imbalances_vec = Vector{Float64}(undef, n_coalitions)
    
    for (i, coalition) in enumerate(coalitions)
        # Convert client names to indices for faster constraint building
        coalition_indices[i] = [client_to_idx[client] for client in coalition]
        
        # Look up imbalance value with fallback
        if haskey(imbalances, coalition)
            imbalances_vec[i] = imbalances[coalition]
        else
            # Try as sorted tuple (more efficient than collect)
            sorted_coalition = sort(coalition)
            imbalances_vec[i] = get(imbalances, sorted_coalition, 0.0)
        end
    end
    
    # Use BitVector for locked status - much more memory efficient than Union{Nothing, Float64}
    locked_status = falses(n_coalitions)
    locked_values = zeros(Float64, n_coalitions)
    
    # Find grand coalition index once
    grand_coalition_idx = findfirst(c -> length(c) == n_clients, coalitions)
    
    payments = Dict{String, Float64}()
    max_iterations = n_coalitions  # Prevent infinite loops
    iteration = 0
    
    while iteration < max_iterations
        iteration += 1
        
        try
            max_excess, new_locked_indices, new_payments = nucleolus_optimize_fast(
                n_clients, imbalances_vec, locked_status, locked_values, 
                coalition_indices, grand_coalition_idx
            )
            
            # Update locked status efficiently
            for idx in new_locked_indices
                locked_status[idx] = true
                locked_values[idx] = max_excess
            end
            
            # Update payments
            for (i, client) in enumerate(clients)
                payments[client] = new_payments[i]
            end
            
            # Check if we're done (all coalitions except grand coalition are locked)
            if count(locked_status) >= n_coalitions - 1
                break
            end
            
        catch e
            if count(locked_status) >= n_coalitions - 1
                # Return current solution
                locked_dict = Dict{Vector{String}, Float64}()
                for (i, coalition) in enumerate(coalitions)
                    if locked_status[i]
                        locked_dict[coalition] = locked_values[i]
                    end
                end
                return locked_dict, payments
            else
                println("Nucleolus optimization failed: ", e)
                return nothing, nothing
            end
        end
    end
    
    # Build final locked dictionary
    locked_dict = Dict{Vector{String}, Float64}()
    for (i, coalition) in enumerate(coalitions)
        if locked_status[i]
            locked_dict[coalition] = locked_values[i]
        end
    end
    
    return locked_dict, payments
end

function nucleolus_optimize_fast(n_clients, imbalances_vec, locked_status, locked_values, 
                                coalition_indices, grand_coalition_idx)
    n_coalitions = length(coalition_indices)
    
    # Create model with optimized settings
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    
    # Set HiGHS-specific parameters for better performance
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "parallel", "on")
    
    @variable(model, payment[1:n_clients])
    @variable(model, max_excess)
    @objective(model, Min, max_excess)
    
    # Build constraints more efficiently using pre-computed indices
    unlocked_coalitions = findall(i -> !locked_status[i] && i != grand_coalition_idx, 1:n_coalitions)
    
    # Excess constraints only for unlocked coalitions (excluding grand coalition)
    @constraint(model, excess_cons[i in unlocked_coalitions],
                sum(payment[j] for j in coalition_indices[i]) - imbalances_vec[i] <= max_excess)
    
    # Grand coalition constraint (budget balance)
    @constraint(model, sum(payment) == imbalances_vec[grand_coalition_idx])
    
    # Locked coalition constraints
    locked_coalitions = findall(locked_status)
    @constraint(model, [i in locked_coalitions],
                sum(payment[j] for j in coalition_indices[i]) - imbalances_vec[i] == locked_values[i])
    
    optimize!(model)
    
    if termination_status(model) == MOI.OPTIMAL
        payment_values = value.(payment)
        max_excess_val = objective_value(model)
        
        # Find coalitions that achieve maximum excess
        new_locked_indices = Int[]
        tol = 1e-8  # Slightly tighter tolerance for better numerical stability
        
        for i in unlocked_coalitions
            excess_val = sum(payment_values[j] for j in coalition_indices[i]) - imbalances_vec[i]
            if abs(excess_val - max_excess_val) < tol
                push!(new_locked_indices, i)
            end
        end
        
        return max_excess_val, new_locked_indices, payment_values
    else
        error("No optimal solution found in nucleolus optimization")
    end
end

function equal_allocation(clients, imbalances)
    # This function calculates an even allocation for each client in the grand coalition
    # It distributes the grand coalition imbalance cost evenly among all clients according to their imbalance
    grand_coalition_imbalance = imbalances[clients]
    total_solo_imbalance = sum(imbalances[[client]] for client in clients)
    imbalance_factor = grand_coalition_imbalance / total_solo_imbalance
    equal_allocation = Dict{String, Float64}()
    for client in clients
        equal_allocation[client] = imbalances[[client]] * imbalance_factor
    end
    return equal_allocation
end
