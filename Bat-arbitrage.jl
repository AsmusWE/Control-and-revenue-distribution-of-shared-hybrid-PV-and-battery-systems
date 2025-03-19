

#************************************************************************
# Food festival
using JuMP
using Gurobi
using Plots
#************************************************************************

#************************************************************************
coalition = [1, 2, 4]
function solve_coalition(coalition)
    # NOTE: Repeating data loading inefficient, change for later implementation
    # Data
    time = range(1,stop=24)
    T = length(time)
    clients = ["A", "B", "C", "D"]
    C = length(clients)
    demand = zeros(Float64, C, T)
    # Dummy demand data
    demand[1, :] = [5, 3, 4, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6, 7, 8, 5, 6]
    demand[2, :] = [6, 4, 5, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7, 8, 9, 6, 7]
    demand[3, :] = [7, 5, 6, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8, 9, 10, 7, 8]
    demand[4, :] = [8, 6, 7, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9, 10, 11, 8, 9]

    # NOTE: Ownership data is not relevant for this code to run alone, important for shapley implementation
    clientPVOwnership = zeros(Float32, C)
    clientPVOwnership = [0.2, 0.3, 0.4, 0.1]
    clientBatteryOwnership = zeros(Float32, C)
    clientBatteryOwnership = [0.1, 0.2, 0.5, 0.2]

    prod = zeros(Float64, T)
    # Dummy production data
    prod = [10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8]*sum(clientPVOwnership[c] for c in coalition)
    P = length(prod)

    λ = zeros(Float64, T)
    λ = [50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300, 50, 150, 100, 200, 250, 300]
    Λ = length(λ)

    #Battery data
        batCap = 50*sum(clientBatteryOwnership[c] for c in coalition)
        chaLim = 10*sum(clientBatteryOwnership[c] for c in coalition)
        disLim = 10*sum(clientBatteryOwnership[c] for c in coalition)
        chaEff = 0.9
        disEff = 0.9
        initSoC = 5

    #Connection data
        gridConn = 50

    #************************************************************************

    #************************************************************************
    # Model

    Bat = Model(Gurobi.Optimizer)

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
                sum(demand[c,t] for c=1:C) + Cha[t] <= prod[t] + Dis[t] + Grid[t])

    # Battery balance constraint
    @constraint(Bat, [t=1:T; t!=1],
                SoC[t-1] + Cha[t] - Dis[t] == SoC[t])
    @constraint(Bat, 
                initSoC + Cha[1] - Dis[1] == SoC[1])

    #************************************************************************

    #************************************************************************
    # Solve
    solution = optimize!(Bat)
    println("Termination status: $(termination_status(Bat))")
    #************************************************************************

    #************************************************************************
    if termination_status(Bat) == MOI.OPTIMAL
        println("Optimal objective value: $(objective_value(Bat))")
        println("solve time = $(solve_time(Bat))")
        

        # Extract the solution values
        soc_values = value.(SoC)

        # Plot the State of Charge (SoC) over time
        plot(time, soc_values, xlabel="Time (hours)", ylabel="State of Charge (SoC)", title="Battery State of Charge Over Time", legend=false)
        savefig("SoC_over_time.png")

        grid_values = value.(Grid)

        # Plot the Grid exchange over time
        plot(time, grid_values, xlabel="Time (hours)", ylabel="Grid Exchange", title="Grid Exchange Over Time", legend=false)
        savefig("Grid_exchange_over_time.png")

    else
        println("No optimal solution available")
    end
    #************************************************************************
