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
    weekday = dayofweek(first_hour)  # 1=Monday, 7=Sunday
    
    if systemData["demand_forecast"] == "perfect"
        # Demand forecast is perfect, use actual demand data
        demand = sum(systemData["price_prod_demand_df"][1:TimeHorizon, client] for client in coalition)
    elseif systemData["demand_forecast"] == "scenarios"
        # Demand forecast is not perfect, use forecast data
        demand = sum(systemData["demand_scenarios"][c,weekday] for c in coalition)
    elseif systemData["demand_forecast"] == "noise"
        # Forecast is set as the actual demand with added noise
        demand = sum(systemData["price_prod_demand_df"][1:TimeHorizon, client] for client in coalition) .* (1 .+ 0.1*randn(TimeHorizon, 1))
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
        pvProduction = systemData["price_prod_demand_df"][1:T, :SolarMWh] .* (1 .+ 0.1 * randn(T, 1))
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

struct PeriodResults
    interval_imbalance::Matrix{Float64}
end

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

function period_imbalance(systemData, clients, startDay, days; printing=true)
    # Calculate the starting interval index
    start_interval = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    intervals_per_day = 96 # 15-min intervals per day
    intervals = days * intervals_per_day
    period_interval_imbalance = zeros(n_coalitions, intervals)
    for day in 1:days
        if printing
            println("Calculating imbalances for day ", day, " of ", days)
        end
        day_start = start_interval + (day - 1) * intervals_per_day
        day_end = day_start + intervals_per_day - 1
        dayData = deepcopy(systemData)
        dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][day_start:day_end, :]
        results = calculate_imbalance(dayData, clients)
        for (i, res) in enumerate(results)
            # Calculate hourly imbalance for this coalition
            hourly_imbalance = get_imbalance(res.bids, res.scaled_pvProd, res.demand_sum)
            period_interval_imbalance[i, (day-1)*intervals_per_day+1:day*intervals_per_day] = hourly_imbalance
        end
    end
    
    # Convert period_interval_imbalance to dictionary for easier access 
    # Keys are coalitions
    # period_interval_imbalance = Dict(coalitions[i] => period_interval_imbalance[i, :] for i in 1:n_coalitions)

    return coalitions, period_interval_imbalance
end


function calculate_CVaR(systemData, clients, startDay, days; alpha=0.05, threads=false, printing=false)
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
    coalitions = collect(combinations(clients))
    # Calculating the imbalances
    results = calculate_imbalance(tempData, clients)
    period_interval_imbalance = zeros(length(coalitions), intervals) # Initialize the imbalance matrix
    for (i, res) in enumerate(results)
        # Calculate hourly imbalance for this coalition
        hourly_imbalance = get_imbalance(res.bids, res.scaled_pvProd, res.demand_sum)
        period_interval_imbalance[i, :] = hourly_imbalance
    end
    
    imbalance_spread = tempData["price_prod_demand_df"][!, "ImbalanceSpreadEUR"]  # Get the imbalance spread from the DataFrame
    # Calculate the CVaR for each coalition
    cvar_array = zeros(length(coalitions))
    for (i, coalition) in enumerate(coalitions)
        imbalances = period_interval_imbalance[i, :] .* imbalance_spread  # Find the cost of the imbalances for this coalition
        sorted_imbalances = sort(imbalances, rev=true)  # Sort in descending order (highest first)
        n = length(sorted_imbalances)
        index = ceil(Int, n * alpha)  # Index for CVaR
        cvar_value = mean(sorted_imbalances[1:index])  # Average of the highest alpha% of imbalances
        cvar_array[i] = cvar_value
    end
    # Convert the CVaR array to a dictionary for easier access
    cvar_dict = Dict{Any, Float64}()
    for (i, coalition) in enumerate(coalitions)
        cvar_dict[coalition] = cvar_array[i]
    end
    return cvar_dict
end


