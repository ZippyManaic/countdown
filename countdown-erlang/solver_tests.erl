%% Check the solver against known answers and the dealer against the game's rules
-module(solver_tests).
-include_lib("eunit/include/eunit.hrl").

finds_simplest_solution_test() ->
    ?assertEqual({125, "75 + 50"}, solver:solve(125, [1, 5, 7, 3, 75, 50])),
    ?assertMatch({552, _}, solver:solve(552, [8, 4, 2, 5, 100, 25])).

reports_closest_when_unsolvable_test() ->
    {Value, _} = solver:solve(974, [8, 8, 6, 8, 25, 100]),
    ?assertEqual(1, abs(Value - 974)).

handles_smaller_pools_test() ->
    ?assertEqual({7, "7"}, solver:solve(7, [7])),
    ?assertEqual({7, "7"}, solver:solve(10, [7])),
    ?assertEqual({12, "4 * 3"}, solver:solve(10, [3, 4])),
    ?assertEqual({6, "3 * 2"}, solver:solve(6, [2, 3, 50])).

deals_a_valid_pool_test() ->
    [begin
         {Target, Pool} = countdown:generate_round(),
         ?assert(Target >= 100 andalso Target =< 999),
         ?assertEqual(6, length(Pool)),
         Large = length([P || P <- Pool, P > 10]),
         ?assert(Large =:= 1 orelse Large =:= 2),
         [?assert(length([P || P <- Pool, P =:= N]) =< 2) || N <- lists:seq(1, 10)]
     end || _ <- lists:seq(1, 1000)].
