# Imbalance Functions for Coalition Analysis
# Functions for calculating imbalances, bids, and CVaR for bidding coalitions

using JuMP
using HiGHS
using Combinatorics
using Dates
using Statistics

function get_demand_forecast(coalition, systemData, TimeHorizon)
    forecast_type = systemData["demand_forecast"]
    if forecast_type == "perfect"
        return sum(systemData["price_prod_demand_df"][1:TimeHorizon, client] for client in coalition)
    elseif forecast_type == "scenarios"
        return sum(systemData["demand_scenarios"][client] for client in coalition)
    elseif forecast_type == "noise"
        std_dev = systemData["demand_noise_std"]
        actual_demand = sum(systemData["price_prod_demand_df"][1:TimeHorizon, client] for client in coalition)
        return actual_demand .* (1 .+ std_dev * randn(TimeHorizon, 1))
    else
        error("Unknown demand forecast type: $forecast_type")
    end
end

function get_pv_forecast(systemData, T)
    forecast_type = systemData["pv_forecast"]
    if forecast_type == "perfect"
        return systemData["price_prod_demand_df"][1:T, :SolarMWh]
    elseif forecast_type == "scenarios"
        return systemData["price_prod_demand_df"][1:T, :PVForecast]
    elseif forecast_type == "noise"
        return systemData["pv_forecast_noise"][1:T]
    else
        error("Unknown PV forecast type: $forecast_type")
    end
end

function optimize_imbalance(coalition, systemData)
    clientPVOwnership = getindex.(Ref(systemData["clientPVOwnership"]), coalition)
    TimeHorizon = length(systemData["price_prod_demand_df"][!, "HourUTC_datetime"])
    T = min(TimeHorizon, size(systemData["price_prod_demand_df"])[1])
    
    demand = get_demand_forecast(coalition, systemData, TimeHorizon)
    pvProduction = get_pv_forecast(systemData, T)
    prod = pvProduction .* sum(clientPVOwnership)
    
    S = length(demand[1,:])  # Number of scenarios
    prob = 1/S

    # Set up optimization model
    model = Model(HiGHS.Optimizer)
    #model = Model(Gurobi.Optimizer)
    #set_optimizer_attribute(model, "OutputFlag", 0)
    set_silent(model)

    @variable(model, imbal[1:T, 1:S]) # Imbalance amount
    @variable(model, pos_imbal[1:T, 1:S] >= 0) # Positive imbalance
    @variable(model, neg_imbal[1:T, 1:S] >= 0) # Negative imbalance
    @variable(model, bid[1:T]) # Bid amount

    # Imbalance should be as close to zero as possible
    @objective(model, Min, prob * sum((pos_imbal[t, s] + neg_imbal[t, s]) for t in 1:T for s in 1:S)) # Objective function

    @constraint(model, [t = 1:T, s = 1:S],
                imbal[t, s] == demand[t, s] - prod[t] - bid[t])
    @constraint(model, [t = 1:T, s = 1:S], pos_imbal[t, s] - neg_imbal[t, s] == imbal[t, s])
    solution = optimize!(model)
    if termination_status(model) == MOI.OPTIMAL
        #println("Optimal solution found")
        #println("Objective value: ", objective_value(model))
        return value.(bid)
    else
        println("No optimal solution found")
    end
end

function get_imbalance(bids, pvProd, demand)
    # Ensure all vectors have the same length
    min_length = min(length(bids), length(pvProd), length(demand))
    return bids[1:min_length] + pvProd[1:min_length] - demand[1:min_length]
end

function calculate_imbalance(systemData, clients)
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    bids_dict = calculate_bids(coalitions, systemData)
    
    # Pre-allocate arrays for better performance
    demand_sum_vec = Vector{Vector{Float64}}(undef, n_coalitions)
    scaled_pvProd_vec = Vector{Vector{Float64}}(undef, n_coalitions)
    for (i, coalition) in enumerate(coalitions)
        demand_sum_vec[i] = sum(systemData["price_prod_demand_df"][!, c] for c in coalition)
        scaled_pvProd_vec[i] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* sum(systemData["clientPVOwnership"][c] for c in coalition)
    end
    
    return coalitions, demand_sum_vec, scaled_pvProd_vec, bids_dict
