#************************************************************************
using JuMP
using HiGHS
using Combinatorics
using Dates
using Statistics
#using Plots
#using Gurobi


#************************************************************************

function optimize_imbalance(coalition, systemData)
    # Importing data that is always known
    clientPVOwnership = getindex.(Ref(systemData["clientPVOwnership"]), coalition)
    #intervals_per_day = 96 # 15-min intervals per day
    #TimeHorizon = intervals_per_day
    TimeHorizon = length(systemData["price_prod_demand_df"][!, "HourUTC_datetime"]) # Total number of 15-min intervals in the dataset
    first_hour = systemData["price_prod_demand_df"][1, "HourUTC_datetime"]
    #weekday = dayofweek(first_hour)  # 1=Monday, 7=Sunday
    if systemData["demand_forecast"] == "perfect"
        # Demand forecast is perfect, use actual demand data
        demand = sum(systemData["price_prod_demand_df"][1:TimeHorizon, client] for client in coalition)
    elseif systemData["demand_forecast"] == "scenarios"
        demand = sum(systemData["demand_scenarios"][client] for client in coalition)# Use the scenarios directly
        # Demand forecast is not perfect, use scenario data
        #demand = sum(systemData["demand_scenarios"][c,weekday] for c in coalition)
        # Demand forecast is not perfect, use scenario data
        #intervals_per_day = 96
        #days = ceil(Int, TimeHorizon / intervals_per_day)
        
        # Initialize demand array
        #demand = zeros(TimeHorizon, size(systemData["demand_scenarios"][coalition[1], 1], 2))
        
        #for day in 1:days
        #    # Calculate which weekday this is 
        #    # Converts to 0 indexing, and then back to 1 indexing
        #    current_weekday = mod(weekday -1 + day - 1, 7) + 1
        #    
        #    # Calculate interval range for this day
        #    start_interval = (day - 1) * intervals_per_day + 1
        #    end_interval = min(day * intervals_per_day, TimeHorizon)
        #    actual_intervals = end_interval - start_interval + 1
        #    
        #    # Sum demand scenarios for all clients in coalition for this weekday
        #    day_demand = sum(systemData["demand_scenarios"][c, current_weekday] for c in coalition)
        #    
        #    # Fill the demand array for this day (handle partial days)
        #    demand[start_interval:end_interval, :] = day_demand[1:actual_intervals, :]
        #end
    elseif systemData["demand_forecast"] == "noise"
        # Forecast is set as the actual demand with added noise
        standard_deviation = systemData["demand_noise_std"]
        demand = sum(systemData["price_prod_demand_df"][1:TimeHorizon, client] for client in coalition) .* (1 .+ standard_deviation*randn(TimeHorizon, 1))
    else
        error("Unknown demand forecast type: $(systemData["demand_forecast"])")
    end
    T = min(TimeHorizon,size(systemData["price_prod_demand_df"])[1]) # 15-min intervals of forecast used
    
    S = length(demand[1,:]) # Number of scenarios
    prob = 1/S # Probability of each scenario

    if systemData["pv_forecast"] == "perfect"
        # PV forecast is perfect, use actual PV production data
        pvProduction = systemData["price_prod_demand_df"][1:T, :SolarMWh]
    elseif systemData["pv_forecast"] == "scenarios"
        # PV forecast is not perfect, use forecast data
        pvProduction = systemData["price_prod_demand_df"][1:T, :PVForecast]
    elseif systemData["pv_forecast"] == "noise"
        # Forecast is set as the actual PV production with added noise
        #standard_deviation = systemData["pv_noise_std"]
        #pvProduction = systemData["price_prod_demand_df"][1:T, :SolarMWh] .* (1 .+ standard_deviation * randn(T, 1))
        pvProduction = systemData["pv_forecast_noise"][1:T] # Use the noise forecast directly
    else
        error("Unknown PV forecast type: $(systemData["pv_forecast"])")
    end
    prod = pvProduction.*sum(clientPVOwnership)

    #************************************************************************

    # Initialize the optimization model
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
    pvProd = pvProd[1:length(bids)] # Ensure pvProd is the same length as bids
    demand = demand[1:length(bids)] # Ensure demand is the same length as bids
    imbalance = bids + pvProd - demand
    return imbalance
