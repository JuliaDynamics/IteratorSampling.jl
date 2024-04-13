
mutable struct ResSampleMultiAlgR{T} <: AbstractReservoirSampleMulti
    state::Int
    value::Vector{T}
end

mutable struct OrdResSampleMultiAlgR{T} <: AbstractOrdReservoirSampleMulti
    state::Int
    value::Vector{T}
    ord::Vector{Int}
end

mutable struct ResSampleMultiAlgL{T} <: AbstractReservoirSampleMulti
    state::Float64
    skip_k::Int
    seen_k::Int
    value::Vector{T}
end

mutable struct OrdResSampleMultiAlgL{T} <: AbstractOrdReservoirSampleMulti
    state::Float64
    skip_k::Int
    seen_k::Int
    value::Vector{T}
    ord::Vector{Int}
end

function ReservoirSample(T, n::Integer; ordered = false, method=:alg_L)
    value = Vector{T}(undef, n)
    if method == :alg_R
        if ordered
            return OrdResSampleMultiAlgR(0, value, Vector{Int}(undef, n))
        else
            return ResSampleMultiAlgR(0, value)
        end
    else
        if ordered
            return OrdResSampleMultiAlgL(0.0, 0, 0, value, Vector{Int}(undef, n))
        else
            return ResSampleMultiAlgL(0.0, 0, 0, value)
        end
    end
end

update!(s::ResSampleMultiAlgR, el) = update!(Random.default_rng(), s, el)
function update!(rng, s::ResSampleMultiAlgR, el)
    n = length(s.value)
    s.state += 1
    if s.state <= n
        s.value[s.state] = el
    else
        j = rand(rng, 1:s.state)
        if j <= n
            s.value[j] = el
        end
    end
    return s
end

update!(s::OrdResSampleMultiAlgR, el) = update!(Random.default_rng(), s, el)
function update!(rng, s::OrdResSampleMultiAlgR, el)
    n = length(s.value)
    s.state += 1
    if s.state <= n
        s.value[s.state] = el
        s.ord[s.state] = s.state
    else
        j = rand(rng, 1:s.state)
        if j <= n
            s.value[j] = el
            s.ord[j] = s.state
        end
    end
    return s
end

update!(s::ResSampleMultiAlgL, el) = update!(Random.default_rng(), s, el)
function update!(rng, s::ResSampleMultiAlgL, el)
    n = length(s.value)
    s.seen_k += 1
    s.skip_k -= 1
    if s.seen_k <= n
        s.value[s.seen_k] = el
        s.seen_k == n && compute_skip(rng, s, n)    
    elseif s.skip_k < 0
        j = rand(rng, 1:n)
        s.value[j] = el
        compute_skip(rng, s, n)
    end
    return s
end

update!(s::OrdResSampleMultiAlgL, el) = update!(Random.default_rng(), s, el)
function update!(rng, s::OrdResSampleMultiAlgL, el)
    n = length(s.value)
    s.seen_k += 1
    s.skip_k -= 1
    if s.seen_k <= n
        s.value[s.seen_k] = el
        s.ord[s.seen_k] = s.seen_k
        s.seen_k == n && compute_skip(rng, s, n)
    elseif s.skip_k < 0
        j = rand(rng, 1:n)
        s.value[j] = el
        s.ord[j] = s.seen_k
        compute_skip(rng, s, n)
    end
    return s
end

@inline function compute_skip(rng, s, n)
    s.state += randexp(rng)
    w = exp(-s.state/n)
    s.skip_k = -ceil(Int, randexp(rng)/log(1-w))
end

function value(s::AbstractReservoirSampleMulti)
    if n_seen(s) < length(s.value)
        return s.value[1:n_seen(s)]
    else
        return s.value
    end
end

function ordered_value(s::AbstractOrdReservoirSampleMulti)
    if n_seen(s) < length(s.value)
        return s.value[1:n_seen(s)]
    else
        return s.value[sortperm(s.ord)]
    end
end

n_seen(s::Union{ResSampleMultiAlgR, OrdResSampleMultiAlgR}) = s.state
n_seen(s::Union{ResSampleMultiAlgL, OrdResSampleMultiAlgL}) = s.seen_k

function itsample(iter, n::Int; replace = false, ordered = false, kwargs...)
    return itsample(Random.default_rng(), iter, n; replace=replace, ordered=ordered, kwargs...)
end

function itsample(rng::AbstractRNG, iter, n::Int; 
        replace = false, ordered = false, kwargs...)
    iter_type = calculate_eltype(iter)
    if Base.IteratorSize(iter) isa Base.SizeUnknown
        reservoir_sample(rng, iter, n; replace, ordered, kwargs...)::Vector{iter_type}
    else
        sortedindices_sample(rng, iter, n; replace, ordered, kwargs...)::Vector{iter_type}
    end
end

function reservoir_sample(rng, iter, n; replace = false, ordered = false, kwargs...)
    if replace
        reservoir_sample_with_replacement(rng, iter, n; ordered, kwargs...)
    else
        reservoir_sample_without_replacement(rng, iter, n; ordered, kwargs...)
    end
end

function reservoir_sample_with_replacement(rng, iter, n; ordered = false, method = :alg_L)
    if ordered
        reservoir_sample_with_replacement(rng, iter, n, ordwrsample)
    else
        reservoir_sample_with_replacement(rng, iter, n, wrsample)
    end
end

