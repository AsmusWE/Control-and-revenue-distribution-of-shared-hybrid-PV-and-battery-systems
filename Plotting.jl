function plot_results(
    systemData,
    allocation_costs,
    bids,
    imbalances,
    clients_without_missing_data,
    start_hour,
    sim_days
)

    

    cost_shapley = allocation_costs["shapley"]
    cost_VCG = allocation_costs["VCG"]
    cost_gately = allocation_costs["gately"]
    cost_full_cost = allocation_costs["full_cost"]
    # Calculating cost per imbalance cost per MWh
    start_idx = findfirst(x -> x >= start_hour, systemData["price_prod_demand_df"][!,"HourUTC_datetime"])
    end_idx = start_idx + sim_days * 24 - 1
    dayData = deepcopy(systemData)
    dayData["price_prod_demand_df"] = systemData["price_prod_demand_df"][start_idx:end_idx, :]

    # Rank clients by average demand
    avg_demands = Dict(client => sum(dayData["price_prod_demand_df"][!, Symbol(client)]) / length(dayData["price_prod_demand_df"][!, Symbol(client)]) for client in clients_without_missing_data)
    sorted_clients = sort(collect(avg_demands), by = x -> -x[2])

    # Use sorted client order for plotting
    plotKeys = [client for (client, _) in sorted_clients]



    cost_MWh_shapley = scale_distribution(cost_shapley, dayData["price_prod_demand_df"], clients_without_missing_data)
    cost_MWh_VCG = scale_distribution(cost_VCG, dayData["price_prod_demand_df"], clients_without_missing_data)
    cost_MWh_gately = scale_distribution(cost_gately, dayData["price_prod_demand_df"], clients_without_missing_data)
    cost_MWh_full_cost = scale_distribution(cost_full_cost, dayData["price_prod_demand_df"], clients_without_missing_data)
    # Plot the imbalance fees for each client
    # Plot imbalance fees per MWh
    p_fees_MWh = plot(title="Imbalance Fees per MWh for Clients", xlabel="Client", ylabel="Imbalance Fee per MWh", xticks=(1:length(plotKeys), plotKeys), xrotation=45)
    plotValsMWh_shapley = [cost_MWh_shapley[k] for k in plotKeys]
    plotValsMWh_VCG = [cost_MWh_VCG[k] for k in plotKeys]
    plotValsMWh_gately = [cost_MWh_gately[k] for k in plotKeys]
    plotValsMWh_full_cost = [cost_MWh_full_cost[k] for k in plotKeys]
    scatter!(p_fees_MWh, 1:length(plotKeys), plotValsMWh_shapley, label="Imbalance Fees per MWh Shapley")
    scatter!(p_fees_MWh, 1:length(plotKeys), plotValsMWh_VCG, label="Imbalance Fees per MWh VCG")
    scatter!(p_fees_MWh, 1:length(plotKeys), plotValsMWh_gately, label="Imbalance Fees per MWh Gately")
    scatter!(p_fees_MWh, 1:length(plotKeys), plotValsMWh_full_cost, label="Imbalance Fees per MWh Full Cost Transfer")
    display(p_fees_MWh)

    # Plot total imbalance fees
    p_fees_total = plot(title="Total Imbalance Fees for Clients", xlabel="Client", ylabel="Total Imbalance Fee", xticks=(1:length(plotKeys), plotKeys), xrotation=45)
    plotVals_shapley = [cost_shapley[k] for k in plotKeys]
    plotVals_VCG = [cost_VCG[k] for k in plotKeys]
    plotVals_gately = [cost_gately[k] for k in plotKeys]
    plotVals_full_cost = [cost_full_cost[k] for k in plotKeys]
    scatter!(p_fees_total, 1:length(plotKeys), plotVals_shapley, label="Total Imbalance Fees Shapley")
    scatter!(p_fees_total, 1:length(plotKeys), plotVals_VCG, label="Total Imbalance Fees VCG")
    scatter!(p_fees_total, 1:length(plotKeys), plotVals_gately, label="Total Imbalance Fees Gately")
    scatter!(p_fees_total, 1:length(plotKeys), plotVals_full_cost, label="Total Imbalance Fees Full Cost Transfer")
    display(p_fees_total)

    # Plot cost per MWh imbalance
    cost_imbalance_shapley = Dict{String, Float64}()
    cost_imbalance_VCG = Dict{String, Float64}()
    cost_imbalance_gately = Dict{String, Float64}()
    cost_imbalance_full_cost = Dict{String, Float64}()
    for client in plotKeys
        cost_imbalance_shapley[client] = cost_shapley[client] / imbalances[[client]]
        cost_imbalance_VCG[client] = cost_VCG[client] / imbalances[[client]]
        cost_imbalance_gately[client] = cost_gately[client] / imbalances[[client]]
        cost_imbalance_full_cost[client] = cost_full_cost[client] / imbalances[[client]]
    end
    p_imbalance_cost = plot(title="Cost per MWh Imbalance for Clients", xlabel="Client", ylabel="Cost per MWh Imbalance", xticks=(1:length(plotKeys), plotKeys), xrotation=45)
    plotVals_imbalance_shapley = [cost_imbalance_shapley[k] for k in plotKeys]
    plotVals_imbalance_VCG = [cost_imbalance_VCG[k] for k in plotKeys]
    plotVals_imbalance_gately = [cost_imbalance_gately[k] for k in plotKeys]
    plotVals_imbalance_full_cost = [cost_imbalance_full_cost[k] for k in plotKeys]
    scatter!(p_imbalance_cost, 1:length(plotKeys), plotVals_imbalance_shapley, label="Cost per MWh Imbalance Shapley")
    scatter!(p_imbalance_cost, 1:length(plotKeys), plotVals_imbalance_VCG, label="Cost per MWh Imbalance VCG")
    scatter!(p_imbalance_cost, 1:length(plotKeys), plotVals_imbalance_gately, label="Cost per MWh Imbalance Gately")
    scatter!(p_imbalance_cost, 1:length(plotKeys), plotVals_imbalance_full_cost, label="Cost per MWh Imbalance Full Cost Transfer")
    display(p_imbalance_cost)

    # Plot aggregate demand, PV production, bids, and imbalance
    p_aggregate = plot(title="Aggregate Demand, PV Production, Bids, and Imbalance", xlabel="Hour", ylabel="Value")
    aggregate_demand = sum(dayData["price_prod_demand_df"][!, client] for client in clients_without_missing_data)
    aggregate_pvProd = sum(dayData["price_prod_demand_df"][!, "SolarMWh"] .* systemData["clientPVOwnership"][client] for client in clients_without_missing_data)
    combined_bids = bids[clients_without_missing_data]
    combined_imbalance = combined_bids + aggregate_pvProd - aggregate_demand


    n_hours = length(aggregate_demand)
    plot!(p_aggregate, 1:n_hours, aggregate_demand, label="Aggregate Demand")
    plot!(p_aggregate, 1:n_hours, aggregate_pvProd, label="Aggregate PV Production")
    plot!(p_aggregate, 1:n_hours, combined_bids, label="Combined Bids")
    plot!(p_aggregate, 1:n_hours, combined_imbalance, label="Combined Imbalance")
    display(p_aggregate)


    # Plot total MWh demand per client
    total_MWh_demand = Dict(client => sum(dayData["price_prod_demand_df"][!, Symbol(client)]) for client in plotKeys)
    p_total_demand = plot(title="Total MWh Demand per Client", xlabel="Client", ylabel="Total MWh Demand", xticks=(1:length(plotKeys), plotKeys), xrotation=45)
    plotVals_total_demand = [total_MWh_demand[k] for k in plotKeys]
    bar!(p_total_demand, 1:length(plotKeys), plotVals_total_demand, label="Total MWh Demand")
    display(p_total_demand)

    # Plot demand for clients F and I
    if "F" in plotKeys || "I" in plotKeys
        p_clients = plot(title="Demand for Clients F and i", xlabel="Hour", ylabel="MWh Demand")
        if "F" in plotKeys
            client_F_demand = dayData["price_prod_demand_df"][!, Symbol("F")]
            plot!(p_clients, 1:length(client_F_demand), client_F_demand, label="Client F Demand")
        end
        if "I" in plotKeys
            client_I_demand = dayData["price_prod_demand_df"][!, Symbol("I")]
            plot!(p_clients, 1:length(client_I_demand), client_I_demand, label="Client I Demand")
        end
        display(p_clients)
    end

end