end

# Structs for coalition results and period results
struct CoalitionResults
    demand_sum::Vector{Float64}
    scaled_pvProd::Vector{Float64}
    bids::Vector{Float64}
end

#struct PeriodResults
#    interval_imbalance::Matrix{Float64}
#end

function calculate_imbalance(systemData, clients)
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    bids_dict = calculate_bids(coalitions, systemData)
    demand_sum_vec = Vector{Vector{Float64}}(undef, n_coalitions)
    scaled_pvProd_vec = Vector{Vector{Float64}}(undef, n_coalitions)
    for (i, coalition) in enumerate(coalitions)
        demand_sum_vec[i] = sum(systemData["price_prod_demand_df"][!, c] for c in coalition)
        scaled_pvProd_vec[i] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* sum(systemData["clientPVOwnership"][c] for c in coalition)
    end
    results = [CoalitionResults(demand_sum_vec[i], scaled_pvProd_vec[i], bids_dict[coalitions[i]]) for i in 1:n_coalitions]
    return results
end

function calculate_bids(coalitions, systemData)
    # This function calculates the bids for each coalition combination
    bids = Dict()

    # Instead of explicitly calculating each coalition's bids, we can combine the individual bids
    # Calculate bids for each single client
    for client in filter(c -> length(c) == 1, coalitions)
        bids[client] = optimize_imbalance(client, systemData)
    end
    # Calculate bids for each coalition by summing the bids of its members
    for coalition in coalitions
        bids[coalition] = sum(bids[[client]] for client in coalition)
    end
    return bids
end

function chunk_imbalance(systemData, clients; printing=false, chunkSize = 14)
    # chunkSize is in days
    # Calculate the starting interval index
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    intervals_per_day = 96 # 15-min intervals per day
    intervals = chunkSize * intervals_per_day
    chunks = ceil(Int, size(systemData["price_prod_demand_df"], 1) / intervals) # Number of chunks (rounded up)
    
    # Initialize the full imbalance matrix
    period_interval_imbalance = zeros(n_coalitions, size(systemData["price_prod_demand_df"], 1)) # Initialize the imbalance matrix
    
    for chunk in 1:chunks
        if printing
            println("Calculating imbalances for chunk ", chunk, " of ", chunks)
        end
        chunkStart = (chunk - 1) * intervals + 1
        chunkLength = min(intervals, size(systemData["price_prod_demand_df"], 1) - chunkStart + 1)
        chunkStartDay = systemData["price_prod_demand_df"][chunkStart, "HourUTC_datetime"]
        chunkDays = div(chunkLength, intervals_per_day)
        chunkData = set_period!(systemData, chunkStartDay, chunkDays)
        
        # Cut demand scenarios to fit the chunk
        if haskey(systemData, "demand_scenarios")
            chunkData["demand_scenarios"] = Dict()
            for (client, scenarios) in systemData["demand_scenarios"]
                # Cut scenarios to match chunk indices
                chunkData["demand_scenarios"][client] = scenarios[chunkStart:chunkStart+chunkLength-1, :]
            end
        end
        
        # Cut PV forecast noise to fit the chunk
        if haskey(systemData, "pv_forecast_noise")
            chunkData["pv_forecast_noise"] = systemData["pv_forecast_noise"][chunkStart:chunkStart+chunkLength-1]
        end
        
        results = calculate_imbalance(chunkData, clients)
        
        # Store imbalances in the appropriate section of the full matrix
        result_start_idx = (chunk - 1) * intervals + 1
        result_end_idx = result_start_idx + chunkLength - 1
        
        for (i, res) in enumerate(results)
            # Calculate hourly imbalance for this coalition
            hourly_imbalance = get_imbalance(res.bids, res.scaled_pvProd, res.demand_sum)
            period_interval_imbalance[i, result_start_idx:result_end_idx] = hourly_imbalance
        end
        GC.gc()  # Force garbage collection to free memory after processing each chunk
    end
    
    # Convert period_interval_imbalance to dictionary for easier access 
    # Keys are coalitions
    # period_interval_imbalance = Dict(coalitions[i] => period_interval_imbalance[i, :] for i in 1:n_coalitions)

    return coalitions, period_interval_imbalance
