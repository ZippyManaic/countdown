%% Check the parallel solver against known answers and the reference at several worker counts
-module(solver_par_tests).
-include_lib("eunit/include/eunit.hrl").

finds_simplest_solution_test() ->
    ?assertEqual({125, "75 + 50"}, solver_par:solve(125, [1, 5, 7, 3, 75, 50])),
    ?assertMatch({552, _}, solver_par:solve(552, [8, 4, 2, 5, 100, 25])).

reports_closest_when_unsolvable_test() ->
    {Value, _} = solver_par:solve(974, [8, 8, 6, 8, 25, 100]),
    ?assertEqual(1, abs(Value - 974)).

handles_smaller_pools_test() ->
    ?assertEqual({7, "7"}, solver_par:solve(7, [7])),
    ?assertEqual({7, "7"}, solver_par:solve(10, [7])),
    ?assertEqual({12, "4 * 3"}, solver_par:solve(10, [3, 4])),
    ?assertEqual({6, "3 * 2"}, solver_par:solve(6, [2, 3, 50])).

reports_a_lone_number_as_closest_test() ->
    ?assertEqual({7, "7"}, solver_par:solve(100, [7])).

solves_with_a_lone_number_test() ->
    ?assertEqual({7, "7"}, solver_par:solve(7, [7])).

reports_closest_with_two_numbers_test() ->
    ?assertEqual({12, "4 * 3"}, solver_par:solve(100, [3, 4])).

deals_a_valid_pool_test() ->
    [begin
         {Target, Pool} = countdown_par:generate_round(),
         ?assert(Target >= 100 andalso Target =< 999),
         ?assertEqual(6, length(Pool)),
         Large = length([P || P <- Pool, P > 10]),
         ?assert(Large =:= 1 orelse Large =:= 2),
         [?assert(length([P || P <- Pool, P =:= N]) =< 2) || N <- lists:seq(1, 10)]
     end || _ <- lists:seq(1, 1000)].

%% Return the large count of a dealt round after checking it keeps the rules of its mode
check_round(Mode, Counts, {Target, Pool}) ->
    ?assert(Target >= 100 andalso Target =< 999),
    ?assertEqual(6, length(Pool)),
    Large = [P || P <- Pool, P > 10],
    ?assert(lists:member(length(Large), Counts)),
    ?assertEqual([], Large -- countdown_par:large_numbers(Mode)),
    ?assertEqual(length(Large), length(lists:usort(Large))),
    %% Allow each small number at most twice since the deck holds two of each
    [?assert(length([P || P <- Pool, P =:= N]) =< 2) || N <- lists:seq(1, 10)],
    length(Large).

deals_every_mode_test() ->
    rand:seed(exsss, 1),
    [begin
         Counts = countdown_par:allowed_counts(Mode),
         Seen = [check_round(Mode, Counts, countdown_par:generate_round(Mode)) || _ <- lists:seq(1, 2000)],
         ?assertEqual(Counts, lists:usort(Seen))
     end || Mode <- [standard, cats, nasty]].

deals_a_fixed_large_count_test() ->
    [?assertEqual(K, check_round(Mode, [K], countdown_par:generate_round(Mode, K))) || Mode <- [cats, nasty], K <- lists:seq(0, 4)].

parses_arguments_test() ->
    ?assertEqual({standard, undefined}, countdown_par:parse_args([])),
    ?assertEqual({nasty, 4}, countdown_par:parse_args(["nasty", "4"])),
    ?assertEqual({cats, 0}, countdown_par:parse_args(["cats", "0"])),
    [?assertEqual(error, countdown_par:parse_args(Bad)) || Bad <- [["standard", "3"], ["cats", "5"], ["dogs"], ["cats", "1", "2"], ["cats", "x"]]].

solves_cats_rounds_test() ->
    ?assertEqual({999, "(((75 + 25) * 100) - 10) / 10"}, solver_par:solve(999, [10, 10, 25, 50, 75, 100])),
    ?assertEqual({81, "(((2 + 1) * (2 + 1)) * 3) * 3"}, solver_par:solve(100, [1, 1, 2, 2, 3, 3])),
    ?assertEqual({999, "37 * ((87 / 3) - 2)"}, solver_par:solve(999, [2, 3, 87, 62, 37, 12])).

%% Solve the reference rounds in a fresh process per worker count so each starts its own pool
matches_reference_at_every_worker_count_test_() ->
    {timeout, 120,
     fun() ->
             {ok, Rounds} = file:read_file("../bench/data/rounds1k.txt"),
             {ok, Ref} = file:read_file("../bench/data/ref1k.tsv"),
             Parsed = [begin [T | P] = [binary_to_integer(W) || W <- binary:split(L, <<" ">>, [global, trim_all])], {T, P} end
                       || L <- binary:split(Rounds, <<"\n">>, [global, trim_all])],
             Expected = [binary_to_list(L) || L <- binary:split(Ref, <<"\n">>, [global, trim_all])],
             Saved = os:getenv("COUNTDOWN_THREADS"),
             [begin
                  os:putenv("COUNTDOWN_THREADS", integer_to_list(K)),
                  Self = self(),
                  spawn(fun() -> Self ! {K, [integer_to_list(V) ++ "\t" ++ E || {T, P} <- Parsed,
                                                                                {V, E} <- [solver_par:solve(T, P)]]} end),
                  receive {K, Got} -> ?assertEqual(Expected, Got) end
              end || K <- [1, 2, 4]],
             case Saved of
                 false -> os:unsetenv("COUNTDOWN_THREADS");
                 _ -> os:putenv("COUNTDOWN_THREADS", Saved)
             end
     end}.
