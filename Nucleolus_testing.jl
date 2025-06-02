include("Game_theoretic_functions.jl")

clients = ["A", "B", "C", "D"]
Payoffs = Dict(
    "A" => 0,
    "B" => 0,
    "C" => 1,
    "D" => 0
)

hourly_imbalances = Dict(
    ["A"] => [2],
    ["B"] => [2],
    ["C"] => [-3],
    ["D"] => [-2]
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

locked_excesses, payments = nucleolus(clients, imbalances)
min_excess = minimum(values(locked_excesses))
max_excess = maximum(values(locked_excesses))

min_coalitions = [coal for (coal, val) in locked_excesses if val == min_excess]
max_coalitions = [coal for (coal, val) in locked_excesses if val == max_excess]

println("Minimum excess: ", min_excess, " for coalitions: ", min_coalitions)
println("Maximum excess: ", max_excess, " for coalitions: ", max_coalitions)
println("Payments: ", payments)

# max_instability = check_stability(Payoffs, imbalances, clients)
# println("Max instability: ", max_instability)

# Brute-force search for lowest max_instability by looping through possible payoffs
# function brute_force_min_instability(hourly_imbalances, imbalances, clients; step=0.1)
#     n = length(clients)
#     total_payoff = abs(sum(hourly_imbalances[[c]] for c in clients)[1])
#     best_payoffs = nothing
#     min_instability = Inf
#     allocations = []
#     # For 4 clients, loop over a grid for 3, compute the 4th
#     rangeA = -5:step:5
#     rangeB = -5:step:5
#     rangeC = -5:step:5
#     for a in rangeA, b in rangeB, c in rangeC
#         d = total_payoff - (a + b + c)
#         # Only consider if d is in the same range
#         if d < -5 || d > 5
#             continue
#         end
#         Payoffs = Dict(
#             clients[1] => a,
#             clients[2] => b,
#             clients[3] => c,
#             clients[4] => d
#         )
#         instab = check_stability(Payoffs, imbalances, clients)
#         if instab < min_instability
#             min_instability = instab
#             best_payoffs = deepcopy(Payoffs)
#             empty!(allocations)
#             push!(allocations, deepcopy(Payoffs))
#         elseif instab == min_instability
#             push!(allocations, deepcopy(Payoffs))
#         end
#     end
#     return best_payoffs, min_instability, length(allocations)
# end

#best_payoffs_bf, min_instability_bf, n_allocs = brute_force_min_instability(hourly_imbalances, imbalances, clients; step=0.1)
#println("Brute-force best payoffs: ", best_payoffs_bf)
#println("Brute-force minimum max instability: ", min_instability_bf)
#println("Number of allocations with minimum instability: ", n_allocs)
