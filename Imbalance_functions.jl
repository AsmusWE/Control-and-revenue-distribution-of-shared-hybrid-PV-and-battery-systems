#************************************************************************
using JuMP
using HiGHS
#using Plots
#using Gurobi


#************************************************************************

function optimize_imbalance(coalition, systemData)
    # Importing data that is always known
    clientPVOwnership = getindex.(Ref(systemData["clientPVOwnership"]), coalition)
    #clientBatteryOwnership = getindex.(Ref(systemData["clientBatteryOwnership"]), coalition)
    TimeHorizon = 24 # Hours optimized
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

    T = min(TimeHorizon,size(systemData["price_prod_demand_df"])[1]) # Hours of forecast used
    
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
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]

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

    @objective(model, Min, prob * sum((downreg_price*pos_imbal[t, s] + upreg_price*neg_imbal[t, s]) for t in 1:T for s in 1:S)) # Objective function

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

function daily_imbalance(bids, pvProd, demand)
    pvProd = pvProd[1:length(bids)] # Ensure pvProd is the same length as bids
    demand = demand[1:length(bids)] # Ensure demand is the same length as bids
    imbalance = bids + pvProd - demand
    return imbalance
end

# Structs for coalition results and period results
struct CoalitionResults
    demand_sum::Vector{Float64}
    scaled_pvProd::Vector{Float64}
    imbalance::Vector{Float64}
    imbalance_cost::Float64
    bids::Vector{Float64}
end

struct PeriodResults
    imbalances::Vector{Float64}
    hourly_imbalance::Matrix{Float64}
end

function calculate_imbalance(systemData, clients)
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    bids_dict = calculate_bids(coalitions, systemData)
    demand_sum_vec = Vector{Vector{Float64}}(undef, n_coalitions)
    scaled_pvProd_vec = Vector{Vector{Float64}}(undef, n_coalitions)
    imbalance_vec = Vector{Vector{Float64}}(undef, n_coalitions)
    imbalance_cost_vec = Vector{Float64}(undef, n_coalitions)
    for (i, coalition) in enumerate(coalitions)
        demand_sum_vec[i] = sum(systemData["price_prod_demand_df"][!, c] for c in coalition)
        scaled_pvProd_vec[i] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* sum(systemData["clientPVOwnership"][c] for c in coalition)
        imbalance_vec[i] = daily_imbalance(bids_dict[coalition], scaled_pvProd_vec[i], demand_sum_vec[i])
    end
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    for (i, _) in enumerate(coalitions)
        positive_imbalance = sum(imbalance_vec[i][imbalance_vec[i] .> 0])
        negative_imbalance = sum(imbalance_vec[i][imbalance_vec[i] .< 0])
        imbalance_cost_vec[i] = positive_imbalance * downreg_price + abs(negative_imbalance) * upreg_price
    end
    results = [CoalitionResults(demand_sum_vec[i], scaled_pvProd_vec[i], imbalance_vec[i], imbalance_cost_vec[i], bids_dict[coalitions[i]]) for i in 1:n_coalitions]
    return results, coalitions
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

function period_imbalance(systemData, clients, startDay, days; threads=true, printing=true)
    # Calculate the starting hour index
    start_hour = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
    coalitions = collect(combinations(clients))
    n_coalitions = length(coalitions)
    hours = days * 24
    period_imbalances = zeros(n_coalitions)
    period_hourly_imbalance = zeros(n_coalitions, hours)
    if threads
        thread_local_imbalances = [zeros(n_coalitions) for _ in 1:Threads.nthreads()]
        thread_local_hourly_imbalance = [zeros(n_coalitions, hours) for _ in 1:Threads.nthreads()]
        Threads.@threads for day in 1:days
            if printing
                println("Calculating imbalances for day ", day, " of ", days)
            end
            tid = Threads.threadid()
            day_start = start_hour + (day - 1) * 24
            day_end = day_start + 23
            dayData = deepcopy(systemData)
            dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][day_start:day_end, :]
            results, _ = calculate_imbalance(dayData, clients)
            for (i, res) in enumerate(results)
                thread_local_hourly_imbalance[tid][i, (day-1)*24+1:day*24] = res.imbalance
                thread_local_imbalances[tid][i] += res.imbalance_cost
            end
        end
        for tid in 1:Threads.nthreads()
            period_imbalances += thread_local_imbalances[tid]
            period_hourly_imbalance += thread_local_hourly_imbalance[tid]
        end
    else
        for day in 1:days
            if printing
                println("Calculating imbalances for day ", day, " of ", days)
            end
            day_start = start_hour + (day - 1) * 24
            day_end = day_start + 23
            dayData = deepcopy(systemData)
            dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][day_start:day_end, :]
            results, _ = calculate_imbalance(dayData, clients)
            for (i, res) in enumerate(results)
                period_hourly_imbalance[i, (day-1)*24+1:day*24] = res.imbalance
                period_imbalances[i] += res.imbalance_cost
            end
        end
    end
    
    # Convert period_imbalances and period_hourly_imbalance to dictionaries for easier access 
    # Keys are coalitions
    period_imbalances = Dict(coalitions[i] => period_imbalances[i] for i in 1:n_coalitions)
    period_hourly_imbalance = Dict(coalitions[i] => period_hourly_imbalance[i, :] for i in 1:n_coalitions)

    return period_imbalances, period_hourly_imbalance
end