end


function calculate_CVaR(systemData, clients, startDay, days; alpha=0.05, threads=false, printing=false, chunkSize=14)
    # Calculates the Conditional Value at Risk (CVaR) for each coalition over a specified period
    # The CVaR is the highest values, not the worst, as this is a cost minimization problem
    
    #coalitions,period_interval_imbalance  = period_imbalance(systemData, clients, startDay, days)
    start_interval = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
    intervals_per_day = 96 # 15-min intervals per day
    intervals = days * intervals_per_day
    # Creating a dataframe that only contains the data for the specified days
    tempData = deepcopy(systemData)
    try
        tempData["price_prod_demand_df"] = systemData["price_prod_demand_df"][start_interval:start_interval+intervals-1, :]
    catch e
        if isa(e, BoundsError)
            error("The specified startDay and days exceed the available data range. Max data range for current data is from $(systemData["price_prod_demand_df"][1, "HourUTC_datetime"]) to $(systemData["price_prod_demand_df"][end, "HourUTC_datetime"]).")
        else
            rethrow(e)
        end
    end
    #coalitions = collect(combinations(clients))
    # Calculating the imbalances
    #results = calculate_imbalance(tempData, clients)
    #period_interval_imbalance = zeros(length(coalitions), intervals) # Initialize the imbalance matrix
    #for (i, res) in enumerate(results)
    #    # Calculate hourly imbalance for this coalition
    #    hourly_imbalance = get_imbalance(res.bids, res.scaled_pvProd, res.demand_sum)
    #    period_interval_imbalance[i, :] = hourly_imbalance
    #end
    coalitions, period_interval_imbalance = chunk_imbalance(tempData, clients; printing=printing, chunkSize=chunkSize)
    imbalance_spread = tempData["price_prod_demand_df"][!, "ImbalanceSpreadEUR"]  # Get the imbalance spread from the DataFrame
    # Calculate the CVaR for each coalition
    cvar_array = zeros(length(coalitions))
    n = intervals
    index = ceil(Int, n * alpha)  # Index for VaR

    for (i, coalition) in enumerate(coalitions)
        imbalances = period_interval_imbalance[i, :] .* imbalance_spread  # Find the cost of the imbalances for this coalition
        partialsort!(imbalances, 1:index, rev=true)  # In-place partial sort
        cvar_value = mean(imbalances[1:index])  # Average of the highest alpha% of imbalances
        cvar_array[i] = cvar_value
    end
    # Convert the CVaR array to a dictionary for easier access
    cvar_dict = Dict{Any, Float64}()
    imbalance_dict = Dict{Any, Vector{Float64}}()
    
    # Preallocate the dictionaries to avoid resizing during insertion
    sizehint!(cvar_dict, length(coalitions))
    sizehint!(imbalance_dict, length(coalitions))
    
    # Fill the dictionaries with the CVaR values and the corresponding imbalances
    for (i, coalition) in enumerate(coalitions)
        cvar_dict[coalition] = cvar_array[i]
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

function set_period!(systemData, startDay, days)
    start_interval = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
    intervals_per_day = 96 # 15-min intervals per day
    intervals = days * intervals_per_day
    # Creating a dataframe that only contains the data for the specified days
    tempData = deepcopy(systemData)
    try
        tempData["price_prod_demand_df"] = systemData["price_prod_demand_df"][start_interval:start_interval+intervals-1, :]
    catch e
        if isa(e, BoundsError)
            error("The specified startDay and days exceed the available data range. Max data range for current data is from $(systemData["price_prod_demand_df"][1, "HourUTC_datetime"]) to $(systemData["price_prod_demand_df"][end, "HourUTC_datetime"]).")
        else
            rethrow(e)
        end
    end
    return tempData
end
