# Import the required functions from imbalance_functions.jl
include("imbalance_functions.jl")

function calculate_CVaR_timing(systemData, coalitions, T, imbalance_spread, alpha)
    # Calculate CVaR for specific coalitions

    # Get all unique clients from all coalitions
    all_clients = unique(vcat(coalitions...))
    
    # Calculate bids for each individual client 
    individual_bids = Dict()
    for client in all_clients
        individual_bids[client] = optimize_imbalance([client], systemData)
    end
    
    # Pre-calculate actual demand and PV for each client
    actual_demand_per_client = Dict()
    actual_pv_per_client = Dict()
    for client in all_clients
        actual_demand_per_client[client] = systemData["price_prod_demand_df"][1:T, client]
        actual_pv_per_client[client] = systemData["price_prod_demand_df"][1:T, :SolarMWh] .* systemData["clientPVOwnership"][client]
    end
    
    # Calculate CVaR for each coalition by summing individual components
    cvar_dict = Dict()
    for coalition in coalitions
        # Sum bids for this coalition
        coalition_bids = sum(individual_bids[client] for client in coalition)
        
        # Sum actual demand for this coalition
        coalition_demand = sum(actual_demand_per_client[client] for client in coalition)
        
        # Sum actual PV for this coalition
        coalition_pv = sum(actual_pv_per_client[client] for client in coalition)
        
        # Calculate actual imbalances
        actual_imbalances = get_imbalance(coalition_bids, coalition_pv, coalition_demand)
        imbalance_costs = actual_imbalances .* imbalance_spread
        
        # Calculate CVaR
        n = length(imbalance_costs)
        index = ceil(Int, n * alpha)  # Index for VaR
        partialsort!(imbalance_costs, 1:index, rev=true)  # In-place partial sort
        cvar_value = mean(imbalance_costs[1:index])  # Average of the highest alpha% of costs
        
        cvar_dict[coalition] = cvar_value
    end
    
    return cvar_dict
end

function CVaR_VCG(systemData, clients, startDay, days; alpha=0.05, printing=false)
    # VCG mechanism requires coalitions of size N-1 and N
    # N-1: all coalitions without one client (needed for VCG calculation)
    # N: the grand coalition (all clients together)
    
    n = length(clients)
    relevant_coalitions = []
    
    # Add grand coalition (size N)
    push!(relevant_coalitions, clients)
    
    # Add all coalitions of size N-1 (exclude one client at a time)
    for i in 1:n
        coalition_wo_i = [clients[j] for j in 1:n if j != i]
        push!(relevant_coalitions, coalition_wo_i)
    end
    
    if printing
        println("CVaR_VCG: Calculating CVaR for $(length(relevant_coalitions)) coalitions")
        println("Coalition sizes: $(sort(unique([length(c) for c in relevant_coalitions])))")
    end
    
    # Set up time period
    tempData = set_period!(systemData, startDay, days)
    T = size(tempData["price_prod_demand_df"], 1)
    imbalance_spread = tempData["price_prod_demand_df"][!, "ImbalanceSpreadEUR"]
    
    # Calculate CVaR for all relevant coalitions at once
    cvar_dict = calculate_CVaR_timing(tempData, relevant_coalitions, T, imbalance_spread, alpha)
    GC.gc()  # Force garbage collection to free memory
    return cvar_dict
end

function CVaR_Gately(systemData, clients, startDay, days; alpha=0.05, printing=false)
    # Gately mechanism requires coalitions of size 1, N-1, and N
    # Size 1: individual clients (needed for Gately calculation)
    # Size N-1: all coalitions without one client
    # Size N: the grand coalition
    
    n = length(clients)
    relevant_coalitions = []
    
    # Add individual coalitions (size 1)
    for client in clients
        push!(relevant_coalitions, [client])
    end
    
    # Add grand coalition (size N)
    push!(relevant_coalitions, clients)
    
    # Add all coalitions of size N-1 (exclude one client at a time)
    for i in 1:n
        coalition_wo_i = [clients[j] for j in 1:n if j != i]
        push!(relevant_coalitions, coalition_wo_i)
    end
    
    if printing
        println("CVaR_Gately: Calculating CVaR for $(length(relevant_coalitions)) coalitions")
        println("Coalition sizes: $(sort(unique([length(c) for c in relevant_coalitions])))")
    end
    
    # Set up time period
    tempData = set_period!(systemData, startDay, days)
    T = size(tempData["price_prod_demand_df"], 1)
    imbalance_spread = tempData["price_prod_demand_df"][!, "ImbalanceSpreadEUR"]
    
    # Calculate CVaR for all relevant coalitions at once
    cvar_dict = calculate_CVaR_timing(tempData, relevant_coalitions, T, imbalance_spread, alpha)
    GC.gc()  # Force garbage collection to free memory
    return cvar_dict
end