function reservoir_sample_without_replacement(rng, iter, n; ordered = false, method = :alg_L)
    if ordered
        if method === :alg_L
            reservoir_sample_without_replacement(rng, iter, n, ordworsample, algL)
        elseif method === :alg_R
            reservoir_sample_without_replacement(rng, iter, n, ordworsample, algR)
        else
            error(lazy"No implemented algorithm was found for specified method $(method)")
        end  
    else
        if method === :alg_L
            reservoir_sample_without_replacement(rng, iter, n, worsample, algL)
        elseif method === :alg_R
            reservoir_sample_without_replacement(rng, iter, n, worsample, algR)
        else
            error(lazy"No implemented algorithm was found for specified method $(method)")
        end    
    end
end

function reservoir_sample_without_replacement(rng, iter, n::Int, is::Union{WORSample, OrdWORSample}, alg::AlgR)
    iter_type = calculate_eltype(iter)
    ordered = is isa OrdWORSample ? true : false
    s = ReservoirSample(Base.@default_eltype(iter), n; ordered = ordered, method = :alg_R)
    for x in iter
        @inline update!(rng, s, x)
    end
    return ordered ? ordered_value(s) : shuffle!(rng, value(s))
end

function reservoir_sample_without_replacement(rng, iter, n::Int, is::Union{WORSample, OrdWORSample}, alg::AlgL)
    iter_type = calculate_eltype(iter)
    ordered = is isa OrdWORSample ? true : false
    s = ReservoirSample(Base.@default_eltype(iter), n; ordered = ordered, method = :alg_L)
    for x in iter
        @inline update!(rng, s, x)
    end
    return ordered ? ordered_value(s) : shuffle!(rng, value(s))
end

function reservoir_sample_with_replacement(rng, iter, n::Int, is::Union{WRSample, OrdWRSample})
    iter_type = calculate_eltype(iter)
    it = iterate(iter)
    isnothing(it) && return iter_type[]
    reservoir = Vector{iter_type}(undef, n)
    el, state = it
    reservoir[1] = el
    @inbounds for i in 2:n
        it = iterate(iter, state)
        isnothing(it) && return sample(rng, resize!(reservoir, i-1), n, 
                                       ordered=is isa WRSample ? false : true)
        el, state = it
        reservoir[i] = el
    end
    i, order = instantiate_order(n, is)
    i = n
    reservoir = sample(rng, reservoir, n, ordered=is isa WRSample ? false : true)
    @inbounds while true
        skip_k = skip(rng, i, n)
        it = skip_ahead_unknown_end(iter, state, skip_k)
        isnothing(it) && return transform(rng, reservoir, order, is)
        el, state = it
        i += skip_k + 1
        p = 1/i
        z = (1-p)^(n-3)
        q = rand(rng, Uniform(z*(1-p)*(1-p)*(1-p),1))
        k = choose(n, p, q, z)
        if k == 1
            r = rand(rng, 1:n)
            reservoir[r] = el
            update_order_single!(i, r, order, is)
        else
            for j in 1:k
                r = rand(rng, j:n)
                reservoir[r] = el
                reservoir[r], reservoir[j] = reservoir[j], reservoir[r]
                update_order_multi!(i, r, j, order, is)
            end
        end 
    end
end

function skip(rng, n, m)
    q = rand(rng)^(1/m)
    t = ceil(Int, n/q - n - 1)
    return t
end

function choose(n, p, q, z)
    m = 1-p
    s = z
    z = s*m*m*(m + n*p)
    z > q && return 1
    z += n*p*(n-1)*p*s*m/2
    z > q && return 2
    z += n*p*(n-1)*p*(n-2)*p*s/6
    z > q && return 3
    b = Binomial(n, p)
    return quantile(b, q)
end

function skip_ahead_no_end(iter, state, n)
    for _ in 1:n
        it = iterate(iter, state)
        state = it[2]
    end
    it = iterate(iter, state)
    return it
end

function skip_ahead_unknown_end(iter, state, n)
    for _ in 1:n
        it = iterate(iter, state)
        isnothing(it) && return nothing
        state = it[2]
    end
    it = iterate(iter, state)
    isnothing(it) && return nothing
    return it
end

instantiate_order(n, ::Union{WORSample, WRSample}) = n, nothing
function instantiate_order(n, ::Union{OrdWORSample, OrdWRSample})
    return n, [i for i in 1:n]
end

update_order!(k, skip_k, q, order, ::WORSample) = nothing
update_order!(k, q, order, ::WORSample) = nothing
function update_order!(k, skip_k, q, order, ::OrdWORSample)
    k += skip_k + 1
    order[q] = k
    return k
end
function update_order!(k, q, order, ::OrdWORSample)
    order[q] = k
    return k
end

update_order_single!(k, r, order, ::WRSample) = nothing
function update_order_single!(k, r, order, ::OrdWRSample)
    order[r] = k
end

update_order_multi!(k, r, j, order, ::WRSample) = nothing
function update_order_multi!(k, r, j, order, ::OrdWRSample)
    order[r], order[j] = order[j], k
end

function transform(rng, reservoir, order, ::Union{WORSample, WRSample})
    return shuffle!(rng, reservoir)
end
function transform(rng, reservoir, order, ::Union{OrdWORSample, OrdWRSample})
    return reservoir[sortperm(order)]
end
function transform(rng, reservoir, order::Nothing, ::Union{OrdWORSample, OrdWRSample})
    return reservoir
end

function calculate_eltype(iter)
    return Base.@default_eltype(iter)
end
function calculate_eltype(iter::ResumableFunctions.FiniteStateMachineIterator)
    return eltype(iter)
end
