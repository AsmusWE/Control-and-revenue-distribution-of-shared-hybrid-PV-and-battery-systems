include("Bat_arbitrage.jl")
include("Common_functions.jl")
include("Data_import.jl")


systemData = load_data()
clients = systemData["clients"]
clients = range(1,stop=length(clients))
solve_coalition(clients, systemData)