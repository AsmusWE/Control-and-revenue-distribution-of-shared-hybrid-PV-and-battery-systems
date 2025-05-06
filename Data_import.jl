using CSV
using DataFrames

function load_data(batCap = 100.0, initSoC = 0.0)
    demand = CSV.read("Data/consumption_data.csv", DataFrame)

    clientPVOwnership = DataFrame(
    Customer = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y"],
    a_ppa_pct = [0.143, 0.006, 0.009, 0.007, 0.005, 0.003, 0.143, 0.014, 0.05, 0.003, 0.004, 0.021, 0.004, 0.001, 0.003, 0.003, 0.028, 0.002, 0.041, 0.002, 0.007, 0.002, 0.001, 0.001, 0.01],
    c_ppa_consumption_pct = [0.17, 0.47, 0.28, 0.33, 1.15, 1.19, 0.33, 0.33, 0.36, 0.57, 0.12, 0.53, 0.33, 0.08, 0.36, 0.38, 0.05, 1.47, 0.50, 0.30, 0.25, 0.67, 0.02, 0.16, 0.34],
    bidding_zone = ["DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1", "DK-DK1"],
    #c_ppa_estimated_yearly_gwh = [2, 0.09, 0.125, 0.1, 0.07, 0.035, 2, 0.2, 0.7, 0.037, 0.056, 0.294, 0.014, 0.042, 0.392, 0.028, 0.574, 0.028, 0.096, 0.028, 0.014, 0.014, 0.14]
)
    clientBatteryOwnership = clientPVOwnership
    pvProduction = CSV.read("Data/ProductionMunicipalityHour.csv", DataFrame; decimal=',')
    priceData = CSV.read("Data/Elspotprices.csv", DataFrame; decimal=',')

    # Extract specific columns or preprocess as needed
    priceImp = priceData[:, :SpotPriceDKK]
    # Elafgift virksomhed 0,4 oere/kWh - 4 dkk/mWh
    # Raadighedstarif antaget b-hoej 8,75 oere/kWh - 87,5 dkk/mWh
    priceExp = priceData[:, :SpotPriceDKK] .+ 4.0 .+ 87.5 # Adjust as needed
    clients = unique(clientPVOwnership[:, :Customer]) # Assuming a ClientID column exists

    # Create a new DataFrame that combines prices and PV production
    # Trim the data to match the shortest length
    min_length = minimum([length(priceData[:, :SpotPriceDKK]), length(pvProduction[:, :SolarMWh]), length(demand[:, :A])])
    priceData = priceData[1:min_length, :]
    pvProduction = pvProduction[1:min_length, :]
    demand = demand[1:min_length, :]

    # Create a new DataFrame that combines prices, PV production, and demand
    price_prod_demand_df = DataFrame(
        SpotPriceDKK = priceData[:, :SpotPriceDKK],
        PriceExp = priceExp[1:min_length],
        PVProduction = pvProduction[:, :SolarMWh], 
        Demand = demand[:, clients] 
    )

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

    return systemData
end
