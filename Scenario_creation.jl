include("Imbalance_functions.jl")

function generate_scenarios_demand(clients, demandDF, start_hour; num_scenarios = 50)
    # Find the index of the first value after the start_hour in the demandDF
    start_idx = findfirst(demandDF[:, :HourUTC_datetime] .> start_hour)
    if start_idx === nothing
        error("No value after start_hour $start_hour found in demandDF[:HourUTC_datetime]")
    end
    scen_length = length(demandDF[1:start_idx, :HourUTC_datetime])  # Length of the historical data before start_hour
    # Filter the demandDF to only include data before the start_hour
    demandDF = demandDF[1:start_idx, :]
    
    # Create a dictionary to store the scenarios
    total_scenarios = div(size(demandDF)[1], scen_length, RoundDown)
    scenarios_dict = Dict()

    for client in clients
        # Looping over weekdays
        for w in 1:7
            key = tuple(client, w)
            # Initialize an array to store scenarios for the client
            client_scenarios = zeros(scen_length, total_scenarios)
            # Determine weekday from "HourUTC_datetime" column
            # Assuming "HourUTC_datetime" is of DateTime type
            weekday_numbers = dayofweek.(demandDF[:, :HourUTC_datetime])  # 1=Monday, ..., 7=Sunday
            weekday_indices = findall(weekday_numbers .== w)
            # Number of scenarios for this weekday
            weekday_total_scenarios = div(length(weekday_indices), scen_length, RoundDown)
            # Only proceed if there are enough samples for this weekday
            if weekday_total_scenarios == 0
                println("Not enough data for client $client on weekday $w. Skipping.")
                continue
            end
            # Initialize array for this weekday
            client_scenarios = zeros(scen_length, weekday_total_scenarios)
            for i in 1:weekday_total_scenarios
                idx_range = weekday_indices[(i-1)*scen_length+1 : i*scen_length]
                client_scenarios[:, i] = demandDF[!, client][idx_range]
            end
            # Randomly select num_scenarios from the generated scenarios
            selected_indices = rand(1:weekday_total_scenarios, min(num_scenarios, weekday_total_scenarios))
            scenarios_dict[key] = client_scenarios[:, selected_indices]
        end
    end

    return scenarios_dict
end

function generate_scenarios_demand_rolling(clients, demandDF, start_hour, sim_days; num_scenarios = 5)
    # Find the length of the data after the start_hour in the demandDF
    start_idx = findfirst(demandDF[:, :HourUTC_datetime] .> start_hour)
    if start_idx === nothing
        error("No value after start_hour $start_hour found in demandDF[:HourUTC_datetime]")
    end
    scen_length = sim_days * 96  # 96 time steps per day, sim_days days
    scenarios_dict = Dict()
    scenario_offset = 96*7 # 96 time steps per day, 7 days in a week. 
    for client in clients
        # Initialize an array to store scenarios for the client
        client_scenarios = zeros(scen_length, num_scenarios)
        # Loop over the number of scenarios
        for i in 1:num_scenarios
            # Scenario i is the real data shifted by i weeks
            client_scenarios[:, i] = demandDF[start_idx - i*scenario_offset : start_idx - i*scenario_offset + scen_length - 1, client]
        end
        scenarios_dict[client] = client_scenarios
    end

    return scenarios_dict
end

function generate_noise_forecast_PV(clients, systemData, start_hour, sim_days)
    standard_deviation = systemData["pv_noise_std"]
    # Get the number of time steps in the forecast
    tempData = set_period!(systemData, start_hour, sim_days)
    data_length = size(tempData["price_prod_demand_df"], 1)
    pvForecast = tempData["price_prod_demand_df"][:, :SolarMWh] .* (1 .+ standard_deviation * randn(data_length, 1))
    return pvForecast
end