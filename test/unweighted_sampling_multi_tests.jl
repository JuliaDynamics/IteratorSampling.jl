
@testset "Unweighted sampling multi tests" begin
	@testset "alloc=$(alloc)" for alloc in [false, true]

		a, b = 1, 10
		# test return values of iter with known lengths are inrange
		iter = a:b
		s = itsample(iter, 2, alloc=alloc)
		@test length(s) == 2
		@test all(x -> a <= x <= b, s)

		@test typeof(s) == Vector{ifelse(alloc, Int, Any)}
		s = itsample(iter, 2, alloc=alloc, iter_type=Int)
		@test length(s) == 2
		@test all(x -> a <= x <= b, s)
		@test typeof(s) == Vector{Int}
		s = itsample(iter, 100, alloc=alloc)
		@test length(s) == 10
		@test length(unique(s)) == 10

		# test return values of iter with unknown lengths are inrange
		iter = Iterators.filter(x -> x < 5, a:b)
		s = itsample(iter, 2, alloc=alloc)
		@test length(s) == 2
		@test all(x -> a <= x <= b, s)

		@test typeof(s) == Vector{ifelse(alloc, Int, Any)}
		s = itsample(iter, 2, alloc=alloc, iter_type=Int)
		@test length(s) == 2
		@test all(x -> a <= x <= b, s)
		@test typeof(s) == Vector{Int}
		s = itsample(iter, 100, alloc=alloc)
		@test length(s) == 4
		@test length(unique(s)) == 4

		# create empirical distribution
		iter = a:b
		rng = StableRNG(43)
		reps = 10000
		dict_res = Dict{Vector, Int}()
		for _ in 1:reps
			s = itsample(rng, iter, 2, alloc=alloc)
			if s in keys(dict_res)
				dict_res[s] += 1
			elseif ifelse(alloc, Int, Any)[s[2], s[1]] in keys(dict_res)
				dict_res[ifelse(alloc, Int, Any)[s[2], s[1]]] += 1
			else
				dict_res[s] = 1
			end
		end
		cases = (10*9)/2
		ps_exact = [1/cases for _ in 1:cases]
		count_est = collect(values(dict_res))

		# chi-squared test
		chisq_test = ChisqTest(count_est, ps_exact)
		@test pvalue(chisq_test) > 0.05
	end
end