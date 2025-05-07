

#************************************************************************
using JuMP
using HiGHS
using Plots
using Gurobi


#************************************************************************

#************************************************************************
#coalition = [1, 2, 4]
function solve_coalition(coalition, systemData, model = "Simple" ,plotting = false)
    # Data
    #demand = systemData["demand"]

    #pvProduction = systemData["pvProduction"]
    pvProduction = systemData["price_prod_demand_df"][!, :PVProduction]
    T = length(pvProduction)
    C = length(coalition)

    demand = zeros(T, C)
    for (i, client) in enumerate(coalition)
        demand[:,i] = systemData["price_prod_demand_df"][!, client]
    end
    clientPVOwnership = getindex.(Ref(systemData["clientPVOwnership"]), coalition)
    clientBatteryOwnership = getindex.(Ref(systemData["clientBatteryOwnership"]), coalition)
    
    initSoC = systemData["initSoC"]
    batCap = systemData["batCap"]
    #priceImp = systemData["priceImp"]
    #priceExp = systemData["priceExp"]
    priceImp = systemData["price_prod_demand_df"][!, :PriceImp]
    priceExp = systemData["price_prod_demand_df"][!, :PriceExp]

    C_Rate = 0.5
    chaEff = 0.95
    disEff = 0.95

    #time = range(1,stop=24)

    coalition_indexes = range(1, stop=C)
    
    prod = pvProduction*sum(clientPVOwnership[c] for c in coalition_indexes)

    #Battery data
        batCap = batCap*sum(clientBatteryOwnership[c] for c in coalition_indexes)
        chaLim = batCap*C_Rate
        disLim = batCap*C_Rate
        initSoC = initSoC*sum(clientBatteryOwnership[c] for c in coalition_indexes)

    #Connection data
    # Inverter size assumed owned according to PV ownership to preserve super-additivity
        gridConn = 11.3*sum(clientPVOwnership[c] for c in coalition_indexes) #MW
    #************************************************************************

    #************************************************************************
    # Model

    Bat = Model(HiGHS.Optimizer)
    #Bat = Model(Gurobi.Optimizer)
    set_silent(Bat)
    #set_optimizer_attribute(Bat, "OutputFlag", 0)

    # Charging rate
    if model == "Simple"
        @variable(Bat, 0<=Cha[1:T]<=chaLim)
    else
        @variable(Bat, 0<=Cha[1:T,c in coalition_indexes])
    end

    # Discharging rate
    if model == "Simple"
        @variable(Bat, 0<=Dis[1:T]<=disLim)
    else
        @variable(Bat, 0<=Dis[1:T,c in coalition_indexes])
    end

    # State of charge at end of period
    @variable(Bat, 0<=SoC[1:T]<=batCap)

    ## Grid exchange, positive is import
    #@variable(Bat, -gridConn<=Grid[1:T]<=gridConn)

    # Grid import
    if model == "Simple"
        @variable(Bat, 0<=GridImp[1:T])
    else
        @variable(Bat, 0<=GridImp[1:T,c in coalition_indexes])
    end

    # Grid export
    if model == "Simple"
        @variable(Bat, 0<=GridExp[1:T])
    else
        @variable(Bat, 0<=GridExp[1:T,c in coalition_indexes])
    end

    # Assigned production
    if model == "Simple"
        @variable(Bat, 0<=prodGiven[1:T])
        for t in 1:T
            @constraint(Bat, prodGiven[t] <= prod[t])
        end
    else
        @variable(Bat, 0<=prodGiven[1:T,c in coalition_indexes])
    end

    # objective
    if model == "Simple"
        @objective(Bat, Max, sum(priceExp[t]*GridExp[t]-priceImp[t]*GridImp[t] for t=1:T))
    else
        @objective(Bat, Max, sum(priceExp[t]*GridExp[t,c]-priceImp[t]*GridImp[t,c] for t=1:T, c in coalition_indexes))
    end
    
    # Power balance constraint
    if model == "Simple"
        @constraint(Bat, powerBal[t=1:T],
                    sum(demand[t,c] for c=coalition_indexes) + Cha[t] + GridExp[t] == prodGiven[t] + Dis[t] + GridImp[t])
    else
        @constraint(Bat, powerBal[t=1:T,c in coalition_indexes],
                    demand[t,c] + Cha[t,c] + GridExp[t,c] == prodGiven[t,c] + Dis[t,c] + GridImp[t,c])
    end

    # Battery balance constraint
    if model == "Simple"
        @constraint(Bat, [t=1:T; t!=1],
                    SoC[t-1] + Cha[t]*chaEff - Dis[t]/disEff == SoC[t])
        @constraint(Bat, 
                    initSoC + Cha[1]*chaEff - Dis[1]/disEff == SoC[1])
    else
        @constraint(Bat, [t=1:T; t!=1],
                    SoC[t-1] + sum(Cha[t,c] for c in coalition_indexes)*chaEff - sum(Dis[t,c] for c in coalition_indexes)/disEff == SoC[t])
        @constraint(Bat, 
                    initSoC + sum(Cha[1,c] for c in coalition_indexes)*chaEff - sum(Dis[1,c] for c in coalition_indexes)/disEff == SoC[1])
    end

    # Grid Connection modelling
    if model == "Simple"
        @constraint(Bat, [t=1:T],
                    prodGiven[t]+Dis[t]-Cha[t] <= gridConn)
    else
        @constraint(Bat, [t=1:T], 
                    sum(prodGiven[t, c] + Dis[t, c] - Cha[t, c] for c in coalition_indexes) <= gridConn)
    end

    # Collective limits 
    if model != "Simple"
        @constraint(Bat, [t=1:T], sum(Cha[t,c] for c in coalition_indexes) <= chaLim)
        @constraint(Bat, [t=1:T], sum(Dis[t,c] for c in coalition_indexes) <= disLim)
        @constraint(Bat, [t=1:T], sum(prodGiven[t,c] for c in coalition_indexes) <= prod[t])
    end
    #************************************************************************

    #************************************************************************
    # Solve
    solution = optimize!(Bat)
    #println("Termination status: $(termination_status(Bat))")
    #************************************************************************

    #************************************************************************
    if termination_status(Bat) == MOI.OPTIMAL
        #println("Optimal objective value: $(objective_value(Bat))")
        #println("solve time = $(solve_time(Bat))")
        

        # Extract the solution values
        soc_values = value.(SoC)

        if plotting
            # Plot the State of Charge (SoC) over time
            plot(time, soc_values, xlabel="Time (hours)", ylabel="State of Charge (SoC)", title="Battery State of Charge Over Time", legend=false)
            savefig("SoC_over_time.png")

            grid_values = value.(Grid)

            # Plot the Grid exchange over time
            plot(time, grid_values, xlabel="Time (hours)", ylabel="Grid Exchange", title="Grid Exchange Over Time", legend=false)
            savefig("Grid_exchange_over_time.png")
        end
        if model == "Simple"
            return objective_value(Bat), sum(value.(GridImp))
        else
            client_import_util = Dict(c => sum(value(GridImp[t, c]) * priceImp[t] for t=1:T) for c in coalition_indexes)
            client_export_util = Dict(c => sum(value(GridExp[t, c]) * priceExp[t] for t=1:T) for c in coalition_indexes)    
            return [objective_value(Bat), client_import_util, client_export_util]    
        end

    else
        println("No optimal solution available")
    end
    #************************************************************************
end