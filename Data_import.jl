using CSV
using DataFrames
using TimeZones

"""
    load_data() -> Dict, Vector{String}

Load and preprocess demand, PV production, price, and forecast data for all clients.
Returns a dictionary with system data and a vector of clients without missing data.
"""
function load_data()
    # --- Load demand data ---
    demand = CSV.read("Data/consumption_data.csv", DataFrame)
    demand[!, :HourUTC_datetime] = DateTime.(demand[:, :datetime_cet], DateFormat("yyyy-mm-dd HH:MM:SSz")) .- Hour(1)
    select!(demand, Not(:datetime_cet))
    demand[!, :Z] .= 0

    # --- Define PV ownership ---
    pvOwnershipDF = CSV.read("Data/Asset_master_data_asmus.csv", DataFrame; decimal=',')
    clientPVOwnership = Dict(String(row.Customer) => row.a_ppa_pct for row in eachrow(pvOwnershipDF))
    # Note: Z is the solar park owner
    clientPVOwnership["Z"] = 1-sum(values(clientPVOwnership)) 

    # --- Load and rescale PV production ---
    pvProduction = CSV.read("Data/ProductionMunicipalityHour.csv", DataFrame; decimal=',')
    pvProduction[!, :HourUTC_datetime] = DateTime.(pvProduction[:, :HourUTC], DateFormat("yyyy-mm-dd HH:MM:SS"))
    plant_size = 14.0 # MW
    old_plant_size = maximum(pvProduction[:, :SolarMWh])
    rename!(pvProduction, :SolarMWh => :SolarMWh_unscaled)
    pvProduction[!, :SolarMWh] = pvProduction[!, :SolarMWh_unscaled] .* plant_size / old_plant_size
    pvProduction = select(pvProduction, [:HourUTC_datetime, :SolarMWh])

    # --- Load price data ---
    #priceData = CSV.read("Data/Elspotprices.csv", DataFrame; decimal=',')
    #priceData[!, :HourUTC_datetime] = DateTime.(priceData[:, :HourUTC], DateFormat("yyyy-mm-dd HH:MM:SS"))
    #priceData = select(priceData, [:HourUTC_datetime, :SpotPriceDKK])

    # --- Combine demand and PV production ---
    combinedData = innerjoin(pvProduction, demand, on=:HourUTC_datetime)

    # --- Prepare client list ---
    clients = sort(collect(keys(clientPVOwnership)))

    # --- Load and rescale PV forecast ---
    pv_forecast = CSV.read("Data/Solar_Forecasts_Hour.csv", DataFrame; decimal=',')
    pv_forecast[!, :HourUTC_datetime] = DateTime.(pv_forecast[:, :HourUTC], DateFormat("yyyy-mm-dd HH:MM:SS"))
    rename!(pv_forecast, :ForecastCurrent => :ForecastCurrent_unscaled)
    old_plant_size = maximum(pv_forecast[:, :ForecastCurrent_unscaled])
    pv_forecast[!, :PVForecast] = pv_forecast[!, :ForecastCurrent_unscaled] .* plant_size / old_plant_size
    pv_forecast = select(pv_forecast, [:HourUTC_datetime, :PVForecast])

    # --- Merge forecast with combined data ---
    combinedData = innerjoin(combinedData, pv_forecast, on=:HourUTC_datetime)

    # --- Filter clients with missing data ---
    missing_data_counts = Dict(client => count(ismissing, demand[:, client]) for client in clients)
    clients_without_missing_data = filter(client -> missing_data_counts[client] == 0, clients)

    # --- Collect system data ---
    systemData = Dict(
        #"demand" => demand,
        "clientPVOwnership" => clientPVOwnership,
        #"clients" => clients,
        "price_prod_demand_df" => combinedData
    )
    return systemData, clients_without_missing_data
end

