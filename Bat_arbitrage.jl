

#************************************************************************
using JuMP
using HiGHS
using Plots


#************************************************************************

#************************************************************************
#coalition = [1, 2, 4]
function solve_coalition(coalition, systemData, model = "Simple" ,plotting = false, vcg_player = nothing)
    # Data
    demand = systemData["demand"]
    clientPVOwnership = systemData["clientPVOwnership"]
    clientBatteryOwnership = systemData["clientBatteryOwnership"]
    pvProduction = systemData["pvProduction"]
    initSoC = systemData["initSoC"]
    batCap = systemData["batCap"]
    priceImp = systemData["priceImp"]
    priceExp = systemData["priceExp"]
    C_Rate = 0.5
    chaEff = 0.95
    disEff = 0.95

    time = range(1,stop=24)
    T = length(time)
    
    prod = pvProduction*sum(clientPVOwnership[c] for c in coalition)

    #Battery data
        batCap = batCap*sum(clientBatteryOwnership[c] for c in coalition)
        chaLim = batCap*C_Rate
        disLim = batCap*C_Rate
        initSoC = initSoC*sum(clientBatteryOwnership[c] for c in coalition)

    #Connection data
        gridConn = 1000000000

    #************************************************************************

    #************************************************************************
    # Model

    Bat = Model(HiGHS.Optimizer)

    set_silent(Bat)
    #set_optimizer_attribute(Bat, "OutputFlag", 0)

    # Removing demand of VCG player from the demand matrix
    if model != "Simple" && vcg_player !== nothing
        demand[vcg_player, :] .= 0
    end

    # Charging rate
    if model == "Simple"
        @variable(Bat, 0<=Cha[1:T]<=chaLim)
    else
        @variable(Bat, 0<=Cha[1:T,c in coalition])
    end

    # Discharging rate
    if model == "Simple"
        @variable(Bat, 0<=Dis[1:T]<=disLim)
    else
        @variable(Bat, 0<=Dis[1:T,c in coalition])
    end

    # State of charge at end of period
    @variable(Bat, 0<=SoC[1:T]<=batCap)

    ## Grid exchange, positive is import
    #@variable(Bat, -gridConn<=Grid[1:T]<=gridConn)

    # Grid import
    if model == "Simple"
        @variable(Bat, 0<=GridImp[1:T]<=gridConn)
    else
        @variable(Bat, 0<=GridImp[1:T,c in coalition])
    end

    # Grid export
    if model == "Simple"
        @variable(Bat, 0<=GridExp[1:T]<=gridConn)
    else
        @variable(Bat, 0<=GridExp[1:T,c in coalition])
    end

    # Assigned production
    if model != "Simple"
        @variable(Bat, 0<=prodGiven[1:T,c in coalition])
    end

    if model == "Simple"
        @objective(Bat, Max, sum(priceExp[t]*GridExp[t]-priceImp[t]*GridImp[t] for t=1:T))
    elseif vcg_player !== nothing
        @objective(Bat, Max, sum(priceExp[t]*GridExp[t,c]-priceImp[t]*GridImp[t,c] for t=1:T, c in coalition if c!=vcg_player))
    else
        @objective(Bat, Max, sum(priceExp[t]*GridExp[t,c]-priceImp[t]*GridImp[t,c] for t=1:T, c in coalition))
    end

    # LIMITING IMPORT OF IGNORED PLAYER, ENSURE THAT THIS IS CORRECT
    if model != "Simple" && vcg_player !== nothing
        @constraint(Bat, [t=1:T],
                    GridImp[t,vcg_player]<=demand[vcg_player,t])
    end
    # Power balance constraint
    if model == "Simple"
        @constraint(Bat, powerBal[t=1:T],
                    sum(demand[c,t] for c=coalition) + Cha[t] + GridExp[t] <= prod[t] + Dis[t] + GridImp[t])
    else
        @constraint(Bat, powerBal[t=1:T,c in coalition],
                    demand[c,t] + Cha[t,c] + GridExp[t,c] <= prodGiven[t,c] + Dis[t,c] + GridImp[t,c])
    end

    # Battery balance constraint
    if model == "Simple"
        @constraint(Bat, [t=1:T; t!=1],
                    SoC[t-1] + Cha[t]*chaEff - Dis[t]/disEff == SoC[t])
        @constraint(Bat, 
                    initSoC + Cha[1]*chaEff - Dis[1]/disEff == SoC[1])
    else
        @constraint(Bat, [t=1:T; t!=1],
                    SoC[t-1] + sum(Cha[t,c] for c in coalition)*chaEff - sum(Dis[t,c] for c in coalition)/disEff == SoC[t])
        @constraint(Bat, 
                    initSoC + sum(Cha[1,c] for c in coalition)*chaEff - sum(Dis[1,c] for c in coalition)/disEff == SoC[1])
    end

    # Collective limits 
    if model != "Simple"
        @constraint(Bat, [t=1:T], sum(Cha[t,c] for c in coalition) <= chaLim)
        @constraint(Bat, [t=1:T], sum(Dis[t,c] for c in coalition) <= disLim)
        @constraint(Bat, [t=1:T], sum(GridImp[t,c] for c in coalition) <= gridConn)
        @constraint(Bat, [t=1:T], sum(GridExp[t,c] for c in coalition) <= gridConn)
        @constraint(Bat, [t=1:T], sum(prodGiven[t,c] for c in coalition) <= prod[t])
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
            return objective_value(Bat)
        else
            client_import_util = Dict(c => sum(value(GridImp[t, c]) * priceImp[t] for t=1:T) for c in coalition)
            client_export_util = Dict(c => sum(value(GridExp[t, c]) * priceExp[t] for t=1:T) for c in coalition)    
            return [objective_value(Bat), client_import_util, client_export_util]    
        end

    else
        println("No optimal solution available")
    end
    #************************************************************************
end