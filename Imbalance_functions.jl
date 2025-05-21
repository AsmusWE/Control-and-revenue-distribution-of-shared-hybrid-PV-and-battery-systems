#************************************************************************
using JuMP
using HiGHS
#using Plots
#using Gurobi


#************************************************************************

function optimize_imbalance(coalition, systemData)
    # Importing data that is always known
    C = length(coalition)
    #initSoC = systemData["initSoC"]
    #batCap = systemData["batCap"]
    #priceImp = systemData["price_prod_demand_df"][!, :PriceImp]
    #priceExp = systemData["price_prod_demand_df"][!, :PriceExp]
    clientPVOwnership = getindex.(Ref(systemData["clientPVOwnership"]), coalition)
    #clientBatteryOwnership = getindex.(Ref(systemData["clientBatteryOwnership"]), coalition)


    TimeHorizon = 24 # Hours of forecast used
    demand = sum(systemData["demand_scenarios"][c] for c in coalition)

    #demand = demand.+5/C

    T = min(TimeHorizon,size(systemData["price_prod_demand_df"])[1]) # Hours of forecast used
    
    S = length(demand[1,:]) # Number of scenarios
    prob = 1/S # Probability of each scenario
    #systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][1:T, :]
    #pvForecast = systemData["price_prod_demand_df"][!, :ForecastCurrent]
    #demand = zeros(T, C, S)
    #for (i, client) in enumerate(coalition)
    #    forecast_column_name = Symbol("Forecast_", client)
    #    demand[:,i,1] = systemData["price_prod_demand_df"][!, forecast_column_name]
    #end
    pvProduction = systemData["price_prod_demand_df"][!, :PVForecast]
    #coalition_indexes = 1:C
    prod = pvProduction.*sum(clientPVOwnership)
    upreg_price = systemData["upreg_price"]
    downreg_price = systemData["downreg_price"]
    #C_Rate = 0.5
    #chaEff = 0.95
    #disEff = 0.95

    #Battery data
    #batCap = batCap*sum(clientBatteryOwnership)
    #chaLim = batCap*C_Rate
    #disLim = batCap*C_Rate
    #initSoC = initSoC*sum(clientBatteryOwnership[c] for c in coalition_indexes)

    #Connection data
    # Inverter size assumed owned according to PV ownership to preserve super-additivity
    #gridConn = 11.3*sum(clientPVOwnership[c] for c in coalition_indexes) #MW
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
    # Multiplying imbalance with regulation prices
    imbalance = imbalance .* ifelse.(imbalance .< 0, systemData["upreg_price"], systemData["downreg_price"])
    # Calculate the signs of the imbalances
    signs = imbalance .>= 0
    return imbalance, signs
end

function calculate_imbalance(systemData, clients)
    coalitions = collect(combinations(clients))
    bids = calculate_bids(coalitions, systemData)
    demand_sum = Dict()
    scaled_pvProd = Dict()
    imbalance = Dict()
    signs = Dict()
    for coalition in coalitions
        demand_sum[coalition] = sum(systemData["price_prod_demand_df"][!, i] for i in coalition)
        scaled_pvProd[coalition] = systemData["price_prod_demand_df"][!, "SolarMWh"] .* sum(systemData["clientPVOwnership"][i] for i in coalition)
        imbalance[coalition], signs[coalition] = daily_imbalance(bids[coalition], scaled_pvProd[coalition], demand_sum[coalition])
    end
    
    # Calculate the total imbalance for each coalition
    total_imbalance = Dict()
    for coalition in coalitions
        #print("Coalition imbalance: ", coalition, " = ", sum(imbalance[coalition]), "\n")
        total_imbalance[coalition] = sum(abs.(imbalance[coalition]))
    end

    return total_imbalance, bids, imbalance
end

function calculate_bids(coalitions, systemData)
    # This function calculates the bids for each coalition combination
    bids = Dict()
    # A different dictionary is initialized for each thread to avoid
    # simultaneous writes to the same dictionary
    #thread_local_bids = Dict(tid => Dict() for tid in 1:Threads.nthreads())
    #Threads.@threads for clients in coalitions
    #    thread_local_bids[Threads.threadid()][clients] = optimize_imbalance(clients, systemData)
    #end
    #for thread_dict in values(thread_local_bids)
    #    merge!(bids, thread_dict)
    #end

    # Instead of explicitly calculating each coalition's bids, we can combine the individual bids
    # Calculate bids for each single client
    for client in coalitions
        if length(client) == 1
            #println("Calculating bids for client: ", client)
            #println(sum(systemData["demand_scenarios"][c] for c in client))
            bids[client] = optimize_imbalance(client, systemData)
        end
    end

    # Calculate bids for each coalition by summing the bids of its members
    for coalition in coalitions
        bids[coalition] = sum(bids[[client]] for client in coalition)
    end
    return bids
end

function period_imbalance(systemData, clients, startDay, days)
    # This function calculates the imbalance for a given period
    # It returns the imbalance for the given period
    # The period is given in hours
    start_hour = findfirst(x -> x >= startDay, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])

    # Initialize thread-specific dictionaries to avoid concurrent writes
    thread_local_imbalances = Dict(tid => Dict() for tid in 1:Threads.nthreads())
    thread_local_hourly_imbalance = Dict(tid => Dict() for tid in 1:Threads.nthreads())
    
    Threads.@threads for day in 1:days
        println("Calculating imbalances for day ", day, " of ", days)
        tid = Threads.threadid()
        dayData = deepcopy(systemData)
        day_start = start_hour + (day - 1) * 24
        day_end = day_start + 23
        dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][day_start:day_end, :]
        daily_imbalances, bids, hourly_imbalance = calculate_imbalance(dayData, clients)
        
        # Store daily imbalances in the thread-specific dictionary
        for (coalition, imbalance) in daily_imbalances
            if haskey(thread_local_imbalances[tid], coalition)
                thread_local_imbalances[tid][coalition] += imbalance

            else
                thread_local_imbalances[tid][coalition] = imbalance
                # Initialize the hourly imbalance and signs for this coalition
                thread_local_hourly_imbalance[tid][coalition] = zeros(days*24)
            end
            # Store the hourly imbalance and signs for this coalition
            thread_local_hourly_imbalance[tid][coalition][(day-1)*24+1:day*24] = hourly_imbalance[coalition]
        end
    end

    # Merge thread-specific dictionaries into a single dictionary
    period_imbalances = Dict()
    period_hourly_imbalance = Dict()

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

    return period_imbalances, period_hourly_imbalance
end