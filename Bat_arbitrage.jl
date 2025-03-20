

#************************************************************************
using JuMP
using HiGHS
using Plots


#************************************************************************

#************************************************************************
#coalition = [1, 2, 4]
function solve_coalition(coalition, demand, clientPVOwnership, clientBatteryOwnership, pvProduction, initSoC, plotting = false)
    # Data
    time = range(1,stop=24)
    T = length(time)
    
    prod = pvProduction*sum(clientPVOwnership[c] for c in coalition)

    λ = zeros(Float64, T)
    λ = [50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300]

    #Battery data
        batCap = 50*sum(clientBatteryOwnership[c] for c in coalition)
        chaLim = 10*sum(clientBatteryOwnership[c] for c in coalition)
        disLim = 10*sum(clientBatteryOwnership[c] for c in coalition)
        initSoC = initSoC*sum(clientBatteryOwnership[c] for c in coalition)
        chaEff = 0.9
        disEff = 0.9
        initSoC = 5

    #Connection data
        gridConn = 100

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

    # Grid exchange, positive is import
    @variable(Bat, -gridConn<=Grid[1:T]<=gridConn)

    @objective(Bat, Min, sum(λ[t]*Grid[t] for t=1:T))

    # Power balance constraint
    @constraint(Bat, [t=1:T],
                sum(demand[c,t] for c=coalition) + Cha[t] <= prod[t] + Dis[t] + Grid[t])

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
