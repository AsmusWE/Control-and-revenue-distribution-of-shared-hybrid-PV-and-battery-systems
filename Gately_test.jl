using NLsolve

imbalances = [2,-1,2]
total_imbalance = abs(sum(imbalances))
A = length(imbalances)
v_without = zeros(Float64, A)
for i in 1:A
    v_without[i] = abs.(sum(imbalances[j] for j in 1:A if j != i))
end
v = abs.(imbalances)


function f!(F, x)
    for a in 1:A-1
        F[a] = ((sum(x[b] for b in 1:A if b != a)-v_without[a])/(x[a]-v[a]) 
        - (sum(x[b] for b in 1:A if b != (a+1))-v_without[a+1])/(x[a+1]-v[a+1]))
    end
    F[A] = sum(x) - total_imbalance
end

sol = nlsolve(f!, zeros(Float64, A))
x = sol.zero
println("x: ", x)
for a in 1:A
    println("d: ", (sum(x[b] for b in 1:A if b != a)-v_without[a])/(x[a]-v[a]))
    println("x[a]: ", x[a])
end