end

function calculate_bids(coalitions, systemData)
    # This function calculates the bids for each coalition combination
    bids = Dict()
    
    # Calculate bids for individual clients first
    individual_clients = filter(c -> length(c) == 1, coalitions)
    for client in individual_clients
        bids[client] = optimize_imbalance(client, systemData)
    end
    
    # Calculate bids for coalitions by summing individual bids
    for coalition in coalitions
        if length(coalition) > 1
            bids[coalition] = sum(bids[[client]] for client in coalition)
        end
    end
    
    return bids
end

function chunk_imbalance(systemData, clients; printing=false, chunkSize = 14)
    # chunkSize is in days
    # Calculate the starting interval index
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    
    # Constants
    INTERVALS_PER_DAY = 96  # 15-min intervals per day
    intervals_per_chunk = chunkSize * INTERVALS_PER_DAY
    total_intervals = size(systemData["price_prod_demand_df"], 1)
    num_chunks = ceil(Int, total_intervals / intervals_per_chunk)
    
    # Initialize result matrix
    period_interval_imbalance = zeros(n_coalitions, total_intervals)
    
    for chunk_idx in 1:num_chunks
        printing && println("Processing chunk $chunk_idx of $num_chunks")
        
        # Calculate chunk boundaries
        start_idx = (chunk_idx - 1) * intervals_per_chunk + 1
        chunk_length = min(intervals_per_chunk, total_intervals - start_idx + 1)
        
        # Prepare chunk data
        chunk_data = prepare_chunk_data(systemData, start_idx, chunk_length, INTERVALS_PER_DAY)
        
        # Calculate imbalances for this chunk
        coalitions, demand_vec, pv_vec, bids_dict = calculate_imbalance(chunk_data, clients)
        
        # Store results
        end_idx = start_idx + chunk_length - 1
        for (i, coalition) in enumerate(coalitions)
            imbalance = get_imbalance(bids_dict[coalition], pv_vec[i], demand_vec[i])
            period_interval_imbalance[i, start_idx:end_idx] = imbalance
        end
        
        GC.gc()  # Force garbage collection
    end
    
    return coalitions, period_interval_imbalance
end

function prepare_chunk_data(systemData, start_idx, chunk_length, intervals_per_day)
    chunk_start_day = systemData["price_prod_demand_df"][start_idx, "HourUTC_datetime"]
    chunk_days = div(chunk_length, intervals_per_day)
    chunk_data = set_period!(systemData, chunk_start_day, chunk_days)
    
    # Adjust scenario data if present
    if haskey(systemData, "demand_scenarios")
        chunk_data["demand_scenarios"] = Dict()
        for (client, scenarios) in systemData["demand_scenarios"]
            end_idx = start_idx + chunk_length - 1
            chunk_data["demand_scenarios"][client] = scenarios[start_idx:end_idx, :]
        end
    end
    
    # Adjust PV forecast noise if present
    if haskey(systemData, "pv_forecast_noise")
        end_idx = start_idx + chunk_length - 1
        chunk_data["pv_forecast_noise"] = systemData["pv_forecast_noise"][start_idx:end_idx]
    end
    
    return chunk_data
end


function calculate_CVaR(systemData, clients, startDay, days; alpha=0.05, printing=false, chunkSize=14)
    # Validate inputs
    alpha > 0 && alpha < 1 || error("Alpha must be between 0 and 1, got $alpha")
    
    # Set up time period
    intervals_per_day = 96
    intervals = days * intervals_per_day
    tempData = create_time_period_data(systemData, startDay, intervals)
    
    # Calculate imbalances for all coalitions
    coalitions, period_interval_imbalance = chunk_imbalance(tempData, clients; printing, chunkSize)
    
    # Calculate CVaR for each coalition
    imbalance_spread = tempData["price_prod_demand_df"][!, "ImbalanceSpreadEUR"]
    cvar_dict, imbalance_dict = calculate_cvar_values(coalitions, period_interval_imbalance, imbalance_spread, alpha)
    
    return cvar_dict, imbalance_dict
