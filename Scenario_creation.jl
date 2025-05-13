function generate_scenarios(clients, demandDF; num_scenarios = 100, scen_length = 24)
    # Create a dictionary to store the scenarios
    total_scenarios = div(size(demandDF)[1], scen_length, RoundDown)
    scenarios_dict = Dict()

    for client in clients
        # Initialize an array to store scenarios for the client
        client_scenarios = zeros(scen_length, total_scenarios)
        for i in 1:total_scenarios
            # Setting each scenario to be a demand sample for the client
            client_scenarios[:, i] = demandDF[!, client][(i-1)*scen_length+1:i*scen_length]
        end
        # Randomly select num_scenarios from the generated scenarios
        selected_indices = rand(1:total_scenarios, num_scenarios)
        scenarios_dict[client] = client_scenarios[:, selected_indices]
    end

    return scenarios_dict
end