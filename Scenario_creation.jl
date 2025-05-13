

function generate_scenarios(clients, demandDF; num_scenarios = 100, scen_length = 24)
    # Create an array to store the scenarios
    
    total_scenarios = div(size(demandDF)[1], scen_length, RoundDown) 
    scenarios = zeros(scen_length, length(clients), total_scenarios)
    for i in 1:total_scenarios
        # Generate a random scenario for each client
        for (idx,j) in enumerate(clients)
            # Setting each scenario to be a demand sample
            scenarios[:, idx, i] = demandDF[!, j][(i-1)*scen_length+1:i*scen_length] 
        end
    end
    # Randomly select num_scenarios from the generated scenarios
    selected_indices = rand(1:total_scenarios, num_scenarios)
    scenarios = scenarios[:, :, selected_indices]
    return scenarios
end