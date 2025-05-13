#************************************************************************
using JuMP
using HiGHS
using Plots
using Gurobi


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
    
    S = length(demand[1,:]) # Number of scenarios, only one scenario for now
    prob = 1/S # Probability of each scenario
    #systemData["price_prod_demand_df"] = systemData["price_prod_demand_df"][1:T, :]
    #pvForecast = systemData["price_prod_demand_df"][!, :ForecastCurrent]
    #demand = zeros(T, C, S)
    #for (i, client) in enumerate(coalition)
    #    forecast_column_name = Symbol("Forecast_", client)
    #    demand[:,i,1] = systemData["price_prod_demand_df"][!, forecast_column_name]
    #end
    pvProduction = systemData["price_prod_demand_df"][!, :PVForecast]
    coalition_indexes = 1:C
    prod = pvProduction.*sum(clientPVOwnership)

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
    set_silent(model)

    @variable(model, imbal[1:T, 1:S]) # Imbalance amount
    @variable(model, pos_imbal[1:T, 1:S] >= 0) # Positive imbalance
    @variable(model, neg_imbal[1:T, 1:S] >= 0) # Negative imbalance
    @variable(model, bid[1:T]) # Bid amount

    @objective(model, Min, prob * sum((pos_imbal[t, s] + neg_imbal[t, s]) for t in 1:T for s in 1:S)) # Objective function

    @constraint(model, [t = 1:T, s = 1:S],
                imbal[t, s]+bid[t] == demand[t, s] - prod[t])
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

