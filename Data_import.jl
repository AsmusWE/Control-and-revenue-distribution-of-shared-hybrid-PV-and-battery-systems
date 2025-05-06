using CSV
using DataFrames

function load_data(batCap = 100.0, initSoC = 0.0)
    demand = CSV.read("Data/consumption_data.csv", DataFrame)

    clientPVOwnership = Dict(
        "A" => 0.143, "B" => 0.006, "C" => 0.009, "D" => 0.007, "E" => 0.005, 
        "F" => 0.003, "G" => 0.143, "H" => 0.014, "I" => 0.05, "J" => 0.003, 
        "K" => 0.004, "L" => 0.021, "M" => 0.004, "N" => 0.001, "O" => 0.003, 
        "P" => 0.003, "Q" => 0.028, "R" => 0.002, "S" => 0.041, "T" => 0.002, 
        "U" => 0.007, "V" => 0.002, "W" => 0.001, "X" => 0.001, "Y" => 0.01
    )
    clientBatteryOwnership = clientPVOwnership

    pvProduction = CSV.read("Data/ProductionMunicipalityHour.csv", DataFrame; decimal=',')
    priceData = CSV.read("Data/Elspotprices.csv", DataFrame; decimal=',')

    # Extract specific columns or preprocess as needed
    priceImp = priceData[:, :SpotPriceDKK]
    # Setting negative prices to zero
    priceImp = max.(priceImp, 0)
    # Elafgift virksomhed 0,4 oere/kWh - 4 dkk/mWh
    # Raadighedstarif antaget b-hoej 8,75 oere/kWh - 87,5 dkk/mWh
    priceExp = priceImp .- 4.0 .- 87.5 # Adjust as needed

    clients = keys(clientPVOwnership)

    # Create a new DataFrame that combines prices and PV production
    # Trim the data to match the shortest length
    min_length = minimum([length(priceData[:, :SpotPriceDKK]), length(pvProduction[:, :SolarMWh]), length(demand[:, :A])])
    priceData = priceData[1:min_length, :]
    pvProduction = pvProduction[1:min_length, :]
    demand = demand[1:min_length, :]

    # Rescale PV production to align with plant size 
    plant_size = 14.0 # MW
    old_plant_size = maximum(pvProduction[:, :SolarMWh])
    pvProduction[:, :SolarMWh] .*= plant_size / old_plant_size

    # Create a new DataFrame that combines prices, PV production, and demand
    price_prod_demand_df = DataFrame(
        PriceImp = priceImp[1:min_length],
        PriceExp = priceExp[1:min_length],
        PVProduction = pvProduction[:, :SolarMWh], 
    )
    for client in clients
        price_prod_demand_df[!, Symbol(client)] = demand[:, client]
    end

    missing_data_counts = Dict()
    for client in clients
        missing_data_counts[client] = count(ismissing, demand[:, client])
    end
    clients_without_missing_data = filter(client -> missing_data_counts[client] == 0, clients)
    println("Clients without missing data: ", clients_without_missing_data)

    # Dropping columns with missing values
    #demand = select!(demand, Not([:"C",:"P",:"B",:"M",:"D",:"E",:"R"]))
    

    println("Missing data points for each client:")
    println(missing_data_counts)

    systemData = Dict(
        "demand" => demand,
        "clientPVOwnership" => clientPVOwnership,
        "clientBatteryOwnership" => clientBatteryOwnership,
        "pvProduction" => pvProduction,
        "initSoC" => initSoC,
        "batCap" => batCap,
        "priceImp" => priceImp,
        "priceExp" => priceExp,
        "clients" => clients,
        "price_prod_demand_df" => price_prod_demand_df
    )
    return systemData, clients_without_missing_data
end



    