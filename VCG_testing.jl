clients = ["A", "B", "C", "D","E"]
systemData = Dict("downreg_price" => 1, "upreg_price" => 1)
downreg_price = systemData["downreg_price"]
upreg_price = systemData["upreg_price"]
hourly_imbalances = Dict(
    ["A"] => [3],
    ["B"] => [-3],
    ["C"] => [-2],
    ["D"] => [12],
    ["E"] => [-1]
)
# This function calculates the VCG value for each client in the grand coalition
T = length(hourly_imbalances[[clients[1]]])
VCG_taxes = Dict()
grand_coalition = vec(clients)
using Combinatorics

# Extend hourly_imbalances to include all possible combinations of clients
coalitions = collect(combinations(clients))
for k in 2:length(clients)
    for combo in coalitions
        key = collect(combo)  # Use a Vector like ["A", "B"]
        # Sum the imbalances for each client in the combination at each hour
        imbalance_sum = [sum(hourly_imbalances[[c]][t] for c in combo) for t in 1:length(hourly_imbalances[[clients[1]]])]
        hourly_imbalances[key] = imbalance_sum
    end
end
imbalances = Dict()
for coalition in coalitions
    imbalances[coalition] = sum(abs.(hourly_imbalances[coalition]))
end
# This function calculates the VCG value for each client in the grand coalition
T = length(hourly_imbalances[[clients[1]]])
VCG_taxes = Dict()
grand_coalition = vec(clients)

coalition = grand_coalition

member_payments = Dict()
for m in coalition
    member_payments[m] = zeros(Float64, T)
    for t in 1:T
        total_pos = sum(max(hourly_imbalances[[i]][t], 0) for i in coalition)
        total_neg = sum(-min(hourly_imbalances[[i]][t], 0) for i in coalition)
        member_imb = hourly_imbalances[[m]][t]
        hour_cost = abs(sum(hourly_imbalances[[i]][t] for i in coalition))
        if member_imb > 0 && total_pos > total_neg
            hour_cost = hour_cost * downreg_price
            member_payments[m][t] = hour_cost * (member_imb / total_pos)
        elseif member_imb < 0 && total_neg > total_pos
            hour_cost = hour_cost * upreg_price
            member_payments[m][t] = hour_cost * (abs(member_imb) / total_neg)
        else
            member_payments[m][t] = 0
        end
    end
end
payments = member_payments

for (idx, i) in enumerate(clients)
    gc_val_minus_i = 0
    coalition_without_i = filter(x -> x != clients[idx], grand_coalition)
    coalition_value_without_i = imbalances[coalition_without_i]
    gc_val_minus_i = sum(sum(payments[client] for client in grand_coalition if client != i))

    # Multiplying by -1 because this is a cost reduction game
    VCG_taxes[[i]] = -(coalition_value_without_i-gc_val_minus_i)
    #println("Client ", i, " VCG tax: ", VCG_taxes[i], " (Grand coalition value minus i: ", grand_coalition_value_minus_i, ", Coalition value without i: ", coalition_value_without_i, ")")
end

VCG_sum = sum(values(VCG_taxes))
println("Sum of VCG taxes: ", VCG_sum)
println("VCG taxes: ", VCG_taxes)