using CSV
using DataFrames
using TimeZones

function load_data(;batCap = 100.0, initSoC = 0.0)
    
    demand = CSV.read("Data/consumption_data.csv", DataFrame)
    #testTimeCET = ZonedDateTime(String(demand[!,"datetime_cet"][1]), "yyyy-mm-dd HH:MM:SSz")
    demand[!, :HourUTC_datetime] = DateTime.(demand[:, :datetime_cet], DateFormat("yyyy-mm-dd HH:MM:SSz")) .- Hour(1)
    demand = select!(demand, Not(:datetime_cet))
    demand[!, :Z] .= 0

    # NOTE: Added client Z who is the PV owner
    clientPVOwnership = Dict(
        "A" => 0.143, "B" => 0.006, "C" => 0.009, "D" => 0.007, "E" => 0.005, 
        "F" => 0.003, "G" => 0.143, "H" => 0.014, "I" => 0.05, "J" => 0.003, 
        "K" => 0.004, "L" => 0.021, "M" => 0.004, "N" => 0.001, "O" => 0.003, 
        "P" => 0.003, "Q" => 0.028, "R" => 0.002, "S" => 0.041, "T" => 0.002, 
        "U" => 0.007, "V" => 0.002, "W" => 0.001, "X" => 0.001, "Y" => 0.01,
        "Z" => 0.487
    )
    clientBatteryOwnership = clientPVOwnership

    pvProduction = CSV.read("Data/ProductionMunicipalityHour.csv", DataFrame; decimal=',')
    pvProduction[!, :HourUTC_datetime] = DateTime.(pvProduction[:, :HourUTC], DateFormat("yyyy-mm-dd HH:MM:SS"))
    # Rescale PV production to align with plant size 
    plant_size = 14.0 # MW
    old_plant_size = maximum(pvProduction[:, :SolarMWh])
    rename!(pvProduction,:SolarMWh => :SolarMWh_unscaled)
    pvProduction[!, :SolarMWh] = pvProduction[!, :SolarMWh_unscaled].*plant_size / old_plant_size
    pvProduction = select(pvProduction, [:HourUTC_datetime, :SolarMWh])

    # Load imbalance prices
    # NOTE: The prices are in EUR/MWh, and the data is in UTC
    imbalanceData = CSV.read("Data/imbalancePrice.csv", DataFrame; decimal=',')
    imbalanceData[!, :HourUTC_datetime] = DateTime.(imbalanceData[:, :HourUTC], DateFormat("yyyy-mm-dd HH:MM:SS"))
    imbalanceData = select(imbalanceData, [:HourUTC_datetime, :ImbalancePriceEUR, :SpotPriceEUR])

    combinedData = innerjoin(pvProduction, imbalanceData, on=:HourUTC_datetime)

    clients = keys(clientPVOwnership)
    clients = sort(collect(clients))

    # Loading forecast data, this is done no matter what to keep datapoints constant between runs
    pv_forecast = CSV.read("Data/Solar_Forecasts_Hour.csv", DataFrame; decimal=',')
    pv_forecast[!, :HourUTC_datetime] = DateTime.(pv_forecast[:, :HourUTC], DateFormat("yyyy-mm-dd HH:MM:SS"))
    rename!(pv_forecast, :ForecastCurrent => :ForecastCurrent_unscaled)
    old_plant_size = maximum(pv_forecast[:, :ForecastCurrent_unscaled])
    pv_forecast[!, :PVForecast] = pv_forecast[!, :ForecastCurrent_unscaled] .* plant_size / old_plant_size
    pv_forecast = select(pv_forecast, [:HourUTC_datetime, :PVForecast])

    # Create forecast columns for each client's demand
    #for client in clients
    #    forecast_column_name = Symbol("Forecast_", client)
    #    combinedData[!, forecast_column_name] = combinedData[!, client] .* (1 .+ 0.1 .* randn(size(combinedData, 1)))
    #end
    combinedData = innerjoin(combinedData, pv_forecast, on=:HourUTC_datetime)
    

    missing_data_counts = Dict()
    for client in clients
        missing_data_counts[client] = count(ismissing, demand[:, client])
    end
    clients_without_missing_data = filter(client -> missing_data_counts[client] == 0, clients)
    #println("Clients without missing data: ", clients_without_missing_data)

    # Dropping columns with missing values
    #demand = select!(demand, Not([:"C",:"P",:"B",:"M",:"D",:"E",:"R"]))

    # Remove weekend hours from combinedData
    #combinedData = filter(row -> dayofweek(row[:HourUTC_datetime]) in 1:4, combinedData)
    # Remove holiday hours from combinedData
    # TODO: Add more holidays 
    #combinedData = filter(row -> !(row[:HourUTC_datetime] in DateTime(2024, 12, 24):Day(1):DateTime(2025, 1, 1)), combinedData)


    #println("Missing data points for each client:")
    #println(missing_data_counts)

    systemData = Dict(
        "demand" => demand,
        "clientPVOwnership" => clientPVOwnership,
        "clientBatteryOwnership" => clientBatteryOwnership,
        "initSoC" => initSoC,
        "batCap" => batCap,
        "clients" => clients,
        "price_prod_demand_df" => combinedData
    )
    return systemData, clients_without_missing_data
end

    