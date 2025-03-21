

#************************************************************************
using JuMP
using HiGHS
using Plots


#************************************************************************

#************************************************************************
#coalition = [1, 2, 4]
function solve_coalition(coalition, demand, clientPVOwnership, clientBatteryOwnership, pvProduction, initSoC, batCap, plotting = false)
    # Data
    time = range(1,stop=24)
    T = length(time)
    
    prod = pvProduction*sum(clientPVOwnership[c] for c in coalition)

    priceImp = zeros(Float64, T)
    priceImp = [50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300]
    priceExp = 0.5*priceImp

    #Battery data
        batCap = batCap*sum(clientBatteryOwnership[c] for c in coalition)
        C_Rate = 0.5
        chaLim = batCap*C_Rate
        disLim = batCap*C_Rate
        initSoC = initSoC*sum(clientBatteryOwnership[c] for c in coalition)
        chaEff = 0.95
        disEff = 0.95

    #Connection data
        gridConn = 1000000000

    #************************************************************************

    #************************************************************************
    # Model

    Bat = Model(HiGHS.Optimizer)

    set_silent(Bat)
    #set_optimizer_attribute(Bat, "OutputFlag", 0)

    # Charging rate
    @variable(Bat, 0<=Cha[1:T]<=chaLim, )

    # Discharging rate
    @variable(Bat, 0<=Dis[1:T]<=disLim)

    # State of charge at end of period
    @variable(Bat, 0<=SoC[1:T]<=batCap)

    ## Grid exchange, positive is import
    #@variable(Bat, -gridConn<=Grid[1:T]<=gridConn)

    # Grid import
    @variable(Bat, 0<=GridImp[1:T]<=gridConn)

    # Grid export
    @variable(Bat, 0<=GridExp[1:T]<=gridConn)

    @objective(Bat, Min, sum(priceImp[t]*GridImp[t]-priceExp[t]*GridExp[t] for t=1:T))

    # Power balance constraint
    @constraint(Bat, [t=1:T],
                sum(demand[c,t] for c=coalition) + Cha[t] + GridExp[t] <= prod[t] + Dis[t] + GridImp[t])

    # Battery balance constraint
    @constraint(Bat, [t=1:T; t!=1],
                SoC[t-1] + Cha[t]*chaEff - Dis[t]/disEff == SoC[t])
    @constraint(Bat, 
                initSoC + Cha[1]*chaEff - Dis[1]/disEff == SoC[1])

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
        return objective_value(Bat)

    else
        println("No optimal solution available")
    end
    #************************************************************************
end