end

function create_time_period_data(systemData, startDay, intervals)
    start_interval = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!, "HourUTC_datetime"])
    tempData = deepcopy(systemData)
    
    try
        end_interval = start_interval + intervals - 1
        tempData["price_prod_demand_df"] = systemData["price_prod_demand_df"][start_interval:end_interval, :]
    catch e
        if isa(e, BoundsError)
            data_range = "$(systemData["price_prod_demand_df"][1, "HourUTC_datetime"]) to $(systemData["price_prod_demand_df"][end, "HourUTC_datetime"])"
            error("Specified time period exceeds available data range: $data_range")
        else
            rethrow(e)
        end
    end
    
    return tempData
end

function set_period!(systemData, startDay, days)
    # Set up time period for the given number of days
    intervals_per_day = 96  # 15-min intervals per day
    intervals = days * intervals_per_day
    return create_time_period_data(systemData, startDay, intervals)
end

function calculate_cvar_values(coalitions, period_interval_imbalance, imbalance_spread, alpha)
    n_coalitions = length(coalitions)
    intervals = size(period_interval_imbalance, 2)
    var_index = ceil(Int, intervals * alpha)
    
    # Pre-allocate results
    cvar_dict = Dict{Any, Float64}()
    imbalance_dict = Dict{Any, Vector{Float64}}()
    sizehint!(cvar_dict, n_coalitions)
    sizehint!(imbalance_dict, n_coalitions)
    
    for (i, coalition) in enumerate(coalitions)
        # Calculate costs and CVaR
        imbalance_costs = period_interval_imbalance[i, :] .* imbalance_spread
        partialsort!(imbalance_costs, 1:var_index, rev=true)
        cvar_value = mean(imbalance_costs[1:var_index])
        
        # Store results
        cvar_dict[coalition] = cvar_value
        imbalance_dict[coalition] = view(period_interval_imbalance, i, :)
    end
    
    return cvar_dict, imbalance_dict
end

function calculate_MAE(systemData, demandForecast, pvForecast, clients, start_interval, days)
    # Calculate the Mean Absolute Error (MAE) of the demand forecast
    totalDemand = 0
    tempData = set_period!(systemData, start_interval, days)
    totalDemandInterval = zeros(size(tempData["price_prod_demand_df"], 1))
    demandForecastType = tempData["demand_forecast"]
    for client in clients
        # Get the demand for the client
        totalDemand += sum(tempData["price_prod_demand_df"][!, client])
        totalDemandInterval += sum(tempData["price_prod_demand_df"][!, client], dims=2)
    end
    absDemandError = 0
    if demandForecastType == "scenarios"
        # Set the forecast as the median of the scenarios
        absDemandError = sum(abs.(median(demandForecast, dims=2) .- totalDemandInterval))
    else
        absDemandError = sum(abs.(demandForecast .- totalDemandInterval))
    end
    println("Total demand: ", totalDemand)
    println("Total demand interval: ", sum(totalDemandInterval))
    println("Absolute demand error: ", absDemandError)
    MAE_Demand = absDemandError / totalDemand

    # Calculate the Mean Absolute Error (MAE) of the PV forecast
    # PV production is scaled according to client PV ownership
    clientPVOwnership = sum(tempData["clientPVOwnership"][c] for c in clients)
    totalPV = sum(tempData["price_prod_demand_df"][!, "SolarMWh"])
    totalPV = totalPV .* clientPVOwnership  # Scale by total PV ownership
    totalPVInterval = sum(tempData["price_prod_demand_df"][!, "SolarMWh"], dims=2)
    totalPVInterval = totalPVInterval .* clientPVOwnership  # Scale by total PV ownership
    # PV forecast is always deterministic
    absPVError = sum(abs.(pvForecast .- totalPVInterval))
    MAE_PV = absPVError / totalPV
    return MAE_Demand, MAE_PV
end


