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

function calculate_imbalance(systemData, clients)
    coalitions = collect(combinations(clients))
    bids = calculate_bids(coalitions, systemData)
    demand_sum = Dict()
    scaled_pvProd = Dict()
    imbalance = Dict()
    for coalition in coalitions
        demand_sum[coalition] = sum(systemData["price_prod_demand_df"][!, i] for i in coalition)
        scaled_pvProd[coalition] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* sum(systemData["clientPVOwnership"][i] for i in coalition)
        imbalance[coalition]= daily_imbalance(bids[coalition], scaled_pvProd[coalition], demand_sum[coalition])
    end
    
    # Calculate the total imbalance for each coalition
    imbalance_cost = Dict()
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    for coalition in coalitions
        #print("Coalition imbalance: ", coalition, " = ", sum(imbalance[coalition]), "\n")
        positive_imbalance = sum(imbalance[coalition][imbalance[coalition] .> 0])
        negative_imbalance = sum(imbalance[coalition][imbalance[coalition] .< 0])
        imbalance_cost[coalition] = positive_imbalance * downreg_price + abs(negative_imbalance) * upreg_price
    end
    # Imbalance is by hour, with sign and without cost include
    return imbalance_cost, bids, imbalance
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
    # This function calculates the imbalance for a given period
    # It returns the imbalance for the given period
    # The period is given in hours
    start_hour = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
    if threads
        # Initialize thread-specific dictionaries to avoid concurrent writes
        thread_local_imbalances = Dict(tid => Dict() for tid in 1:Threads.nthreads())
        thread_local_hourly_imbalance = Dict(tid => Dict() for tid in 1:Threads.nthreads())
        thread_local_bids = Dict(tid => Dict() for tid in 1:Threads.nthreads())

        Threads.@threads for day in 1:days
            if printing
                println("Calculating imbalances for day ", day, " of ", days)
            end
            tid = Threads.threadid()
            dayData = deepcopy(systemData)
            day_start = start_hour + (day - 1) * 24
            day_end = day_start + 23
            dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][day_start:day_end, :]
            daily_imbalance_cost, bids, hourly_imbalance = calculate_imbalance(dayData, clients)
            
            # Store daily imbalances in the thread-specific dictionary
            for (coalition, imbalance) in daily_imbalance_cost
                if haskey(thread_local_imbalances[tid], coalition)
                    thread_local_imbalances[tid][coalition] += imbalance
                else
                    thread_local_imbalances[tid][coalition] = imbalance
                    # Initialize the hourly imbalance and bids for this coalition
                    thread_local_hourly_imbalance[tid][coalition] = zeros(days*24)
                    thread_local_bids[tid][coalition] = zeros(days*24)
                end
                # Store the hourly imbalance and bids for this coalition
                thread_local_hourly_imbalance[tid][coalition][(day-1)*24+1:day*24] = hourly_imbalance[coalition]
                thread_local_bids[tid][coalition][(day-1)*24+1:day*24] = bids[coalition]
            end
        end

        # Merge thread-specific dictionaries into a single dictionary
        period_imbalances = Dict()
        period_hourly_imbalance = Dict()
        period_bids = Dict()

        for thread_dict in values(thread_local_imbalances)
            for (coalition, imbalance) in thread_dict
                if haskey(period_imbalances, coalition)
                    period_imbalances[coalition] += imbalance
                else
                    period_imbalances[coalition] = imbalance
                end
            end
        end

        for thread_dict in values(thread_local_hourly_imbalance)
            for (coalition, hourly_imbalance) in thread_dict
                if !haskey(period_hourly_imbalance, coalition)
                    period_hourly_imbalance[coalition] = zeros(days*24)
                end    
                period_hourly_imbalance[coalition] += hourly_imbalance   
            end
        end

        # Merge bids from all threads
        for thread_dict in values(thread_local_bids)
            for (coalition, bid) in thread_dict
                if !haskey(period_bids, coalition)
                    period_bids[coalition] = zeros(days*24)
                end    
                period_bids[coalition] += bid   
            end
        end
    else
        # If not using threads, calculate imbalances in a single loop
        period_imbalances = Dict()
        period_hourly_imbalance = Dict()
        period_bids = Dict()
        # Initialize dictionaries to hold results
        for coalition in collect(combinations(clients))
            period_imbalances[coalition] = 0.0
            period_hourly_imbalance[coalition] = zeros(days*24)
            period_bids[coalition] = zeros(days*24)
        end

        for day in 1:days
            if printing
                println("Calculating imbalances for day ", day, " of ", days)
            end
            day_start = start_hour + (day - 1) * 24
            day_end = day_start + 23
            dayData = deepcopy(systemData)
            dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][day_start:day_end, :]
            daily_imbalance_cost, bids, hourly_imbalance = calculate_imbalance(dayData, clients)

            for (coalition, imbalance) in daily_imbalance_cost
                period_hourly_imbalance[coalition][(day-1)*24+1:day*24] = hourly_imbalance[coalition]
                period_bids[coalition][(day-1)*24+1:day*24] = bids[coalition]
                period_imbalances[coalition] += imbalance
            end
        end
    end
    return period_imbalances, period_hourly_imbalance
end