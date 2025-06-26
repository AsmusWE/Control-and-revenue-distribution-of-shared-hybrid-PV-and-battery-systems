include("Plotting.jl")
include("Game_theoretic_functions.jl")
using DataFrames, CSV, Dates


struct PlotData
    allocations::Vector{String}
    systemData::Dict{String, Any}
    allocation_costs::Dict{String, Any}
    imbalances::Dict{Any, Any}
    clients::Vector{String}
    start_hour::DateTime
    sim_days::Int
    daily_cost_MWh_imbalance::Any
end
plot_data_all_noise = deserialize("plot_data_all_noise.jls")
plot_data_all_scenarios = deserialize("plot_data_all_scen.jls")
plot_data_nuc_noise = deserialize("plot_data_nuc_noise.jls")
plot_data_nuc_scenarios = deserialize("plot_data_nuc_scen.jls")
structs = [
    ("All, Noise", plot_data_all_noise),
    ("All, Scenario", plot_data_all_scenarios),
    ("Nucleolus, Noise", plot_data_nuc_noise),
    ("Nucleolus, Scenario", plot_data_nuc_scenarios)
]

save_rel_imbal(plot_data_all_noise, plot_data_all_scenarios, plot_data_nuc_noise, plot_data_nuc_scenarios)

excessDF = DataFrame()
for (scenario,structure) in structs
    for alloc in structure.allocations
        max_instability = check_stability(structure.allocation_costs[alloc], structure.imbalances, structure.clients)
        push!(excessDF, (
        Scenario = scenario,
        Allocation = alloc,
        MaxInstability = max_instability)
        )
    end
end

CSV.write("Results/excess_data.csv", excessDF)



